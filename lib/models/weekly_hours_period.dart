import 'package:hive/hive.dart';
part 'weekly_hours_period.g.dart';

/// Represents a period with specific weekly hours target.
/// Used for tracking changing work hour requirements over time.
/// For example: 40h until March 1st, then 30h from March 1st.
@HiveType(typeId: 4)
class WeeklyHoursPeriod extends HiveObject {
  @HiveField(0)
  DateTime startDate;

  @HiveField(1)
  DateTime? endDate; // null = ongoing/no end date

  @HiveField(2)
  double weeklyHours;

  @HiveField(3)
  String? description; // Optional description like "Teilzeit"

  WeeklyHoursPeriod({
    required this.startDate,
    this.endDate,
    required this.weeklyHours,
    this.description,
  });

  /// Check if a given date falls within this period
  bool containsDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);

    if (normalizedDate.isBefore(normalizedStart)) return false;

    if (endDate != null) {
      final normalizedEnd = DateTime(endDate!.year, endDate!.month, endDate!.day);
      if (normalizedDate.isAfter(normalizedEnd)) return false;
    }

    return true;
  }

  /// Get daily target hours (assuming 5-day work week)
  double get dailyHours => weeklyHours / 5;
}
