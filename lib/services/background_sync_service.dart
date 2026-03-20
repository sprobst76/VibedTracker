import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/work_entry.dart';
import '../models/pause.dart';
import './geofence_sync_service.dart';
import './secure_storage_service.dart';

const _taskName = 'vibed_bg_sync';
const _lastSyncKey = 'vibed_last_bg_sync';

/// WorkManager callback dispatcher – runs in a separate background isolate.
/// Must be a top-level function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void workManagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    log('BackgroundSyncService: task started – $taskName',
        name: 'BackgroundSyncService');

    try {
      Box<WorkEntry> workBox;

      if (Hive.isBoxOpen('work')) {
        // Box is already open (should not normally happen in an isolate, but
        // guard against it to avoid HiveError).
        log('BackgroundSyncService: work box already open',
            name: 'BackgroundSyncService');
        workBox = Hive.box<WorkEntry>('work');
      } else {
        // Initialise Hive for the background isolate.
        final appDir = await getApplicationDocumentsDirectory();
        Hive.init(appDir.path);

        // Register adapters if not yet registered.
        if (!Hive.isAdapterRegistered(0)) {
          Hive.registerAdapter(WorkEntryAdapter());
        }
        if (!Hive.isAdapterRegistered(1)) {
          Hive.registerAdapter(PauseAdapter());
        }

        // Try to open the box with encryption first.
        try {
          final secureStorage = SecureStorageService();
          final keyBytes = await secureStorage.getOrCreateHiveKey();
          final cipher = HiveAesCipher(keyBytes);

          workBox = await Hive.openBox<WorkEntry>(
            'work',
            encryptionCipher: cipher,
          );
          log('BackgroundSyncService: opened encrypted work box',
              name: 'BackgroundSyncService');
        } catch (encryptionError) {
          // Fall back to unencrypted if encryption is unavailable.
          log('BackgroundSyncService: encrypted open failed, '
              'falling back to unencrypted – $encryptionError',
              name: 'BackgroundSyncService');
          workBox = await Hive.openBox<WorkEntry>('work');
        }
      }

      // Sync pending geofence events (skip notifications in background).
      final syncService = GeofenceSyncService(
        workBox,
        skipNotifications: true,
      );
      final processed = await syncService.syncPendingEvents();
      log('BackgroundSyncService: syncPendingEvents processed $processed event(s)',
          name: 'BackgroundSyncService');

      // Record the timestamp of this successful sync run.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      log('BackgroundSyncService: updated last sync timestamp',
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
