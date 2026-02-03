import 'pomodoro_session.dart';

/// Computed daily statistics for Pomodoro sessions
/// This model is NOT persisted to Hive - it's calculated on-the-fly
class PomodoroStats {
  final int completedPomodoros;      // Completed work cycles today
  final int completedBreaks;          // Completed breaks today
  final int totalSessionsToday;       // Total sessions started today
  final Duration totalPomodoroTime;   // Total duration of work cycles
  final int sequenceProgress;         // Current position in daily sequence (1-8)
  final bool hasActiveSession;        // Currently running timer
  final PomodoroPhase? currentPhase;  // Current phase if active

  PomodoroStats({
    required this.completedPomodoros,
    required this.completedBreaks,
    required this.totalSessionsToday,
    required this.totalPomodoroTime,
    required this.sequenceProgress,
    required this.hasActiveSession,
    this.currentPhase,
  });

  /// Factory to compute stats from session list
  factory PomodoroStats.from(
    List<PomodoroSession> sessions,
    PomodoroPhase? currentPhase,
    bool hasActive,
  ) {
    // Filter today's sessions
    final todaySessions = sessions.where((s) => s.isToday).toList();

    // Count completed pomodoros (work phases that are completed)
    final completedPomodoros = todaySessions
        .where((s) => s.phase == PomodoroPhase.work && s.completed)
        .length;

    // Count completed breaks
    final completedBreaks = todaySessions
        .where((s) =>
            (s.phase == PomodoroPhase.shortBreak ||
                s.phase == PomodoroPhase.longBreak) &&
            s.completed)
        .length;

    // Total duration of work cycles
    final totalTime = todaySessions
        .where((s) => s.phase == PomodoroPhase.work)
        .fold<Duration>(
          Duration.zero,
          (sum, s) => sum + s.elapsed,
        );

    // Sequence progress: highest sequence number of today's sessions
    int maxSequence = 0;
    if (todaySessions.isNotEmpty) {
      maxSequence = todaySessions.map((s) => s.sequenceNumber).reduce((a, b) => a > b ? a : b);
    }

    return PomodoroStats(
      completedPomodoros: completedPomodoros,
      completedBreaks: completedBreaks,
      totalSessionsToday: todaySessions.length,
      totalPomodoroTime: totalTime,
      sequenceProgress: maxSequence,
      hasActiveSession: hasActive,
      currentPhase: currentPhase,
    );
  }

  /// Empty stats (no sessions today)
  factory PomodoroStats.empty() {
    return PomodoroStats(
      completedPomodoros: 0,
      completedBreaks: 0,
      totalSessionsToday: 0,
      totalPomodoroTime: Duration.zero,
      sequenceProgress: 0,
      hasActiveSession: false,
      currentPhase: null,
    );
  }

  /// Human-readable summary
  String get summary {
    if (completedPomodoros == 0 && !hasActiveSession) {
      return 'Noch keine Pomodoros heute';
    }
    return '$completedPomodoros Pomodoro${completedPomodoros != 1 ? 's' : ''} abgeschlossen';
  }
}
