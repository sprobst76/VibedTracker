import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../services/holiday_service.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  final HolidayService _holidayService = HolidayService();
  Map<DateTime, Holiday> _holidays = {};

  static DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    try {
      final year = DateTime.now().year;
      final holidays = await _holidayService.fetchHolidays(year);
      final nextYearHolidays = await _holidayService.fetchHolidays(year + 1);
      final prevYearHolidays = await _holidayService.fetchHolidays(year - 1);

      setState(() {
        _holidays = {
          for (final h in [...prevYearHolidays, ...holidays, ...nextYearHolidays])
            DateTime(h.date.year, h.date.month, h.date.day): h
        };
      });
    } catch (e) {
      // Feiertage konnten nicht geladen werden
    }
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final workEntries = ref.watch(workListProvider);
    final vacations = ref.watch(vacationProvider);
    final settings = ref.watch(settingsProvider);
    final periodsNotifier = ref.watch(weeklyHoursPeriodsProvider.notifier);

    final weekData = _calculateWeekData(
      workEntries,
      vacations,
      settings.weeklyHours,
      periodsNotifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wochenbericht'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: _goToCurrentWeek,
            tooltip: 'Aktuelle Woche',
          ),
        ],
      ),
      body: Column(
        children: [
          // Week Selector
          _buildWeekSelector(),
          const Divider(height: 1),

          // Summary Card
          _buildSummaryCard(weekData, settings.weeklyHours),

          const Divider(height: 1),

          // Daily Breakdown
          Expanded(
            child: _buildDailyBreakdown(weekData),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final isCurrentWeek = _getWeekStart(DateTime.now()) == _selectedWeekStart;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousWeek,
          ),
          GestureDetector(
            onTap: _goToCurrentWeek,
            child: Column(
              children: [
                Text(
                  'KW ${_getWeekNumber(_selectedWeekStart)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_formatShortDate(_selectedWeekStart)} - ${_formatShortDate(weekEnd)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (isCurrentWeek)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Aktuelle Woche',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextWeek,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(WeekData weekData, double weeklyHours) {
    final difference = weekData.totalWorked - weekData.targetHours;
    final isPositive = difference >= 0;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  'Soll',
                  _formatHours(weekData.targetHours),
                  Colors.grey,
                  subtitle: '${weekData.workDays} Arbeitstage',
                ),
                _buildSummaryItem(
                  'Ist',
                  _formatHours(weekData.totalWorked),
                  Colors.blue,
                  subtitle: '${weekData.entriesCount} Einträge',
                ),
                _buildSummaryItem(
                  isPositive ? 'Überstunden' : 'Fehlzeit',
                  '${isPositive ? '+' : ''}${_formatHours(difference)}',
                  isPositive ? Colors.green : Colors.red,
                ),
              ],
            ),
            if (weekData.pauseHours > 0) ...[
              const SizedBox(height: 12),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.coffee, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Pausen: ${_formatHours(weekData.pauseHours)}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            if (weekData.holidayCount > 0 || weekData.vacationCount > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  if (weekData.holidayCount > 0)
                    Chip(
                      avatar: const Icon(Icons.celebration, size: 16),
                      label: Text('${weekData.holidayCount} Feiertag(e)'),
                      backgroundColor: Colors.red.shade50,
                    ),
                  if (weekData.vacationCount > 0)
                    Chip(
                      avatar: const Icon(Icons.beach_access, size: 16),
                      label: Text('${weekData.vacationCount} Urlaubstag(e)'),
                      backgroundColor: Colors.orange.shade50,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color, {String? subtitle}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
      ],
    );
  }

  Widget _buildDailyBreakdown(WeekData weekData) {
    return ListView.builder(
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = _selectedWeekStart.add(Duration(days: index));
        final dayData = weekData.days[index];
        final isToday = _isSameDay(day, DateTime.now());
        final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

        return Container(
          color: isToday ? Colors.blue.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getDayColor(dayData, isWeekend),
              child: Text(
                _getWeekdayShort(day.weekday),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Row(
              children: [
                Text(
                  _formatDate(day),
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Heute',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
            subtitle: _buildDaySubtitle(dayData, isWeekend),
            trailing: dayData.workedHours > 0
                ? Text(
                    _formatHours(dayData.workedHours),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDaySubtitle(DayData dayData, bool isWeekend) {
    final parts = <String>[];

    if (dayData.isHoliday) {
      parts.add('Feiertag: ${dayData.holidayName}');
    }
    if (dayData.isVacation) {
      parts.add('Urlaub');
    }
    if (isWeekend && !dayData.isHoliday && !dayData.isVacation) {
      parts.add('Wochenende');
    }
    if (dayData.entriesCount > 0) {
      parts.add('${dayData.entriesCount} Eintrag${dayData.entriesCount > 1 ? 'e' : ''}');
    }
    if (dayData.pauseHours > 0) {
      parts.add('Pause: ${_formatHours(dayData.pauseHours)}');
    }

    if (parts.isEmpty && !isWeekend) {
      parts.add('Keine Einträge');
    }

    return Text(
      parts.join(' • '),
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 12,
      ),
    );
  }

  Color _getDayColor(DayData dayData, bool isWeekend) {
    if (dayData.isHoliday) return Colors.red;
    if (dayData.isVacation) return Colors.orange;
    if (isWeekend) return Colors.grey;
    if (dayData.workedHours > 0) return Colors.green;
    return Colors.grey.shade400;
  }

  WeekData _calculateWeekData(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    double defaultWeeklyHours,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final days = <DayData>[];
    var totalWorked = 0.0;
    var totalPause = 0.0;
    var totalTargetHours = 0.0;
    var workDays = 0;
    var holidayCount = 0;
    var vacationCount = 0;
    var entriesCount = 0;

    for (var i = 0; i < 7; i++) {
      final day = _selectedWeekStart.add(Duration(days: i));
      final normalizedDay = DateTime(day.year, day.month, day.day);
      final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

      // Check holiday
      final holiday = _holidays[normalizedDay];
      final isHoliday = holiday != null;

      // Check vacation
      final isVacation = vacations.any((v) =>
          v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);

      // Get daily target hours for this specific day (period-aware)
      final dailyHours = periodsNotifier.getDailyHoursForDate(day);

      // Calculate worked hours for this day
      var dayWorked = 0.0;
      var dayPause = 0.0;
      var dayEntries = 0;

      for (final entry in entries) {
        if (_isSameDay(entry.start, day)) {
          final endTime = entry.stop ?? DateTime.now();
          final duration = endTime.difference(entry.start);
          var workedMinutes = duration.inMinutes.toDouble();

          // Subtract pauses
          for (final pause in entry.pauses) {
            final pauseEnd = pause.end ?? DateTime.now();
            final pauseDuration = pauseEnd.difference(pause.start);
            workedMinutes -= pauseDuration.inMinutes;
            dayPause += pauseDuration.inMinutes / 60;
          }

          dayWorked += workedMinutes / 60;
          dayEntries++;
        }
      }

      // Count work days (excluding weekends, holidays, vacations)
      if (!isWeekend && !isHoliday && !isVacation) {
        workDays++;
        totalTargetHours += dailyHours;
      }

      if (isHoliday) holidayCount++;
      if (isVacation) vacationCount++;

      totalWorked += dayWorked;
      totalPause += dayPause;
      entriesCount += dayEntries;

      days.add(DayData(
        date: day,
        workedHours: dayWorked,
        pauseHours: dayPause,
        entriesCount: dayEntries,
        isHoliday: isHoliday,
        holidayName: holiday?.localName,
        isVacation: isVacation,
      ));
    }

    return WeekData(
      days: days,
      totalWorked: totalWorked,
      pauseHours: totalPause,
      targetHours: totalTargetHours,
      workDays: workDays,
      holidayCount: holidayCount,
      vacationCount: vacationCount,
      entriesCount: entriesCount,
    );
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday - 1) / 7).ceil();
  }

  String _formatShortDate(DateTime date) {
    return '${date.day}.${date.month}.';
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _getWeekdayShort(int weekday) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return days[weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Daten für einen einzelnen Tag
class DayData {
  final DateTime date;
  final double workedHours;
  final double pauseHours;
  final int entriesCount;
  final bool isHoliday;
  final String? holidayName;
  final bool isVacation;

  DayData({
    required this.date,
    required this.workedHours,
    required this.pauseHours,
    required this.entriesCount,
    required this.isHoliday,
    this.holidayName,
    required this.isVacation,
  });
}

/// Zusammenfassung für eine Woche
class WeekData {
  final List<DayData> days;
  final double totalWorked;
  final double pauseHours;
  final double targetHours;
  final int workDays;
  final int holidayCount;
  final int vacationCount;
  final int entriesCount;

  WeekData({
    required this.days,
    required this.totalWorked,
    required this.pauseHours,
    required this.targetHours,
    required this.workDays,
    required this.holidayCount,
    required this.vacationCount,
    required this.entriesCount,
  });
}
