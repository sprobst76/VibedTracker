import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class CopyEntryDialog extends StatefulWidget {
  final DateTime sourceDate;

  const CopyEntryDialog({super.key, required this.sourceDate});

  @override
  State<CopyEntryDialog> createState() => _CopyEntryDialogState();
}

class _CopyEntryDialogState extends State<CopyEntryDialog> {
  final Set<DateTime> _selectedDays = {};
  DateTime _focusedDay = DateTime.now();

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _focusedDay = focusedDay;
      final normalizedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      if (_selectedDays.contains(normalizedDay)) {
        _selectedDays.remove(normalizedDay);
      } else {
        _selectedDays.add(normalizedDay);
      }
    });
  }

  bool _isDaySelected(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _selectedDays.contains(normalizedDay);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.copy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Eintrag kopieren',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Text(
                'Wähle die Tage, auf die der Eintrag kopiert werden soll:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: TableCalendar(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  calendarFormat: CalendarFormat.month,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  selectedDayPredicate: _isDaySelected,
                  onDaySelected: _onDaySelected,
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      // Disable source day
                      if (_isSameDay(day, widget.sourceDate)) {
                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        );
                      }
                      return null;
                    },
                    selectedBuilder: (context, day, focusedDay) {
                      return Container(
                        margin: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedDays.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_selectedDays.length} Tag(e) ausgewählt',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedDays.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selectedDays.toList()),
                    icon: const Icon(Icons.copy),
                    label: Text('Kopieren (${_selectedDays.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
