import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers.dart';
import '../services/holiday_service.dart';

class VacationScreen extends ConsumerStatefulWidget {
  const VacationScreen({super.key});

  @override
  ConsumerState<VacationScreen> createState() => _VacationScreenState();
}

class _VacationScreenState extends ConsumerState<VacationScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  final HolidayService _holidayService = HolidayService();
  Map<DateTime, Holiday> _holidays = {};

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    try {
      final year = DateTime.now().year;
      final holidays = await _holidayService.fetchHolidays(year);
      // Auch nächstes Jahr laden für Jahreswechsel
      final nextYearHolidays = await _holidayService.fetchHolidays(year + 1);

      setState(() {
        _holidays = {
          for (final h in [...holidays, ...nextYearHolidays])
            DateTime(h.date.year, h.date.month, h.date.day): h
        };
      });
    } catch (e) {
      // Feiertage konnten nicht geladen werden - ignorieren
    }
  }

  bool _isHoliday(DateTime day) {
    return _holidays.containsKey(DateTime(day.year, day.month, day.day));
  }

  Holiday? _getHoliday(DateTime day) {
    return _holidays[DateTime(day.year, day.month, day.day)];
  }

  @override
  Widget build(BuildContext context) {
    final vacations = ref.watch(vacationProvider);
    final notifier = ref.read(vacationProvider.notifier);

    // Vacation days als Set für schnellen Lookup
    final vacationDays = {
      for (final v in vacations)
        DateTime(v.day.year, v.day.month, v.day.day): v
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Urlaub verwalten'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showLegend(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Kalender
          TableCalendar(
            locale: 'de_DE',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() => _calendarFormat = format);
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, vacationDays, isSelected: false);
              },
              selectedBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, vacationDays, isSelected: true);
              },
              todayBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, vacationDays, isToday: true);
              },
              outsideBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, vacationDays, isOutside: true);
              },
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
            ),
          ),
          const Divider(),

          // Ausgewählter Tag Info
          if (_selectedDay != null) _buildSelectedDayInfo(vacationDays, notifier),

          const Divider(),

          // Urlaubsliste
          Expanded(
            child: _buildVacationList(vacations, notifier),
          ),
        ],
      ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton(
              onPressed: () => notifier.toggleVacation(_selectedDay!),
              child: Icon(
                vacationDays.containsKey(DateTime(
                    _selectedDay!.year, _selectedDay!.month, _selectedDay!.day))
                    ? Icons.remove
                    : Icons.add,
              ),
            )
          : null,
    );
  }

  Widget _buildDayCell(
    DateTime day,
    Map<DateTime, dynamic> vacationDays, {
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final isVacation = vacationDays.containsKey(normalizedDay);
    final isHoliday = _isHoliday(day);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Colors.black;

    if (isVacation) {
      bgColor = Colors.orange.shade200;
    } else if (isHoliday) {
      bgColor = Colors.red.shade100;
      textColor = Colors.red.shade700;
    } else if (isWeekend && !isOutside) {
      textColor = Colors.grey.shade600;
    }

    if (isSelected) {
      bgColor = Colors.blue.shade300;
      textColor = Colors.white;
    } else if (isToday && !isVacation) {
      bgColor = Colors.blue.shade100;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: Colors.blue, width: 2) : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: textColor,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDayInfo(
    Map<DateTime, dynamic> vacationDays,
    VacationNotifier notifier,
  ) {
    final normalizedDay = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final vacation = vacationDays[normalizedDay];
    final holiday = _getHoliday(_selectedDay!);
    final isVacation = vacation != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _formatDate(_selectedDay!),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isVacation)
                Chip(
                  label: const Text('Urlaub'),
                  backgroundColor: Colors.orange.shade200,
                ),
              if (holiday != null)
                Chip(
                  label: Text(holiday.localName),
                  backgroundColor: Colors.red.shade100,
                ),
            ],
          ),
          if (isVacation && vacation.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                vacation.description!,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!isVacation)
                ElevatedButton.icon(
                  onPressed: () => _showAddVacationDialog(notifier),
                  icon: const Icon(Icons.beach_access),
                  label: const Text('Urlaub eintragen'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => notifier.removeVacation(_selectedDay!),
                  icon: const Icon(Icons.delete),
                  label: const Text('Urlaub entfernen'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVacationList(List vacations, VacationNotifier notifier) {
    if (vacations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.beach_access, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Keine Urlaubstage eingetragen',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Tippe auf einen Tag, um Urlaub einzutragen',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Sortiert nach Datum
    final sortedVacations = List.from(vacations)
      ..sort((a, b) => a.day.compareTo(b.day));

    return ListView.builder(
      itemCount: sortedVacations.length,
      itemBuilder: (context, index) {
        final vacation = sortedVacations[index];
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.orange,
            child: Icon(Icons.beach_access, color: Colors.white),
          ),
          title: Text(_formatDate(vacation.day)),
          subtitle: vacation.description != null
              ? Text(vacation.description!)
              : null,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => notifier.removeVacation(vacation.day),
          ),
          onTap: () {
            setState(() {
              _selectedDay = vacation.day;
              _focusedDay = vacation.day;
            });
          },
        );
      },
    );
  }

  Future<void> _showAddVacationDialog(VacationNotifier notifier) async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Urlaub am ${_formatDate(_selectedDay!)}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Beschreibung (optional)',
            hintText: 'z.B. Sommerurlaub',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result == true) {
      await notifier.addVacation(
        _selectedDay!,
        description: controller.text.isEmpty ? null : controller.text,
      );
    }
  }

  void _showLegend(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Legende'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem(Colors.orange.shade200, 'Urlaub'),
            _buildLegendItem(Colors.red.shade100, 'Feiertag'),
            _buildLegendItem(Colors.blue.shade100, 'Heute'),
            _buildLegendItem(Colors.blue.shade300, 'Ausgewählt'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    const months = [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day}. ${months[date.month - 1]} ${date.year}';
  }
}
