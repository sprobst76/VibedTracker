import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers.dart';
import '../models/vacation.dart';
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
  String? _loadedBundesland;

  @override
  void initState() {
    super.initState();
    // Feiertage werden im build() geladen, nachdem Settings verfügbar sind
  }

  Future<void> _loadHolidays(String bundesland) async {
    if (_loadedBundesland == bundesland && _holidays.isNotEmpty) return;

    try {
      final year = DateTime.now().year;
      final holidays = await _holidayService.fetchHolidaysForBundesland(year, bundesland);
      // Auch nächstes Jahr laden für Jahreswechsel
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
    final settings = ref.watch(settingsProvider);

    // Lade Feiertage wenn sich das Bundesland ändert
    if (_loadedBundesland != settings.bundesland) {
      _loadHolidays(settings.bundesland);
    }

    // Vacation days als Map für schnellen Lookup
    final vacationDays = {
      for (final v in vacations)
        DateTime(v.day.year, v.day.month, v.day.day): v
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abwesenheit verwalten'),
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

          // Abwesenheitsliste
          Expanded(
            child: _buildVacationList(vacations, notifier),
          ),
        ],
      ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton(
              onPressed: () => _showAddAbsenceDialog(notifier),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildDayCell(
    DateTime day,
    Map<DateTime, Vacation> vacationDays, {
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final vacation = vacationDays[normalizedDay];
    final isHoliday = _isHoliday(day);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Colors.black;

    if (vacation != null) {
      bgColor = vacation.type.color.withOpacity(0.3);
      textColor = vacation.type.color;
    } else if (isHoliday) {
      bgColor = Colors.red.shade100;
      textColor = Colors.red.shade700;
    } else if (isWeekend && !isOutside) {
      textColor = Colors.grey.shade600;
    }

    if (isSelected) {
      bgColor = Colors.blue.shade300;
      textColor = Colors.white;
    } else if (isToday && vacation == null) {
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
    Map<DateTime, Vacation> vacationDays,
    VacationNotifier notifier,
  ) {
    final normalizedDay = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final vacation = vacationDays[normalizedDay];
    final holiday = _getHoliday(_selectedDay!);

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
              if (vacation != null)
                Chip(
                  avatar: Icon(vacation.type.icon, size: 16),
                  label: Text(vacation.type.label),
                  backgroundColor: vacation.type.color.withOpacity(0.2),
                ),
              if (holiday != null)
                Chip(
                  label: Text(holiday.localName),
                  backgroundColor: Colors.red.shade100,
                ),
            ],
          ),
          if (vacation != null && vacation.description != null)
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
              if (vacation == null)
                ElevatedButton.icon(
                  onPressed: () => _showAddAbsenceDialog(notifier),
                  icon: const Icon(Icons.add),
                  label: const Text('Abwesenheit eintragen'),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: () => _showEditAbsenceDialog(notifier, vacation),
                  icon: const Icon(Icons.edit),
                  label: const Text('Bearbeiten'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => notifier.removeVacation(_selectedDay!),
                  icon: const Icon(Icons.delete),
                  label: const Text('Entfernen'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVacationList(List<Vacation> vacations, VacationNotifier notifier) {
    if (vacations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Keine Abwesenheiten eingetragen',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Tippe auf einen Tag, um Abwesenheit einzutragen',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Sortiert nach Datum
    final sortedVacations = List<Vacation>.from(vacations)
      ..sort((a, b) => a.day.compareTo(b.day));

    return ListView.builder(
      itemCount: sortedVacations.length,
      itemBuilder: (context, index) {
        final vacation = sortedVacations[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: vacation.type.color,
            child: Icon(vacation.type.icon, color: Colors.white),
          ),
          title: Text(_formatDate(vacation.day)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vacation.type.label),
              if (vacation.description != null)
                Text(
                  vacation.description!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
            ],
          ),
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

  Future<void> _showAddAbsenceDialog(VacationNotifier notifier) async {
    final descController = TextEditingController();
    AbsenceType selectedType = AbsenceType.vacation;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Abwesenheit am ${_formatDate(_selectedDay!)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Typ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AbsenceType.values.map((type) {
                    final isSelected = selectedType == type;
                    return ChoiceChip(
                      avatar: Icon(type.icon, size: 16, color: isSelected ? Colors.white : type.color),
                      label: Text(type.label),
                      selected: isSelected,
                      selectedColor: type.color,
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => selectedType = type);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    hintText: 'z.B. Sommerurlaub, Grippe, ...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
      ),
    );

    if (result == true) {
      await notifier.addVacation(
        _selectedDay!,
        type: selectedType,
        description: descController.text.isEmpty ? null : descController.text,
      );
    }
  }

  Future<void> _showEditAbsenceDialog(VacationNotifier notifier, Vacation vacation) async {
    final descController = TextEditingController(text: vacation.description);
    AbsenceType selectedType = vacation.type;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Abwesenheit bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Typ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AbsenceType.values.map((type) {
                    final isSelected = selectedType == type;
                    return ChoiceChip(
                      avatar: Icon(type.icon, size: 16, color: isSelected ? Colors.white : type.color),
                      label: Text(type.label),
                      selected: isSelected,
                      selectedColor: type.color,
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => selectedType = type);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    hintText: 'z.B. Sommerurlaub, Grippe, ...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
      ),
    );

    if (result == true) {
      await notifier.updateType(_selectedDay!, selectedType);
      await notifier.updateDescription(
        _selectedDay!,
        descController.text.isEmpty ? null : descController.text,
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
            ...AbsenceType.values.map((type) =>
              _buildLegendItem(type.color.withOpacity(0.3), type.label, icon: type.icon)
            ),
            const Divider(),
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

  Widget _buildLegendItem(Color color, String label, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: icon != null ? Icon(icon, size: 14, color: Colors.white) : null,
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
