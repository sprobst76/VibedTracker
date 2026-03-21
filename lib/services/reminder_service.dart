import 'dart:developer';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/work_entry.dart';
import '../models/vacation.dart';
import 'holiday_service.dart';
import 'notification_dispatcher.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final HolidayService _holidayService = HolidayService();
  bool _initialized = false;
  bool _tzInitialized = false;

  // Notification IDs (410-419 reserviert für ReminderService)
  static const int _dailyReminderId        = 410;
  static const int _targetReachedId        = 411;

  // SharedPreferences key for "target already notified today"
  static const String _targetNotifiedDayKey = 'reminder_target_reached_day';

  static const String _channelId = 'reminder_channel';

  FlutterLocalNotificationsPlugin get _plugin =>
      NotificationDispatcher.instance.plugin;

  /// Initialisiert Channel (idempotent).
  Future<void> init() async {
    if (!_tzInitialized) {
      tz.initializeTimeZones();
      _tzInitialized = true;
    }
    if (_initialized) return;

    await NotificationDispatcher.instance.createChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Erinnerungen',
        description: 'Erinnerungen für fehlende Zeiteinträge und Tagesziele',
        importance: Importance.defaultImportance,
      ),
    );

    NotificationDispatcher.instance.register(_onNotificationResponse);
    _initialized = true;
    log('ReminderService initialized', name: 'ReminderService');
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload == 'daily_reminder' ||
        response.payload == 'target_reached') {
      log('ReminderService tap: ${response.payload}', name: 'ReminderService');
    }
  }

  // ── Tägliche Erinnerung ────────────────────────────────────────────────────

  /// Plant eine tägliche Erinnerung um die angegebene Uhrzeit.
  Future<void> scheduleDailyReminder(int hour) async {
    await init();
    await _plugin.cancel(_dailyReminderId);

    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _dailyReminderId,
      'Zeiterfassung prüfen',
      'Hast du heute deine Arbeitszeit eingetragen?',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Erinnerungen',
          channelDescription: 'Erinnerungen für fehlende Zeiteinträge',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_reminder',
    );

    log('Daily reminder scheduled at $hour:00', name: 'ReminderService');
  }

  /// Stoppt alle geplanten Erinnerungen.
  Future<void> cancelAllReminders() async {
    await _plugin.cancel(_dailyReminderId);
    log('Daily reminder cancelled', name: 'ReminderService');
  }

  // ── Tagesziel-Erinnerung ──────────────────────────────────────────────────

  /// Schickt einmalig pro Tag eine Benachrichtigung wenn das Tagessoll erreicht wurde.
  ///
  /// [netMinutes] – geleistete Netto-Minuten heute
  /// [targetMinutes] – Soll-Minuten für heute
  Future<void> notifyDailyTargetIfReached({
    required int netMinutes,
    required int targetMinutes,
  }) async {
    if (targetMinutes <= 0) return;
    if (netMinutes < targetMinutes) return;

    // Nur einmal pro Tag
    final today = _isoDate(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_targetNotifiedDayKey) == today) return;
    await prefs.setString(_targetNotifiedDayKey, today);

    await init();

    final h = netMinutes ~/ 60;
    final m = netMinutes % 60;
    final durStr = h > 0 ? '${h}h ${m}min' : '${m}min';

    await _plugin.show(
      _targetReachedId,
      'Tagesziel erreicht 🎉',
      'Du hast heute $durStr gearbeitet – Feierabend!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Erinnerungen',
          channelDescription: 'Erinnerungen für fehlende Zeiteinträge',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: 'target_reached',
    );

    log('Daily target notification sent ($durStr / ${targetMinutes}min target)',
        name: 'ReminderService');
  }

  // ── Fehlende Tage ─────────────────────────────────────────────────────────

  /// Berechnet die Anzahl der Tage ohne Eintrag (letzte 30 Tage)
  Future<int> getMissingDaysCount({
    required List<WorkEntry> workEntries,
    required List<Vacation> vacations,
    required String bundesland,
    int daysToCheck = 30,
  }) async {
    final missing = await getMissingDays(
      workEntries: workEntries,
      vacations: vacations,
      bundesland: bundesland,
      daysToCheck: daysToCheck,
    );
    return missing.length;
  }

  /// Gibt eine Liste der Arbeitstage ohne Eintrag zurück (letzte [daysToCheck] Tage).
  Future<List<DateTime>> getMissingDays({
    required List<WorkEntry> workEntries,
    required List<Vacation> vacations,
    required String bundesland,
    int daysToCheck = 30,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final missingDays = <DateTime>[];

    Map<DateTime, Holiday> holidays = {};
    try {
      final list = await _holidayService.fetchHolidaysForBundesland(now.year, bundesland);
      holidays = {
        for (final h in list)
          DateTime(h.date.year, h.date.month, h.date.day): h
      };
    } catch (e) {
      log('Holiday fetch error: $e', name: 'ReminderService');
    }

    final workDays = <DateTime>{
      for (final e in workEntries)
        DateTime(e.start.year, e.start.month, e.start.day)
    };

    final vacationDays = <DateTime>{
      for (final v in vacations)
        DateTime(v.day.year, v.day.month, v.day.day)
    };

    for (var i = 1; i <= daysToCheck; i++) {
      final day = today.subtract(Duration(days: i));
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        continue;
      }
      if (holidays.containsKey(day)) continue;
      if (vacationDays.contains(day)) continue;
      if (!workDays.contains(day)) missingDays.add(day);
    }

    missingDays.sort((a, b) => b.compareTo(a));
    return missingDays;
  }

  /// Zeigt eine sofortige Test-Notification.
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      999,
      'Test-Erinnerung',
      'Dies ist eine Test-Notification.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Erinnerungen',
          channelDescription: 'Erinnerungen für fehlende Zeiteinträge',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
