import 'package:hive/hive.dart';
part 'settings.g.dart';

/// Theme-Modus: 0 = System, 1 = Hell, 2 = Dunkel
enum AppThemeMode {
  system, // 0
  light,  // 1
  dark,   // 2
}

@HiveType(typeId: 3)
class Settings extends HiveObject {
  @HiveField(0)
  double weeklyHours;
  @HiveField(1)
  String locale;
  @HiveField(2)
  String? outlookIcsPath;
  @HiveField(3)
  @Deprecated('Use themeMode instead')
  bool isDarkMode;
  @HiveField(4)
  bool enableLocationTracking;
  @HiveField(5)
  bool googleCalendarEnabled;
  @HiveField(6)
  String? googleCalendarId;
  @HiveField(7)
  int themeModeIndex; // 0 = system, 1 = light, 2 = dark
  @HiveField(8)
  String bundesland; // Bundesland für Feiertage (DE = alle)
  @HiveField(9)
  bool enableReminders; // Erinnerungen aktiviert
  @HiveField(10)
  int reminderHour; // Uhrzeit für tägliche Erinnerung (0-23)
  @HiveField(11)
  List<int> nonWorkingWeekdays; // Arbeitsfreie Wochentage: 1=Mo, 2=Di, ..., 7=So

  Settings({
    this.weeklyHours = 40.0,
    this.locale = 'de_DE',
    this.outlookIcsPath,
    this.isDarkMode = false,
    this.enableLocationTracking = false,
    this.googleCalendarEnabled = false,
    this.googleCalendarId,
    this.themeModeIndex = 0, // Default: System
    this.bundesland = 'DE', // Default: Alle Bundesländer
    this.enableReminders = true, // Default: aktiviert
    this.reminderHour = 18, // Default: 18:00 Uhr
    List<int>? nonWorkingWeekdays,
  }) : nonWorkingWeekdays = nonWorkingWeekdays ?? [6, 7]; // Default: Sa, So

  /// Gibt den aktuellen Theme-Modus zurück
  AppThemeMode get themeMode => AppThemeMode.values[themeModeIndex.clamp(0, 2)];

  /// Setzt den Theme-Modus
  set themeMode(AppThemeMode mode) => themeModeIndex = mode.index;

  /// Prüft ob ein Wochentag ein Standard-Arbeitstag ist
  bool isWorkingWeekday(int weekday) => !nonWorkingWeekdays.contains(weekday);

  /// Anzahl der Arbeitstage pro Woche
  int get workingDaysPerWeek => 7 - nonWorkingWeekdays.length;
}
