import 'package:flutter_holiday/flutter_holiday.dart';

class HolidayService {
  Future<List<DateTime>> fetchHolidays(int year) async {
    final list = await Holiday.getHolidays(year: year, country: 'DE');
    return list.map((h) => h.date).toList();
  }
}
