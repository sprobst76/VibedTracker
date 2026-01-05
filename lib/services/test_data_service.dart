import 'dart:math';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../models/pause.dart';
import 'package:hive/hive.dart';

/// Service zum Generieren von Testdaten
class TestDataService {
  final Random _random = Random();

  /// Generiert Testdaten für die letzten [months] Monate
  Future<TestDataResult> generateTestData({int months = 3}) async {
    final workBox = Hive.box<WorkEntry>('work');
    final vacBox = Hive.box<Vacation>('vacation');

    int entriesCreated = 0;
    int vacationsCreated = 0;

    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - months, 1);

    // Generiere einige zufällige Urlaubstage (ca. 5-10 Tage)
    final vacationDays = _generateVacationDays(startDate, now, 5 + _random.nextInt(6));

    // Durchlaufe alle Tage
    var currentDate = startDate;
    while (currentDate.isBefore(now)) {
      final isWeekend = currentDate.weekday == DateTime.saturday ||
          currentDate.weekday == DateTime.sunday;
      final isVacation = vacationDays.any((v) =>
          v.year == currentDate.year &&
          v.month == currentDate.month &&
          v.day == currentDate.day);

      if (!isWeekend && !isVacation) {
        // Arbeitstag - Eintrag generieren
        final entry = _generateWorkEntry(currentDate);
        await workBox.add(entry);
        entriesCreated++;
      }

      if (isVacation) {
        // Urlaubstag hinzufügen
        await vacBox.add(Vacation(
          day: DateTime(currentDate.year, currentDate.month, currentDate.day),
          description: 'Urlaub',
        ));
        vacationsCreated++;
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return TestDataResult(
      entriesCreated: entriesCreated,
      vacationsCreated: vacationsCreated,
      startDate: startDate,
      endDate: now,
    );
  }

  /// Generiert eine Liste von zufälligen Urlaubstagen
  List<DateTime> _generateVacationDays(DateTime start, DateTime end, int count) {
    final days = <DateTime>[];
    final totalDays = end.difference(start).inDays;

    for (var i = 0; i < count; i++) {
      final randomDay = start.add(Duration(days: _random.nextInt(totalDays)));
      // Keine Wochenenden
      if (randomDay.weekday != DateTime.saturday &&
          randomDay.weekday != DateTime.sunday) {
        days.add(DateTime(randomDay.year, randomDay.month, randomDay.day));
      }
    }

    return days;
  }

  /// Generiert einen Arbeitseintrag für einen bestimmten Tag
  WorkEntry _generateWorkEntry(DateTime date) {
    // Startzeit: 7:30 - 9:00 mit Varianz
    final startHour = 7 + _random.nextInt(2);
    final startMinute = _random.nextInt(60);
    final start = DateTime(date.year, date.month, date.day, startHour, startMinute);

    // Arbeitszeit: 7.5 - 9 Stunden
    final workMinutes = 450 + _random.nextInt(90); // 7.5h - 9h
    final stop = start.add(Duration(minutes: workMinutes));

    final entry = WorkEntry(start: start, stop: stop);

    // 1-2 Pausen hinzufügen
    final pauseCount = 1 + _random.nextInt(2);
    final pauses = _generatePauses(start, stop, pauseCount);
    for (final pause in pauses) {
      entry.pauses.add(pause);
    }

    return entry;
  }

  /// Generiert Pausen für einen Arbeitstag
  List<Pause> _generatePauses(DateTime start, DateTime stop, int count) {
    final pauses = <Pause>[];

    if (count >= 1) {
      // Mittagspause: ca. 12:00-13:00
      final lunchStart = DateTime(start.year, start.month, start.day, 12, _random.nextInt(30));
      if (lunchStart.isAfter(start) && lunchStart.isBefore(stop)) {
        final lunchDuration = 30 + _random.nextInt(31); // 30-60 min
        pauses.add(Pause(
          start: lunchStart,
          end: lunchStart.add(Duration(minutes: lunchDuration)),
        ));
      }
    }

    if (count >= 2) {
      // Kurze Pause am Nachmittag: ca. 15:00-16:00
      final afternoonStart = DateTime(start.year, start.month, start.day, 15, _random.nextInt(30));
      if (afternoonStart.isAfter(start) && afternoonStart.isBefore(stop)) {
        final afternoonDuration = 10 + _random.nextInt(21); // 10-30 min
        pauses.add(Pause(
          start: afternoonStart,
          end: afternoonStart.add(Duration(minutes: afternoonDuration)),
        ));
      }
    }

    return pauses;
  }

  /// Löscht alle vorhandenen Testdaten
  Future<void> clearAllData() async {
    final workBox = Hive.box<WorkEntry>('work');
    final vacBox = Hive.box<Vacation>('vacation');

    await workBox.clear();
    await vacBox.clear();
  }
}

/// Ergebnis der Testdaten-Generierung
class TestDataResult {
  final int entriesCreated;
  final int vacationsCreated;
  final DateTime startDate;
  final DateTime endDate;

  TestDataResult({
    required this.entriesCreated,
    required this.vacationsCreated,
    required this.startDate,
    required this.endDate,
  });
}
