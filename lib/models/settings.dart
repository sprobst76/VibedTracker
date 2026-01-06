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

  Settings({
    this.weeklyHours = 40.0,
    this.locale = 'de_DE',
    this.outlookIcsPath,
    this.isDarkMode = false,
    this.enableLocationTracking = false,
    this.googleCalendarEnabled = false,
    this.googleCalendarId,
    this.themeModeIndex = 0, // Default: System
  });

  /// Gibt den aktuellen Theme-Modus zurück
  AppThemeMode get themeMode => AppThemeMode.values[themeModeIndex.clamp(0, 2)];

  /// Setzt den Theme-Modus
  set themeMode(AppThemeMode mode) => themeModeIndex = mode.index;
}
