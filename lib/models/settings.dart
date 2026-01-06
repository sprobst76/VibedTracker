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
  @HiveField(12)
  int annualVacationDays; // Jahresurlaub in Tagen (Standard: 30)
  @HiveField(13)
  bool enableVacationCarryover; // Resturlaub ins nächste Jahr übertragen
  @HiveField(14)
  double christmasEveWorkFactor; // 24.12.: 0.0=frei, 0.5=halber Tag, 1.0=voll
  @HiveField(15)
  double newYearsEveWorkFactor; // 31.12.: 0.0=frei, 0.5=halber Tag, 1.0=voll

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
    this.annualVacationDays = 30, // Default: 30 Tage
    this.enableVacationCarryover = true, // Default: Übertrag erlaubt
    this.christmasEveWorkFactor = 0.5, // Default: halber Tag
    this.newYearsEveWorkFactor = 0.5, // Default: halber Tag
  }) : nonWorkingWeekdays = nonWorkingWeekdays ?? [6, 7]; // Default: Sa, So

  /// Gibt den aktuellen Theme-Modus zurück
  AppThemeMode get themeMode => AppThemeMode.values[themeModeIndex.clamp(0, 2)];

  /// Setzt den Theme-Modus
  set themeMode(AppThemeMode mode) => themeModeIndex = mode.index;

  /// Prüft ob ein Wochentag ein Standard-Arbeitstag ist
  bool isWorkingWeekday(int weekday) => !nonWorkingWeekdays.contains(weekday);

  /// Anzahl der Arbeitstage pro Woche
  int get workingDaysPerWeek => 7 - nonWorkingWeekdays.length;

  /// Prüft ob ein Datum Heiligabend ist
  bool isChristmasEve(DateTime date) => date.month == 12 && date.day == 24;

  /// Prüft ob ein Datum Silvester ist
  bool isNewYearsEve(DateTime date) => date.month == 12 && date.day == 31;

  /// Gibt den Arbeitsfaktor für ein spezielles Datum zurück (1.0 = normal)
  /// Berücksichtigt Heiligabend und Silvester
  double getWorkFactorForDate(DateTime date) {
    if (isChristmasEve(date)) return christmasEveWorkFactor;
    if (isNewYearsEve(date)) return newYearsEveWorkFactor;
    return 1.0;
  }

  /// Menschenlesbare Beschreibung des Arbeitsfaktors
  static String workFactorLabel(double factor) {
    if (factor <= 0.0) return 'Frei';
    if (factor <= 0.5) return 'Halber Tag';
    return 'Voller Tag';
  }
}
