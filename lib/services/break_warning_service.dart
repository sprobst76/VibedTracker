import 'dart:developer';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/work_entry.dart';
import 'notification_dispatcher.dart';

/// Schwellenwerte nach § 4 ArbZG (Arbeitszeitgesetz)
///
/// - Nach  6 Stunden Nettoarbeitszeit: mind. 30 Minuten Pause
/// - Nach  9 Stunden Nettoarbeitszeit: mind. 45 Minuten Pause
///
/// Der Service prüft bei jeder Aktualisierung ob eine Warnung fällig ist
/// und sendet pro Session nur eine Warnung pro Schwellenwert.
class BreakWarningService {
  static final BreakWarningService _instance = BreakWarningService._internal();
  factory BreakWarningService() => _instance;
  BreakWarningService._internal();

  FlutterLocalNotificationsPlugin get _notifications =>
      NotificationDispatcher.instance.plugin;
  bool _initialized = false;

  // Notification-IDs
  static const int _warn6hId = 310;
  static const int _warn9hId = 311;

  // Channel
  static const String _channelId = 'break_warning_channel';

  // Schwellenwerte
  static const Duration _threshold6h = Duration(hours: 6);
  static const Duration _threshold9h = Duration(hours: 9);
  static const Duration _requiredBreak6h = Duration(minutes: 30);
  static const Duration _requiredBreak9h = Duration(minutes: 45);

  // Session-State: verhindert wiederholte Warnungen pro Session
  DateTime? _currentSessionStart;
  bool _warned6h = false;
  bool _warned9h = false;

  /// Initialisiert den Notification-Channel.
  Future<void> init() async {
    if (_initialized) return;

    await NotificationDispatcher.instance.createChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Pausenpflicht-Warnung',
        description: 'Warnt wenn gesetzliche Pausenpflicht nach § 4 ArbZG fällig ist',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    _initialized = true;
    log('BreakWarningService initialized', name: 'BreakWarningService');
  }

  /// Prüft ob Pausen-Warnungen fällig sind und sendet sie ggf.
  ///
  /// Wird periodisch aus dem HomeScreen-Timer aufgerufen (z.B. alle 60 Sek.).
  /// [entry] ist der aktuell laufende WorkEntry oder null wenn kein Tracking.
  Future<void> checkAndWarn(WorkEntry? entry) async {
    if (entry == null || entry.stop != null) {
      _resetSession();
      return;
    }

    // Session gewechselt → State zurücksetzen
    if (_currentSessionStart != entry.start) {
      _currentSessionStart = entry.start;
      _warned6h = false;
      _warned9h = false;
    }

    final netWork = calculateNetWorkDuration(entry);
    final totalPause = calculateTotalPauseDuration(entry);

    // 9h-Schwelle: Vorrang (überschreibt 6h-Warnung wenn nötig)
    if (!_warned9h && netWork >= _threshold9h && totalPause < _requiredBreak9h) {
      await init();
      _warned9h = true;
      final missing = _requiredBreak9h - totalPause;
      await _sendWarning(
        id: _warn9hId,
        netWork: netWork,
        requiredBreak: _requiredBreak9h,
        missingBreak: missing,
      );
      log('Break warning 9h sent (net: ${netWork.inMinutes} min, '
          'pause: ${totalPause.inMinutes} min)',
          name: 'BreakWarningService');
      return;
    }

    // 6h-Schwelle
    if (!_warned6h && netWork >= _threshold6h && totalPause < _requiredBreak6h) {
      await init();
      _warned6h = true;
      final missing = _requiredBreak6h - totalPause;
      await _sendWarning(
        id: _warn6hId,
        netWork: netWork,
        requiredBreak: _requiredBreak6h,
        missingBreak: missing,
      );
      log('Break warning 6h sent (net: ${netWork.inMinutes} min, '
          'pause: ${totalPause.inMinutes} min)',
          name: 'BreakWarningService');
    }
  }

  /// Berechnet die Netto-Arbeitszeit (Brutto minus Pausen).
  static Duration calculateNetWorkDuration(WorkEntry entry) {
    final end = entry.stop ?? DateTime.now();
    final gross = end.difference(entry.start);
    final pause = calculateTotalPauseDuration(entry);
    final net = gross - pause;
    return net.isNegative ? Duration.zero : net;
  }

  /// Berechnet die gesamte Pausendauer des Eintrags.
  static Duration calculateTotalPauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      final d = end.difference(pause.start);
      if (!d.isNegative) total += d;
    }
    return total;
  }

  /// Gibt zurück ob eine 6h-Warnung für die aktuelle Session fällig ist.
  /// (Pure Logik ohne Seiteneffekte — für Tests und UI.)
  static bool shouldWarn6h(WorkEntry entry) {
    final net = calculateNetWorkDuration(entry);
    final pause = calculateTotalPauseDuration(entry);
    return net >= _threshold6h && pause < _requiredBreak6h;
  }

  /// Gibt zurück ob eine 9h-Warnung für die aktuelle Session fällig ist.
  static bool shouldWarn9h(WorkEntry entry) {
    final net = calculateNetWorkDuration(entry);
    final pause = calculateTotalPauseDuration(entry);
    return net >= _threshold9h && pause < _requiredBreak9h;
  }

  /// Gibt den fälligen ArbZG-Status zurück (null = alles ok).
  static BreakWarningLevel? currentWarningLevel(WorkEntry entry) {
    if (shouldWarn9h(entry)) return BreakWarningLevel.nineHours;
    if (shouldWarn6h(entry)) return BreakWarningLevel.sixHours;
    return null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _sendWarning({
    required int id,
    required Duration netWork,
    required Duration requiredBreak,
    required Duration missingBreak,
  }) async {
    final workStr = _formatDuration(netWork);
    final missingStr = _formatDuration(missingBreak);

    await _notifications.show(
      id,
      '⚠️ Pausenpflicht (§ 4 ArbZG)',
      'Du arbeitest seit $workStr ohne ausreichende Pause. '
          'Bitte $missingStr Pause machen.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Pausenpflicht-Warnung',
          channelDescription:
              'Warnt wenn gesetzliche Pausenpflicht nach § 4 ArbZG fällig ist',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  void _resetSession() {
    _currentSessionStart = null;
    _warned6h = false;
    _warned9h = false;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}min';
    if (h > 0) return '${h}h';
    return '${m}min';
  }
}

/// Fällige Warnstufe nach ArbZG
enum BreakWarningLevel {
  /// Nach 6h Arbeit: mind. 30 Min. Pause nötig
  sixHours,

  /// Nach 9h Arbeit: mind. 45 Min. Pause nötig
  nineHours,
}
