import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_entry.dart';
import 'notification_dispatcher.dart';

/// Service für persistente Statusanzeige in der Benachrichtigungsleiste.
///
/// Zeigt während einer aktiven Session eine Ongoing-Notification mit:
/// - Startzeit und bisheriger Netto-Arbeitszeit (via nativer Chronometer)
/// - Aktuelle Pause-Dauer (falls pausiert)
/// - [Pause / Fortsetzen] und [Stopp] Buttons
///
/// Die Notification ist nicht wischbar (ongoing: true).
/// Nutzt NotificationDispatcher — keine eigene initialize()-Initialisierung.
class WorkStatusNotificationService {
  static final WorkStatusNotificationService _instance =
      WorkStatusNotificationService._internal();
  factory WorkStatusNotificationService() => _instance;
  WorkStatusNotificationService._internal();

  bool _initialized = false;
  Timer? _pauseUpdateTimer; // Nur für Pause-Anzeige nötig (kein Chronometer)

  // Notification-IDs
  static const int _statusNotificationId = 200;

  // Channel
  static const String _channelId = 'work_status_channel';

  // Action-IDs
  static const String actionStop   = 'work_action_stop';
  static const String actionPause  = 'work_action_pause';
  static const String actionResume = 'work_action_resume';

  // SharedPreferences-Key für pending Actions (Background)
  static const String _pendingActionKey = 'work_status_pending_action';

  // Callback: HomeScreen registriert sich für direkte Verarbeitung (Foreground)
  void Function(String action)? _actionCallback;

  /// Registriert einen Callback für Stopp/Pause/Fortsetzen-Actions.
  void setActionCallback(void Function(String action) callback) {
    _actionCallback = callback;
  }

  /// Initialisiert Channel und registriert Handler am NotificationDispatcher.
  Future<void> init() async {
    if (_initialized) return;

    await NotificationDispatcher.instance.createChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Arbeitszeit-Status',
        description: 'Zeigt den aktuellen Status der Arbeitszeit an',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    NotificationDispatcher.instance.register(_onNotificationResponse);

    _initialized = true;
    log('WorkStatusNotificationService initialized', name: 'WorkStatusNotificationService');
  }

  // ── Öffentliche API ──────────────────────────────────────────────────────────

  /// Aktualisiert den Status basierend auf dem aktuellen WorkEntry.
  Future<void> updateStatus(WorkEntry? runningEntry) async {
    if (runningEntry == null || runningEntry.stop != null) {
      await hideNotification();
    } else {
      await showRunningNotification(runningEntry);
    }
  }

  /// Zeigt oder aktualisiert die Ongoing-Notification für einen laufenden Entry.
  Future<void> showRunningNotification(WorkEntry entry) async {
    await init();
    _startPauseTimer(entry);
    await _sendNotification(entry);
  }

  /// Zeigt die Pause-Notification (delegiert an showRunningNotification).
  Future<void> showPausedNotification(WorkEntry entry) async {
    await showRunningNotification(entry);
  }

  /// Entfernt die Status-Notification aus der Statusleiste.
  Future<void> hideNotification() async {
    _stopPauseTimer();
    await NotificationDispatcher.instance.plugin.cancel(_statusNotificationId);
  }

  /// Liest und verarbeitet eine ausstehende Action (Background-Fallback).
  /// Gibt 'stop', 'pause', 'resume' oder null zurück.
  static Future<String?> consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString(_pendingActionKey);
    if (action != null) await prefs.remove(_pendingActionKey);
    return action;
  }

  // ── Notification ──────────────────────────────────────────────────────────

  Future<void> _sendNotification(WorkEntry entry) async {
    final inPause = entry.pauses.isNotEmpty && entry.pauses.last.end == null;
    final pauseDuration = _calculatePauseDuration(entry);
    final netDuration = DateTime.now().difference(entry.start) - pauseDuration;

    String title;
    String body;
    int colorHex;
    List<AndroidNotificationAction> actions;

    if (inPause) {
      final currentPause = DateTime.now().difference(entry.pauses.last.start);
      title = 'Pause';
      body = 'Pausiert seit ${_fmtDuration(currentPause)}'
          ' · Gearbeitet: ${_fmtDuration(netDuration)}';
      colorHex = 0xFFFF9800; // Orange
      actions = const [
        AndroidNotificationAction(
          actionResume,
          'Fortsetzen',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          actionStop,
          'Stopp',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ];
    } else {
      title = 'Arbeitszeit läuft';
      body = 'Seit ${_fmtTime(entry.start)} · ${_fmtDuration(netDuration)}';
      if (pauseDuration.inMinutes > 0) {
        body += ' · Pausen: ${_fmtDuration(pauseDuration)}';
      }
      colorHex = 0xFF4CAF50; // Grün
      actions = const [
        AndroidNotificationAction(
          actionPause,
          'Pause',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          actionStop,
          'Stopp',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ];
    }

    await NotificationDispatcher.instance.plugin.show(
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
          ongoing: true,
          autoCancel: false,
          showWhen: !inPause,
          playSound: false,
          enableVibration: false,
          icon: '@mipmap/ic_launcher',
          color: Color(colorHex),
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          // Chronometer nur bei laufender Arbeit (native Zeit-Anzeige ohne Timer)
          usesChronometer: !inPause,
          chronometerCountDown: false,
          when: !inPause ? entry.start.millisecondsSinceEpoch : null,
          actions: actions,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ── Handler ──────────────────────────────────────────────────────────────────

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null) return;
    if (actionId != actionStop && actionId != actionPause && actionId != actionResume) return;

    log('WorkStatus action: $actionId', name: 'WorkStatusNotificationService');

    if (_actionCallback != null) {
      _actionCallback!(actionId);
    } else {
      // App war nicht bereit → für späteren Resume speichern
      _savePendingAction(actionId);
    }
  }

  static Future<void> _savePendingAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, action);
  }

  // ── Pause-Timer ───────────────────────────────────────────────────────────────

  /// Timer nur für die Pause-Anzeige (aktualisiert alle 30s während Pause).
  /// Während normaler Arbeit übernimmt der native Chronometer.
  void _startPauseTimer(WorkEntry entry) {
    _stopPauseTimer();
    final inPause = entry.pauses.isNotEmpty && entry.pauses.last.end == null;
    if (inPause) {
      _pauseUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendNotification(entry);
      });
    }
  }

  void _stopPauseTimer() {
    _pauseUpdateTimer?.cancel();
    _pauseUpdateTimer = null;
  }

  // ── Hilfsfunktionen ───────────────────────────────────────────────────────────

  Duration _calculatePauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      total += end.difference(pause.start);
    }
    return total;
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }
}
