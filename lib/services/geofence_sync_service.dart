import 'dart:developer';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import 'geofence_event_queue.dart';

/// Service zum Synchronisieren von Geofence-Events mit der Hive-Datenbank
/// Wird im Foreground aufgerufen, wenn die App aktiv ist
class GeofenceSyncService {
  final Box<WorkEntry> workBox;

  GeofenceSyncService(this.workBox);

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

  /// Behandelt ein ENTER-Event: Neue Arbeitszeit starten
  Future<void> _handleEnter(GeofenceEventData event) async {
    // Prüfen ob bereits eine laufende Arbeitszeit existiert
    final runningEntry = _getRunningEntry();

    if (runningEntry != null) {
      log('GeofenceSyncService: Already running entry exists, skipping ENTER');
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
      return;
    }

    // Neue Arbeitszeit erstellen
    final entry = WorkEntry(start: event.timestamp);
    await workBox.add(entry);
    log('GeofenceSyncService: Created new WorkEntry at ${event.timestamp}');
  }

  /// Behandelt ein EXIT-Event: Laufende Arbeitszeit stoppen
  Future<void> _handleExit(GeofenceEventData event) async {
    final runningEntry = _getRunningEntry();

    if (runningEntry == null) {
      log('GeofenceSyncService: No running entry to stop');
      return;
    }

    // Prüfen ob Exit nach Start liegt
    if (event.timestamp.isBefore(runningEntry.start)) {
      log('GeofenceSyncService: EXIT timestamp before START, ignoring');
      return;
    }

    // Arbeitszeit beenden
    runningEntry.stop = event.timestamp;
    await runningEntry.save();
    log('GeofenceSyncService: Stopped WorkEntry at ${event.timestamp}');
  }

  /// Findet die aktuell laufende Arbeitszeit (ohne stop)
  WorkEntry? _getRunningEntry() {
    try {
      return workBox.values.lastWhere((e) => e.stop == null);
    } catch (e) {
      return null;
    }
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

    return GeofenceStatus(
      isInZone: isInZone,
      isTracking: isTracking,
      lastEvent: lastEvent,
      pendingEventsCount: pendingEvents.length,
    );
  }
}

/// Status-Informationen für die UI
class GeofenceStatus {
  final bool isInZone;
  final bool isTracking;
  final GeofenceEventData? lastEvent;
  final int pendingEventsCount;

  GeofenceStatus({
    required this.isInZone,
    required this.isTracking,
    this.lastEvent,
    required this.pendingEventsCount,
  });

  String get statusText {
    if (isTracking) {
      return isInZone ? 'Im Büro - Arbeitszeit läuft' : 'Arbeitszeit läuft';
    } else {
      return isInZone ? 'Im Büro - Nicht gestartet' : 'Außerhalb';
    }
  }
}
