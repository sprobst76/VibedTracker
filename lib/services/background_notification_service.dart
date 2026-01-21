import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service für Notifications aus dem Background-Isolate
/// Wird vom Geofence-Callback verwendet
class BackgroundNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notification IDs
  static const int geofenceEventNotificationId = 300;

  // Channel ID
  static const String channelId = 'geofence_event_channel';

  /// Initialisiert den Service (kann mehrfach aufgerufen werden)
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    _initialized = true;
  }

  /// Zeigt eine Notification für Geofence ENTER (Arbeitszeit gestartet)
  static Future<void> showWorkStartedNotification(DateTime timestamp) async {
    await init();

    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';

    await _notifications.show(
      geofenceEventNotificationId,
      '▶️ Arbeitszeit automatisch gestartet',
      'Gestartet um $timeStr - Tippe zum Öffnen',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Geofence Events',
          channelDescription: 'Benachrichtigungen bei automatischem Start/Stop',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFF4CAF50), // Grün
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Zeigt eine Notification für Geofence EXIT (Arbeitszeit gestoppt)
  static Future<void> showWorkStoppedNotification(DateTime timestamp) async {
    await init();

    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';

    await _notifications.show(
      geofenceEventNotificationId,
      '⏹️ Arbeitszeit automatisch gestoppt',
      'Gestoppt um $timeStr - Tippe zum Öffnen',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Geofence Events',
          channelDescription: 'Benachrichtigungen bei automatischem Start/Stop',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFF44336), // Rot
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Zeigt eine Notification dass Event ignoriert wurde (Bounce-Protection)
  static Future<void> showEventIgnoredNotification(String reason) async {
    await init();

    await _notifications.show(
      geofenceEventNotificationId + 1,
      'Geofence Event ignoriert',
      reason,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Geofence Events',
          channelDescription: 'Benachrichtigungen bei automatischem Start/Stop',
          importance: Importance.low,
          priority: Priority.low,
          icon: '@mipmap/ic_launcher',
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
