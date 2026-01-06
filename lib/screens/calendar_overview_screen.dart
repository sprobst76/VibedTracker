import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../services/holiday_service.dart';
import '../theme/theme_colors.dart';
import 'entry_edit_screen.dart';
import 'vacation_screen.dart';

class CalendarOverviewScreen extends ConsumerStatefulWidget {
  const CalendarOverviewScreen({super.key});

  @override
  ConsumerState<CalendarOverviewScreen> createState() => _CalendarOverviewScreenState();
}

class _CalendarOverviewScreenState extends ConsumerState<CalendarOverviewScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  final HolidayService _holidayService = HolidayService();
  Map<DateTime, Holiday> _holidays = {};
  String? _loadedBundesland;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  Future<void> _loadHolidays(String bundesland) async {
    if (_loadedBundesland == bundesland && _holidays.isNotEmpty) return;

    try {
      final year = _selectedMonth.year;
      final holidays = await _holidayService.fetchHolidaysForBundesland(year, bundesland);
      final nextYearHolidays = await _holidayService.fetchHolidaysForBundesland(year + 1, bundesland);

      if (mounted) {
        setState(() {
          _holidays = {
            for (final h in [...holidays, ...nextYearHolidays])
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

    if (_loadedBundesland != settings.bundesland) {
      _loadHolidays(settings.bundesland);
    }

    // Daten aufbereiten
    final workByDay = _groupWorkByDay(workEntries);
    final vacationByDay = _groupVacationByDay(vacations);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender'),
      ),
      body: Column(
        children: [
          // Monatswähler
          _buildMonthSelector(),
          const Divider(height: 1),
          // Wochentage Header
          _buildWeekdayHeader(),
          const Divider(height: 1),
          // Kalender Grid
          Expanded(
            child: _buildCalendarGrid(workByDay, vacationByDay, periodsNotifier),
          ),
          // Ausgewählter Tag Details
          if (_selectedDay != null)
            _buildDayDetails(workByDay, vacationByDay, periodsNotifier),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final isCurrentMonth = _selectedMonth.year == DateTime.now().year &&
        _selectedMonth.month == DateTime.now().month;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
              _selectedDay = null;
            }),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
              _selectedDay = DateTime.now();
            }),
            child: Column(
              children: [
                Text(
                  '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (isCurrentMonth)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Aktueller Monat',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
              _selectedDay = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: weekdays.map((day) {
          final isWeekend = day == 'Sa' || day == 'So';
          return Expanded(
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isWeekend ? context.subtleText : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(
    Map<DateTime, List<WorkEntry>> workByDay,
    Map<DateTime, Vacation> vacationByDay,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final startWeekday = firstDayOfMonth.weekday; // 1 = Monday

    final cells = <Widget>[];

    // Leere Zellen vor dem ersten Tag
    for (var i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }

    // Tage des Monats
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      cells.add(_buildDayCell(date, workByDay, vacationByDay, periodsNotifier));
    }

    return GridView.count(
      crossAxisCount: 7,
      childAspectRatio: 1.0,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }

  Widget _buildDayCell(
    DateTime date,
    Map<DateTime, List<WorkEntry>> workByDay,
    Map<DateTime, Vacation> vacationByDay,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final isToday = _isSameDay(date, DateTime.now());
    final isSelected = _selectedDay != null && _isSameDay(date, _selectedDay!);
    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    final workEntries = workByDay[normalizedDate] ?? [];
    final vacation = vacationByDay[normalizedDate];
    final holiday = _holidays[normalizedDate];

    // Arbeitsstunden berechnen
    double workedHours = 0;
    for (final entry in workEntries) {
      if (entry.stop != null) {
        var minutes = entry.stop!.difference(entry.start).inMinutes.toDouble();
        for (final pause in entry.pauses) {
          final pauseEnd = pause.end ?? DateTime.now();
          minutes -= pauseEnd.difference(pause.start).inMinutes;
        }
        workedHours += minutes / 60;
      }
    }

    // Hintergrundfarbe bestimmen mit Priorität:
    // Feiertag (100) > Krankheit (50) > Sonderurlaub (30) > Urlaub (20) > Unbezahlt (10)
    Color? bgColor;
    Color textColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    // Feiertag hat höchste Priorität (außer bei medizinischer Abwesenheit)
    final bool holidayOverridesVacation = holiday != null &&
        (vacation == null || vacation.type.isVacation || vacation.type == AbsenceType.unpaid);

    if (isSelected) {
      bgColor = Theme.of(context).colorScheme.primary;
      textColor = Theme.of(context).colorScheme.onPrimary;
    } else if (vacation != null && vacation.type.isMedical) {
      // Krankheit/Kind krank hat Priorität (auch über Feiertag visuell erkennbar)
      bgColor = vacation.type.color.withAlpha(context.isDark ? 80 : 50);
      textColor = context.isDark ? vacation.type.color.withAlpha(220) : vacation.type.color;
    } else if (holidayOverridesVacation) {
      // Feiertag überschreibt Urlaub/Sonderurlaub visuell
      bgColor = context.holidayBackground;
      textColor = context.holidayForeground;
    } else if (vacation != null) {
      // Andere Abwesenheitstypen
      bgColor = vacation.type.color.withAlpha(context.isDark ? 80 : 50);
      textColor = context.isDark ? vacation.type.color.withAlpha(220) : vacation.type.color;
    } else if (holiday != null) {
      bgColor = context.holidayBackground;
      textColor = context.holidayForeground;
    } else if (isToday) {
      bgColor = context.infoBackground;
    } else if (isWeekend) {
      textColor = context.subtleText;
    }

    // Status-Indikator mit Priorität
    Widget? indicator;
    if (!isSelected) {
      if (workedHours > 0) {
        indicator = Text(
          '${workedHours.toStringAsFixed(1)}h',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: context.isDark ? Colors.green.shade300 : Colors.green.shade700,
          ),
        );
      } else if (vacation != null && vacation.type.isMedical) {
        // Medizinische Abwesenheit immer anzeigen
        indicator = Icon(vacation.type.icon, size: 12, color: vacation.type.color);
      } else if (holidayOverridesVacation) {
        // Bei Feiertag: Feiertags-Icon, aber kleiner Punkt wenn auch Urlaub eingetragen
        indicator = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration, size: 12, color: context.holidayForeground),
            if (vacation != null) // Urlaub auf Feiertag markieren
              Container(
                margin: const EdgeInsets.only(left: 2),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: vacation.type.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        );
      } else if (vacation != null) {
        indicator = Icon(vacation.type.icon, size: 12, color: vacation.type.color);
      } else if (holiday != null) {
        indicator = Icon(Icons.celebration, size: 12, color: context.holidayForeground);
      }
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = date),
      onDoubleTap: () => _showAddMenuForDay(date),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: isToday && !isSelected
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: textColor,
                fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (indicator != null) ...[
              const SizedBox(height: 2),
              indicator,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDayDetails(
    Map<DateTime, List<WorkEntry>> workByDay,
    Map<DateTime, Vacation> vacationByDay,
    WeeklyHoursPeriodsNotifier periodsNotifier,
  ) {
    final normalizedDate = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final workEntries = workByDay[normalizedDate] ?? [];
    final vacation = vacationByDay[normalizedDate];
    final holiday = _holidays[normalizedDate];
    final dailyTarget = periodsNotifier.getDailyHoursForDate(_selectedDay!);

    // Arbeitsstunden berechnen
    double workedHours = 0;
    Duration totalPause = Duration.zero;
    for (final entry in workEntries) {
      if (entry.stop != null) {
        var minutes = entry.stop!.difference(entry.start).inMinutes.toDouble();
        for (final pause in entry.pauses) {
          final pauseEnd = pause.end ?? DateTime.now();
          final pauseDuration = pauseEnd.difference(pause.start);
          minutes -= pauseDuration.inMinutes;
          totalPause += pauseDuration;
        }
        workedHours += minutes / 60;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                _formatDate(_selectedDay!),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (holiday != null)
                Chip(
                  label: Text(holiday.localName, style: const TextStyle(fontSize: 11)),
                  backgroundColor: context.holidayBackground,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (vacation != null)
                Chip(
                  avatar: Icon(vacation.type.icon, size: 14),
                  label: Text(vacation.type.label, style: const TextStyle(fontSize: 11)),
                  backgroundColor: vacation.type.color.withAlpha(context.isDark ? 80 : 50),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          // Hinweis bei Urlaub auf Feiertag
          if (holiday != null && vacation != null && vacation.type.isVacation)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(context.isDark ? 40 : 30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Feiertag – kein Urlaubstag wird verbraucht',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Arbeitszeit-Info
          if (workEntries.isNotEmpty) ...[
            Row(
              children: [
                _buildInfoChip(Icons.access_time, '${workedHours.toStringAsFixed(1)}h', context.successForeground),
                const SizedBox(width: 8),
                _buildInfoChip(Icons.track_changes, 'Soll: ${dailyTarget.toStringAsFixed(1)}h', context.subtleText),
                if (totalPause.inMinutes > 0) ...[
                  const SizedBox(width: 8),
                  _buildInfoChip(Icons.coffee, '${totalPause.inMinutes}m Pause', context.pauseForeground),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Einträge Liste
            ...workEntries.map((entry) => _buildEntryTile(entry)),
          ] else if (vacation == null && holiday == null) ...[
            Text(
              'Keine Einträge',
              style: TextStyle(color: context.subtleText),
            ),
          ],
          const SizedBox(height: 8),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addWorkEntry(_selectedDay!),
                  icon: const Icon(Icons.add),
                  label: const Text('Arbeitszeit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addAbsence(_selectedDay!),
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Abwesenheit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEntryTile(WorkEntry entry) {
    final duration = entry.stop != null
        ? entry.stop!.difference(entry.start)
        : DateTime.now().difference(entry.start);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: entry.stop != null ? context.successBackground : context.warningBackground,
        child: Icon(
          entry.stop != null ? Icons.check : Icons.play_arrow,
          size: 16,
          color: entry.stop != null ? context.successForeground : context.warningForeground,
        ),
      ),
      title: Text(
        '${_formatTime(entry.start)} - ${entry.stop != null ? _formatTime(entry.stop!) : 'läuft'}',
      ),
      subtitle: entry.pauses.isNotEmpty
          ? Text('${entry.pauses.length} Pause(n)', style: TextStyle(fontSize: 11, color: context.subtleText))
          : null,
      trailing: Text(
        _formatDuration(duration),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: () => _editWorkEntry(entry),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Arbeitszeit hinzufügen'),
              onTap: () {
                Navigator.pop(context);
                _addWorkEntry(_selectedDay ?? DateTime.now());
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_busy),
              title: const Text('Abwesenheit eintragen'),
              onTap: () {
                Navigator.pop(context);
                _addAbsence(_selectedDay ?? DateTime.now());
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMenuForDay(DateTime date) {
    setState(() => _selectedDay = date);
    _showAddMenu();
  }

  Future<void> _addWorkEntry(DateTime date) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditScreen(
          entry: null,
          initialDate: date,
        ),
      ),
    );
    if (result == true) {
      ref.invalidate(workListProvider);
      ref.invalidate(workEntryProvider);
    }
  }

  Future<void> _editWorkEntry(WorkEntry entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditScreen(entry: entry),
      ),
    );
    if (result == true) {
      ref.invalidate(workListProvider);
      ref.invalidate(workEntryProvider);
    }
  }

  Future<void> _addAbsence(DateTime date) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const VacationScreen(),
      ),
    );
    // Refresh after returning
    ref.invalidate(vacationProvider);
  }

  // Helper methods
  Map<DateTime, List<WorkEntry>> _groupWorkByDay(List<WorkEntry> entries) {
    final map = <DateTime, List<WorkEntry>>{};
    for (final entry in entries) {
      final date = DateTime(entry.start.year, entry.start.month, entry.start.day);
      map.putIfAbsent(date, () => []).add(entry);
    }
    return map;
  }

  Map<DateTime, Vacation> _groupVacationByDay(List<Vacation> vacations) {
    return {
      for (final v in vacations)
        DateTime(v.day.year, v.day.month, v.day.day): v
    };
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _getMonthName(int month) => const [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ][month - 1];

  String _formatDate(DateTime date) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[date.weekday - 1]}, ${date.day}. ${_getMonthName(date.month)}';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
