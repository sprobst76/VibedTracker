import 'package:hive/hive.dart';

part 'work_exception.g.dart';

/// Ausnahme für arbeitsfreie Tage
/// Erlaubt es, einzelne Tage als Arbeitstag oder freien Tag zu markieren,
/// unabhängig von den Standard-Wochentags-Einstellungen.
@HiveType(typeId: 10)
class WorkException extends HiveObject {
  @HiveField(0)
  DateTime date;

  /// true = Ausnahme: doch arbeiten (z.B. Freitag ist normalerweise frei, aber heute arbeiten)
  /// false = Ausnahme: doch frei (z.B. Mittwoch ist normalerweise Arbeitstag, aber heute frei)
  @HiveField(1)
  bool isWorkingDay;

  @HiveField(2)
  String? reason;

  WorkException({
    required this.date,
    required this.isWorkingDay,
    this.reason,
  });

  /// Normalisiertes Datum für Vergleiche (ohne Uhrzeit)
  DateTime get normalizedDate => DateTime(date.year, date.month, date.day);
}
