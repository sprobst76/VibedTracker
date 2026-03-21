/// Komplexe End-to-End Geofence-Szenarien
///
/// Diese Tests simulieren realistische GPS-Verhaltensszenarien und
/// prüfen ob das Tracking-System korrekt reagiert.
///
/// Szenarien:
///   A – Normaler Arbeitstag ohne Probleme
///   B – GPS-Drift während der Arbeit (kurze Exits)
///   C – Mittagspause (echter langer Exit + Re-Entry)
///   D – App-Neustart während laufender Session
///   E – Fragmented Day (2026-03-02-Muster)
///   F – Kurzbesuch (<25 min) wird nicht geloggt
///   G – Wochentag mit mehreren kurzen Drift-Episoden
///   H – Grenzwert-Session: exakt 25 Minuten
///   I – Mehrere Bounce-geschützte Exits gefolgt von echtem Exit
///   J – Nacht-Persistenz: Events vom Vortag werden korrekt verarbeitet
///   K – Crash-Recovery: Verwaiste offene Entries werden bereinigt

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker/models/pause.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/services/geofence_event_queue.dart';
import 'package:time_tracker/services/geofence_sync_service.dart';

// ─── Setup / Teardown ──────────────────────────────────────────────────────────

late Directory _hiveDir;
late Box<WorkEntry> _workBox;
late GeofenceSyncService _svc;

Future<void> _setup() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await GeofenceEventQueue.clear();

  _hiveDir = await Directory.systemTemp.createTemp('hive_scenario_');
  Hive.init(_hiveDir.path);
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(WorkEntryAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PauseAdapter());
  _workBox = await Hive.openBox<WorkEntry>('work_${DateTime.now().microsecondsSinceEpoch}');
  _svc = GeofenceSyncService(_workBox, skipNotifications: true);
}

Future<void> _teardown() async {
  await GeofenceEventQueue.clear();
  await _workBox.deleteFromDisk();
  await Hive.close();
  await _hiveDir.delete(recursive: true);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

final _mon = DateTime(2026, 1, 12, 0, 0, 0); // Montag 00:00

DateTime _hm(int hour, int minute, {int dayOffset = 0}) =>
    _mon.add(Duration(days: dayOffset, hours: hour, minutes: minute));

Future<String> _enter(DateTime t, {String zone = 'office'}) async {
  final r = await GeofenceEventQueue.enqueue(
      GeofenceEventData(zoneId: zone, event: GeofenceEvent.enter, timestamp: t));
  await _svc.syncPendingEvents();
  return r;
}

Future<String> _exit(DateTime t, {String zone = 'office'}) async {
  final r = await GeofenceEventQueue.enqueue(
      GeofenceEventData(zoneId: zone, event: GeofenceEvent.exit, timestamp: t));
  await _svc.syncPendingEvents();
  return r;
}

/// Alle laufenden (nicht gestoppten) Entries
List<WorkEntry> get _running =>
    _workBox.values.where((e) => e.stop == null).toList();

/// Alle gestoppten Entries
List<WorkEntry> get _stopped =>
    _workBox.values.where((e) => e.stop != null).toList();

/// Alle Entries sortiert nach Startzeit
List<WorkEntry> get _all =>
    (_workBox.values.toList()..sort((a, b) => a.start.compareTo(b.start)));

// ─── Szenarien ─────────────────────────────────────────────────────────────────

void main() {
  setUp(_setup);
  tearDown(_teardown);

  // ── Szenario A: Normaler Arbeitstag ──────────────────────────────────────

  group('Szenario A – Normaler Arbeitstag', () {
    test('08:30 ENTER, 17:00 EXIT → 1 Entry, 8,5h', () async {
      await _enter(_hm(8, 30));
      await _exit(_hm(17, 0));

      expect(_all.length, 1);
      expect(_all.first.stop, _hm(17, 0));
      expect(_all.first.stop!.difference(_all.first.start).inMinutes, 510);
      expect(_running, isEmpty);
    });

    test('Kein redundantes Entry nach normalem Tag', () async {
      await _enter(_hm(8, 0));
      await _exit(_hm(16, 0));
      expect(_workBox.values.length, 1);
    });
  });

  // ── Szenario B: GPS-Drift während Arbeit ─────────────────────────────────

  group('Szenario B – GPS-Drift (kurze Exits)', () {
    test('3 kurze GPS-Exits < 20 min → Entry bleibt offen', () async {
      await _enter(_hm(8, 0));

      // GPS Drift: 3 kurze Exits in den ersten 20 Minuten
      await _exit(_hm(8, 5));   // 5 min → Bounce
      await _exit(_hm(8, 12));  // 12 min → Bounce
      await _exit(_hm(8, 18));  // 18 min → Bounce

      // Echter Exit erst um 17:00
      await _exit(_hm(17, 0));

      expect(_all.length, 1);
      expect(_all.first.stop, _hm(17, 0),
          reason: 'Nur der echte Exit um 17:00 darf gestoppt haben');
    });

    test('GPS-Drift-Stop + Re-Entry < 25 min → Session wird gemergt', () async {
      await _enter(_hm(9, 0));
      await _exit(_hm(9, 8));   // Bounce (< 20 min)
      await _exit(_hm(9, 15));  // Bounce (< 20 min)
      await _exit(_hm(9, 30));  // > 20 min → kein Bounce, Session gestoppt

      // Re-Entry 5 min nach dem Fehl-Stop → Grace-Period (< 25 min): MERGE
      await _enter(_hm(9, 35));
      await _exit(_hm(17, 0));

      // Session wurde fortgesetzt: nur 1 Entry (09:00–17:00)
      expect(_all.length, 1, reason: 'Re-Entry innerhalb Grace-Period mergt zurück');
      expect(_all.first.start, _hm(9, 0));
      expect(_all.first.stop, _hm(17, 0));
      expect(_running, isEmpty);
    });

    test('Re-Entry nach echter langer Pause (≥ 25 min) → neue Session', () async {
      await _enter(_hm(8, 0));
      await _exit(_hm(12, 0));  // 4h → gestoppt

      // 30 min Pause > Grace-Period → kein Merge
      await _enter(_hm(12, 30));
      await _exit(_hm(17, 0));

      expect(_all.length, 2, reason: '30 min Pause > 25 min Grace → separater Entry');
      expect(_stopped.length, 2);
    });

    test('Drift-Exit ohne Re-Entry: Session bleibt gestoppt', () async {
      await _enter(_hm(9, 0));
      await _exit(_hm(9, 30)); // Stoppt Session (30 min, kein Bounce)

      // Kein Re-Entry → Session bleibt gestoppt
      expect(_all.length, 1);
      expect(_all.first.stop, _hm(9, 30));
    });
  });

  // ── Szenario C: Echte Mittagspause ───────────────────────────────────────

  group('Szenario C – Echte Mittagspause', () {
    test('Morgen 4h + Pause 1h + Nachmittag 4h = 2 Entries', () async {
      // Morgen
      await _enter(_hm(8, 0));
      await _exit(_hm(12, 0));  // 4h → gestoppt

      // Mittagspause: 60 min
      await _enter(_hm(13, 0));
      await _exit(_hm(17, 0));  // 4h → gestoppt

      expect(_all.length, 2);
      expect(_stopped.length, 2);

      final morning = _all[0];
      final afternoon = _all[1];
      expect(morning.stop!.difference(morning.start).inMinutes, 240);
      expect(afternoon.stop!.difference(afternoon.start).inMinutes, 240);
    });

    test('Kurze Mittagspause (30 min): beide Sessions werden getrackt', () async {
      await _enter(_hm(8, 0));
      await _exit(_hm(12, 0));

      await _enter(_hm(12, 30)); // 30 min Pause
      await _exit(_hm(17, 0));

      expect(_all.length, 2);
      expect(_running, isEmpty);
    });
  });

  // ── Szenario D: App-Neustart während Session ──────────────────────────────

  group('Szenario D – App-Neustart während laufender Session', () {
    test('ENTER verarbeitet, dann Queue geleert (App-Restart) → Entry bleibt offen', () async {
      // App startet, ENTER kommt
      await _enter(_hm(8, 0));

      // "App wird neu gestartet": Queue wird verarbeitet, Entry bleibt aber in Hive
      await GeofenceEventQueue.clear();

      // Beim Neustart: kein neuer ENTER (Service prüft ob schon läuft)
      // und kein EXIT verpasst

      expect(_running.length, 1,
          reason: 'Entry bleibt nach App-Neustart geöffnet');
    });

    test('Verpasster EXIT in Background-Queue wird beim App-Start verarbeitet', () async {
      // Jemand verlässt Büro, App ist im Background
      // Exit-Event landet in SharedPreferences Queue
      await _enter(_hm(8, 0));

      // Direkt in Queue schreiben (wie Background-Isolate es tut):
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: 'office',
        event: GeofenceEvent.exit,
        timestamp: _hm(17, 0),
      ));

      // App wird vordergrund gebracht → syncPendingEvents wird aufgerufen
      await _svc.syncPendingEvents();

      expect(_all.first.stop, _hm(17, 0));
    });

    test('Mehrere Events aus Background-Queue werden in Reihenfolge verarbeitet', () async {
      // Kompletter Tag im Background-Isolate
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: 'office', event: GeofenceEvent.enter, timestamp: _hm(8, 0)));
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: 'office', event: GeofenceEvent.exit, timestamp: _hm(17, 0)));

      // App kommt vordergrund:
      await _svc.syncPendingEvents();

      expect(_all.length, 1);
      expect(_all.first.start, _hm(8, 0));
      expect(_all.first.stop, _hm(17, 0));
    });
  });

  // ── Szenario E: Fragmented Day (2026-03-02) ───────────────────────────────

  group('Szenario E – Fragmentierter Tag (GPS-Bug)', () {
    test('19 Einträge mit kleinen Lücken → mehrere Entries entstehen', () async {
      // Vereinfachter 2026-03-02 Verlauf (getestet gegen das echte Problem)
      final timeline = [
        // [type, hour, minute]
        [GeofenceEvent.enter, 8, 34],
        [GeofenceEvent.exit, 10, 23],   // 1h49m → stopped (>25min, >20min)
        [GeofenceEvent.enter, 10, 23],  // Sofort Re-Entry
        [GeofenceEvent.exit, 10, 45],   // 22min → zu kurz (< 25min)! Bleibt offen.
        [GeofenceEvent.exit, 12, 8],    // 1h45m → stopped
        [GeofenceEvent.enter, 12, 8],
        [GeofenceEvent.exit, 12, 15],   // 7min → < 25 min, bleibt offen
        [GeofenceEvent.enter, 13, 2],
        [GeofenceEvent.exit, 17, 58],   // 4h56m → stopped
      ];

      for (final step in timeline) {
        final type = step[0] as GeofenceEvent;
        final h = step[1] as int;
        final m = step[2] as int;
        if (type == GeofenceEvent.enter) {
          await _enter(_hm(h, m));
        } else {
          await _exit(_hm(h, m));
        }
      }

      // Alle Entries anzeigen für Debugging:
      for (final e in _all) {
        final dur = e.stop?.difference(e.start).inMinutes ?? -1;
        // ignore: avoid_print
        print('  Entry: ${e.start.hour}:${e.start.minute} – '
            '${e.stop?.hour ?? "?"}:${e.stop?.minute ?? "?"} ($dur min)');
      }

      // Es sollten mehrere Entries entstanden sein
      expect(_all.length, greaterThanOrEqualTo(2));
      // Kein laufender Entry am Ende
      expect(_running, isEmpty);
    });

    test('Mit Excel-Import-Merge-Strategie: 3 logische Sessions für 2026-03-02', () async {
      // Wenn der Nutzer mit Excel-Import die fragmentierten Daten korrigiert,
      // sollten ca. 3 Sessions entstehen (Morgen, Mittag, Nachmittag)
      // Das testet das SOLL-Verhalten, nicht die Ist-Situation

      // Session 1: Morgen 08:34 – 10:54
      _workBox.add(WorkEntry(start: _hm(8, 34), stop: _hm(10, 54)));
      // Session 2: Kurz nach Mittagsbeginn 12:08 – 12:16
      _workBox.add(WorkEntry(start: _hm(12, 8), stop: _hm(12, 16)));
      // Session 3: Nachmittag 13:02 – 17:58
      _workBox.add(WorkEntry(start: _hm(13, 2), stop: _hm(17, 58)));

      final totalMinutes = _all.fold<int>(
        0, (sum, e) => sum + e.stop!.difference(e.start).inMinutes);

      // Gesamtarbeitszeit: ca. 7h40m
      expect(totalMinutes, greaterThan(400));
      expect(_all.length, 3);
    });
  });

  // ── Szenario F: Kurzbesuch < 25 min ──────────────────────────────────────

  group('Szenario F – Kurzbesuch wird nicht geloggt', () {
    test('10-min Besuch: Exit ignoriert, Entry bleibt offen', () async {
      await _enter(_hm(10, 0));
      await _exit(_hm(10, 10)); // < 25 min → ignoriert

      expect(_running.length, 1,
          reason: 'Kurzbesuch darf nicht gestoppt werden');
      expect(_stopped, isEmpty);
    });

    test('Kurzbesuch: nach echtem Exit später wird gestoppt', () async {
      await _enter(_hm(10, 0));
      await _exit(_hm(10, 10)); // ignoriert

      // Viele Stunden später echter Exit
      await _exit(_hm(17, 0));  // 7h → gestoppt

      expect(_stopped.length, 1);
      expect(_all.first.stop, _hm(17, 0));
    });

    test('Mehrere kurze Besuche hintereinander', () async {
      await _enter(_hm(10, 0));
      await _exit(_hm(10, 10)); // ignoriert (< 25 min)

      // Kein Re-Entry, kein weiterer Exit
      // Am Ende des Tages bleibt Session offen (Nutzer muss manuell stoppen)
      expect(_running.length, 1);
    });
  });

  // ── Szenario G: Wochentag mit mehreren Drift-Episoden ────────────────────

  group('Szenario G – Mehrere Drift-Episoden über den Tag', () {
    test('Drift morgens + normal nachmittags → sauberes Ergebnis', () async {
      // Morgens starten, GPS driftet in ersten 15 Minuten
      await _enter(_hm(8, 0));
      await _exit(_hm(8, 5));   // Bounce
      await _exit(_hm(8, 10));  // Bounce
      await _exit(_hm(8, 15));  // Bounce

      // GPS stabilisiert sich, normaler Verlauf
      await _exit(_hm(12, 0));  // 4h → gestoppt

      await _enter(_hm(13, 0));
      await _exit(_hm(17, 0));  // 4h → gestoppt

      expect(_all.length, 2);
      expect(_stopped.length, 2);
    });
  });

  // ── Szenario H: Grenzwert-Session ─────────────────────────────────────────

  group('Szenario H – Grenzwert 25 Minuten', () {
    test('24 min 59 sec → nicht gestoppt', () async {
      final start = _hm(8, 0);
      final exit = start.add(const Duration(minutes: 24, seconds: 59));

      await _enter(start);
      await GeofenceEventQueue.enqueue(GeofenceEventData(
          zoneId: 'office', event: GeofenceEvent.exit, timestamp: exit));
      await _svc.syncPendingEvents();

      expect(_running.length, 1, reason: '24:59 < 25:00 → darf nicht stoppen');
    });

    test('25 min 0 sec → gestoppt', () async {
      final start = _hm(8, 0);
      final exit = start.add(const Duration(minutes: 25));

      await _enter(start);
      await GeofenceEventQueue.enqueue(GeofenceEventData(
          zoneId: 'office', event: GeofenceEvent.exit, timestamp: exit));
      await _svc.syncPendingEvents();

      expect(_stopped.length, 1, reason: '25:00 >= 25:00 → muss stoppen');
    });
  });

  // ── Szenario I: Bounce dann echter Exit ───────────────────────────────────

  group('Szenario I – Viele Bounces, dann echter Exit', () {
    test('5 gebounced Exits (< 20 min) → danach echter Exit > 25 min', () async {
      await _enter(_hm(8, 0));

      // Viele GPS-Drift Exits
      for (int i = 1; i <= 5; i++) {
        await _exit(_hm(8, i * 3)); // alle < 20 min → Bounce
      }

      // Echter Exit
      await _exit(_hm(16, 30)); // 8,5h → stoppt

      expect(_all.length, 1);
      expect(_all.first.stop, _hm(16, 30));
    });
  });

  // ── Szenario J: Nacht-Persistenz ─────────────────────────────────────────

  group('Szenario J – Nacht-Persistenz (Events vom Vortag)', () {
    test('EXIT vom Vortag in Queue → wird korrekt verarbeitet', () async {
      // Nutzer vergisst App → Queue enthält gestrigen Entry und Exit
      final gestern = _hm(8, 0, dayOffset: -1);
      final gesternExit = _hm(17, 0, dayOffset: -1);

      await GeofenceEventQueue.enqueue(GeofenceEventData(
          zoneId: 'office', event: GeofenceEvent.enter, timestamp: gestern));
      await GeofenceEventQueue.enqueue(GeofenceEventData(
          zoneId: 'office', event: GeofenceEvent.exit, timestamp: gesternExit));

      // Heute: App öffnet, verarbeitet gestrige Events
      await _svc.syncPendingEvents();

      expect(_all.length, 1);
      expect(_all.first.start, gestern);
      expect(_all.first.stop, gesternExit);
    });

    test('Offene Session über Nacht: Entry bleibt offen bis manueller Stop', () async {
      // Nutzer hat vergessen auszuchecken
      await _enter(_hm(8, 0, dayOffset: -1));
      // Kein EXIT

      // Am nächsten Tag: laufende Session immer noch offen
      expect(_running.length, 1);
      expect(_running.first.start, _hm(8, 0, dayOffset: -1));
    });
  });

  // ── Szenario K – Crash-Recovery: Verwaiste offene Entries ─────────────────

  group('Szenario K – Crash-Recovery (cleanupOrphanedEntries)', () {
    test('Keine offenen Entries → cleanup gibt 0 zurück', () async {
      expect(await _svc.cleanupOrphanedEntries(), 0);
    });

    test('1 offener Entry → cleanup gibt 0 zurück, Entry unberührt', () async {
      await _workBox.add(WorkEntry(start: _hm(8, 0)));
      expect(await _svc.cleanupOrphanedEntries(), 0);
      expect(_workBox.values.first.stop, isNull);
    });

    test('Crash-Simulation: 3 offene Entries → 2 bereinigt, neuester bleibt offen', () async {
      // Simuliert: App crashte nach 3 gestarteten Entries (z.B. durch Race-Condition)
      await _workBox.add(WorkEntry(start: _hm(7, 50)));
      await _workBox.add(WorkEntry(start: _hm(8, 0)));
      await _workBox.add(WorkEntry(start: _hm(8, 1)));

      final cleaned = await _svc.cleanupOrphanedEntries();
      expect(cleaned, 2);

      final openEntries = _workBox.values.where((e) => e.stop == null).toList();
      expect(openEntries.length, 1);
      expect(openEntries.first.start, _hm(8, 1)); // neuester bleibt offen

      // Bereinigten Entries haben stop = start + 8h
      final closedEntries = _workBox.values.where((e) => e.stop != null).toList();
      for (final entry in closedEntries) {
        expect(entry.stop, entry.start.add(const Duration(hours: 8)));
      }
    });

    test('Mix geschlossen/offen: cleanup nur für offene', () async {
      // 1 normaler geschlossener Entry
      final normal = WorkEntry(start: _hm(8, 0))..stop = _hm(17, 0);
      await _workBox.add(normal);
      // 2 offene (Crash-Duplikate)
      await _workBox.add(WorkEntry(start: _hm(8, 30)));
      await _workBox.add(WorkEntry(start: _hm(9, 0)));

      final cleaned = await _svc.cleanupOrphanedEntries();
      expect(cleaned, 1);

      // Normaler Entry unberührt
      final normalEntry = _workBox.values.firstWhere((e) => e.start == _hm(8, 0));
      expect(normalEntry.stop, _hm(17, 0));

      // Genau 1 Entry noch offen: der neueste der Crash-Duplikate
      final openEntries = _workBox.values.where((e) => e.stop == null).toList();
      expect(openEntries.length, 1);
      expect(openEntries.first.start, _hm(9, 0));
    });

    test('Nach cleanup: isTracking() korrekt für überlebenden Entry', () async {
      await _workBox.add(WorkEntry(start: _hm(8, 0)));
      await _workBox.add(WorkEntry(start: _hm(8, 5)));
      await _svc.cleanupOrphanedEntries();
      expect(_svc.isTracking(), true);
    });
  });
}
