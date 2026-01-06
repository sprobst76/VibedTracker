import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../services/holiday_service.dart';

// Re-export AbsenceType for convenience
export '../models/vacation.dart' show AbsenceType;

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;
  final HolidayService _holidayService = HolidayService();
  Map<DateTime, Holiday> _holidays = {};
  String? _loadedBundesland;

  static DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHolidays(String bundesland) async {
    if (_loadedBundesland == bundesland && _holidays.isNotEmpty) return;

    try {
      final year = DateTime.now().year;
      final holidays = await _holidayService.fetchHolidaysForBundesland(year, bundesland);
      final nextYearHolidays = await _holidayService.fetchHolidaysForBundesland(year + 1, bundesland);
      final prevYearHolidays = await _holidayService.fetchHolidaysForBundesland(year - 1, bundesland);

      if (mounted) {
        setState(() {
          _holidays = {
            for (final h in [...prevYearHolidays, ...holidays, ...nextYearHolidays])
              DateTime(h.date.year, h.date.month, h.date.day): h
          };
          _loadedBundesland = bundesland;
        });
      }
    } catch (e) {
      // Feiertage konnten nicht geladen werden
    }
  }

  @override
  Widget build(BuildContext context) {
    final workEntries = ref.watch(workListProvider);
    final vacations = ref.watch(vacationProvider);
    final settings = ref.watch(settingsProvider);
    final periodsNotifier = ref.watch(weeklyHoursPeriodsProvider.notifier);

    // Lade Feiertage wenn sich das Bundesland ändert
    if (_loadedBundesland != settings.bundesland) {
      _loadHolidays(settings.bundesland);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Berichte'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Woche', icon: Icon(Icons.view_week, size: 20)),
            Tab(text: 'Monat', icon: Icon(Icons.calendar_month, size: 20)),
            Tab(text: 'Jahr', icon: Icon(Icons.calendar_today, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeekView(workEntries, vacations, settings.weeklyHours, periodsNotifier),
          _buildMonthView(workEntries, vacations, settings.weeklyHours, periodsNotifier),
          _buildYearView(workEntries, vacations, settings.weeklyHours, periodsNotifier),
        ],
      ),
    );
  }

  // ============ WEEK VIEW ============
  Widget _buildWeekView(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    double weeklyHours,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final weekData = _calculateWeekData(entries, vacations, weeklyHours, periodsNotifier);

    return Column(
      children: [
        _buildWeekSelector(),
        const Divider(height: 1),
        _buildWeekSummaryCard(weekData, weeklyHours),
        const Divider(height: 1),
        Expanded(child: _buildDailyBreakdown(weekData)),
      ],
    );
  }

  Widget _buildWeekSelector() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final isCurrentWeek = _getWeekStart(DateTime.now()) == _selectedWeekStart;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
            }),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedWeekStart = _getWeekStart(DateTime.now());
            }),
            child: Column(
              children: [
                Text(
                  'KW ${_getWeekNumber(_selectedWeekStart)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_formatShortDate(_selectedWeekStart)} - ${_formatShortDate(weekEnd)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (isCurrentWeek)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Aktuelle Woche', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSummaryCard(WeekData weekData, double weeklyHours) {
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
                _buildStatItem('Soll', _formatHours(weekData.targetHours), Colors.grey,
                    subtitle: '${weekData.workDays} Tage'),
                _buildStatItem('Ist', _formatHours(weekData.totalWorked), Colors.blue,
                    subtitle: '${weekData.entriesCount} Einträge'),
                _buildStatItem(
                  isPositive ? 'Plus' : 'Minus',
                  '${isPositive ? '+' : ''}${_formatHours(difference)}',
                  isPositive ? Colors.green : Colors.red,
                  icon: isPositive ? Icons.trending_up : Icons.trending_down,
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
                  Text('Pausen: ${_formatHours(weekData.pauseHours)}',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ],
            if (weekData.holidayCount > 0 || weekData.absenceCounts.values.any((c) => c > 0)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (weekData.holidayCount > 0)
                    Chip(
                      avatar: const Icon(Icons.celebration, size: 16),
                      label: Text('${weekData.holidayCount} Feiertag(e)'),
                      backgroundColor: Colors.red.shade50,
                    ),
                  ...weekData.absenceCounts.entries
                      .where((e) => e.value > 0)
                      .map((e) => Chip(
                            avatar: Icon(e.key.icon, size: 16),
                            label: Text('${e.value} ${e.key.label}'),
                            backgroundColor: e.key.color.withAlpha(50),
                          )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============ MONTH VIEW ============
  Widget _buildMonthView(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    double weeklyHours,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final monthData = _calculateMonthData(entries, vacations, periodsNotifier);
    final isCurrentMonth = _selectedMonth.year == DateTime.now().year &&
        _selectedMonth.month == DateTime.now().month;

    return Column(
      children: [
        // Month Selector
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                }),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
                }),
                child: Column(
                  children: [
                    Text(
                      _getMonthName(_selectedMonth.month),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text('${_selectedMonth.year}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    if (isCurrentMonth)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Aktueller Monat', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                }),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Month Summary
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildOvertimeDashboard(monthData),
                const SizedBox(height: 16),
                _buildMonthDetailsCard(monthData),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOvertimeDashboard(MonthData monthData) {
    final difference = monthData.totalWorked - monthData.targetHours;
    final isPositive = difference >= 0;
    final percentage = monthData.targetHours > 0
        ? (monthData.totalWorked / monthData.targetHours * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Überstunden-Saldo', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  size: 40,
                  color: isPositive ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 12),
                Text(
                  '${isPositive ? '+' : ''}${_formatHours(difference)}',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percentage / 100).clamp(0.0, 1.5),
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percentage >= 100 ? Colors.green : Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${percentage.toStringAsFixed(1)}% des Solls erreicht',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMiniStat('Soll', _formatHours(monthData.targetHours), Colors.grey),
                _buildMiniStat('Ist', _formatHours(monthData.totalWorked), Colors.blue),
                _buildMiniStat('Arbeitstage', '${monthData.workDays}', Colors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthDetailsCard(MonthData monthData) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.calendar_today, 'Arbeitstage', '${monthData.workDays}'),
            _buildDetailRow(Icons.celebration, 'Feiertage', '${monthData.holidayCount}'),
            _buildDetailRow(Icons.coffee, 'Pausen gesamt', _formatHours(monthData.pauseHours)),
            _buildDetailRow(Icons.note, 'Einträge', '${monthData.entriesCount}'),
            const Divider(),
            const Text('Abwesenheiten', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...monthData.absenceCounts.entries.map((e) => _buildDetailRow(
                  e.key.icon,
                  e.key.label,
                  '${e.value} Tag(e)',
                  color: e.key.color,
                )),
          ],
        ),
      ),
    );
  }

  // ============ YEAR VIEW ============
  Widget _buildYearView(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    double weeklyHours,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final yearData = _calculateYearData(entries, vacations, periodsNotifier);
    final isCurrentYear = _selectedYear == DateTime.now().year;

    return Column(
      children: [
        // Year Selector
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _selectedYear--),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedYear = DateTime.now().year),
                child: Column(
                  children: [
                    Text('$_selectedYear',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    if (isCurrentYear)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Aktuelles Jahr', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _selectedYear++),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Year Summary
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildYearOvertimeCard(yearData),
                const SizedBox(height: 16),
                _buildMonthlyBreakdown(yearData),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYearOvertimeCard(YearData yearData) {
    final difference = yearData.totalWorked - yearData.targetHours;
    final isPositive = difference >= 0;

    return Card(
      color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Jahres-Überstundensaldo', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPositive ? Icons.emoji_events : Icons.warning,
                  size: 48,
                  color: isPositive ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 16),
                Text(
                  '${isPositive ? '+' : ''}${_formatHours(difference)}',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMiniStat('Soll', _formatHours(yearData.targetHours), Colors.grey),
                _buildMiniStat('Ist', _formatHours(yearData.totalWorked), Colors.blue),
                _buildMiniStat('Tage', '${yearData.workDays}', Colors.teal),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isPositive
                  ? 'Du hast ${_formatHours(difference)} mehr gearbeitet als geplant!'
                  : 'Du hast ${_formatHours(difference.abs())} weniger gearbeitet als geplant.',
              style: TextStyle(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyBreakdown(YearData yearData) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monatsübersicht', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...yearData.monthlyData.entries.map((e) {
              final month = e.key;
              final data = e.value;
              final diff = data.totalWorked - data.targetHours;
              final isPos = diff >= 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 80, child: Text(_getMonthName(month))),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: data.targetHours > 0
                            ? (data.totalWorked / data.targetHours).clamp(0.0, 1.5)
                            : 0,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isPos ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${isPos ? '+' : ''}${_formatHours(diff)}',
                        style: TextStyle(
                          color: isPos ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============ SHARED WIDGETS ============
  Widget _buildStatItem(String label, String value, Color color, {String? subtitle, IconData? icon}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: 4)],
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Text(_formatDate(day),
                    style: TextStyle(fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Heute', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ],
            ),
            subtitle: _buildDaySubtitle(dayData, isWeekend),
            trailing: dayData.workedHours > 0
                ? Text(_formatHours(dayData.workedHours),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDaySubtitle(DayData dayData, bool isWeekend) {
    final parts = <String>[];
    if (dayData.isHoliday) parts.add('Feiertag: ${dayData.holidayName}');
    if (dayData.isAbsent && dayData.absenceType != null) parts.add(dayData.absenceType!.label);
    if (isWeekend && !dayData.isHoliday && !dayData.isAbsent) parts.add('Wochenende');
    if (dayData.entriesCount > 0) parts.add('${dayData.entriesCount} Eintrag${dayData.entriesCount > 1 ? 'e' : ''}');
    if (dayData.pauseHours > 0) parts.add('Pause: ${_formatHours(dayData.pauseHours)}');
    if (parts.isEmpty && !isWeekend) parts.add('Keine Einträge');

    return Text(parts.join(' • '), style: TextStyle(color: Colors.grey.shade600, fontSize: 12));
  }

  Color _getDayColor(DayData dayData, bool isWeekend) {
    if (dayData.isHoliday) return Colors.red;
    if (dayData.isAbsent && dayData.absenceType != null) return dayData.absenceType!.color;
    if (isWeekend) return Colors.grey;
    if (dayData.workedHours > 0) return Colors.green;
    return Colors.grey.shade400;
  }

  // ============ CALCULATIONS ============
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
    final absenceCounts = <AbsenceType, int>{for (final type in AbsenceType.values) type: 0};
    var entriesCount = 0;

    for (var i = 0; i < 7; i++) {
      final day = _selectedWeekStart.add(Duration(days: i));
      final result = _calculateDayData(day, entries, vacations, periodsNotifier);

      days.add(result.dayData);
      totalWorked += result.dayData.workedHours;
      totalPause += result.dayData.pauseHours;
      entriesCount += result.dayData.entriesCount;

      if (result.dayData.isHoliday) holidayCount++;
      if (result.absence != null) {
        absenceCounts[result.absence!.type] = (absenceCounts[result.absence!.type] ?? 0) + 1;
      }

      if (result.countsAsWorkDay) {
        workDays++;
        totalTargetHours += result.dailyTarget;
      }
    }

    return WeekData(
      days: days,
      totalWorked: totalWorked,
      pauseHours: totalPause,
      targetHours: totalTargetHours,
      workDays: workDays,
      holidayCount: holidayCount,
      absenceCounts: absenceCounts,
      entriesCount: entriesCount,
    );
  }

  MonthData _calculateMonthData(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    var totalWorked = 0.0;
    var totalPause = 0.0;
    var totalTargetHours = 0.0;
    var workDays = 0;
    var holidayCount = 0;
    final absenceCounts = <AbsenceType, int>{for (final type in AbsenceType.values) type: 0};
    var entriesCount = 0;

    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;

    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_selectedMonth.year, _selectedMonth.month, d);
      final result = _calculateDayData(day, entries, vacations, periodsNotifier);

      totalWorked += result.dayData.workedHours;
      totalPause += result.dayData.pauseHours;
      entriesCount += result.dayData.entriesCount;

      if (result.dayData.isHoliday) holidayCount++;
      if (result.absence != null) {
        absenceCounts[result.absence!.type] = (absenceCounts[result.absence!.type] ?? 0) + 1;
      }

      if (result.countsAsWorkDay) {
        workDays++;
        totalTargetHours += result.dailyTarget;
      }
    }

    return MonthData(
      totalWorked: totalWorked,
      pauseHours: totalPause,
      targetHours: totalTargetHours,
      workDays: workDays,
      holidayCount: holidayCount,
      absenceCounts: absenceCounts,
      entriesCount: entriesCount,
    );
  }

  YearData _calculateYearData(
    List<WorkEntry> entries,
    List<Vacation> vacations,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    var totalWorked = 0.0;
    var totalTargetHours = 0.0;
    var workDays = 0;
    final monthlyData = <int, MonthData>{};

    for (var m = 1; m <= 12; m++) {
      final savedMonth = _selectedMonth;
      _selectedMonth = DateTime(_selectedYear, m);
      final monthData = _calculateMonthData(entries, vacations, periodsNotifier);
      _selectedMonth = savedMonth;

      monthlyData[m] = monthData;
      totalWorked += monthData.totalWorked;
      totalTargetHours += monthData.targetHours;
      workDays += monthData.workDays;
    }

    return YearData(
      totalWorked: totalWorked,
      targetHours: totalTargetHours,
      workDays: workDays,
      monthlyData: monthlyData,
    );
  }

  _DayCalculationResult _calculateDayData(
    DateTime day,
    List<WorkEntry> entries,
    List<Vacation> vacations,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final holiday = _holidays[normalizedDay];
    final isHoliday = holiday != null;

    Vacation? absence;
    try {
      absence = vacations.firstWhere((v) =>
          v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
    } catch (e) {
      absence = null;
    }

    final dailyHours = periodsNotifier.getDailyHoursForDate(day);
    var dayWorked = 0.0;
    var dayPause = 0.0;
    var dayEntries = 0;

    for (final entry in entries) {
      if (_isSameDay(entry.start, day)) {
        final endTime = entry.stop ?? DateTime.now();
        var workedMinutes = endTime.difference(entry.start).inMinutes.toDouble();
        for (final pause in entry.pauses) {
          final pauseEnd = pause.end ?? DateTime.now();
          workedMinutes -= pauseEnd.difference(pause.start).inMinutes;
          dayPause += pauseEnd.difference(pause.start).inMinutes / 60;
        }
        dayWorked += workedMinutes / 60;
        dayEntries++;
      }
    }

    final isPaidAbsence = absence != null && absence.type.isPaid;
    final countsAsWorkDay = !isWeekend && !isHoliday && !isPaidAbsence;

    return _DayCalculationResult(
      dayData: DayData(
        date: day,
        workedHours: dayWorked,
        pauseHours: dayPause,
        entriesCount: dayEntries,
        isHoliday: isHoliday,
        holidayName: holiday?.localName,
        isAbsent: absence != null,
        absenceType: absence?.type,
      ),
      absence: absence,
      countsAsWorkDay: countsAsWorkDay,
      dailyTarget: dailyHours,
    );
  }

  // ============ HELPERS ============
  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday - 1) / 7).ceil();
  }

  String _formatShortDate(DateTime date) => '${date.day}.${date.month}.';
  String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h).abs() * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _getWeekdayShort(int weekday) => const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][weekday - 1];

  String _getMonthName(int month) => const [
        'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
      ][month - 1];

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

// ============ DATA CLASSES ============
class _DayCalculationResult {
  final DayData dayData;
  final Vacation? absence;
  final bool countsAsWorkDay;
  final double dailyTarget;

  _DayCalculationResult({
    required this.dayData,
    required this.absence,
    required this.countsAsWorkDay,
    required this.dailyTarget,
  });
}

class DayData {
  final DateTime date;
  final double workedHours;
  final double pauseHours;
  final int entriesCount;
  final bool isHoliday;
  final String? holidayName;
  final bool isAbsent;
  final AbsenceType? absenceType;

  DayData({
    required this.date,
    required this.workedHours,
    required this.pauseHours,
    required this.entriesCount,
    required this.isHoliday,
    this.holidayName,
    required this.isAbsent,
    this.absenceType,
  });

  bool get isVacation => isAbsent;
}

class WeekData {
  final List<DayData> days;
  final double totalWorked;
  final double pauseHours;
  final double targetHours;
  final int workDays;
  final int holidayCount;
  final Map<AbsenceType, int> absenceCounts;
  final int entriesCount;

  WeekData({
    required this.days,
    required this.totalWorked,
    required this.pauseHours,
    required this.targetHours,
    required this.workDays,
    required this.holidayCount,
    required this.absenceCounts,
    required this.entriesCount,
  });

  int get vacationCount => absenceCounts.values.fold(0, (a, b) => a + b);
}

class MonthData {
  final double totalWorked;
  final double pauseHours;
  final double targetHours;
  final int workDays;
  final int holidayCount;
  final Map<AbsenceType, int> absenceCounts;
  final int entriesCount;

  MonthData({
    required this.totalWorked,
    required this.pauseHours,
    required this.targetHours,
    required this.workDays,
    required this.holidayCount,
    required this.absenceCounts,
    required this.entriesCount,
  });
}

class YearData {
  final double totalWorked;
  final double targetHours;
  final int workDays;
  final Map<int, MonthData> monthlyData;

  YearData({
    required this.totalWorked,
    required this.targetHours,
    required this.workDays,
    required this.monthlyData,
  });
}
