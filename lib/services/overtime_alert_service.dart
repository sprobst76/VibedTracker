import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';
import 'notification_dispatcher.dart';

/// Prüft das Gleitzeit-Konto und sendet Push-Warnungen bei Schwellenwert-Überschreitung.
///
/// Logik:
/// - Kontostand wird in drei Zonen eingeteilt: 'high', 'low', 'normal'
/// - Notification wird nur beim Zonen-Wechsel gesendet (nicht bei jedem Check)
/// - Beim Rückweg in 'normal' wird die Warnung wieder gelöscht
class OvertimeAlertService {
  static const String _channelId = 'overtime_alerts';
  static const String _channelName = 'Kontostand-Warnungen';
  static const String _prefKey = 'overtime_alert_last_zone';
  static const int _notifId = 300;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: 'Warnungen bei Überschreitung des Überstunden- oder Minusstunden-Limits',
    importance: Importance.defaultImportance,
  );

  /// Initialisiert den Notification-Channel (einmalig beim App-Start aufrufen).
  static Future<void> init() async {
    await NotificationDispatcher.instance.createChannel(_channel);
  }

  /// Prüft den Kontostand und sendet ggf. eine Warnung.
  ///
  /// [totalBalanceHours] = Vortrag + All-Time-Saldo (wie im HomeScreen-Chip).
  /// Wird nur bei Zonen-Wechsel aktiv.
  static Future<void> checkAndNotify({
    required double totalBalanceHours,
    required Settings settings,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastZone = prefs.getString(_prefKey) ?? 'normal';

    final high = settings.overtimeWarnHighHours.toDouble();
    final low  = settings.overtimeWarnLowHours.toDouble(); // negativ

    final String currentZone;
    if (totalBalanceHours >= high) {
      currentZone = 'high';
    } else if (totalBalanceHours <= low) {
      currentZone = 'low';
    } else {
      currentZone = 'normal';
    }

    if (currentZone == lastZone) return;
    await prefs.setString(_prefKey, currentZone);

    final plugin = NotificationDispatcher.instance.plugin;

    if (currentZone == 'high') {
      final label = _fmtHours(totalBalanceHours, signed: true);
      await plugin.show(
        _notifId,
        'Überstundenkonto: $label',
        'Du hast ${settings.overtimeWarnHighHours}h Überstunden erreicht – '
            'bitte mit deiner Führungskraft abstimmen.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } else if (currentZone == 'low') {
      final label = _fmtHours(totalBalanceHours, signed: true);
      await plugin.show(
        _notifId,
        'Überstundenkonto: $label',
        'Du hast ${settings.overtimeWarnLowHours.abs()}h Minusstunden erreicht – '
            'bitte Stunden nachholen.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } else {
      // Zurück im normalen Bereich – Warnung entfernen
      await plugin.cancel(_notifId);
    }
  }

  static String _fmtHours(double h, {bool signed = false}) {
    final sign = h >= 0 ? '+' : '−';
    final abs  = h.abs();
    final hh   = abs.floor();
    final mm   = ((abs - hh) * 60).round();
    final core = mm == 0 ? '${hh}h' : '${hh}h ${mm}m';
    return signed ? '$sign$core' : core;
  }
}
