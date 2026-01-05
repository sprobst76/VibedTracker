import 'package:ics/ics.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';

class IcsService {
  final Box<WorkEntry> workBox;
  final Box<Vacation> vacBox;
  IcsService(this.workBox, this.vacBox);

  String buildCalendar() {
    final cal = IcsCalendar();
    for (final e in workBox.values) {
      cal.addEvent(IcsEvent(
        uid: e.key.toString(),
        start: e.start,
        end: e.stop ?? DateTime.now(),
        summary: 'Arbeit',
        categories: ['Arbeit'],
      ));
    }
    for (final v in vacBox.values) {
      cal.addEvent(IcsEvent(
        uid: 'vac${v.key}',
        start: v.day,
        end: v.day.add(Duration(days:1)),
        summary: 'Urlaub',
        categories: ['Urlaub'],
      ));
    }
    return cal.build();
  }
}
