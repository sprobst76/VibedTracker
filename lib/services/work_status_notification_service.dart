import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/work_entry.dart';

/// Service für persistente Statusanzeige in der Benachrichtigungsleiste
/// Zeigt an ob Arbeitszeit läuft oder pausiert ist
class WorkStatusNotificationService {
  static final WorkStatusNotificationService _instance =
      WorkStatusNotificationService._internal();
  factory WorkStatusNotificationService() => _instance;
  WorkStatusNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _updateTimer;

  // Notification IDs
  static const int _statusNotificationId = 200;

  // Channel ID
  static const String _channelId = 'work_status_channel';

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

    // Low-Priority Channel für Status-Notification (kein Sound, minimale Störung)
    const channel = AndroidNotificationChannel(
      _channelId,
      'Arbeitszeit-Status',
      description: 'Zeigt den aktuellen Status der Arbeitszeit an',
      importance: Importance.low, // Kein Sound, nur in Statusleiste
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint('WorkStatusNotificationService initialized');
  }

  /// Zeigt die Arbeitszeit-läuft Notification
  Future<void> showRunningNotification(WorkEntry entry) async {
    await init();

    // Timer für regelmäßige Updates starten
    _startUpdateTimer(entry);

    await _updateRunningNotification(entry);
  }

  /// Aktualisiert die laufende Notification
  Future<void> _updateRunningNotification(WorkEntry entry) async {
    final duration = DateTime.now().difference(entry.start);

    // Pausen-Zeit abziehen für Netto-Arbeitszeit
    final pauseDuration = _calculatePauseDuration(entry);
    final netDuration = duration - pauseDuration;
    final netDurationStr = _formatDuration(netDuration);

    String title;
    String body;
    int color;

    if (entry.pauses.isNotEmpty && entry.pauses.last.end == null) {
      // Aktuell in Pause
      final currentPauseDuration =
          DateTime.now().difference(entry.pauses.last.start);
      title = '⏸️ Pause';
      body = 'Pausiert seit ${_formatDuration(currentPauseDuration)}\n'
          'Arbeitszeit: $netDurationStr';
      color = 0xFFFF9800; // Orange
    } else {
      // Arbeitet
      title = '▶️ Arbeitszeit läuft';
      body = 'Seit ${_formatTime(entry.start)} • $netDurationStr';
      if (pauseDuration.inMinutes > 0) {
        body += '\nPausen: ${_formatDuration(pauseDuration)}';
      }
      color = 0xFF4CAF50; // Grün
    }

    await _notifications.show(
      _statusNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Arbeitszeit-Status',
          channelDescription: 'Zeigt den aktuellen Status der Arbeitszeit an',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // Kann nicht weggewischt werden
          autoCancel: false,
          showWhen: false,
          playSound: false,
          enableVibration: false,
          icon: '@mipmap/ic_launcher',
          color: Color(color),
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          // Chronometer für automatische Zeit-Aktualisierung
          usesChronometer: entry.pauses.isEmpty ||
              entry.pauses.last.end != null, // Nur wenn nicht pausiert
          when: entry.pauses.isEmpty || entry.pauses.last.end != null
              ? entry.start.millisecondsSinceEpoch
              : null,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Zeigt die Pause-Notification
  Future<void> showPausedNotification(WorkEntry entry) async {
    await init();
    await _updateRunningNotification(entry);
  }

  /// Entfernt die Status-Notification
  Future<void> hideNotification() async {
    _stopUpdateTimer();
    await _notifications.cancel(_statusNotificationId);
    debugPrint('Work status notification hidden');
  }

  /// Startet den Timer für regelmäßige Updates
  void _startUpdateTimer(WorkEntry entry) {
    _stopUpdateTimer();
    // Update alle 30 Sekunden (für Pause-Anzeige)
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateRunningNotification(entry);
    });
  }

  /// Stoppt den Update-Timer
  void _stopUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// Berechnet die gesamte Pausendauer
  Duration _calculatePauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      total += end.difference(pause.start);
    }
    return total;
  }

  /// Formatiert Zeit für Anzeige (HH:MM)
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  /// Formatiert Dauer für Anzeige
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }

  /// Aktualisiert den Status basierend auf dem aktuellen WorkEntry
  Future<void> updateStatus(WorkEntry? runningEntry) async {
    if (runningEntry == null || runningEntry.stop != null) {
      await hideNotification();
    } else {
      await showRunningNotification(runningEntry);
    }
  }
}
