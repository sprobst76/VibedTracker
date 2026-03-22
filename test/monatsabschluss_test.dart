/// Tests für den Monatsabschluss (beta.67)
///
/// Abgedeckte Szenarien:
///   A – Settings.monthKey: korrekte YYYY-MM-Formatierung
///   B – Settings.isMonthLocked: Sperr-Erkennung (einzeln, mehrfach, Grenzen)
///   C – SettingsNotifier.lockMonth: Monat sperren (inkl. Idempotenz)
///   D – SettingsNotifier.unlockMonth: Monat entsperren
///   E – Kombinierte Lock/Unlock-Sequenzen
///   F – Monatsgrenz-Edge-Cases (Jahreswechsel, Februar, aktueller Monat)
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:time_tracker/models/settings.dart';
import 'package:time_tracker/providers.dart';

// ── Hive-Setup ───────────────────────────────────────────────────────────────

late Directory _hiveDir;
late Box<Settings> _settingsBox;

Future<void> _initHive() async {
  _hiveDir = await Directory.systemTemp.createTemp('hive_monatsabschluss_');
  Hive.init(_hiveDir.path);
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SettingsAdapter());
  _settingsBox = await Hive.openBox<Settings>(
      'settings_${DateTime.now().microsecondsSinceEpoch}');
}

Future<void> _closeHive() async {
  await _settingsBox.deleteFromDisk();
  await Hive.close();
  await _hiveDir.delete(recursive: true);
}

/// Erstellt einen SettingsNotifier mit einer frischen Settings-Instanz.
SettingsNotifier _makeNotifier({List<String>? lockedMonths}) {
  final s = Settings(lockedMonths: lockedMonths);
  _settingsBox.put('prefs', s);
  return SettingsNotifier(_settingsBox);
}

void main() {
  // ── A: monthKey ────────────────────────────────────────────────────────────
  group('A – Settings.monthKey', () {
    test('A1: Normales Datum → YYYY-MM mit führender Null', () {
      expect(Settings.monthKey(DateTime(2026, 2, 15)), '2026-02');
    });

    test('A2: Zweistelliger Monat ohne Null', () {
      expect(Settings.monthKey(DateTime(2026, 12, 1)), '2026-12');
    });

    test('A3: Erster Tag des Monats', () {
      expect(Settings.monthKey(DateTime(2025, 1, 1)), '2025-01');
    });

    test('A4: Letzter Tag des Monats', () {
      expect(Settings.monthKey(DateTime(2026, 3, 31)), '2026-03');
    });

    test('A5: Jahreswechsel — Dezember', () {
      expect(Settings.monthKey(DateTime(2025, 12, 31)), '2025-12');
    });

    test('A6: Jahreswechsel — Januar Folgejahr', () {
      expect(Settings.monthKey(DateTime(2026, 1, 1)), '2026-01');
    });

    test('A7: Mit Uhrzeit — nur Datum zählt', () {
      expect(Settings.monthKey(DateTime(2026, 6, 15, 23, 59, 59)), '2026-06');
    });
  });

  // ── B: isMonthLocked ───────────────────────────────────────────────────────
  group('B – Settings.isMonthLocked', () {
    test('B1: Leere Liste → kein Monat gesperrt', () {
      final s = Settings();
      expect(s.isMonthLocked(DateTime(2026, 2)), false);
      expect(s.isMonthLocked(DateTime(2025, 12)), false);
    });

    test('B2: Gesperrter Monat wird erkannt', () {
      final s = Settings(lockedMonths: ['2026-02']);
      expect(s.isMonthLocked(DateTime(2026, 2, 1)), true);
    });

    test('B3: Verschiedene Tage im gesperrten Monat', () {
      final s = Settings(lockedMonths: ['2026-02']);
      expect(s.isMonthLocked(DateTime(2026, 2, 1)), true);
      expect(s.isMonthLocked(DateTime(2026, 2, 14)), true);
      expect(s.isMonthLocked(DateTime(2026, 2, 28)), true);
    });

    test('B4: Benachbarter Monat nicht gesperrt', () {
      final s = Settings(lockedMonths: ['2026-02']);
      expect(s.isMonthLocked(DateTime(2026, 1, 31)), false,
          reason: 'Januar ist nicht gesperrt');
      expect(s.isMonthLocked(DateTime(2026, 3, 1)), false,
          reason: 'März ist nicht gesperrt');
    });

    test('B5: Gleiches Monat, anderes Jahr → nicht gesperrt', () {
      final s = Settings(lockedMonths: ['2026-02']);
      expect(s.isMonthLocked(DateTime(2025, 2, 1)), false);
      expect(s.isMonthLocked(DateTime(2027, 2, 1)), false);
    });

    test('B6: Mehrere Monate gesperrt', () {
      final s = Settings(lockedMonths: ['2026-01', '2026-02', '2026-03']);
      expect(s.isMonthLocked(DateTime(2026, 1, 15)), true);
      expect(s.isMonthLocked(DateTime(2026, 2, 1)), true);
      expect(s.isMonthLocked(DateTime(2026, 3, 31)), true);
      expect(s.isMonthLocked(DateTime(2026, 4, 1)), false);
    });

    test('B7: Alle Monate eines Jahres gesperrt', () {
      final all = List.generate(12, (i) => '2025-${(i + 1).toString().padLeft(2, '0')}');
      final s = Settings(lockedMonths: all);
      for (var m = 1; m <= 12; m++) {
        expect(s.isMonthLocked(DateTime(2025, m, 1)), true,
            reason: 'Monat $m 2025 soll gesperrt sein');
      }
      expect(s.isMonthLocked(DateTime(2026, 1, 1)), false,
          reason: '2026 soll nicht gesperrt sein');
    });
  });

  // ── C: lockMonth ───────────────────────────────────────────────────────────
  group('C – SettingsNotifier.lockMonth', () {
    setUp(_initHive);
    tearDown(_closeHive);

    test('C1: Monat sperren → isMonthLocked gibt true zurück', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2026, 2));
      expect(notifier.state.isMonthLocked(DateTime(2026, 2, 1)), true);
    });

    test('C2: Monat sperren → andere Monate bleiben entsperrt', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2026, 2));
      expect(notifier.state.isMonthLocked(DateTime(2026, 1, 1)), false);
      expect(notifier.state.isMonthLocked(DateTime(2026, 3, 1)), false);
    });

    test('C3: lockMonth ist idempotent — kein Duplikat in Liste', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2026, 2));
      notifier.lockMonth(DateTime(2026, 2)); // zweimal
      final keys = notifier.state.lockedMonths
          .where((k) => k == '2026-02')
          .toList();
      expect(keys.length, 1, reason: 'Kein Duplikat erwartet');
    });

    test('C4: Mehrere Monate nacheinander sperren', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2026, 1));
      notifier.lockMonth(DateTime(2026, 2));
      notifier.lockMonth(DateTime(2026, 3));
      expect(notifier.state.lockedMonths.length, 3);
      expect(notifier.state.isMonthLocked(DateTime(2026, 1)), true);
      expect(notifier.state.isMonthLocked(DateTime(2026, 2)), true);
      expect(notifier.state.isMonthLocked(DateTime(2026, 3)), true);
    });

    test('C5: Lock eines bereits von Anfang an leeren Monats', () {
      final notifier = _makeNotifier(lockedMonths: []);
      notifier.lockMonth(DateTime(2025, 12));
      expect(notifier.state.isMonthLocked(DateTime(2025, 12)), true);
      expect(notifier.state.lockedMonths, ['2025-12']);
    });
  });

  // ── D: unlockMonth ─────────────────────────────────────────────────────────
  group('D – SettingsNotifier.unlockMonth', () {
    setUp(_initHive);
    tearDown(_closeHive);

    test('D1: Gesperrten Monat entsperren', () {
      final notifier = _makeNotifier(lockedMonths: ['2026-02']);
      notifier.unlockMonth(DateTime(2026, 2));
      expect(notifier.state.isMonthLocked(DateTime(2026, 2)), false);
      expect(notifier.state.lockedMonths, isEmpty);
    });

    test('D2: Einen von mehreren gesperrten Monaten entsperren', () {
      final notifier = _makeNotifier(lockedMonths: ['2026-01', '2026-02', '2026-03']);
      notifier.unlockMonth(DateTime(2026, 2));
      expect(notifier.state.isMonthLocked(DateTime(2026, 1)), true);
      expect(notifier.state.isMonthLocked(DateTime(2026, 2)), false);
      expect(notifier.state.isMonthLocked(DateTime(2026, 3)), true);
      expect(notifier.state.lockedMonths.length, 2);
    });

    test('D3: Entsperren eines nicht gesperrten Monats → keine Fehler', () {
      final notifier = _makeNotifier();
      notifier.unlockMonth(DateTime(2026, 5)); // war nie gesperrt
      expect(notifier.state.lockedMonths, isEmpty);
    });

    test('D4: Alle Monate einzeln entsperren → leere Liste', () {
      final notifier =
          _makeNotifier(lockedMonths: ['2025-11', '2025-12', '2026-01']);
      notifier.unlockMonth(DateTime(2025, 11));
      notifier.unlockMonth(DateTime(2025, 12));
      notifier.unlockMonth(DateTime(2026, 1));
      expect(notifier.state.lockedMonths, isEmpty);
    });
  });

  // ── E: Kombinierte Sequenzen ───────────────────────────────────────────────
  group('E – Kombinierte Lock/Unlock-Sequenzen', () {
    setUp(_initHive);
    tearDown(_closeHive);

    test('E1: Lock → Unlock → Lock selber Monat', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2026, 3));
      expect(notifier.state.isMonthLocked(DateTime(2026, 3)), true);
      notifier.unlockMonth(DateTime(2026, 3));
      expect(notifier.state.isMonthLocked(DateTime(2026, 3)), false);
      notifier.lockMonth(DateTime(2026, 3));
      expect(notifier.state.isMonthLocked(DateTime(2026, 3)), true);
      // Kein Duplikat
      expect(notifier.state.lockedMonths.length, 1);
    });

    test('E2: Lock 12 Monate, dann alle entsperren', () {
      final notifier = _makeNotifier();
      for (var m = 1; m <= 12; m++) {
        notifier.lockMonth(DateTime(2025, m));
      }
      expect(notifier.state.lockedMonths.length, 12);
      for (var m = 1; m <= 12; m++) {
        notifier.unlockMonth(DateTime(2025, m));
      }
      expect(notifier.state.lockedMonths, isEmpty);
    });

    test('E3: Jahreswechsel — Dez 2025 und Jan 2026 separat sperrbar', () {
      final notifier = _makeNotifier();
      notifier.lockMonth(DateTime(2025, 12));
      notifier.lockMonth(DateTime(2026, 1));
      expect(notifier.state.isMonthLocked(DateTime(2025, 12)), true);
      expect(notifier.state.isMonthLocked(DateTime(2026, 1)), true);
      expect(notifier.state.isMonthLocked(DateTime(2025, 11)), false);
      expect(notifier.state.isMonthLocked(DateTime(2026, 2)), false);
    });
  });

  // ── F: Edge-Cases ──────────────────────────────────────────────────────────
  group('F – Monatsgrenz-Edge-Cases', () {
    test('F1: Februar ohne Schaltjahr (28 Tage)', () {
      final s = Settings(lockedMonths: ['2025-02']);
      expect(s.isMonthLocked(DateTime(2025, 2, 28)), true);
      expect(s.isMonthLocked(DateTime(2025, 3, 1)), false);
    });

    test('F2: Februar im Schaltjahr (29 Tage)', () {
      final s = Settings(lockedMonths: ['2024-02']);
      expect(s.isMonthLocked(DateTime(2024, 2, 29)), true);
      expect(s.isMonthLocked(DateTime(2024, 3, 1)), false);
    });

    test('F3: monthKey mit Uhrzeit kurz vor Mitternacht', () {
      expect(
        Settings.monthKey(DateTime(2026, 1, 31, 23, 59, 59)),
        '2026-01',
        reason: 'Uhrzeit darf den Monatschlüssel nicht ändern',
      );
    });

    test('F4: Sehr altes Datum (2000)', () {
      final s = Settings(lockedMonths: ['2000-01']);
      expect(s.isMonthLocked(DateTime(2000, 1, 15)), true);
      expect(s.isMonthLocked(DateTime(2000, 2, 1)), false);
    });

    test('F5: Fernere Zukunft (2035)', () {
      expect(Settings.monthKey(DateTime(2035, 6, 1)), '2035-06');
    });
  });
}
