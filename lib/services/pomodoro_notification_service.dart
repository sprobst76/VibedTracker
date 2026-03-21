import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/pomodoro_session.dart';
import 'notification_dispatcher.dart';

/// Service für Pomodoro-Timer Benachrichtigungen.
/// Zeigt Benachrichtigungen wenn eine Phase endet.
class PomodoroNotificationService {
  static final PomodoroNotificationService _instance =
      PomodoroNotificationService._internal();

  factory PomodoroNotificationService() => _instance;
  PomodoroNotificationService._internal();

  bool _initialized = false;

  // Notification IDs (420-429 reserviert für PomodoroNotificationService)
  static const int _pomodoroEndedId = 420;
  static const int _breakEndedId    = 421;

  static const String _channelId = 'pomodoro_timer_channel';

  FlutterLocalNotificationsPlugin get _plugin =>
      NotificationDispatcher.instance.plugin;

  /// Initialisiert Channel (idempotent).
  Future<void> init() async {
    if (_initialized) return;

    await NotificationDispatcher.instance.createChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Pomodoro Timer',
        description: 'Benachrichtigungen wenn Pomodoro-Phasen enden',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    _initialized = true;
    log('PomodoroNotificationService initialized', name: 'PomodoroNotificationService');
  }

  /// Zeigt Benachrichtigung wenn eine Phase endet.
  static Future<void> showPhaseCompleted({
    required PomodoroPhase phase,
  }) async {
    final service = PomodoroNotificationService();
    await service.init();

    String title;
    String body;
    int notificationId;
    int color;

    switch (phase) {
      case PomodoroPhase.work:
        title = '🎯 Pomodoro fertig!';
        body = 'Zeit für eine Pause.\nGuter Job! 👏';
        notificationId = _pomodoroEndedId;
        color = 0xFF2196F3; // Blue
        break;
      case PomodoroPhase.shortBreak:
        title = '☕ Pause vorbei!';
        body = 'Bereit für die nächste Runde?\nLos geht\'s! 💪';
        notificationId = _breakEndedId;
        color = 0xFF4CAF50; // Green
        break;
      case PomodoroPhase.longBreak:
        title = '🏨 Lange Pause fertig!';
        body = 'Zeit für 4 neue Pomodoros.\nErfrischt und bereit! 🚀';
        notificationId = _breakEndedId;
        color = 0xFF9C27B0; // Purple
        break;
    }

    try {
      await service._plugin.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Pomodoro Timer',
            channelDescription: 'Benachrichtigungen wenn Pomodoro-Phasen enden',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            color: Color(color),
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
      log('Pomodoro phase completed: $phase', name: 'PomodoroNotificationService');
    } catch (e) {
      log('Error showing pomodoro notification: $e', name: 'PomodoroNotificationService');
    }
  }

  /// Entfernt alle Pomodoro-Benachrichtigungen.
  Future<void> cancelAll() async {
    await _plugin.cancel(_pomodoroEndedId);
    await _plugin.cancel(_breakEndedId);
  }
}
