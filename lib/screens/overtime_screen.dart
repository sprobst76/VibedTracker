import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/settings.dart';
import '../models/vacation.dart';
import '../models/work_entry.dart';
import '../models/weekly_hours_period.dart';
import '../services/holiday_service.dart';
import '../services/overtime_service.dart';

class OvertimeScreen extends ConsumerStatefulWidget {
  const OvertimeScreen({super.key});

  @override
  ConsumerState<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends ConsumerState<OvertimeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final HolidayService _holidayService = HolidayService();
  Map<DateTime, Holiday> _holidays = {};
  String? _loadedBundesland;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime _weekStart = _getWeekStart(DateTime.now());

  static DateTime _getWeekStart(DateTime d) {
    final days = d.weekday - 1;
    return DateTime(d.year, d.month, d.day - days);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHolidays(String bundesland) async {
    if (_loadedBundesland == bundesland && _holidays.isNotEmpty) return;
    try {
      final allEntries = <Holiday>[];
      for (final y in [_selectedYear - 1, _selectedYear, _selectedYear + 1]) {
        allEntries.addAll(await _holidayService.fetchHolidaysForBundesland(y, bundesland));
      }
      if (mounted) {
        setState(() {
          _holidays = {
            for (final h in allEntries)
              DateTime(h.date.year, h.date.month, h.date.day): h
          };
          _loadedBundesland = bundesland;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    _loadHolidays(settings.bundesland);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Überstundenkonto'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Woche'),
            Tab(text: 'Monat'),
            Tab(text: 'Jahr'),
            Tab(text: 'Gesamt'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeekTab(settings),
          _buildMonthTab(settings),
          _buildYearTab(settings),
          _buildAllTimeTab(settings),
        ],
      ),
    );
  }

  // ── Tabs ────────────────────────────────────────────────────────────────────

  Widget _buildWeekTab(Settings settings) {
    final entries = ref.watch(workEntryProvider);
    final vacations = ref.watch(vacationProvider);
    final periods = ref.watch(weeklyHoursPeriodsProvider);

    final weekEnd = _weekStart.add(const Duration(days: 6));
    final result = OvertimeService.calculate(
      from: _weekStart,
      to: weekEnd,
      entries: entries,
      settings: settings,
      periods: periods,
      holidays: _holidays.keys.toSet(),
      absences: vacations,
    );

    return Column(
      children: [
        _buildWeekNavigation(),
        _buildBalanceCard(result),
        const Divider(height: 1),
        Expanded(child: _buildDayList(result)),
      ],
    );
  }

  Widget _buildMonthTab(Settings settings) {
    final entries = ref.watch(workEntryProvider);
    final vacations = ref.watch(vacationProvider);
    final periods = ref.watch(weeklyHoursPeriodsProvider);

    final from = DateTime(_selectedYear, _selectedMonth, 1);
    final to = DateTime(_selectedYear, _selectedMonth + 1, 0); // last day of month
    final result = OvertimeService.calculate(
      from: from,
      to: to,
      entries: entries,
      settings: settings,
      periods: periods,
      holidays: _holidays.keys.toSet(),
      absences: vacations,
    );

    return Column(
      children: [
        _buildMonthNavigation(),
        _buildBalanceCard(result),
        const Divider(height: 1),
        Expanded(child: _buildDayList(result)),
      ],
    );
  }

  Widget _buildYearTab(Settings settings) {
    final entries = ref.watch(workEntryProvider);
    final vacations = ref.watch(vacationProvider);
    final periods = ref.watch(weeklyHoursPeriodsProvider);

    final from = DateTime(_selectedYear, 1, 1);
    final to = DateTime(_selectedYear, 12, 31);
    final result = OvertimeService.calculate(
      from: from,
      to: to,
      entries: entries,
      settings: settings,
      periods: periods,
      holidays: _holidays.keys.toSet(),
      absences: vacations,
    );

    return Column(
      children: [
        _buildYearNavigation(),
        _buildBalanceCard(result),
        const Divider(height: 1),
        Expanded(child: _buildMonthBreakdown(result, settings, entries, vacations, periods)),
      ],
    );
  }

  Widget _buildAllTimeTab(Settings settings) {
    final entries = ref.watch(workEntryProvider);
    final vacations = ref.watch(vacationProvider);
    final periods = ref.watch(weeklyHoursPeriodsProvider);

    final result = OvertimeService.calculateAllTime(
      entries: entries,
      settings: settings,
      periods: periods,
      holidays: _holidays.keys.toSet(),
      absences: vacations,
    );

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'Noch keine Arbeitszeiten erfasst.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        _buildAllTimeSummary(result),
        _buildBalanceCard(result),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Berechnet ab dem ersten erfassten Arbeitstag.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  Widget _buildWeekNavigation() {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final label = '${_weekStart.day}.${_weekStart.month}. – ${weekEnd.day}.${weekEnd.month}.${weekEnd.year}';
    return _buildNavRow(
      label: label,
      onPrev: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7))),
      onNext: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7))),
      onToday: () => setState(() => _weekStart = _getWeekStart(DateTime.now())),
    );
  }

  Widget _buildMonthNavigation() {
    final monthNames = const [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];
    return _buildNavRow(
      label: '${monthNames[_selectedMonth - 1]} $_selectedYear',
      onPrev: () => setState(() {
        if (_selectedMonth == 1) { _selectedMonth = 12; _selectedYear--; }
        else { _selectedMonth--; }
      }),
      onNext: () => setState(() {
        if (_selectedMonth == 12) { _selectedMonth = 1; _selectedYear++; }
        else { _selectedMonth++; }
      }),
      onToday: () => setState(() {
        _selectedYear = DateTime.now().year;
        _selectedMonth = DateTime.now().month;
      }),
    );
  }

  Widget _buildYearNavigation() {
    return _buildNavRow(
      label: '$_selectedYear',
      onPrev: () => setState(() => _selectedYear--),
      onNext: () => setState(() => _selectedYear++),
      onToday: () => setState(() => _selectedYear = DateTime.now().year),
    );
  }

  Widget _buildNavRow({
    required String label,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onToday,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(child: Center(child: TextButton(onPressed: onToday, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))))),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }

  // ── Balance Card ────────────────────────────────────────────────────────────

  Widget _buildBalanceCard(OvertimeResult result) {
    final balance = result.balanceHours;
    final isPositive = balance >= 0;
    final color = isPositive ? Colors.green.shade700 : Colors.red.shade700;
    final bgColor = isPositive ? Colors.green.shade50 : Colors.red.shade50;
    final sign = isPositive ? '+' : '';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        children: [
          Text(
            'Überstunden-Saldo',
            style: TextStyle(fontSize: 13, color: color.withAlpha(200)),
          ),
          const SizedBox(height: 8),
          Text(
            '$sign${_fmtHours(balance)}',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMiniStat('Soll', _fmtHours(result.targetHours), Colors.grey.shade700),
              _buildMiniStat('Ist', _fmtHours(result.actualHours), Colors.blue.shade700),
              _buildMiniStat('Arbeitstage', '${result.workDays}', Colors.grey.shade700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ── Tages-Liste ──────────────────────────────────────────────────────────────

  Widget _buildDayList(OvertimeResult result) {
    final weekdays = const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: result.days.length,
      itemBuilder: (ctx, i) {
        final d = result.days[i];
        final isToday = _isToday(d.date);
        return _buildDayRow(d, weekdays[d.date.weekday - 1], isToday);
      },
    );
  }

  Widget _buildDayRow(OvertimeDayResult d, String weekdayLabel, bool isToday) {
    String subtitle;
    Color subtitleColor = Colors.grey;

    switch (d.dayType) {
      case DayType.weekend:
        subtitle = 'Wochenende';
        break;
      case DayType.holiday:
        subtitle = 'Feiertag';
        subtitleColor = Colors.orange.shade700;
        break;
      case DayType.absent:
        subtitle = _absenceLabel(d.absenceType);
        subtitleColor = Colors.blue.shade600;
        break;
      case DayType.reducedWorkDay:
        subtitle = 'Soll ${_fmtHours(d.targetMinutes / 60)} (Sonderregel)';
        break;
      case DayType.workDay:
        if (d.actualMinutes == 0 && d.targetMinutes > 0) {
          subtitle = 'Kein Eintrag';
          subtitleColor = Colors.orange.shade700;
        } else {
          subtitle = 'Soll ${_fmtHours(d.targetMinutes / 60)}';
        }
        break;
    }

    final hasBalance = d.dayType == DayType.workDay || d.dayType == DayType.reducedWorkDay;
    final delta = d.deltaMinutes;
    final deltaColor = delta >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      color: isToday ? Colors.blue.shade50 : null,
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(weekdayLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                '${d.date.day}.${d.date.month}.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        title: Text(
          d.actualMinutes > 0 ? _fmtHours(d.actualMinutes / 60) : '–',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor)),
        trailing: hasBalance
            ? Text(
                '${delta >= 0 ? '+' : ''}${_fmtHours(delta / 60)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: deltaColor),
              )
            : null,
      ),
    );
  }

  // ── Monatsübersicht im Jahres-Tab ─────────────────────────────────────────

  Widget _buildMonthBreakdown(
    OvertimeResult yearResult,
    Settings settings,
    List<WorkEntry> entries,
    List<Vacation> vacations,
    List<WeeklyHoursPeriod> periods,
  ) {
    final monthNames = const [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
    ];

    double running = 0;
    final today = DateTime.now();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: 12,
      itemBuilder: (ctx, i) {
        final month = i + 1;
        final from = DateTime(_selectedYear, month, 1);
        final to = DateTime(_selectedYear, month + 1, 0);
        if (from.isAfter(today)) return const SizedBox.shrink();

        final res = OvertimeService.calculate(
          from: from,
          to: to,
          entries: entries,
          settings: settings,
          periods: periods,
          holidays: _holidays.keys.toSet(),
          absences: vacations,
        );
        running += res.balanceHours;
        final delta = res.balanceHours;
        final color = delta >= 0 ? Colors.green.shade700 : Colors.red.shade700;

        return ListTile(
          dense: true,
          leading: SizedBox(
            width: 40,
            child: Text(monthNames[i], style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          title: Row(
            children: [
              Text(_fmtHours(res.actualHours), style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(' / ${_fmtHours(res.targetHours)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${delta >= 0 ? '+' : ''}${_fmtHours(delta)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                'Σ ${running >= 0 ? '+' : ''}${_fmtHours(running)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Gesamt-Summary ──────────────────────────────────────────────────────────

  Widget _buildAllTimeSummary(OvertimeResult result) {
    if (result.days.isEmpty) return const SizedBox.shrink();
    final firstDay = result.days.first.date;
    final lastDay = result.days.last.date;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        'Zeitraum: ${firstDay.day}.${firstDay.month}.${firstDay.year} – ${lastDay.day}.${lastDay.month}.${lastDay.year}',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Hilfsmethoden ────────────────────────────────────────────────────────────

  String _fmtHours(double hours) {
    final negative = hours < 0;
    final abs = hours.abs();
    final h = abs.floor();
    final m = ((abs - h) * 60).round();
    final str = m == 0 ? '${h}h' : '${h}h ${m}m';
    return negative ? '-$str' : str;
  }

  String _absenceLabel(AbsenceType? type) {
    switch (type) {
      case AbsenceType.vacation: return 'Urlaub';
      case AbsenceType.illness: return 'Krank';
      case AbsenceType.childSick: return 'Kind krank';
      case AbsenceType.specialLeave: return 'Sonderurlaub';
      case AbsenceType.unpaid: return 'Unbezahlt';
      default: return 'Abwesend';
    }
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}
