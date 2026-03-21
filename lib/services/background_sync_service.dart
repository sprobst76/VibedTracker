import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _taskName = 'vibed_bg_sync';
const _lastSyncKey = 'vibed_last_bg_sync';
const _syncNeededKey = 'vibed_sync_needed';

/// WorkManager callback dispatcher – runs in a separate background isolate.
/// Must be a top-level function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void workManagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    log('BackgroundSyncService: task started – $taskName',
        name: 'BackgroundSyncService');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Hive ist nicht thread-safe: Wenn die Box bereits durch die Haupt-App
      // geöffnet ist, darf der Hintergrund-Task sie nicht erneut öffnen.
      // In einem echten Hintergrund-Isolate ist die Box immer geschlossen.
      if (Hive.isBoxOpen('work')) {
        // App läuft im Vordergrund – die App selbst synct die Queue.
        log('BackgroundSyncService: work box already open by main app, skipping',
            name: 'BackgroundSyncService');
        await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
        return Future.value(true);
      }

      // Box ist zu → echter Hintergrund-Isolate.
      // Events in der Queue können nicht verarbeitet werden ohne Hive zu öffnen.
      // Stattdessen: Flag setzen, damit die App beim nächsten Vordergrundkommen
      // sofort einen Sync ausführt.
      final pendingEventCount = (await SharedPreferences.getInstance())
          .getStringList('geofence_event_queue')
          ?.length ?? 0;

      if (pendingEventCount > 0) {
        await prefs.setBool(_syncNeededKey, true);
        log('BackgroundSyncService: $pendingEventCount pending events – '
            'set sync-needed flag for foreground pickup',
            name: 'BackgroundSyncService');
      }

      // Timestamp trotzdem aktualisieren (der Task lief, auch wenn kein Hive-Sync)
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      log('BackgroundSyncService: background check complete',
          name: 'BackgroundSyncService');

      return Future.value(true);
    } catch (e, st) {
      log('BackgroundSyncService: task failed – $e\n$st',
          name: 'BackgroundSyncService');
      return Future.value(false);
    }
  });
}

/// Manages periodic and one-off WorkManager background sync tasks.
class BackgroundSyncService {
  /// Initialises WorkManager with [workManagerCallbackDispatcher].
  ///
  /// Must be called once during app startup (before any task is registered).
  static Future<void> init() async {
    if (kIsWeb) {
      return;
    }
    await Workmanager().initialize(
      workManagerCallbackDispatcher,
      isInDebugMode: false,
    );
    log('BackgroundSyncService: WorkManager initialised',
        name: 'BackgroundSyncService');
  }

  /// Registers a periodic background sync task that runs every 15 minutes.
  ///
  /// Uses [ExistingWorkPolicy.keep] so an already-scheduled task is not
  /// replaced on every app launch.
  static Future<void> registerPeriodicSync() async {
    if (kIsWeb) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    log('BackgroundSyncService: periodic sync registered',
        name: 'BackgroundSyncService');
  }

  /// Schedules a one-off background sync that runs after a 30-second delay.
  ///
  /// Uses [ExistingWorkPolicy.replace] so any previously scheduled immediate
  /// sync is superseded by the new request.
  static Future<void> scheduleImmediateSync() async {
    if (kIsWeb) {
      return;
    }
    await Workmanager().registerOneOffTask(
      'vibed_bg_sync_immediate',
      _taskName,
      initialDelay: const Duration(seconds: 30),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    log('BackgroundSyncService: immediate sync scheduled',
        name: 'BackgroundSyncService');
  }

  /// Gibt zurück ob der Hintergrund-Task einen ausstehenden Sync markiert hat.
  /// Der HomeScreen soll diesen Flag beim Vordergrundkommen prüfen.
  static Future<bool> isSyncNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_syncNeededKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Löscht den "Sync benötigt"-Flag nach erfolgreichem Foreground-Sync.
  static Future<void> clearSyncNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncNeededKey);
  }

  /// Returns the [DateTime] of the last completed background sync, or [null]
  /// if no sync has run yet.
  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_lastSyncKey);
      if (value == null) {
        return null;
      }
      return DateTime.parse(value);
    } catch (e) {
      log('BackgroundSyncService: could not read last sync time – $e',
          name: 'BackgroundSyncService');
      return null;
    }
  }
}
