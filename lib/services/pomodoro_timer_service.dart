import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/pomodoro_session.dart';
import '../models/settings.dart';
import '../models/work_entry.dart';
import 'pomodoro_notification_service.dart';

/// State of the Pomodoro timer
class PomodoroTimerState {
  final PomodoroSession? currentSession;
  final List<PomodoroSession> allSessions;
  final PomodoroPhase currentPhase;
  final Duration timeRemaining;
  final bool isRunning;
  final bool isPaused;
  final int pomodoroCountToday;
  final int sequenceProgress; // 1-8, resets daily

  const PomodoroTimerState({
    required this.currentSession,
    required this.allSessions,
    required this.currentPhase,
    required this.timeRemaining,
    required this.isRunning,
    required this.isPaused,
    required this.pomodoroCountToday,
    required this.sequenceProgress,
  });

  /// Empty initial state
  factory PomodoroTimerState.initial() {
    return const PomodoroTimerState(
      currentSession: null,
      allSessions: [],
      currentPhase: PomodoroPhase.work,
      timeRemaining: Duration(minutes: 25),
      isRunning: false,
      isPaused: false,
      pomodoroCountToday: 0,
      sequenceProgress: 0,
    );
  }

  /// Copy state with modified fields
  PomodoroTimerState copyWith({
    PomodoroSession? currentSession,
    List<PomodoroSession>? allSessions,
    PomodoroPhase? currentPhase,
    Duration? timeRemaining,
    bool? isRunning,
    bool? isPaused,
    int? pomodoroCountToday,
    int? sequenceProgress,
  }) {
    return PomodoroTimerState(
      currentSession: currentSession ?? this.currentSession,
      allSessions: allSessions ?? this.allSessions,
      currentPhase: currentPhase ?? this.currentPhase,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      pomodoroCountToday: pomodoroCountToday ?? this.pomodoroCountToday,
      sequenceProgress: sequenceProgress ?? this.sequenceProgress,
    );
  }

  @override
  String toString() =>
      'PomodoroTimerState(phase: $currentPhase, remaining: $timeRemaining, running: $isRunning, paused: $isPaused)';
}

/// StateNotifier for managing Pomodoro timer state
class PomodoroTimerNotifier extends StateNotifier<PomodoroTimerState> {
  final Box<PomodoroSession> _box;
  late Settings _settings;

  Timer? _updateTimer;

  PomodoroTimerNotifier(
    this._box,
    Settings initialSettings,
  )   : _settings = initialSettings,
        super(PomodoroTimerState.initial()) {
    _init();
  }

  /// Initialize timer and restore state
  void _init() {
    _restoreState();
    _startUpdateTimer();
  }

  /// Restore state from Hive and previous pause if applicable
  void _restoreState() {
    // Load all sessions from box
    final allSessions = _box.values.toList();

    // Find today's sessions
    final todaysSessions =
        allSessions.where((s) => s.isToday && !s.completed).toList();

    if (todaysSessions.isEmpty) {
      // No active session today
      state = state.copyWith(
        allSessions: allSessions,
        currentSession: null,
        isRunning: false,
        isPaused: false,
        pomodoroCountToday: allSessions
            .where((s) => s.isToday && s.phase == PomodoroPhase.work && s.completed)
            .length,
        sequenceProgress: allSessions
                .where((s) => s.isToday)
                .map((s) => s.sequenceNumber)
                .fold<int>(0, (a, b) => a > b ? a : b) ??
            0,
      );
      return;
    }

    // Get the most recent uncompleted session
    final currentSession = todaysSessions.last;
    final completed = allSessions
        .where((s) => s.isToday && s.phase == PomodoroPhase.work && s.completed)
        .length;
    final maxSequence = allSessions
            .where((s) => s.isToday)
            .map((s) => s.sequenceNumber)
            .fold<int>(0, (a, b) => a > b ? a : b) ??
        0;

    // Calculate time remaining based on elapsed time
    final duration = _getDurationForPhase(currentSession.phase);
    final elapsed = currentSession.elapsed;
    final remaining = duration.inSeconds > elapsed.inSeconds
        ? duration - elapsed
        : Duration.zero;

    state = state.copyWith(
      currentSession: currentSession,
      allSessions: allSessions,
      currentPhase: currentSession.phase,
      timeRemaining: remaining,
      isRunning: remaining.inSeconds > 0, // Was running if still has time
      isPaused: false,
      pomodoroCountToday: completed,
      sequenceProgress: maxSequence,
    );
  }

  /// Get duration for a phase based on current settings
  Duration _getDurationForPhase(PomodoroPhase phase) {
    switch (phase) {
      case PomodoroPhase.work:
        return Duration(minutes: _settings.pomodoroWorkMinutes);
      case PomodoroPhase.shortBreak:
        return Duration(minutes: _settings.pomodoroShortBreakMinutes);
      case PomodoroPhase.longBreak:
        return Duration(minutes: _settings.pomodoroLongBreakMinutes);
    }
  }

  /// Start the 1-second update timer
  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
    });
  }

  /// Called every second
  void _tick() {
    if (!state.isRunning) return;
    if (state.isPaused) return;

    final newRemaining =
        state.timeRemaining.inSeconds > 0 ? state.timeRemaining - const Duration(seconds: 1) : Duration.zero;

    state = state.copyWith(timeRemaining: newRemaining);

    // Check if phase completed
    if (newRemaining.inSeconds == 0) {
      _completePhase();
    }
  }

  /// Called when a phase completes
  Future<void> _completePhase() async {
    final session = state.currentSession;
    if (session == null) return;

    // Mark as completed
    session.completed = true;
    session.endTime = DateTime.now();
    await session.save();

    // Play notification
    if (_settings.pomodoroShowNotifications) {
      await PomodoroNotificationService.showPhaseCompleted(
        phase: session.phase,
      );
    }

    // Transition to next phase
    await _transitionToNextPhase();

    // Auto-start if enabled
    if (_settings.pomodoroAutoStart) {
      startSession();
    }
  }

  /// Transition to the next phase in the sequence
  Future<void> _transitionToNextPhase() async {
    final currentSession = state.currentSession;
    if (currentSession == null) return;

    final nextSequence = currentSession.sequenceNumber + 1;
    final nextPhase = _getPhaseForSequence(nextSequence);

    // Create new session
    final newSession = PomodoroSession(
      startTime: DateTime.now(),
      phase: nextPhase,
      sequenceNumber: nextSequence,
    );

    await _box.add(newSession);

    // Update state
    final duration = _getDurationForPhase(nextPhase);
    state = state.copyWith(
      currentSession: newSession,
      currentPhase: nextPhase,
      timeRemaining: duration,
      isRunning: false,
      isPaused: false,
      sequenceProgress: nextSequence,
      pomodoroCountToday: _countCompletedPomodoros(),
    );
  }

  /// Get phase for sequence number (1-4 work, 5 long break, 6-7 work, 8 long break, then repeat)
  PomodoroPhase _getPhaseForSequence(int sequence) {
    final mod = (sequence - 1) % 8;
    if (mod < 4) return PomodoroPhase.work; // 1-4: work
    if (mod == 4) return PomodoroPhase.longBreak; // 5: long break
    if (mod < 7) return PomodoroPhase.work; // 6-7: work
    return PomodoroPhase.longBreak; // 8: long break
  }

  /// Count completed pomodoros today
  int _countCompletedPomodoros() {
    return state.allSessions
        .where((s) => s.isToday && s.phase == PomodoroPhase.work && s.completed)
        .length;
  }

  /// Start a new session (or resume if paused)
  void startSession() {
    if (state.currentSession == null) {
      // Create first session of the day
      final newSession = PomodoroSession(
        startTime: DateTime.now(),
        phase: PomodoroPhase.work,
        sequenceNumber: 1,
      );
      _box.add(newSession);

      final duration = _getDurationForPhase(PomodoroPhase.work);
      state = state.copyWith(
        currentSession: newSession,
        currentPhase: PomodoroPhase.work,
        timeRemaining: duration,
        isRunning: true,
        isPaused: false,
        sequenceProgress: 1,
      );
    } else {
      // Resume if paused
      state = state.copyWith(isRunning: true, isPaused: false);
    }
  }

  /// Pause the current session
  void pauseSession() {
    if (!state.isRunning) return;
    state = state.copyWith(isRunning: false, isPaused: true);
  }

  /// Resume a paused session
  void resumeSession() {
    if (!state.isPaused) return;
    state = state.copyWith(isRunning: true, isPaused: false);
  }

  /// Skip current phase and move to next
  Future<void> skipSession() async {
    final session = state.currentSession;
    if (session == null) return;

    session.skipped = true;
    session.endTime = DateTime.now();
    await session.save();

    await _transitionToNextPhase();
  }

  /// Stop the timer and complete the session
  Future<void> stopSession() async {
    final session = state.currentSession;
    if (session == null) return;

    session.endTime = DateTime.now();
    await session.save();

    state = state.copyWith(
      currentSession: null,
      isRunning: false,
      isPaused: false,
      pomodoroCountToday: _countCompletedPomodoros(),
    );
  }

  /// Sync with work entry status (auto pause/resume)
  void syncWithWorkEntry(WorkEntry? workEntry) {
    if (workEntry == null) {
      // No active work entry - don't force stop, but could pause
      return;
    }

    // If work entry is active and timer is paused, resume timer
    if (workEntry.stop == null && state.isPaused && state.currentSession != null) {
      resumeSession();
    }

    // If work entry is paused and timer is running, pause timer
    if (workEntry.pauses.isNotEmpty &&
        workEntry.pauses.last.end == null &&
        state.isRunning) {
      pauseSession();
    }

    // If work entry stopped, don't auto-stop timer (user can finish manually)
  }

  /// Update settings (called when settings change)
  void updateSettings(Settings settings) {
    _settings = settings;
    // Recalculate time remaining based on new settings if needed
    if (state.currentSession != null) {
      final newDuration = _getDurationForPhase(state.currentPhase);
      final elapsed = state.currentSession!.elapsed;
      final remaining = newDuration.inSeconds > elapsed.inSeconds
          ? newDuration - elapsed
          : Duration.zero;

      state = state.copyWith(timeRemaining: remaining);
    }
  }

  /// Cleanup resources
  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
