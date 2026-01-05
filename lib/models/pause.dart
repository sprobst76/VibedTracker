import 'package:hive/hive.dart';
part 'pause.g.dart';

@HiveType(typeId: 1)
class Pause extends HiveObject {
  @HiveField(0)
  DateTime start;
  @HiveField(1)
  DateTime? end;

  Pause({required this.start, this.end});
}
