import 'package:hive/hive.dart';
part 'vacation.g.dart';

@HiveType(typeId: 2)
class Vacation extends HiveObject {
  @HiveField(0)
  DateTime day;
  @HiveField(1)
  String? description;

  Vacation({required this.day, this.description});
}
