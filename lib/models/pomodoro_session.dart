import 'package:hive/hive.dart';
part 'pomodoro_session.g.dart';

/// Phase eines Pomodoro-Zyklus
enum PomodoroPhase {
  work,       // Arbeitsphase (25 Minuten)
  shortBreak, // Kurze Pause (5 Minuten)
  longBreak,  // Lange Pause (15 Minuten)
}

/// Persistente Pomodoro-Session mit Hive-Speicherung
@HiveType(typeId: 7)
class PomodoroSession extends HiveObject {
  @HiveField(0)
  DateTime startTime; // Startzeit dieser Session

  @HiveField(1)
  DateTime? endTime; // Endzeit (null wenn laufend)

  @HiveField(2)
  late PomodoroPhase phase; // work, shortBreak, oder longBreak

  @HiveField(3)
  int sequenceNumber; // Position im täglichen Zyklus (1-8): 1-4=work, 5=long break, 6-7=work, 8=long break

  @HiveField(4)
  bool completed; // Wurde dieser Zyklus vollständig abgeschlossen?

  @HiveField(5)
  bool skipped; // Wurde dieser Zyklus übersprungen?

  PomodoroSession({
    required this.startTime,
    this.endTime,
    required this.phase,
    required this.sequenceNumber,
    this.completed = false,
    this.skipped = false,
  });

  /// Gibt die verstrichene Zeit zurück
  Duration get elapsed => endTime != null
      ? endTime!.difference(startTime)
      : DateTime.now().difference(startTime);

  /// Gibt true zurück wenn diese Session heute stattfand
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = DateTime(startTime.year, startTime.month, startTime.day);
    return startDate.isAtSameMomentAs(today);
  }

  /// Gibt ein Label für die Phase zurück (deutsch)
  String get phaseLabel {
    switch (phase) {
      case PomodoroPhase.work:
        return 'Arbeitsphase';
      case PomodoroPhase.shortBreak:
        return 'Kurze Pause';
      case PomodoroPhase.longBreak:
        return 'Lange Pause';
    }
  }

  /// Gibt ein Icon-Identifier für die Phase zurück
  String get phaseIcon {
    switch (phase) {
      case PomodoroPhase.work:
        return 'work'; // 🎯
      case PomodoroPhase.shortBreak:
        return 'coffee'; // ☕
      case PomodoroPhase.longBreak:
        return 'hotel'; // 🏨
    }
  }
}
