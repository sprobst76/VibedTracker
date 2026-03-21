import 'dart:developer';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zentraler Notification-Dispatcher: eine einzige FlutterLocalNotificationsPlugin-Instanz,
/// eine einzige initialize()-Initialisierung, mehrere Handler-Registrierungen.
///
/// Problem ohne diesen Dispatcher:
/// - Jeder Service ruft FlutterLocalNotificationsPlugin().initialize() auf
/// - Jeder Aufruf überschreibt den onDidReceiveNotificationResponse-Callback
/// - → Nur der letzte initialisierte Service bekommt Notification-Tap-Events
///
/// Lösung: Alle Services nutzen NotificationDispatcher.instance als Plugin,
/// registrieren ihren Handler einmalig. Der Dispatcher delegiert alle Events.
class NotificationDispatcher {
  static final NotificationDispatcher _instance = NotificationDispatcher._();
  NotificationDispatcher._();
  static NotificationDispatcher get instance => _instance;

  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final List<void Function(NotificationResponse)> _handlers = [];

  // SharedPreferences-Key für Background-Actions
  static const String _pendingActionKey = 'notification_pending_background_action_id';
  static const String _pendingPayloadKey = 'notification_pending_background_payload';

  /// Registriert einen Handler für Notification-Responses (Taps und Action-Buttons).
  /// Mehrere Services können sich registrieren — alle werden benachrichtigt.
  void register(void Function(NotificationResponse) handler) {
    _handlers.add(handler);
  }

  /// Initialisiert das Plugin einmalig mit kombiniertem Dispatcher.
  /// Kann mehrfach aufgerufen werden (idempotent).
  Future<void> init() async {
    if (_initialized) return;

    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _dispatchForeground,
      onDidReceiveBackgroundNotificationResponse: _dispatchBackground,
    );

    _initialized = true;
    log('NotificationDispatcher initialized', name: 'NotificationDispatcher');
  }

  /// Erstellt einen Notification-Channel auf Android.
  Future<void> createChannel(AndroidNotificationChannel channel) async {
    await init();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Foreground-Dispatch (läuft im Main Isolate)
  void _dispatchForeground(NotificationResponse response) {
    log('Notification foreground: action=${response.actionId}, id=${response.id}',
        name: 'NotificationDispatcher');
    for (final h in _handlers) {
      h(response);
    }
  }

  /// Verarbeitet ausstehende Background-Actions (beim App-Start aufrufen).
  Future<void> processPendingBackgroundActions() async {
    final prefs = await SharedPreferences.getInstance();
    final actionId = prefs.getString(_pendingActionKey);
    final payload = prefs.getString(_pendingPayloadKey);
    if (actionId == null) return;

    await prefs.remove(_pendingActionKey);
    await prefs.remove(_pendingPayloadKey);

    log('Processing pending background action: $actionId', name: 'NotificationDispatcher');
    _dispatchForeground(NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      actionId: actionId,
      payload: payload,
      id: 0,
    ));
  }
}

/// Background-Handler (muss Top-Level-Funktion sein, läuft in separatem Isolate).
@pragma('vm:entry-point')
void _dispatchBackground(NotificationResponse response) {
  // Kann nicht auf Dart-Objekte im Main Isolate zugreifen.
  // Speichert die Action für spätere Verarbeitung über SharedPreferences.
  _saveBackgroundAction(response.actionId, response.payload);
}

Future<void> _saveBackgroundAction(String? actionId, String? payload) async {
  if (actionId == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('notification_pending_background_action_id', actionId);
  if (payload != null) {
    await prefs.setString('notification_pending_background_payload', payload);
  }
}
