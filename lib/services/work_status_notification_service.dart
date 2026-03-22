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
/// - Netto-Arbeitszeit als nativer Chronometer (live, kein Flutter-Timer nötig)
///   → `when = entry.start + abgeschlossene_Pausen`, sodass Pausenzeiten
///     korrekt herausgerechnet sind
/// - Pause-Dauer während Pause (minütlich aktualisiert)
/// - [Pause / Fortsetzen] und [Stopp] Buttons
///
/// Die Notification ist nicht wischbar (ongoing: true).
class WorkStatusNotificationService {
  static final WorkStatusNotificationService _instance =
      WorkStatusNotificationService._internal();
  factory WorkStatusNotificationService() => _instance;
  WorkStatusNotificationService._internal();

  bool _initialized = false;
  Timer? _updateTimer;

  static const int    _statusNotificationId = 200;
  static const String _channelId            = 'work_status_channel';

  static const String actionStop   = 'work_action_stop';
  static const String actionPause  = 'work_action_pause';
  static const String actionResume = 'work_action_resume';

  static const String _pendingActionKey = 'work_status_pending_action';

  void Function(String action)? _actionCallback;

  void setActionCallback(void Function(String action) callback) {
    _actionCallback = callback;
  }

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
    log('WorkStatusNotificationService initialized',
        name: 'WorkStatusNotificationService');
  }

  // ── Öffentliche API ────────────────────────────────────────────────────────

  Future<void> updateStatus(WorkEntry? runningEntry) async {
    if (runningEntry == null || runningEntry.stop != null) {
      await hideNotification();
    } else {
      await showRunningNotification(runningEntry);
    }
  }

  Future<void> showRunningNotification(WorkEntry entry) async {
    await init();
    _startUpdateTimer(entry);
    await _sendNotification(entry);
  }

  Future<void> showPausedNotification(WorkEntry entry) async {
    await showRunningNotification(entry);
  }

  Future<void> hideNotification() async {
    _stopUpdateTimer();
    await NotificationDispatcher.instance.plugin.cancel(_statusNotificationId);
  }

  static Future<String?> consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString(_pendingActionKey);
    if (action != null) await prefs.remove(_pendingActionKey);
    return action;
  }

  // ── Notification ──────────────────────────────────────────────────────────

  Future<void> _sendNotification(WorkEntry entry) async {
    final inPause         = entry.pauses.isNotEmpty && entry.pauses.last.end == null;
    final completedPauses = _completedPauseDuration(entry);
    final totalPauses     = _totalPauseDuration(entry);
    final netDuration     = DateTime.now().difference(entry.start) - totalPauses;

    // Chronometer-Ankerpunkt: entry.start verschoben um abgeschlossene Pausen
    // → Chronometer zählt korrekte Netto-Arbeitszeit, live ohne eigenen Timer.
    final chronometerWhen =
        entry.start.millisecondsSinceEpoch + completedPauses.inMilliseconds;

    String title;
    String body;
    int colorHex;
    List<AndroidNotificationAction> actions;

    if (inPause) {
      final pauseSince = DateTime.now().difference(entry.pauses.last.start);
      title    = '⏸ Pause';
      body     = 'Pausiert seit ${_fmtDuration(pauseSince)}'
                 ' · Gearbeitet: ${_fmtDuration(netDuration)}';
      colorHex = 0xFFFF9800;
      actions  = const [
        AndroidNotificationAction(actionResume, 'Fortsetzen',
            showsUserInterface: true, cancelNotification: false),
        AndroidNotificationAction(actionStop, 'Stopp',
            showsUserInterface: true, cancelNotification: false),
      ];
    } else {
      title = '▶ Arbeitszeit läuft';
      // Body zeigt Start + Pauseninfo; Chronometer zeigt live die Nettozeit.
      body  = 'Seit ${_fmtTime(entry.start)}';
      if (completedPauses.inMinutes > 0) {
        body += ' · Pause: ${_fmtDuration(completedPauses)}';
      }
      colorHex = 0xFF4CAF50;
      actions  = const [
        AndroidNotificationAction(actionPause, 'Pause',
            showsUserInterface: true, cancelNotification: false),
        AndroidNotificationAction(actionStop, 'Stopp',
            showsUserInterface: true, cancelNotification: false),
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
          playSound: false,
          enableVibration: false,
          icon: '@mipmap/ic_launcher',
          color: Color(colorHex),
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          showWhen: true,
          // Chronometer zeigt Netto-Arbeitszeit live ohne Flutter-Timer.
          // Bei Pause: zeigt Start der Pause (bleibt stehen = sichtbar statisch).
          usesChronometer: !inPause,
          chronometerCountDown: false,
          when: inPause
              ? entry.pauses.last.start.millisecondsSinceEpoch
              : chronometerWhen,
          actions: actions,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ── Handler ───────────────────────────────────────────────────────────────

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null) return;
    if (actionId != actionStop &&
        actionId != actionPause &&
        actionId != actionResume) {
      return;
    }

    log('WorkStatus action: $actionId', name: 'WorkStatusNotificationService');

    if (_actionCallback != null) {
      _actionCallback!(actionId);
    } else {
      _savePendingAction(actionId);
    }
  }

  static Future<void> _savePendingAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, action);
  }

  // ── Update-Timer ──────────────────────────────────────────────────────────

  /// Timer läuft immer während einer Session (Arbeit + Pause).
  ///
  /// Während Arbeit: Chronometer ist live → Timer nur für Body-Text-Refresh
  ///   (Pauseninfo, falls neue Pause abgeschlossen wurde).
  /// Während Pause: Body zeigt "Pausiert seit Xmin" → jede Minute updaten.
  void _startUpdateTimer(WorkEntry entry) {
    _stopUpdateTimer();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _sendNotification(entry);
    });
  }

  void _stopUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  // ── Hilfsfunktionen ───────────────────────────────────────────────────────

  /// Summe aller **abgeschlossenen** Pausen (für Chronometer-Anker).
  Duration _completedPauseDuration(WorkEntry entry) =>
      entry.pauses
          .where((p) => p.end != null)
          .fold(Duration.zero, (s, p) => s + p.end!.difference(p.start));

  /// Summe aller Pausen inkl. laufender (für Netto-Anzeige).
  Duration _totalPauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final p in entry.pauses) {
      total += (p.end ?? DateTime.now()).difference(p.start);
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
