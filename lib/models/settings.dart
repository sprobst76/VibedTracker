import 'package:hive/hive.dart';
part 'settings.g.dart';

@HiveType(typeId: 3)
class Settings extends HiveObject {
  @HiveField(0)
  double weeklyHours;
  @HiveField(1)
  String locale;
  @HiveField(2)
  String? outlookIcsPath;
  @HiveField(3)
  bool isDarkMode;
  @HiveField(4)
  bool enableLocationTracking;
  @HiveField(5)
  bool googleCalendarEnabled;
  @HiveField(6)
  String? googleCalendarId;

  Settings({
    this.weeklyHours = 40.0,
    this.locale = 'de_DE',
    this.outlookIcsPath,
    this.isDarkMode = false,
    this.enableLocationTracking = false,
    this.googleCalendarEnabled = false,
    this.googleCalendarId,
  });
}
