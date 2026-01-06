import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/work_entry.dart';
import '../models/vacation.dart';
import 'holiday_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final HolidayService _holidayService = HolidayService();
  bool _initialized = false;

  /// Initialisiert den Notification-Service
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

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
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android Notification Channel erstellen
    const channel = AndroidNotificationChannel(
      'reminder_channel',
      'Erinnerungen',
      description: 'Erinnerungen für fehlende Zeiteinträge',
      importance: Importance.defaultImportance,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    // Hier könnte die App geöffnet werden
    debugPrint('Notification tapped: ${response.payload}');
  }

  /// Plant eine tägliche Erinnerung um die angegebene Uhrzeit
  Future<void> scheduleDailyReminder(int hour) async {
    await _notifications.cancelAll();

    // Nächsten Zeitpunkt für die Erinnerung berechnen
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      0, // Notification ID
      'Zeiterfassung prüfen',
      'Hast du heute deine Arbeitszeit eingetragen?',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Erinnerungen',
          channelDescription: 'Erinnerungen für fehlende Zeiteinträge',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Täglich wiederholen
      payload: 'daily_reminder',
    );

    debugPrint('Daily reminder scheduled for $hour:00');
  }

  /// Stoppt alle geplanten Erinnerungen
  Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();
    debugPrint('All reminders cancelled');
  }

  /// Berechnet die Anzahl der Tage ohne Eintrag (letzte 30 Tage)
  Future<int> getMissingDaysCount({
    required List<WorkEntry> workEntries,
    required List<Vacation> vacations,
    required String bundesland,
    int daysToCheck = 30,
  }) async {
    final missingDays = await getMissingDays(
      workEntries: workEntries,
      vacations: vacations,
      bundesland: bundesland,
      daysToCheck: daysToCheck,
    );
    return missingDays.length;
  }

  /// Gibt eine Liste der Tage ohne Eintrag zurück
  Future<List<DateTime>> getMissingDays({
    required List<WorkEntry> workEntries,
    required List<Vacation> vacations,
    required String bundesland,
    int daysToCheck = 30,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final missingDays = <DateTime>[];

    // Feiertage laden
    Map<DateTime, Holiday> holidays = {};
    try {
      final holidayList = await _holidayService.fetchHolidaysForBundesland(now.year, bundesland);
      holidays = {
        for (final h in holidayList)
          DateTime(h.date.year, h.date.month, h.date.day): h
      };
    } catch (e) {
      debugPrint('Fehler beim Laden der Feiertage: $e');
    }

    // Work entries als Set für schnellen Lookup
    final workDays = <DateTime>{};
    for (final entry in workEntries) {
      workDays.add(DateTime(entry.start.year, entry.start.month, entry.start.day));
    }

    // Vacation days als Set
    final vacationDays = <DateTime>{};
    for (final v in vacations) {
      vacationDays.add(DateTime(v.day.year, v.day.month, v.day.day));
    }

    // Prüfe jeden Tag der letzten X Tage (ohne heute)
    for (var i = 1; i <= daysToCheck; i++) {
      final day = today.subtract(Duration(days: i));
      final normalizedDay = DateTime(day.year, day.month, day.day);

      // Wochenende überspringen
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        continue;
      }

      // Feiertag überspringen
      if (holidays.containsKey(normalizedDay)) {
        continue;
      }

      // Urlaub/Abwesenheit überspringen
      if (vacationDays.contains(normalizedDay)) {
        continue;
      }

      // Prüfen ob Arbeitszeit vorhanden
      if (!workDays.contains(normalizedDay)) {
        missingDays.add(normalizedDay);
      }
    }

    // Nach Datum sortieren (neueste zuerst)
    missingDays.sort((a, b) => b.compareTo(a));
    return missingDays;
  }

  /// Zeigt eine sofortige Test-Notification
  Future<void> showTestNotification() async {
    await _notifications.show(
      999,
      'Test-Erinnerung',
      'Dies ist eine Test-Notification.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Erinnerungen',
          channelDescription: 'Erinnerungen für fehlende Zeiteinträge',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Aktualisiert die App-Badge mit der Anzahl fehlender Tage
  Future<void> updateBadge(int count) async {
    // iOS Badge aktualisieren
    if (count > 0) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(badge: true);
    }
  }
}
