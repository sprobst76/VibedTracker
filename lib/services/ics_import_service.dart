import 'dart:io';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:hive/hive.dart';
import '../models/pause.dart';

class IcsImportService {
  final Box<Pause> pauseBox;
  IcsImportService(this.pauseBox);

  Future<void> importFromFile(String path) async {
    final icsString = await File(path).readAsString();
    final iCal = ICalendar.fromString(icsString);

    for (final component in iCal.data) {
      if (component['BEGIN'] != 'VEVENT') continue;
      final catsRaw = component['CATEGORIES'];
      final categories = (catsRaw is String)
          ? catsRaw.split(',')
          : (catsRaw is List ? List<String>.from(catsRaw) : []);
      if (categories.contains('Pause')) {
        final start = DateTime.parse(component['DTSTART']);
        final end = DateTime.parse(component['DTEND']);
        pauseBox.add(Pause(start: start, end: end));
      }
    }
  }
}
