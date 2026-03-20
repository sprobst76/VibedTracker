import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker/services/geofence_event_queue.dart';

/// Helper: erstellt ein Event zu einem bestimmten Zeitpunkt
GeofenceEventData _event(GeofenceEvent type, DateTime time,
    {String zone = 'office'}) {
  return GeofenceEventData(zoneId: zone, event: type, timestamp: time);
}

/// Fester Basis-Timestamp (Montag 08:00)
final _base = DateTime(2026, 1, 12, 8, 0, 0);

DateTime _t(int minutes) => _base.add(Duration(minutes: minutes));

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await GeofenceEventQueue.clear();
  });

  tearDown(() async {
    await GeofenceEventQueue.clear();
  });

  // ── Basis ─────────────────────────────────────────────────────────────────

  group('Basis-Enqueue', () {
    test('Einfaches ENTER wird hinzugefügt', () async {
      final result =
          await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      expect(result, GeofenceEventQueue.resultAdded);
      final queue = await GeofenceEventQueue.getQueue();
      expect(queue.length, 1);
      expect(queue.first.event, GeofenceEvent.enter);
    });

    test('ENTER dann EXIT → beide gespeichert', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));
      final queue = await GeofenceEventQueue.getQueue();
      expect(queue.length, 2);
    });

    test('isCurrentlyInZone() = false wenn Queue leer', () async {
      expect(await GeofenceEventQueue.isCurrentlyInZone(), false);
    });

    test('isCurrentlyInZone() = true nach ENTER', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      expect(await GeofenceEventQueue.isCurrentlyInZone(), true);
    });

    test('isCurrentlyInZone() = false nach EXIT', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));
      expect(await GeofenceEventQueue.isCurrentlyInZone(), false);
    });
  });

  // ── Duplikat-Schutz ───────────────────────────────────────────────────────

  group('Duplikat-Schutz (< 30 Sekunden)', () {
    test('Gleiches ENTER innerhalb 15 sec = Duplikat', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final result = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.enter, _base.add(const Duration(seconds: 15))));
      expect(result, GeofenceEventQueue.resultDuplicate);
      expect((await GeofenceEventQueue.getQueue()).length, 1);
    });

    test('Gleiches ENTER nach 31 sec = kein Duplikat', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final result = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.enter, _base.add(const Duration(seconds: 31))));
      expect(result, GeofenceEventQueue.resultAdded);
    });

    test('Gleiches EXIT kurz nach EXIT = Duplikat', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));
      final result = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.exit, _t(60).add(const Duration(seconds: 5))));
      expect(result, GeofenceEventQueue.resultDuplicate);
    });
  });

  // ── Bounce-Schutz ENTER→EXIT ──────────────────────────────────────────────

  group('Bounce-Schutz: ENTER→EXIT < 20 Minuten', () {
    test('EXIT nach 5 min → BOUNCE', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final r = await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(5)));
      expect(r, GeofenceEventQueue.resultBounce);
      expect((await GeofenceEventQueue.getQueue()).length, 1);
    });

    test('EXIT nach 19 min 59 sec → BOUNCE (knapp unter 20 min)', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final r = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.exit, _base.add(const Duration(seconds: 1199))));
      expect(r, GeofenceEventQueue.resultBounce);
    });

    test('EXIT nach genau 20 min → NICHT gebounced', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final r =
          await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(20)));
      expect(r, GeofenceEventQueue.resultAdded);
    });

    test('EXIT nach 30 min → normal hinzugefügt', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final r =
          await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(30)));
      expect(r, GeofenceEventQueue.resultAdded);
    });

    test('Mehrere gebounce EXITs → Queue enthält nur ENTER', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(3)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(7)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(12)));

      final queue = await GeofenceEventQueue.getQueue();
      expect(queue.where((e) => e.event == GeofenceEvent.exit).length, 0);
    });
  });

  // ── EXIT→ENTER nie gebounced ──────────────────────────────────────────────

  group('Kein Bounce bei EXIT→ENTER (Re-Entry immer erlaubt)', () {
    test('ENTER 1 min nach EXIT → hinzugefügt', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(30)));
      final r =
          await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(31)));
      expect(r, GeofenceEventQueue.resultAdded);
    });

    test('ENTER 2 min nach EXIT → hinzugefügt', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));
      final r =
          await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(62)));
      expect(r, GeofenceEventQueue.resultAdded);
    });
  });

  // ── Zonen-Unabhängigkeit ──────────────────────────────────────────────────

  group('Verschiedene Zonen unabhängig', () {
    test('EXIT in Zone B kurz nach ENTER in Zone A → kein Bounce', () async {
      await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.enter, _t(0), zone: 'office'));
      final r = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.exit, _t(5), zone: 'parking'));
      expect(r, GeofenceEventQueue.resultAdded);
    });

    test('Bounce gilt nur für gleiche Zone', () async {
      await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.enter, _t(0), zone: 'zone_a'));
      final r1 = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.exit, _t(5), zone: 'zone_a'));
      final r2 = await GeofenceEventQueue.enqueue(
          _event(GeofenceEvent.exit, _t(6), zone: 'zone_b'));

      expect(r1, GeofenceEventQueue.resultBounce);
      expect(r2, GeofenceEventQueue.resultAdded);
    });
  });

  // ── Persistenz und Hilfsmethoden ──────────────────────────────────────────

  group('Persistenz', () {
    test('getLastEvent() gibt zuletzt hinzugefügtes Event zurück', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));
      final last = await GeofenceEventQueue.getLastEvent();
      expect(last?.event, GeofenceEvent.exit);
    });

    test('clear() leert Queue und LastEvent', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.clear();
      expect((await GeofenceEventQueue.getQueue()).length, 0);
      expect(await GeofenceEventQueue.getLastEvent(), isNull);
    });

    test('markAsProcessed() markiert Events', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      final events = await GeofenceEventQueue.getQueue();
      await GeofenceEventQueue.markAsProcessed(events);
      expect((await GeofenceEventQueue.getUnprocessedEvents()).length, 0);
    });

    test('getUnprocessedEvents() gibt nur unverarbeitete zurück', () async {
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0)));
      await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(60)));

      final events = await GeofenceEventQueue.getQueue();
      await GeofenceEventQueue.markAsProcessed([events.first]); // Nur ENTER markieren

      final unprocessed = await GeofenceEventQueue.getUnprocessedEvents();
      expect(unprocessed.length, 1);
      expect(unprocessed.first.event, GeofenceEvent.exit);
    });
  });

  // ── GPS-Drift-Realitätstest ───────────────────────────────────────────────

  group('GPS-Drift Realismus-Tests', () {
    test('Drift-Muster: Viele schnelle ENTER/EXIT → meist Bounce', () async {
      final results = <String>[];
      // Tag: 08:00 ENTER
      results.add(await GeofenceEventQueue.enqueue(_event(GeofenceEvent.enter, _t(0))));
      // Drift: kurze Exits
      results.add(await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(2))));
      results.add(await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(7))));
      results.add(await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(13))));
      // Echter Exit erst nach 8 Stunden
      results.add(await GeofenceEventQueue.enqueue(_event(GeofenceEvent.exit, _t(480))));

      expect(results[0], GeofenceEventQueue.resultAdded);   // ENTER OK
      expect(results[1], GeofenceEventQueue.resultBounce);  // 2min → Bounce
      expect(results[2], GeofenceEventQueue.resultBounce);  // 7min → Bounce
      expect(results[3], GeofenceEventQueue.resultBounce);  // 13min → Bounce
      expect(results[4], GeofenceEventQueue.resultAdded);   // 8h → OK

      final queue = await GeofenceEventQueue.getQueue();
      expect(queue.length, 2); // 1 ENTER + 1 EXIT
    });

    test('Problem-Szenario 2026-03-02: Viele kurze Sessions', () async {
      // Simuliert die 19-Row-Fragmentation vom 2026-03-02
      // Format: [type, offsetMinutes]
      final sequenceTypes = [
        GeofenceEvent.enter, // 08:34 → +0 min
        GeofenceEvent.exit,  // 10:23 → +109 min (> 20 min → kein Bounce)
        GeofenceEvent.enter, // 10:23 → +109 min
        GeofenceEvent.enter, // 10:25 → +111 min
        GeofenceEvent.exit,  // 10:32 → +118 min (7 min → Bounce)
        GeofenceEvent.exit,  // 10:45 → +131 min (20 min → kein Bounce)
      ];
      final sequenceOffsets = [0, 109, 109, 111, 118, 131];

      final results = <String>[];
      for (int i = 0; i < sequenceTypes.length; i++) {
        results.add(await GeofenceEventQueue.enqueue(
            _event(sequenceTypes[i], _t(sequenceOffsets[i]))));
      }

      // ENTER 08:34 → added
      expect(results[0], GeofenceEventQueue.resultAdded);
      // EXIT 10:23 → > 20 min → added
      expect(results[1], GeofenceEventQueue.resultAdded);
      // ENTER 10:23 → gleicher Zeitpunkt als EXIT: 0 sec Diff, different event → kein Duplikat (nur same event)
      // Aber duplicate check: lastEvent=EXIT, newEvent=ENTER → different type → kein Duplikat
      // Also: added
      expect(results[2], GeofenceEventQueue.resultAdded);
      // ENTER 10:25 → lastEvent ist ENTER (10:23). 2 min → kein Duplikat. ENTER→ENTER kein Bounce. Added.
      // Actually: 2 min = 120 sec > 30 sec → kein Duplikat. Bounce prüft nur ENTER→EXIT. Added.
      expect(results[3], GeofenceEventQueue.resultAdded);
      // EXIT 10:32 → lastEvent ist ENTER (10:25). 7min < 20min → Bounce
      expect(results[4], GeofenceEventQueue.resultBounce);
      // EXIT 10:45 → lastEvent ist ENTER (10:25). 20min → exakt 20min → kein Bounce (< 1200 sec = 1200 sec)
      // Exakt 20 min = 1200 sec. Bounce Bedingung: timeDiff < 1200. 1200 < 1200 = false → kein Bounce!
      expect(results[5], GeofenceEventQueue.resultAdded);
    });
  });
}
