import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pomodoro_session.dart';
import '../providers.dart';
import '../services/pomodoro_timer_service.dart';

/// Pomodoro Timer Card Widget für Home Screen
class PomodoroCard extends ConsumerWidget {
  const PomodoroCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final timerState = ref.watch(pomodoroTimerProvider);

    // Nur anzeigen wenn Pomodoro aktiviert ist
    if (!settings.enablePomodoro) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titel und Phase
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pomodoro Timer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timerState.currentPhase == PomodoroPhase.work
                            ? 'Arbeitsphase'
                            : timerState.currentPhase == PomodoroPhase.shortBreak
                                ? 'Kurze Pause'
                                : 'Lange Pause',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Sequence Badge
                Container(
                  decoration: BoxDecoration(
                    color: _getPhaseColor(context, timerState.currentPhase),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '${timerState.sequenceProgress}/8',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Timer Display
            Center(
              child: Text(
                _formatTimer(timerState.timeRemaining),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'monospace',
                  color: _getPhaseColor(context, timerState.currentPhase),
                  letterSpacing: 2,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getPhaseColor(context, timerState.currentPhase),
                ),
                value: _getProgressValue(timerState),
              ),
            ),

            const SizedBox(height: 16),

            // Control Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Pause/Resume Button
                if (timerState.currentSession != null)
                  ElevatedButton.icon(
                    onPressed: timerState.isRunning
                        ? () => ref
                            .read(pomodoroTimerProvider.notifier)
                            .pauseSession()
                        : () => ref
                            .read(pomodoroTimerProvider.notifier)
                            .resumeSession(),
                    icon: Icon(
                      timerState.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(
                      timerState.isRunning ? 'Pause' : 'Fortsetzen',
                    ),
                  ),

                // Skip Button
                if (timerState.currentSession != null)
                  ElevatedButton.icon(
                    onPressed: () async => ref
                        .read(pomodoroTimerProvider.notifier)
                        .skipSession(),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Überspringen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.white,
                    ),
                  ),

                // Stop Button
                if (timerState.currentSession != null)
                  ElevatedButton.icon(
                    onPressed: () async => ref
                        .read(pomodoroTimerProvider.notifier)
                        .stopSession(),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stopp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),

                // Start Button
                if (timerState.currentSession == null)
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(pomodoroTimerProvider.notifier).startSession(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Starten'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getPhaseColor(
                        context,
                        timerState.currentPhase,
                      ),
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Stats/Info Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${timerState.pomodoroCountToday} Pomodoros heute',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (timerState.currentSession != null)
                  Text(
                    timerState.currentPhase == PomodoroPhase.work
                        ? 'Nächste Pause in ${timerState.timeRemaining.inMinutes}m'
                        : 'Nächste Arbeitsphase in ${timerState.timeRemaining.inMinutes}m',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Formatiert die verbleibende Zeit als MM:SS
  String _formatTimer(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Gibt die Fortschrittsquote zurück (0.0-1.0)
  double _getProgressValue(PomodoroTimerState state) {
    if (state.currentSession == null) return 0.0;

    final totalDuration = _getTotalDuration(state);
    final elapsed =
        totalDuration.inSeconds - state.timeRemaining.inSeconds;

    if (totalDuration.inSeconds == 0) return 0.0;
    return (elapsed / totalDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Gibt die Gesamtdauer der aktuellen Phase zurück
  Duration _getTotalDuration(PomodoroTimerState state) {
    switch (state.currentPhase) {
      case PomodoroPhase.work:
        return const Duration(minutes: 25); // Default, sollte von Settings kommen
      case PomodoroPhase.shortBreak:
        return const Duration(minutes: 5);
      case PomodoroPhase.longBreak:
        return const Duration(minutes: 15);
    }
  }

  /// Gibt die Farbe basierend auf der Phase zurück
  Color _getPhaseColor(BuildContext context, PomodoroPhase phase) {
    switch (phase) {
      case PomodoroPhase.work:
        return Colors.blue; // Arbeitsphase = Blau
      case PomodoroPhase.shortBreak:
        return Colors.green; // Kurze Pause = Grün
      case PomodoroPhase.longBreak:
        return Colors.purple; // Lange Pause = Lila
    }
  }
}
