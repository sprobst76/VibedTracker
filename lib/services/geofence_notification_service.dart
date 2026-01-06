import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_entry.dart';

/// Notification-Typ für Geofence-Events
enum GeofenceNotificationType { autoStart, autoStop }

/// Payload für Geofence-Notifications
class GeofenceNotificationPayload {
  final GeofenceNotificationType type;
  final int workEntryKey;
  final DateTime timestamp;
  final String? zoneName;

  GeofenceNotificationPayload({
    required this.type,
    required this.workEntryKey,
    required this.timestamp,
    this.zoneName,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'workEntryKey': workEntryKey,
        'timestamp': timestamp.toIso8601String(),
        'zoneName': zoneName,
      };

  factory GeofenceNotificationPayload.fromJson(Map<String, dynamic> json) {
    return GeofenceNotificationPayload(
      type: GeofenceNotificationType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      workEntryKey: json['workEntryKey'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      zoneName: json['zoneName'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static GeofenceNotificationPayload? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return GeofenceNotificationPayload.fromJson(jsonDecode(payload));
    } catch (e) {
      return null;
    }
  }
}

/// Service für Geofence-Benachrichtigungen mit Einspruch-Möglichkeit
class GeofenceNotificationService {
  static final GeofenceNotificationService _instance =
      GeofenceNotificationService._internal();
  factory GeofenceNotificationService() => _instance;
  GeofenceNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification IDs
  static const int _autoStartNotificationId = 100;
  static const int _autoStopNotificationId = 101;

  // Action IDs
  static const String actionObjection = 'geofence_objection';
  static const String actionDismiss = 'geofence_dismiss';

  // SharedPreferences key für pending objections
  static const String _pendingObjectionKey = 'pending_geofence_objection';

  /// Initialisiert den Notification-Service
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    // Geofence Notification Channel erstellen
    const channel = AndroidNotificationChannel(
      'geofence_channel',
      'Automatische Zeiterfassung',
      description: 'Benachrichtigungen wenn Arbeitszeit automatisch gestartet/gestoppt wird',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint('GeofenceNotificationService initialized');
  }

  /// Zeigt Benachrichtigung für automatischen Arbeitsstart
  Future<void> showAutoStartNotification({
    required int workEntryKey,
    required DateTime timestamp,
    String? zoneName,
  }) async {
    await init();

    final payload = GeofenceNotificationPayload(
      type: GeofenceNotificationType.autoStart,
      workEntryKey: workEntryKey,
      timestamp: timestamp,
      zoneName: zoneName,
    );

    final timeStr = _formatTime(timestamp);
    final zoneText = zoneName != null ? ' ($zoneName)' : '';

    await _notifications.show(
      _autoStartNotificationId,
      'Arbeitszeit gestartet',
      'Automatisch um $timeStr$zoneText',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'geofence_channel',
          'Automatische Zeiterfassung',
          channelDescription:
              'Benachrichtigungen wenn Arbeitszeit automatisch gestartet/gestoppt wird',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              actionObjection,
              'Einspruch',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              actionDismiss,
              'OK',
              cancelNotification: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'geofence_category',
        ),
      ),
      payload: payload.encode(),
    );

    debugPrint('Showed auto-start notification for entry $workEntryKey');
  }

  /// Zeigt Benachrichtigung für automatischen Arbeitsstopp
  Future<void> showAutoStopNotification({
    required int workEntryKey,
    required DateTime timestamp,
    required Duration workedDuration,
    String? zoneName,
  }) async {
    await init();

    final payload = GeofenceNotificationPayload(
      type: GeofenceNotificationType.autoStop,
      workEntryKey: workEntryKey,
      timestamp: timestamp,
      zoneName: zoneName,
    );

    final timeStr = _formatTime(timestamp);
    final durationStr = _formatDuration(workedDuration);
    final zoneText = zoneName != null ? ' ($zoneName)' : '';

    await _notifications.show(
      _autoStopNotificationId,
      'Arbeitszeit beendet',
      'Automatisch um $timeStr$zoneText\nArbeitszeit: $durationStr',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'geofence_channel',
          'Automatische Zeiterfassung',
          channelDescription:
              'Benachrichtigungen wenn Arbeitszeit automatisch gestartet/gestoppt wird',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(
            'Automatisch um $timeStr$zoneText\nArbeitszeit: $durationStr',
          ),
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              actionObjection,
              'Einspruch',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              actionDismiss,
              'OK',
              cancelNotification: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'geofence_category',
        ),
      ),
      payload: payload.encode(),
    );

    debugPrint('Showed auto-stop notification for entry $workEntryKey');
  }

  /// Handler für Notification-Interaktionen (Foreground)
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint(
        'Notification response: action=${response.actionId}, payload=${response.payload}');

    if (response.actionId == actionObjection) {
      _handleObjection(response.payload);
    }
    // actionDismiss braucht keine Behandlung - Notification wird geschlossen
  }

  /// Handler für Notification-Interaktionen (Background)
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    // Im Background können wir nicht direkt auf Hive zugreifen
    // Speichere die Objection für spätere Verarbeitung
    if (response.actionId == actionObjection && response.payload != null) {
      _savePendingObjection(response.payload!);
    }
  }

  /// Speichert eine pending Objection für spätere Verarbeitung
  static Future<void> _savePendingObjection(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_pendingObjectionKey) ?? [];
    existing.add(payload);
    await prefs.setStringList(_pendingObjectionKey, existing);
    debugPrint('Saved pending objection for later processing');
  }

  /// Verarbeitet Einspruch (löscht oder korrigiert den Eintrag)
  Future<void> _handleObjection(String? payloadStr) async {
    final payload = GeofenceNotificationPayload.decode(payloadStr);
    if (payload == null) {
      debugPrint('Invalid objection payload');
      return;
    }

    await processObjection(payload);
  }

  /// Verarbeitet einen Einspruch
  Future<bool> processObjection(GeofenceNotificationPayload payload) async {
    try {
      final workBox = Hive.box<WorkEntry>('work');
      final entry = workBox.get(payload.workEntryKey);

      if (entry == null) {
        debugPrint('WorkEntry ${payload.workEntryKey} not found');
        return false;
      }

      if (payload.type == GeofenceNotificationType.autoStart) {
        // Bei Einspruch gegen Auto-Start: Eintrag löschen
        await entry.delete();
        debugPrint('Deleted auto-started entry ${payload.workEntryKey}');
      } else {
        // Bei Einspruch gegen Auto-Stop: Stop-Zeit entfernen (Eintrag läuft weiter)
        entry.stop = null;
        await entry.save();
        debugPrint('Removed stop time from entry ${payload.workEntryKey}');
      }

      return true;
    } catch (e) {
      debugPrint('Error processing objection: $e');
      return false;
    }
  }

  /// Prüft und verarbeitet pending Objections (beim App-Start aufrufen)
  Future<int> processPendingObjections() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingObjectionKey) ?? [];

    if (pending.isEmpty) return 0;

    var processed = 0;
    for (final payloadStr in pending) {
      final payload = GeofenceNotificationPayload.decode(payloadStr);
      if (payload != null) {
        final success = await processObjection(payload);
        if (success) processed++;
      }
    }

    // Pending Liste leeren
    await prefs.remove(_pendingObjectionKey);
    debugPrint('Processed $processed pending objections');
    return processed;
  }

  /// Formatiert Zeit für Anzeige
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
}
