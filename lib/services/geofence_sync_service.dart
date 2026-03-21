import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/geofence_zone.dart';
import 'background_sync_service.dart';
import 'geofence_event_log.dart';
import 'geofence_event_queue.dart';
import 'geofence_notification_service.dart';

/// Service zum Synchronisieren von Geofence-Events mit der Hive-Datenbank
/// Wird im Foreground aufgerufen, wenn die App aktiv ist
class GeofenceSyncService {
  final Box<WorkEntry> workBox;
  // Nullable for test injection (pass null to skip notifications in tests)
  final GeofenceNotificationService? _notificationService;

  /// [skipNotifications] = true disables all notifications (e.g. in tests)
  GeofenceSyncService(this.workBox,
      {GeofenceNotificationService? notificationService,
      bool skipNotifications = false})
      : _notificationService = skipNotifications
            ? null
            : (notificationService ?? GeofenceNotificationService());

  /// Re-Entry-Merge: Wenn ein ENTER nach einem GPS-bedingten Fehl-Exit
  /// innerhalb dieser Zeitspanne nach dem Stop kommt, wird die Session
  /// wieder geöffnet statt eine neue zu erstellen.
  static const _mergeGracePeriod = Duration(minutes: 25);

  /// Verarbeitet alle ausstehenden Geofence-Events
  /// Gibt die Anzahl der verarbeiteten Events zurück
  Future<int> syncPendingEvents() async {
    final events = await GeofenceEventQueue.getUnprocessedEvents();

    if (events.isEmpty) {
      return 0;
    }

    log('GeofenceSyncService: Processing ${events.length} pending events');

    // Events nach Zeitstempel sortieren
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var processedCount = 0;

    for (final event in events) {
      try {
        await _processEvent(event);
        processedCount++;
      } catch (e) {
        log('Error processing event: $e', name: 'GeofenceSyncService');
      }
    }

    // Events als verarbeitet markieren
    await GeofenceEventQueue.markAsProcessed(events);

    // Alte Events aufräumen
    await GeofenceEventQueue.cleanup();

    log('GeofenceSyncService: Processed $processedCount events');
    return processedCount;
  }

  Future<void> _processEvent(GeofenceEventData event) async {
    if (event.event == GeofenceEvent.enter) {
      await _handleEnter(event);
    } else if (event.event == GeofenceEvent.exit) {
      await _handleExit(event);
    }
  }

  /// Behandelt ein ENTER-Event: Neue Arbeitszeit starten (oder Session fortsetzen)
  Future<void> _handleEnter(GeofenceEventData event) async {
    // Prüfen ob bereits eine laufende Arbeitszeit existiert
    final runningEntry = _getRunningEntry();

    if (runningEntry != null) {
      log('GeofenceSyncService: Already running entry exists, skipping ENTER');
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.ignored,
      ));
      return;
    }

    // Re-Entry-Merge: Wurde die Session kürzlich durch GPS-Drift gestoppt?
    // Wenn der Re-Entry innerhalb der Grace-Period nach dem letzten Stop liegt,
    // wird die vorhandene Session wieder geöffnet statt eine neue zu starten.
    final recentStopped = _getRecentlyStoppedEntry(event.timestamp);
    if (recentStopped != null) {
      final gap = event.timestamp.difference(recentStopped.stop!);
      log('GeofenceSyncService: Re-entry ${gap.inMinutes}min after stop – '
          'merging back into session started at ${recentStopped.start}');
      recentStopped.stop = null;
      await recentStopped.save();

      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.merged,
        gapMinutes: gap.inMinutes,
      ));

      if (_notificationService != null) {
        final zoneName = _getZoneName(event.zoneId);
        await _notificationService!.showMergeNotification(
          workEntryKey: recentStopped.key as int,
          gap: gap,
          zoneName: zoneName,
        );
      }
      return;
    }

    // Prüfen ob es bereits einen Eintrag für diesen Zeitstempel gibt
    final existingEntry = workBox.values.any((e) =>
        e.start.year == event.timestamp.year &&
        e.start.month == event.timestamp.month &&
        e.start.day == event.timestamp.day &&
        e.start.hour == event.timestamp.hour &&
        e.start.minute == event.timestamp.minute);

    if (existingEntry) {
      log('GeofenceSyncService: Entry already exists for this timestamp');
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.ignored,
      ));
      return;
    }

    // Neue Arbeitszeit erstellen
    final entry = WorkEntry(start: event.timestamp);
    final key = await workBox.add(entry);
    log('GeofenceSyncService: Created new WorkEntry at ${event.timestamp}');

    await GeofenceEventLog.append(GeofenceEventLogEntry(
      timestamp: event.timestamp,
      event: event.event,
      zoneId: event.zoneId,
      outcome: GeofenceEventOutcome.started,
    ));

    // Benachrichtigung mit Einspruch-Möglichkeit anzeigen
    if (_notificationService != null) {
      final zoneName = _getZoneName(event.zoneId);
      await _notificationService!.showAutoStartNotification(
        workEntryKey: key,
        timestamp: event.timestamp,
        zoneName: zoneName,
      );
    }
  }

  /// Behandelt ein EXIT-Event: Laufende Arbeitszeit stoppen
  Future<void> _handleExit(GeofenceEventData event) async {
    final runningEntry = _getRunningEntry();

    if (runningEntry == null) {
      log('GeofenceSyncService: No running entry to stop');
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.ignored,
      ));
      return;
    }

    // Prüfen ob Exit nach Start liegt
    if (event.timestamp.isBefore(runningEntry.start)) {
      log('GeofenceSyncService: EXIT timestamp before START, ignoring');
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.ignored,
      ));
      return;
    }

    // Mindest-Sitzungsdauer: Erst nach 25 Minuten automatisch stoppen.
    // GPS-Drift kann echte Sessions früh unterbrechen – kurze Sessions
    // werden daher als Fehler gewertet und ignoriert.
    final sessionDuration = event.timestamp.difference(runningEntry.start);
    if (sessionDuration.inMinutes < 25) {
      log('GeofenceSyncService: EXIT ignored – session too short (${sessionDuration.inMinutes} min < 25 min)');
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: event.timestamp,
        event: event.event,
        zoneId: event.zoneId,
        outcome: GeofenceEventOutcome.shortSession,
      ));
      return;
    }

    // Arbeitszeit beenden
    final startTime = runningEntry.start;
    runningEntry.stop = event.timestamp;
    await runningEntry.save();
    log('GeofenceSyncService: Stopped WorkEntry at ${event.timestamp}');

    await GeofenceEventLog.append(GeofenceEventLogEntry(
      timestamp: event.timestamp,
      event: event.event,
      zoneId: event.zoneId,
      outcome: GeofenceEventOutcome.stopped,
    ));

    // Benachrichtigung mit Einspruch-Möglichkeit anzeigen
    if (_notificationService != null) {
      final zoneName = _getZoneName(event.zoneId);
      final workedDuration = event.timestamp.difference(startTime);
      await _notificationService!.showAutoStopNotification(
        workEntryKey: runningEntry.key as int,
        timestamp: event.timestamp,
        workedDuration: workedDuration,
        zoneName: zoneName,
      );
    }
  }

  /// Holt den Zone-Namen aus der Hive-Box
  String? _getZoneName(String zoneId) {
    try {
      final zonesBox = Hive.box<GeofenceZone>('geofence_zones');
      final zone = zonesBox.values.firstWhere(
        (z) => z.id == zoneId,
        orElse: () => GeofenceZone(
          id: '',
          name: '',
          latitude: 0,
          longitude: 0,
        ),
      );
      return zone.name.isNotEmpty ? zone.name : null;
    } catch (e) {
      log('Error getting zone name: $e');
      return null;
    }
  }

  /// Findet die aktuell laufende Arbeitszeit (ohne stop)
  WorkEntry? _getRunningEntry() {
    try {
      return workBox.values.lastWhere((e) => e.stop == null);
    } catch (e) {
      return null;
    }
  }

  /// Findet einen kürzlich gestoppten Eintrag für den Re-Entry-Merge.
  /// Gibt den zuletzt gestoppten Eintrag zurück, dessen Stop-Zeit innerhalb
  /// der Grace-Period vor [enterTime] liegt – oder null wenn keiner passt.
  WorkEntry? _getRecentlyStoppedEntry(DateTime enterTime) {
    final candidates = workBox.values
        .where((e) => e.stop != null)
        .toList()
      ..sort((a, b) => b.stop!.compareTo(a.stop!)); // neueste zuerst

    for (final entry in candidates) {
      final gap = enterTime.difference(entry.stop!);
      if (gap >= Duration.zero && gap <= _mergeGracePeriod) {
        return entry;
      }
    }
    return null;
  }

  /// Bereinigt verwaiste offene Einträge (z.B. nach einem App-Crash).
  ///
  /// Wenn mehrere Einträge ohne [stop]-Zeit existieren, werden alle außer
  /// dem neuesten automatisch geschlossen: [stop] = [start] + 8 Stunden.
  ///
  /// Gibt die Anzahl der bereinigten Einträge zurück (0 = alles in Ordnung).
  Future<int> cleanupOrphanedEntries() async {
    final open = workBox.values.where((e) => e.stop == null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (open.length <= 1) return 0;

    // Alle außer dem neuesten schließen
    final toClose = open.sublist(0, open.length - 1);
    for (final entry in toClose) {
      entry.stop = entry.start.add(const Duration(hours: 8));
      await entry.save();
      log('GeofenceSyncService: Closed orphaned entry started at ${entry.start}',
          name: 'GeofenceSyncService');
    }
    log('GeofenceSyncService: Cleaned up ${toClose.length} orphaned entries',
        name: 'GeofenceSyncService');
    return toClose.length;
  }

  /// Prüft ob aktuell eine Arbeitszeit läuft
  bool isTracking() {
    return _getRunningEntry() != null;
  }

  /// Manuell Arbeitszeit starten (für Button)
  Future<void> startManually() async {
    if (isTracking()) return;

    final entry = WorkEntry(start: DateTime.now());
    await workBox.add(entry);
    log('GeofenceSyncService: Manually started WorkEntry');
  }

  /// Manuell Arbeitszeit stoppen (für Button)
  Future<void> stopManually() async {
    final runningEntry = _getRunningEntry();
    if (runningEntry == null) return;

    runningEntry.stop = DateTime.now();
    await runningEntry.save();
    log('GeofenceSyncService: Manually stopped WorkEntry');
  }

  /// Holt den Status für die UI
  Future<GeofenceStatus> getStatus() async {
    final isInZone = await GeofenceEventQueue.isCurrentlyInZone();
    final lastEvent = await GeofenceEventQueue.getLastEvent();
    final isTracking = this.isTracking();
    final pendingEvents = await GeofenceEventQueue.getUnprocessedEvents();

    bool isServiceRunning = false;
    if (!kIsWeb) {
      try {
        isServiceRunning =
            await GeofenceForegroundService().isForegroundServiceRunning();
      } catch (_) {}
    }

    final lastBgSync = await BackgroundSyncService.getLastSyncTime();

    return GeofenceStatus(
      isInZone: isInZone,
      isTracking: isTracking,
      lastEvent: lastEvent,
      pendingEventsCount: pendingEvents.length,
      isServiceRunning: isServiceRunning,
      lastBackgroundSync: lastBgSync,
    );
  }
}

/// Status-Informationen für die UI
class GeofenceStatus {
  final bool isInZone;
  final bool isTracking;
  final GeofenceEventData? lastEvent;
  final int pendingEventsCount;
  final bool isServiceRunning;
  final DateTime? lastBackgroundSync;

  GeofenceStatus({
    required this.isInZone,
    required this.isTracking,
    this.lastEvent,
    required this.pendingEventsCount,
    this.isServiceRunning = false,
    this.lastBackgroundSync,
  });

  String get statusText {
    if (isTracking) {
      return isInZone ? 'Im Büro - Arbeitszeit läuft' : 'Arbeitszeit läuft';
    } else {
      return isInZone ? 'Im Büro - Nicht gestartet' : 'Außerhalb';
    }
  }
}
