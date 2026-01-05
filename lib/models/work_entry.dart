import 'package:hive/hive.dart';
import 'pause.dart';

part 'work_entry.g.dart';

@HiveType(typeId: 0)
class WorkEntry extends HiveObject {
  @HiveField(0)
  DateTime start;
  @HiveField(1)
  DateTime? stop;
  @HiveField(2)
  List<Pause> pauses;

  WorkEntry({required this.start, this.stop, List<Pause>? pauses})
      : pauses = pauses ?? [];
}
