import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';

/// Service für ICS-Kalender Export
class IcsService {
  final Box<WorkEntry> workBox;
  final Box<Vacation> vacBox;

  IcsService(this.workBox, this.vacBox);

  /// Baut einen iCalendar-String aus allen WorkEntries und Vacations
  String buildCalendar() {
    final calendar = VCalendar();
    calendar.productId = '-//VibedTracker//TimeTracker//DE';
    calendar.version = '2.0';

    // WorkEntries hinzufügen
    for (final entry in workBox.values) {
      final event = VEvent(parent: calendar);
      event.uid = 'work-${entry.key}@vibedtracker';
      event.start = entry.start;
      event.end = entry.stop ?? DateTime.now();
      event.summary = 'Arbeit';
      event.categories = ['Arbeit'];
      calendar.children.add(event);
    }

    // Vacations hinzufügen
    for (final vacation in vacBox.values) {
      final event = VEvent(parent: calendar);
      event.uid = 'vacation-${vacation.key}@vibedtracker';
      event.start = vacation.day;
      event.end = vacation.day.add(const Duration(days: 1));
      event.summary = vacation.description ?? 'Urlaub';
      event.categories = ['Urlaub'];
      calendar.children.add(event);
    }

    return calendar.toString();
  }
}
