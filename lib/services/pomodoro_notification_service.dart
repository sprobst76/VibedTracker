import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/pomodoro_session.dart';

/// Service für Pomodoro-Timer Benachrichtigungen
/// Zeigt Benachrichtigungen wenn eine Phase endet
class PomodoroNotificationService {
  static final PomodoroNotificationService _instance =
      PomodoroNotificationService._internal();

  factory PomodoroNotificationService() => _instance;
  PomodoroNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification IDs
  static const int _pomodoroEndedId = 400;
  static const int _breakEndedId = 401;

  // Channel ID
  static const String _channelId = 'pomodoro_timer_channel';

  /// Initialisiert den Service
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // High-Priority Channel für Pomodoro-Benachrichtigungen
    const channel = AndroidNotificationChannel(
      _channelId,
      'Pomodoro Timer',
      description: 'Benachrichtigungen wenn Pomodoro-Phasen enden',
      importance: Importance.high, // Mit Sound und Vibration
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint('PomodoroNotificationService initialized');
  }

  /// Zeigt Benachrichtigung wenn eine Phase endet
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
      await service._notifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Pomodoro Timer',
            channelDescription:
                'Benachrichtigungen wenn Pomodoro-Phasen enden',
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
      debugPrint('Pomodoro phase completed notification shown: $phase');
    } catch (e) {
      debugPrint('Error showing pomodoro notification: $e');
    }
  }

  /// Entfernt alle Pomodoro-Benachrichtigungen
  Future<void> cancelAll() async {
    await _notifications.cancel(_pomodoroEndedId);
    await _notifications.cancel(_breakEndedId);
    debugPrint('All pomodoro notifications cancelled');
  }
}
