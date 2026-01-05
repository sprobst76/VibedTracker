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

  Settings({
    this.weeklyHours = 40.0,
    this.locale = 'de_DE',
    this.outlookIcsPath,
  });
}
