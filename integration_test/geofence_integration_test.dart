/// Geofence Integration Tests – laufen auf echtem Gerät / Emulator
///
/// Ausführen mit:
///   flutter test integration_test/geofence_integration_test.dart
///
/// Diese Tests prüfen den vollständigen Ablauf auf dem echten Gerät:
/// Queue → SyncService → Hive → UI. Sie verwenden KEINE Mocks für
/// SharedPreferences und Hive, sondern die echten Implementierungen.
///
/// Voraussetzung: Verbundenes Gerät oder Emulator mit `flutter devices`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker/models/pause.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/services/geofence_event_log.dart';
import 'package:time_tracker/services/geofence_event_queue.dart';
import 'package:time_tracker/services/geofence_sync_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

late Box<WorkEntry> _workBox;
late GeofenceSyncService _svc;
late Directory _hiveDir;

final _base = DateTime(2026, 1, 12, 8, 0, 0);
DateTime _t(int minutes) => _base.add(Duration(minutes: minutes));

Future<void> _setup() async {
  // Echtes SharedPreferences leeren (auf Gerät)
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await GeofenceEventQueue.clear();
  await GeofenceEventLog.clear();

  // Echtes Hive in temporärem Verzeichnis
  final appDir = await getApplicationDocumentsDirectory();
  _hiveDir = Directory('${appDir.path}/integration_test_${DateTime.now().microsecondsSinceEpoch}');
  await _hiveDir.create(recursive: true);
  Hive.init(_hiveDir.path);

  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(WorkEntryAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PauseAdapter());

  _workBox = await Hive.openBox<WorkEntry>('work_integration_test');
  _svc = GeofenceSyncService(_workBox, skipNotifications: true);
}

Future<void> _teardown() async {
  await GeofenceEventQueue.clear();
  await GeofenceEventLog.clear();
  if (_workBox.isOpen) {
    await _workBox.deleteFromDisk();
  }
  await Hive.close();
  if (await _hiveDir.exists()) {
    await _hiveDir.delete(recursive: true);
  }
}

Future<void> _enter(DateTime t) async {
  await GeofenceEventQueue.enqueue(
    GeofenceEventData(zoneId: 'office', event: GeofenceEvent.enter, timestamp: t),
  );
  await _svc.syncPendingEvents();
}

Future<void> _exit(DateTime t) async {
  await GeofenceEventQueue.enqueue(
    GeofenceEventData(zoneId: 'office', event: GeofenceEvent.exit, timestamp: t),
  );
  await _svc.syncPendingEvents();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(_setup);
  tearDown(_teardown);

  // ── Normaler Arbeitstag (End-to-End auf Gerät) ─────────────────────────────

  group('Normaler Arbeitstag (E2E auf Gerät)', () {
    testWidgets('ENTER → EXIT → 1 WorkEntry in Hive', (tester) async {
      await _enter(_t(0));
      await _exit(_t(480));

      expect(_workBox.values.length, 1);
      final entry = _workBox.values.first;
      expect(entry.start, _t(0));
      expect(entry.stop, _t(480));
    });

    testWidgets('EventLog enthält started + stopped', (tester) async {
      await _enter(_t(0));
      await _exit(_t(480));

      final log = await GeofenceEventLog.getAll();
      expect(log.any((e) => e.outcome == GeofenceEventOutcome.started), isTrue);
      expect(log.any((e) => e.outcome == GeofenceEventOutcome.stopped), isTrue);
    });
  });

  // ── GPS-Drift + Re-Entry-Merge (E2E auf Gerät) ────────────────────────────

  group('GPS-Drift + Re-Entry-Merge (E2E auf Gerät)', () {
    testWidgets('Exit nach 30 min + Re-Entry nach 5 min → 1 Entry', (tester) async {
      await _enter(_t(0));
      await _exit(_t(30));    // Stoppt Session (> 25 min)
      await _enter(_t(35));   // 5 min → Merge (< 25 min Grace-Period)
      await _exit(_t(480));

      expect(_workBox.values.length, 1);
      expect(_workBox.values.first.start, _t(0));
      expect(_workBox.values.first.stop, _t(480));
    });

    testWidgets('EventLog enthält merged-Eintrag mit korrektem gapMinutes',
        (tester) async {
      await _enter(_t(0));
      await _exit(_t(30));
      await _enter(_t(35));   // 5 min Lücke
      await _exit(_t(480));

      final log = await GeofenceEventLog.getAll();
      final merge = log.where((e) => e.outcome == GeofenceEventOutcome.merged);
      expect(merge.length, 1);
      expect(merge.first.gapMinutes, 5);
    });
  });

  // ── Crash-Recovery (E2E auf Gerät) ────────────────────────────────────────

  group('Crash-Recovery: cleanupOrphanedEntries (E2E auf Gerät)', () {
    testWidgets('2 offene Entries → cleanup bereinigt einen', (tester) async {
      await _workBox.add(WorkEntry(start: _t(0)));
      await _workBox.add(WorkEntry(start: _t(10)));

      final cleaned = await _svc.cleanupOrphanedEntries();
      expect(cleaned, 1);
      expect(_workBox.values.where((e) => e.stop == null).length, 1);
    });
  });

  // ── Queue-Persistenz (E2E auf Gerät) ──────────────────────────────────────

  group('Queue-Persistenz (E2E auf Gerät)', () {
    testWidgets('Events in Queue überleben syncPendingEvents()', (tester) async {
      await GeofenceEventQueue.enqueue(
        GeofenceEventData(zoneId: 'office', event: GeofenceEvent.enter, timestamp: _t(0)),
      );
      await GeofenceEventQueue.enqueue(
        GeofenceEventData(zoneId: 'office', event: GeofenceEvent.exit, timestamp: _t(480)),
      );

      final count = await _svc.syncPendingEvents();
      expect(count, 2);

      final unprocessed = await GeofenceEventQueue.getUnprocessedEvents();
      expect(unprocessed, isEmpty);
    });

    testWidgets('Nach Sync: isCurrentlyInZone() korrekt', (tester) async {
      await _enter(_t(0));
      expect(await GeofenceEventQueue.isCurrentlyInZone(), isTrue);

      await _exit(_t(480));
      expect(await GeofenceEventQueue.isCurrentlyInZone(), isFalse);
    });
  });
}
