import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker/services/geofence_event_log.dart';
import 'package:time_tracker/services/geofence_event_queue.dart';

final _base = DateTime(2026, 1, 12, 8, 0, 0);
DateTime _t(int minutes) => _base.add(Duration(minutes: minutes));

GeofenceEventLogEntry _entry({
  required GeofenceEvent event,
  required GeofenceEventOutcome outcome,
  int minuteOffset = 0,
  int? gapMinutes,
}) {
  return GeofenceEventLogEntry(
    timestamp: _t(minuteOffset),
    event: event,
    zoneId: 'office',
    outcome: outcome,
    gapMinutes: gapMinutes,
  );
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await GeofenceEventLog.clear();
  });

  tearDown(() async {
    await GeofenceEventLog.clear();
  });

  // ── Basis ─────────────────────────────────────────────────────────────────

  group('Basis', () {
    test('Leerer Log → getAll() gibt leere Liste', () async {
      expect(await GeofenceEventLog.getAll(), isEmpty);
    });

    test('append() fügt Eintrag hinzu', () async {
      await GeofenceEventLog.append(
        _entry(event: GeofenceEvent.enter, outcome: GeofenceEventOutcome.started),
      );
      final all = await GeofenceEventLog.getAll();
      expect(all.length, 1);
      expect(all.first.outcome, GeofenceEventOutcome.started);
    });

    test('Neueste Einträge stehen vorne (prepend)', () async {
      await GeofenceEventLog.append(
        _entry(event: GeofenceEvent.enter, outcome: GeofenceEventOutcome.started, minuteOffset: 0),
      );
      await GeofenceEventLog.append(
        _entry(event: GeofenceEvent.exit, outcome: GeofenceEventOutcome.stopped, minuteOffset: 60),
      );
      final all = await GeofenceEventLog.getAll();
      expect(all.length, 2);
      // Neuester zuerst
      expect(all[0].outcome, GeofenceEventOutcome.stopped);
      expect(all[1].outcome, GeofenceEventOutcome.started);
    });

    test('clear() leert den Log vollständig', () async {
      await GeofenceEventLog.append(
        _entry(event: GeofenceEvent.enter, outcome: GeofenceEventOutcome.started),
      );
      await GeofenceEventLog.clear();
      expect(await GeofenceEventLog.getAll(), isEmpty);
    });
  });

  // ── Rotation auf maxEntries ────────────────────────────────────────────────

  group('Rotation', () {
    test('Nach ${GeofenceEventLog.maxEntries} Einträgen: genau maxEntries vorhanden', () async {
      for (int i = 0; i <= GeofenceEventLog.maxEntries; i++) {
        await GeofenceEventLog.append(
          _entry(
            event: GeofenceEvent.enter,
            outcome: GeofenceEventOutcome.ignored,
            minuteOffset: i,
          ),
        );
      }
      final all = await GeofenceEventLog.getAll();
      expect(all.length, GeofenceEventLog.maxEntries);
    });

    test('Ältester Eintrag wird bei Überlauf entfernt', () async {
      // Erst maxEntries Einträge mit outcome=started hinzufügen
      for (int i = 0; i < GeofenceEventLog.maxEntries; i++) {
        await GeofenceEventLog.append(
          _entry(
            event: GeofenceEvent.enter,
            outcome: GeofenceEventOutcome.started,
            minuteOffset: i,
          ),
        );
      }
      // Dann einen mit outcome=stopped (wird neuester = ganz vorne)
      await GeofenceEventLog.append(
        _entry(
          event: GeofenceEvent.exit,
          outcome: GeofenceEventOutcome.stopped,
          minuteOffset: GeofenceEventLog.maxEntries,
        ),
      );

      final all = await GeofenceEventLog.getAll();
      expect(all.length, GeofenceEventLog.maxEntries);
      // Neuester (stopped) steht vorne
      expect(all.first.outcome, GeofenceEventOutcome.stopped);
      // Kein Eintrag hat outcome=started mit dem allerersten Timestamp
      // (er wurde rausrotiert; der letzte Eintrag ist der zweitälteste started)
      final timestamps = all.map((e) => e.timestamp).toList();
      expect(timestamps.contains(_t(0)), isFalse,
          reason: 'Ältester Eintrag (t=0) muss rausrotiert worden sein');
    });
  });

  // ── JSON Round-Trip ───────────────────────────────────────────────────────

  group('JSON-Persistenz', () {
    test('Alle GeofenceEventOutcome-Werte werden korrekt serialisiert', () async {
      for (final outcome in GeofenceEventOutcome.values) {
        await GeofenceEventLog.clear();
        await GeofenceEventLog.append(
          _entry(event: GeofenceEvent.enter, outcome: outcome),
        );
        final loaded = await GeofenceEventLog.getAll();
        expect(loaded.first.outcome, outcome,
            reason: 'Round-trip für $outcome fehlgeschlagen');
      }
    });

    test('gapMinutes wird korrekt gespeichert und geladen', () async {
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: _t(0),
        event: GeofenceEvent.enter,
        zoneId: 'office',
        outcome: GeofenceEventOutcome.merged,
        gapMinutes: 7,
      ));
      final loaded = await GeofenceEventLog.getAll();
      expect(loaded.first.gapMinutes, 7);
    });

    test('gapMinutes ist null wenn nicht gesetzt', () async {
      await GeofenceEventLog.append(
        _entry(event: GeofenceEvent.enter, outcome: GeofenceEventOutcome.started),
      );
      final loaded = await GeofenceEventLog.getAll();
      expect(loaded.first.gapMinutes, isNull);
    });

    test('Timestamp wird exakt gespeichert und geladen', () async {
      final ts = DateTime(2026, 3, 21, 9, 34, 56);
      await GeofenceEventLog.append(GeofenceEventLogEntry(
        timestamp: ts,
        event: GeofenceEvent.exit,
        zoneId: 'parking',
        outcome: GeofenceEventOutcome.stopped,
      ));
      final loaded = await GeofenceEventLog.getAll();
      expect(loaded.first.timestamp, ts);
      expect(loaded.first.zoneId, 'parking');
    });
  });

  // ── Mehrere Aufrufe ohne clear ─────────────────────────────────────────────

  group('Akkumulation', () {
    test('10 Einträge nacheinander → alle gespeichert in richtiger Reihenfolge', () async {
      for (int i = 0; i < 10; i++) {
        await GeofenceEventLog.append(
          _entry(event: GeofenceEvent.enter, outcome: GeofenceEventOutcome.ignored, minuteOffset: i),
        );
      }
      final all = await GeofenceEventLog.getAll();
      expect(all.length, 10);
      // Neuester zuerst: offset 9, dann 8, ..., 0
      for (int i = 0; i < 10; i++) {
        expect(all[i].timestamp, _t(9 - i));
      }
    });
  });
}
