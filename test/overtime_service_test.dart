import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/models/pause.dart';
import 'package:time_tracker/models/settings.dart';
import 'package:time_tracker/models/vacation.dart';
import 'package:time_tracker/models/weekly_hours_period.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/services/overtime_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// Montag, 12. Januar 2026 (Wochentag 1)
final _mon = DateTime(2026, 1, 12); // Mo
final _tue = DateTime(2026, 1, 13); // Di
final _wed = DateTime(2026, 1, 14); // Mi
final _thu = DateTime(2026, 1, 15); // Do
final _fri = DateTime(2026, 1, 16); // Fr
final _sat = DateTime(2026, 1, 17); // Sa
final _sun = DateTime(2026, 1, 18); // So

Settings _settings({double weeklyHours = 40, List<int>? nonWorkingWeekdays}) {
  return Settings(
    weeklyHours: weeklyHours,
    nonWorkingWeekdays: nonWorkingWeekdays ?? [6, 7],
  );
}

/// Erstellt einen abgeschlossenen WorkEntry mit Netto-Minuten.
WorkEntry _entry(DateTime day, {required int netMinutes, int pauseMinutes = 0}) {
  final start = DateTime(day.year, day.month, day.day, 8, 0);
  final grossMinutes = netMinutes + pauseMinutes;
  final stop = start.add(Duration(minutes: grossMinutes));
  final entry = WorkEntry(start: start)..stop = stop;
  if (pauseMinutes > 0) {
    final pauseStart = start.add(Duration(minutes: netMinutes ~/ 2));
    entry.pauses.add(Pause(start: pauseStart)
      ..end = pauseStart.add(Duration(minutes: pauseMinutes)));
  }
  return entry;
}

OvertimeResult _calc({
  required DateTime from,
  required DateTime to,
  List<WorkEntry> entries = const [],
  Settings? settings,
  List<WeeklyHoursPeriod> periods = const [],
  Set<DateTime> holidays = const {},
  List<Vacation> absences = const [],
  DateTime? today,
}) {
  return OvertimeService.calculate(
    from: from,
    to: to,
    entries: entries,
    settings: settings ?? _settings(),
    periods: periods,
    holidays: holidays,
    absences: absences,
    today: today ?? DateTime(2026, 12, 31), // Weit in der Zukunft → ganzer Zeitraum gültig
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Basis-Berechnungen ────────────────────────────────────────────────────

  group('Soll-Berechnung (targetMinutes)', () {
    test('Montag–Freitag: je 8h Soll bei 40h/Woche (5-Tage)', () {
      final result = _calc(from: _mon, to: _fri);
      expect(result.totalTarget, closeTo(40 * 60, 1));
      expect(result.workDays, 5);
    });

    test('Wochenende: Soll = 0', () {
      final result = _calc(from: _sat, to: _sun);
      expect(result.totalTarget, 0);
      expect(result.workDays, 0);
    });

    test('Mo–So: Soll nur für 5 Arbeitstage (Sa/So = 0)', () {
      final result = _calc(from: _mon, to: _sun);
      expect(result.totalTarget, closeTo(40 * 60, 1));
      expect(result.workDays, 5);
    });

    test('30h/Woche bei 5 Arbeitstagen → 6h/Tag Soll', () {
      final result = _calc(
        from: _mon,
        to: _fri,
        settings: _settings(weeklyHours: 30),
      );
      expect(result.totalTarget, closeTo(30 * 60, 1));
    });

    test('Feiertag: Soll = 0', () {
      final holiday = DateTime(2026, 1, 12); // Montag als Feiertag
      final result = _calc(from: _mon, to: _mon, holidays: {holiday});
      expect(result.totalTarget, 0);
      expect(result.workDays, 0);
    });

    test('Urlaubstag (bezahlt): Soll = 0 für diesen Tag', () {
      final vacation = Vacation(day: _mon);
      final result = _calc(from: _mon, to: _mon, absences: [vacation]);
      expect(result.totalTarget, 0);
      expect(result.workDays, 0);
    });

    test('Unbezahlter Urlaub: Soll bleibt (nicht paid)', () {
      final unpaid = Vacation(day: _mon, type: AbsenceType.unpaid);
      final result = _calc(from: _mon, to: _mon, absences: [unpaid]);
      // unpaid.isPaid == false → zählt wie normaler Arbeitstag
      expect(result.totalTarget, closeTo(8 * 60, 1));
      expect(result.workDays, 1);
    });
  });

  // ── Ist-Berechnung (actualMinutes) ────────────────────────────────────────

  group('Ist-Berechnung (actualMinutes)', () {
    test('Kein Entry → Ist = 0', () {
      final result = _calc(from: _mon, to: _fri);
      expect(result.totalActual, 0);
    });

    test('8h Netto-Arbeit an Montag → Ist = 480 min', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 480)],
      );
      expect(result.totalActual, closeTo(480, 1));
    });

    test('Pause wird korrekt abgezogen', () {
      // Brutto 10h, 30 min Pause → Netto 9.5h = 570 min
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 570, pauseMinutes: 30)],
      );
      expect(result.totalActual, closeTo(570, 1));
    });

    test('Mehrere Entries an verschiedenen Tagen werden summiert', () {
      final result = _calc(
        from: _mon,
        to: _fri,
        entries: [
          _entry(_mon, netMinutes: 480),
          _entry(_tue, netMinutes: 420),
          _entry(_wed, netMinutes: 510),
        ],
      );
      expect(result.totalActual, closeTo(480 + 420 + 510, 2));
    });

    test('Laufender Entry (kein stop) wird NICHT gezählt', () {
      final running = WorkEntry(start: DateTime(_mon.year, _mon.month, _mon.day, 8, 0));
      // Kein stop → sollte ignoriert werden
      final result = _calc(from: _mon, to: _mon, entries: [running]);
      expect(result.totalActual, 0);
    });
  });

  // ── Balance ───────────────────────────────────────────────────────────────

  group('Balance (delta)', () {
    test('Exakt 8h gearbeitet bei 8h Soll → balance = 0', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 480)],
      );
      expect(result.balanceMinutes, closeTo(0, 1));
    });

    test('9h gearbeitet bei 8h Soll → +60 min Überstunden', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 540)],
      );
      expect(result.balanceMinutes, closeTo(60, 1));
    });

    test('6h gearbeitet bei 8h Soll → -120 min Minusstunden', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 360)],
      );
      expect(result.balanceMinutes, closeTo(-120, 1));
    });

    test('Ganze Woche: 5×9h = +5h Überstunden', () {
      final result = _calc(
        from: _mon,
        to: _fri,
        entries: [
          _entry(_mon, netMinutes: 540),
          _entry(_tue, netMinutes: 540),
          _entry(_wed, netMinutes: 540),
          _entry(_thu, netMinutes: 540),
          _entry(_fri, netMinutes: 540),
        ],
      );
      expect(result.balanceHours, closeTo(5, 0.1));
    });

    test('Urlaubswoche: Soll = 0, keine Arbeit → balance = 0', () {
      final absences = [_mon, _tue, _wed, _thu, _fri]
          .map((d) => Vacation(day: d))
          .toList();
      final result = _calc(from: _mon, to: _fri, absences: absences);
      expect(result.balanceMinutes, closeTo(0, 1));
      expect(result.totalTarget, 0);
    });

    test('Feiertag + 8h gearbeitet → +8h Überstunden', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        entries: [_entry(_mon, netMinutes: 480)],
        holidays: {DateTime(2026, 1, 12)},
      );
      expect(result.balanceMinutes, closeTo(480, 1)); // Soll=0, Ist=480
    });
  });

  // ── WeeklyHoursPeriods ────────────────────────────────────────────────────

  group('WeeklyHoursPeriods', () {
    test('Periode mit 30h/Woche gilt für passenden Tag', () {
      final period = WeeklyHoursPeriod(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
        weeklyHours: 30,
      );
      final result = _calc(
        from: _mon,
        to: _mon,
        periods: [period],
      );
      expect(result.totalTarget, closeTo(6 * 60, 1)); // 30h / 5 Tage = 6h/Tag
    });

    test('Ohne Periode gilt Settings.weeklyHours', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        settings: _settings(weeklyHours: 40),
      );
      expect(result.totalTarget, closeTo(8 * 60, 1)); // 40h / 5 Tage = 8h/Tag
    });
  });

  // ── OvertimeDayResult ─────────────────────────────────────────────────────

  group('OvertimeDayResult.dayType', () {
    test('Wochentag ohne Abwesenheit → DayType.workDay', () {
      final result = _calc(from: _mon, to: _mon);
      expect(result.days.first.dayType, DayType.workDay);
    });

    test('Samstag → DayType.weekend', () {
      final result = _calc(from: _sat, to: _sat);
      expect(result.days.first.dayType, DayType.weekend);
    });

    test('Feiertag → DayType.holiday', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        holidays: {DateTime(2026, 1, 12)},
      );
      expect(result.days.first.dayType, DayType.holiday);
    });

    test('Urlaubstag → DayType.absent', () {
      final result = _calc(
        from: _mon,
        to: _mon,
        absences: [Vacation(day: _mon)],
      );
      expect(result.days.first.dayType, DayType.absent);
    });
  });

  // ── calculateAllTime ─────────────────────────────────────────────────────

  group('calculateAllTime', () {
    test('Keine Entries → leeres Ergebnis', () {
      final result = OvertimeService.calculateAllTime(
        entries: [],
        settings: _settings(),
        periods: [],
        holidays: {},
        absences: [],
      );
      expect(result.days, isEmpty);
    });

    test('Frühester Entry bestimmt Startdatum', () {
      final result = OvertimeService.calculateAllTime(
        entries: [
          _entry(_wed, netMinutes: 480),
          _entry(_mon, netMinutes: 480),
        ],
        settings: _settings(),
        periods: [],
        holidays: {},
        absences: [],
        today: _fri,
      );
      // Startet ab Montag
      expect(result.from.day, _mon.day);
    });

    test('Gesamt-Balance über 3 Tage korrekt', () {
      // Mo: 8h (genau), Di: 9h (+1h), Mi: 7h (-1h)
      final result = OvertimeService.calculateAllTime(
        entries: [
          _entry(_mon, netMinutes: 480),
          _entry(_tue, netMinutes: 540),
          _entry(_wed, netMinutes: 420),
        ],
        settings: _settings(),
        periods: [],
        holidays: {},
        absences: [],
        today: _fri,
      );
      // Soll: 5 Tage × 8h = 40h (Mo–Fr)
      // Ist: 8+9+7 = 24h
      // Balance: 24h - 40h = -16h (Do+Fr fehlen ohne Einträge)
      expect(result.balanceHours, closeTo(-16, 0.5));
    });
  });

  // ── Cutoff (today) ─────────────────────────────────────────────────────────

  group('Cutoff durch today-Parameter', () {
    test('Tage nach today werden ignoriert', () {
      final result = _calc(
        from: _mon,
        to: _fri,
        today: _wed, // Mittwoch → Do/Fr werden ignoriert
      );
      expect(result.days.length, 3); // Mo, Di, Mi
      expect(result.totalTarget, closeTo(3 * 8 * 60, 1));
    });

    test('from nach today → leeres Ergebnis', () {
      final result = _calc(
        from: _fri,
        to: _fri,
        today: _wed,
      );
      expect(result.days, isEmpty);
    });
  });
}
