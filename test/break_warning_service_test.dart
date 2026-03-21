import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/models/pause.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/services/break_warning_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _base = DateTime(2026, 1, 12, 8, 0, 0);
DateTime _t(int minutes) => _base.add(Duration(minutes: minutes));

/// Erstellt einen WorkEntry mit beliebiger Netto-Arbeitszeit.
/// [workMinutes] = Brutto-Minuten (Start bis jetzt/stop)
/// [pauseMinutes] = Pausen-Minuten innerhalb der Brutto-Zeit
WorkEntry _entry({
  required int workMinutes,
  int pauseMinutes = 0,
  bool stopped = false,
}) {
  final start = _base;
  final stop = stopped ? _t(workMinutes) : null;

  final entry = WorkEntry(start: start)..stop = stop;

  if (pauseMinutes > 0) {
    final pauseStart = _t(workMinutes ~/ 2);
    final pause = Pause(start: pauseStart)
      ..end = pauseStart.add(Duration(minutes: pauseMinutes));
    entry.pauses.add(pause);
  }

  return entry;
}

/// Erstellt einen WorkEntry mit einer laufenden Pause (kein end).
WorkEntry _entryWithOpenPause({
  required int workMinutes,
  required int pauseStartOffset,
}) {
  final entry = WorkEntry(start: _base);
  final pause = Pause(start: _t(pauseStartOffset));
  entry.pauses.add(pause);
  return entry;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── calculateNetWorkDuration ───────────────────────────────────────────────

  group('calculateNetWorkDuration', () {
    test('0 min Arbeit, keine Pause → 0 min netto', () {
      final entry = WorkEntry(start: _base)..stop = _base;
      expect(BreakWarningService.calculateNetWorkDuration(entry), Duration.zero);
    });

    test('8h Arbeit, keine Pause → 8h netto', () {
      final entry = _entry(workMinutes: 480, stopped: true);
      expect(BreakWarningService.calculateNetWorkDuration(entry),
          const Duration(hours: 8));
    });

    test('8h Arbeit, 30 min Pause → 7h 30min netto', () {
      final entry = _entry(workMinutes: 480, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.calculateNetWorkDuration(entry),
          const Duration(hours: 7, minutes: 30));
    });

    test('Laufende Session (kein stop): berechnet bis DateTime.now()', () {
      // 10 min vor jetzt gestartet, keine Pause
      final start = DateTime.now().subtract(const Duration(minutes: 10));
      final entry = WorkEntry(start: start);
      final net = BreakWarningService.calculateNetWorkDuration(entry);
      // Sollte ~10 min sein (±2 min Toleranz)
      expect(net.inMinutes, greaterThanOrEqualTo(9));
      expect(net.inMinutes, lessThanOrEqualTo(11));
    });

    test('Laufende Pause zählt zur Pausendauer', () {
      // Start vor 120 min, Pause seit 30 min
      final entry = _entryWithOpenPause(workMinutes: 120, pauseStartOffset: 90);
      final net = BreakWarningService.calculateNetWorkDuration(entry);
      // Brutto ~120 min, Pause ~30 min → netto ~90 min (±2 min)
      expect(net.inMinutes, greaterThanOrEqualTo(88));
      expect(net.inMinutes, lessThanOrEqualTo(92));
    });
  });

  // ── calculateTotalPauseDuration ────────────────────────────────────────────

  group('calculateTotalPauseDuration', () {
    test('Keine Pausen → 0 min', () {
      final entry = WorkEntry(start: _base);
      expect(BreakWarningService.calculateTotalPauseDuration(entry),
          Duration.zero);
    });

    test('Eine abgeschlossene Pause von 30 min', () {
      final entry = _entry(workMinutes: 480, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.calculateTotalPauseDuration(entry),
          const Duration(minutes: 30));
    });

    test('Zwei Pausen summiert', () {
      final entry = WorkEntry(start: _base);
      final p1 = Pause(start: _t(60))..end = _t(75);  // 15 min
      final p2 = Pause(start: _t(240))..end = _t(265); // 25 min
      entry.pauses.addAll([p1, p2]);
      expect(BreakWarningService.calculateTotalPauseDuration(entry),
          const Duration(minutes: 40));
    });
  });

  // ── shouldWarn6h ──────────────────────────────────────────────────────────

  group('shouldWarn6h', () {
    test('5h 59min netto, keine Pause → kein Warning', () {
      final entry = _entry(workMinutes: 359, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isFalse);
    });

    test('6h 0min netto, keine Pause → Warning', () {
      final entry = _entry(workMinutes: 360, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isTrue);
    });

    test('6h 30min netto, keine Pause → Warning', () {
      final entry = _entry(workMinutes: 390, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isTrue);
    });

    test('6h 0min netto, 30 min Pause → kein Warning (Pause reicht)', () {
      final entry = _entry(workMinutes: 390, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isFalse);
    });

    test('6h 0min netto, 29 min Pause → Warning (Pause fehlt 1 min)', () {
      final entry = _entry(workMinutes: 389, pauseMinutes: 29, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isTrue);
    });

    test('9h netto, keine Pause → shouldWarn6h true (6h ist Subset)', () {
      final entry = _entry(workMinutes: 540, stopped: true);
      expect(BreakWarningService.shouldWarn6h(entry), isTrue);
    });
  });

  // ── shouldWarn9h ──────────────────────────────────────────────────────────

  group('shouldWarn9h', () {
    test('8h 59min netto, keine Pause → kein 9h-Warning', () {
      final entry = _entry(workMinutes: 539, stopped: true);
      expect(BreakWarningService.shouldWarn9h(entry), isFalse);
    });

    test('9h 0min netto, keine Pause → Warning', () {
      final entry = _entry(workMinutes: 540, stopped: true);
      expect(BreakWarningService.shouldWarn9h(entry), isTrue);
    });

    test('9h netto, 45 min Pause → kein Warning (Pause reicht)', () {
      final entry = _entry(workMinutes: 585, pauseMinutes: 45, stopped: true);
      expect(BreakWarningService.shouldWarn9h(entry), isFalse);
    });

    test('9h netto, 44 min Pause → Warning (1 min zu wenig)', () {
      final entry = _entry(workMinutes: 584, pauseMinutes: 44, stopped: true);
      expect(BreakWarningService.shouldWarn9h(entry), isTrue);
    });

    test('9h netto, nur 30 min Pause → Warning (30 < 45 min)', () {
      final entry = _entry(workMinutes: 570, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.shouldWarn9h(entry), isTrue);
    });
  });

  // ── currentWarningLevel ────────────────────────────────────────────────────

  group('currentWarningLevel', () {
    test('5h → null', () {
      final entry = _entry(workMinutes: 300, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry), isNull);
    });

    test('6h, keine Pause → sixHours', () {
      final entry = _entry(workMinutes: 360, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry),
          BreakWarningLevel.sixHours);
    });

    test('9h, keine Pause → nineHours (Vorrang vor 6h)', () {
      final entry = _entry(workMinutes: 540, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry),
          BreakWarningLevel.nineHours);
    });

    test('6h, 30 min Pause → null (6h Pflicht erfüllt, unter 9h)', () {
      final entry = _entry(workMinutes: 390, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry), isNull);
    });

    test('9h, 30 min Pause → nineHours (30 < 45 min)', () {
      final entry = _entry(workMinutes: 570, pauseMinutes: 30, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry),
          BreakWarningLevel.nineHours);
    });

    test('9h, 45 min Pause → null (beide Pflichten erfüllt)', () {
      final entry = _entry(workMinutes: 585, pauseMinutes: 45, stopped: true);
      expect(BreakWarningService.currentWarningLevel(entry), isNull);
    });
  });

  // ── Grenzwerte ────────────────────────────────────────────────────────────

  group('Grenzwerte', () {
    for (final minutes in [0, 60, 120, 180, 240, 299, 359]) {
      test('$minutes min netto → kein Warning', () {
        final entry = _entry(workMinutes: minutes, stopped: true);
        expect(BreakWarningService.currentWarningLevel(entry), isNull,
            reason: '$minutes min < 6h, keine Pflichtpause');
      });
    }

    for (final minutes in [360, 361, 420, 480, 539]) {
      test('$minutes min netto, keine Pause → sixHours Warning', () {
        final entry = _entry(workMinutes: minutes, stopped: true);
        expect(BreakWarningService.currentWarningLevel(entry),
            BreakWarningLevel.sixHours,
            reason: '$minutes min ≥ 6h ohne Pause → Warnung fällig');
      });
    }

    for (final minutes in [540, 541, 600, 720]) {
      test('$minutes min netto, keine Pause → nineHours Warning', () {
        final entry = _entry(workMinutes: minutes, stopped: true);
        expect(BreakWarningService.currentWarningLevel(entry),
            BreakWarningLevel.nineHours,
            reason: '$minutes min ≥ 9h → 9h-Warnung hat Vorrang');
      });
    }
  });
}
