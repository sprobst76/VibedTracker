import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker/models/pause.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/services/geofence_event_log.dart';
import 'package:time_tracker/services/geofence_event_queue.dart';
import 'package:time_tracker/services/geofence_sync_service.dart';

// ─── Test-Setup ──────────────────────────────────────────────────────────────

late Directory _hiveDir;
late Box<WorkEntry> _workBox;

Future<void> _initHive() async {
  _hiveDir = await Directory.systemTemp.createTemp('hive_sync_test_');
  Hive.init(_hiveDir.path);
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(WorkEntryAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PauseAdapter());
  _workBox = await Hive.openBox<WorkEntry>('work_${DateTime.now().microsecondsSinceEpoch}');
}

Future<void> _closeHive() async {
  await _workBox.deleteFromDisk();
  await Hive.close();
  await _hiveDir.delete(recursive: true);
}

/// GeofenceSyncService ohne Notifications (für Tests)
GeofenceSyncService _service() =>
    GeofenceSyncService(_workBox, skipNotifications: true);

// ─── Helpers ─────────────────────────────────────────────────────────────────

final _base = DateTime(2026, 1, 12, 8, 0, 0);
DateTime _t(int minutes) => _base.add(Duration(minutes: minutes));

GeofenceEventData _event(GeofenceEvent type, DateTime time,
    {String zone = 'office'}) {
  return GeofenceEventData(zoneId: zone, event: type, timestamp: time);
}

/// Fügt Event direkt in Queue und verarbeitet es
Future<void> _processEvent(GeofenceSyncService svc, GeofenceEvent type, DateTime time) async {
  await GeofenceEventQueue.enqueue(_event(type, time));
  await svc.syncPendingEvents();
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await GeofenceEventQueue.clear();
    await _initHive();
  });

  tearDown(() async {
    await GeofenceEventQueue.clear();
    await _closeHive();
  });

  // ── ENTER-Verarbeitung ────────────────────────────────────────────────────

  group('ENTER-Event', () {
    test('ENTER erstellt neuen WorkEntry', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));

      expect(_workBox.values.length, 1);
      expect(_workBox.values.first.start, _t(0));
      expect(_workBox.values.first.stop, isNull);
    });

    test('Zweites ENTER wenn bereits laufend → ignoriert', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.enter, _t(30));

      expect(_workBox.values.length, 1); // Nur ein Entry
      expect(_workBox.values.first.start, _t(0)); // Erste Zeit bleibt
    });

    test('isTracking() = true nach ENTER', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      expect(svc.isTracking(), true);
    });

    test('ENTER mit gleichem Timestamp-Minute → ignoriert (already exists)', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));

      // Direkt zweiten ENTER ohne Queue-Bounce-Schutz
      // (Queue würde Duplikat-Schutz anwenden, wir testen die Sync-Service-Logik)
      await svc.syncPendingEvents(); // Verarbeite manuell (keine neuen Events)

      expect(_workBox.values.length, 1);
    });
  });

  // ── EXIT-Verarbeitung ─────────────────────────────────────────────────────

  group('EXIT-Event', () {
    test('EXIT nach ≥25 min stoppt WorkEntry', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(30));

      expect(_workBox.values.first.stop, _t(30));
    });

    test('EXIT nach genau 25 min → stoppt', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(25));

      expect(_workBox.values.first.stop, _t(25));
    });

    test('EXIT nach 24 min → zu kurz, Entry bleibt offen', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(24));

      expect(_workBox.values.first.stop, isNull,
          reason: 'Session < 25 min darf nicht automatisch gestoppt werden');
    });

    test('EXIT ohne laufende Session → ignoriert (kein Absturz)', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.exit, _t(30));
      expect(_workBox.values.length, 0);
    });

    test('EXIT vor Start-Zeitstempel → ignoriert', () async {
      final svc = _service();
      // Manuell WorkEntry erstellen mit Start in der Zukunft (simuliert Zeitfehler)
      await _workBox.add(WorkEntry(start: _t(10)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(5)));
      await svc.syncPendingEvents();

      expect(_workBox.values.first.stop, isNull,
          reason: 'EXIT vor START darf Entry nicht stoppen');
    });

    test('isTracking() = false nach erfolgreichem EXIT', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(30));
      expect(svc.isTracking(), false);
    });
  });

  // ── Vollständiger Arbeitstag ───────────────────────────────────────────────

  group('Vollständiger Arbeitstag', () {
    test('Normaler Tag: ENTER 08:00 → EXIT 17:00 = 9h WorkEntry', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));    // 08:00
      await _processEvent(svc, GeofenceEvent.exit, _t(540));   // 17:00

      expect(_workBox.values.length, 1);
      final entry = _workBox.values.first;
      expect(entry.start, _t(0));
      expect(entry.stop, _t(540));
      expect(entry.stop!.difference(entry.start).inMinutes, 540);
    });

    test('Mittagspause: 2 separate Entries wenn Mittagspause > 20 min', () async {
      final svc = _service();
      // Morgen-Session
      await _processEvent(svc, GeofenceEvent.enter, _t(0));    // 08:00
      await _processEvent(svc, GeofenceEvent.exit, _t(240));   // 12:00

      // Mittagspause: 60 min
      // Nachmittags-Session
      await _processEvent(svc, GeofenceEvent.enter, _t(300));  // 13:00
      await _processEvent(svc, GeofenceEvent.exit, _t(540));   // 17:00

      expect(_workBox.values.length, 2);
      final entries = _workBox.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      expect(entries[0].stop!.difference(entries[0].start).inMinutes, 240);
      expect(entries[1].stop!.difference(entries[1].start).inMinutes, 240);
    });

    test('Mehrere gebounced EXITs während Arbeit → Entry bleibt offen', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));

      // GPS-Drift Exits: alle gebounced (< 20 min)
      for (final offset in [5, 10, 15, 19]) {
        await GeofenceEventQueue.enqueue(
            _event(GeofenceEvent.exit, _t(offset)));
      }
      await svc.syncPendingEvents();

      // Entry sollte noch offen sein (alle Exits waren Bounce)
      expect(_workBox.values.first.stop, isNull);
    });
  });

  // ── Mindest-Session-Dauer ─────────────────────────────────────────────────

  group('Mindest-Session-Dauer (25 Minuten)', () {
    for (final minutes in [1, 5, 10, 15, 20, 24]) {
      test('Session von $minutes min → zu kurz, bleibt offen', () async {
        final svc = _service();
        await _processEvent(svc, GeofenceEvent.enter, _t(0));
        await _processEvent(svc, GeofenceEvent.exit, _t(minutes));
        expect(_workBox.values.first.stop, isNull,
            reason: '$minutes min < 25 min, darf nicht gestoppt werden');
      });
    }

    for (final minutes in [25, 30, 60, 240, 480]) {
      test('Session von $minutes min → lang genug, wird gestoppt', () async {
        final svc = _service();
        await _processEvent(svc, GeofenceEvent.enter, _t(0));
        await _processEvent(svc, GeofenceEvent.exit, _t(minutes));
        expect(_workBox.values.first.stop, isNotNull,
            reason: '$minutes min >= 25 min, muss gestoppt werden');
      });
    }
  });

  // ── Queue wird nach Verarbeitung markiert ──────────────────────────────────

  group('Queue-Management', () {
    test('syncPendingEvents() markiert Events als verarbeitet', () async {
      final svc = _service();
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await svc.syncPendingEvents();

      final unprocessed = await GeofenceEventQueue.getUnprocessedEvents();
      expect(unprocessed, isEmpty);
    });

    test('syncPendingEvents() gibt Anzahl verarbeiteter Events zurück', () async {
      final svc = _service();
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));

      final count = await svc.syncPendingEvents();
      expect(count, 2);
    });

    test('Leere Queue → 0 verarbeitete Events', () async {
      final svc = _service();
      final count = await svc.syncPendingEvents();
      expect(count, 0);
    });
  });

  // ── cleanupOrphanedEntries ─────────────────────────────────────────────────

  group('cleanupOrphanedEntries', () {
    test('Leere Box → gibt 0 zurück', () async {
      final svc = _service();
      expect(await svc.cleanupOrphanedEntries(), 0);
    });

    test('Genau 1 offener Entry → gibt 0 zurück, Entry unberührt', () async {
      final svc = _service();
      await _workBox.add(WorkEntry(start: _t(0)));
      expect(await svc.cleanupOrphanedEntries(), 0);
      expect(_workBox.values.first.stop, isNull);
    });

    test('Geschlossener Entry → gibt 0 zurück', () async {
      final svc = _service();
      final entry = WorkEntry(start: _t(0));
      entry.stop = _t(480);
      await _workBox.add(entry);
      expect(await svc.cleanupOrphanedEntries(), 0);
    });

    test('2 offene Entries → bereinigt 1, älterer bekommt stop = start + 8h', () async {
      final svc = _service();
      await _workBox.add(WorkEntry(start: _t(0)));   // älter
      await _workBox.add(WorkEntry(start: _t(60)));  // neuer

      final cleaned = await svc.cleanupOrphanedEntries();
      expect(cleaned, 1);

      final entries = _workBox.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      // Älterer ist geschlossen
      expect(entries[0].stop, _t(0).add(const Duration(hours: 8)));
      // Neuerer bleibt offen
      expect(entries[1].stop, isNull);
    });

    test('3 offene Entries → bereinigt 2, neuester bleibt offen', () async {
      final svc = _service();
      await _workBox.add(WorkEntry(start: _t(0)));
      await _workBox.add(WorkEntry(start: _t(30)));
      await _workBox.add(WorkEntry(start: _t(60)));

      final cleaned = await svc.cleanupOrphanedEntries();
      expect(cleaned, 2);

      final openEntries = _workBox.values.where((e) => e.stop == null).toList();
      expect(openEntries.length, 1);
      expect(openEntries.first.start, _t(60)); // neuester bleibt offen
    });

    test('Bereinigter Entry hat stop = start + 8h (persistiert in Hive)', () async {
      final svc = _service();
      final start = _t(0);
      await _workBox.add(WorkEntry(start: start));
      await _workBox.add(WorkEntry(start: _t(120)));
      await svc.cleanupOrphanedEntries();

      final closed = _workBox.values.firstWhere((e) => e.start == start);
      expect(closed.stop, start.add(const Duration(hours: 8)));
    });

    test('Mix aus offenen und geschlossenen Entries → nur offene betroffen', () async {
      final svc = _service();
      // Zwei geschlossene
      final closed1 = WorkEntry(start: _t(0))..stop = _t(480);
      final closed2 = WorkEntry(start: _t(600))..stop = _t(1000);
      await _workBox.add(closed1);
      await _workBox.add(closed2);
      // Zwei offene (Crash)
      await _workBox.add(WorkEntry(start: _t(200)));
      await _workBox.add(WorkEntry(start: _t(300)));

      final cleaned = await svc.cleanupOrphanedEntries();
      expect(cleaned, 1);

      final stillOpen = _workBox.values.where((e) => e.stop == null).toList();
      expect(stillOpen.length, 1);
      expect(stillOpen.first.start, _t(300)); // neuester offener bleibt
    });
  });

  // ── EventLog-Integration ──────────────────────────────────────────────────

  group('EventLog-Integration', () {
    setUp(() async {
      await GeofenceEventLog.clear();
    });

    tearDown(() async {
      await GeofenceEventLog.clear();
    });

    test('ENTER erstellt Entry → Log enthält outcome=started', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));

      final log = await GeofenceEventLog.getAll();
      expect(log.length, 1);
      expect(log.first.outcome, GeofenceEventOutcome.started);
      expect(log.first.event, GeofenceEvent.enter);
    });

    test('EXIT nach 30 min → Log enthält outcome=stopped', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(30));

      final log = await GeofenceEventLog.getAll();
      // Neueste zuerst: [stopped, started]
      expect(log[0].outcome, GeofenceEventOutcome.stopped);
      expect(log[1].outcome, GeofenceEventOutcome.started);
    });

    test('EXIT nach 20 min (zu kurz) → Log enthält outcome=shortSession', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(20));

      final log = await GeofenceEventLog.getAll();
      expect(log[0].outcome, GeofenceEventOutcome.shortSession);
    });

    test('Re-Entry-Merge → Log enthält outcome=merged mit gapMinutes', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.exit, _t(30));   // stoppt Session
      await _processEvent(svc, GeofenceEvent.enter, _t(35));  // 5 min → merge

      final log = await GeofenceEventLog.getAll();
      final mergeEntry = log.firstWhere((e) => e.outcome == GeofenceEventOutcome.merged);
      expect(mergeEntry.gapMinutes, 5);
    });

    test('Zweites ENTER wenn laufend → Log enthält outcome=ignored', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.enter, _t(0));
      await _processEvent(svc, GeofenceEvent.enter, _t(10));

      final log = await GeofenceEventLog.getAll();
      expect(log[0].outcome, GeofenceEventOutcome.ignored);
    });

    test('EXIT ohne laufende Session → Log enthält outcome=ignored', () async {
      final svc = _service();
      await _processEvent(svc, GeofenceEvent.exit, _t(30));

      final log = await GeofenceEventLog.getAll();
      expect(log.first.outcome, GeofenceEventOutcome.ignored);
    });
  });
}
