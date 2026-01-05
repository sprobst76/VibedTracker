import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service für deutsche Feiertage via date.nager.at API
class HolidayService {
  static const _baseUrl = 'https://date.nager.at/api/v3';

  /// Holt alle Feiertage für Deutschland im angegebenen Jahr
  Future<List<Holiday>> fetchHolidays(int year) async {
    final url = Uri.parse('$_baseUrl/PublicHolidays/$year/DE');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Holiday.fromJson(json)).toList();
    } else {
      throw Exception('Fehler beim Laden der Feiertage: ${response.statusCode}');
    }
  }

  /// Holt nur die Feiertags-Daten als DateTime-Liste
  Future<List<DateTime>> fetchHolidayDates(int year) async {
    final holidays = await fetchHolidays(year);
    return holidays.map((h) => h.date).toList();
  }

  /// Prüft ob ein Datum ein Feiertag ist
  Future<bool> isHoliday(DateTime date) async {
    final holidays = await fetchHolidayDates(date.year);
    return holidays.any((h) =>
        h.year == date.year && h.month == date.month && h.day == date.day);
  }
}

/// Modell für einen Feiertag
class Holiday {
  final DateTime date;
  final String localName;
  final String name;
  final String countryCode;
  final bool global;
  final List<String>? counties;

  Holiday({
    required this.date,
    required this.localName,
    required this.name,
    required this.countryCode,
    required this.global,
    this.counties,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      date: DateTime.parse(json['date']),
      localName: json['localName'] ?? '',
      name: json['name'] ?? '',
      countryCode: json['countryCode'] ?? 'DE',
      global: json['global'] ?? false,
      counties: json['counties'] != null
          ? List<String>.from(json['counties'])
          : null,
    );
  }
}
