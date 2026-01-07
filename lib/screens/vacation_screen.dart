import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers.dart';
import '../models/vacation.dart';
import '../models/vacation_quota.dart';
import '../services/holiday_service.dart';
import '../theme/theme_colors.dart';
import 'vacation_quota_screen.dart';

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
      // Vorjahr, aktuelles Jahr und nächstes Jahr laden
      final prevYearHolidays = await _holidayService.fetchHolidaysForBundesland(year - 1, bundesland);
      final holidays = await _holidayService.fetchHolidaysForBundesland(year, bundesland);
      final nextYearHolidays = await _holidayService.fetchHolidaysForBundesland(year + 1, bundesland);

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
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Urlaubsanspruch pro Jahr',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VacationQuotaScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showLegend(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Urlaubskontingent-Karte
          _buildVacationStatsCard(),

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

  Widget _buildVacationStatsCard() {
    final stats = ref.watch(vacationStatsProvider(_focusedDay.year));
    final settings = ref.watch(settingsProvider);
    final isCurrentYear = _focusedDay.year == DateTime.now().year;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Urlaub ${_focusedDay.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (isCurrentYear)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Aktuell',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: stats.totalEntitlement > 0
                    ? (stats.usedDays / stats.totalEntitlement).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  stats.isOverdrawn ? Colors.red : Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                GestureDetector(
                  onTap: () => _showAnnualEntitlementDialog(stats),
                  child: _buildStatItem(
                    'Anspruch',
                    '${stats.totalEntitlement.toStringAsFixed(stats.totalEntitlement == stats.totalEntitlement.roundToDouble() ? 0 : 1)}',
                    Colors.grey,
                    subtitle: stats.carryover > 0
                        ? '(${stats.annualEntitlement.toStringAsFixed(0)} + ${stats.carryover.toStringAsFixed(0)} Übertrag)'
                        : '${stats.annualEntitlement.toStringAsFixed(0)} Tage/Jahr',
                    showEditIcon: true,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showManualUsedDaysDialog(stats),
                  child: _buildStatItem(
                  'Genommen',
                  '${stats.usedDays.toStringAsFixed(0)}',
                  Colors.orange,
                  subtitle: stats.manualDays > 0
                      ? '(${stats.trackedDays.toStringAsFixed(0)} + ${stats.manualDays.toStringAsFixed(0)} manuell)'
                      : stats.trackedDays > 0 ? '(${stats.trackedDays.toStringAsFixed(0)} erfasst)' : null,
                  showEditIcon: true,
                ),
              ),
                _buildStatItem(
                  'Verbleibend',
                  '${stats.remainingDays.toStringAsFixed(stats.remainingDays == stats.remainingDays.roundToDouble() ? 0 : 1)}',
                  stats.isOverdrawn ? Colors.red : Colors.green,
                ),
              ],
            ),
            // Übertrag bearbeiten Button
            if (settings.enableVacationCarryover) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: Text(
                  stats.carryover > 0
                      ? 'Übertrag: ${stats.carryover.toStringAsFixed(1)} Tage'
                      : 'Übertrag hinzufügen',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _showCarryoverDialog(stats),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, {String? subtitle, bool showEditIcon = false}) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if (showEditIcon) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 10, color: Colors.grey.shade400),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
      ],
    );
  }

  Future<void> _showCarryoverDialog(VacationStats stats) async {
    final quotaNotifier = ref.read(vacationQuotaProvider.notifier);
    final controller = TextEditingController(
      text: stats.carryover > 0 ? stats.carryover.toStringAsFixed(1) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Übertrag ${stats.year}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resturlaub aus ${stats.year - 1}, der ins aktuelle Jahr übertragen wird.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Übertrag (Tage)',
                border: OutlineInputBorder(),
                suffixText: 'Tage',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.replaceAll(',', '.');
              final value = double.tryParse(text) ?? 0.0;
              Navigator.pop(context, value);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null) {
      await quotaNotifier.setCarryover(stats.year, result);
    }
  }

  Future<void> _showManualUsedDaysDialog(VacationStats stats) async {
    final quotaNotifier = ref.read(vacationQuotaProvider.notifier);
    final controller = TextEditingController(
      text: stats.manualDays > 0 ? stats.manualDays.toStringAsFixed(0) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Urlaub ${stats.year}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Erfasste Urlaubstage: ${stats.trackedDays.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Zusätzlich manuell eingetragene Tage (z.B. für Vorjahre ohne Kalender-Tracking):',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Manuell genommene Tage',
                border: OutlineInputBorder(),
                suffixText: 'Tage',
                hintText: '0',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Gesamt genommen: ${stats.trackedDays.toStringAsFixed(0)} + ? = ?',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.replaceAll(',', '.');
              final value = double.tryParse(text) ?? 0.0;
              Navigator.pop(context, value);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null) {
      await quotaNotifier.setManualUsedDays(stats.year, result);
    }
  }

  Future<void> _showAnnualEntitlementDialog(VacationStats stats) async {
    final quotaNotifier = ref.read(vacationQuotaProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final quota = quotaNotifier.getForYear(stats.year);
    final hasCustomEntitlement = quota?.annualEntitlementDays != null;

    final controller = TextEditingController(
      text: stats.annualEntitlement.toStringAsFixed(0),
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Urlaubsanspruch ${stats.year}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standard aus Einstellungen: ${settings.annualVacationDays} Tage/Jahr',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Urlaubstage ${stats.year}',
                border: const OutlineInputBorder(),
                suffixText: 'Tage',
                hintText: settings.annualVacationDays.toString(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              hasCustomEntitlement
                  ? 'Individueller Anspruch für dieses Jahr gesetzt.'
                  : 'Nutzt Standard aus Einstellungen.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            if (hasCustomEntitlement) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, -1.0), // -1 als Signal für "zurücksetzen"
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Auf Standard zurücksetzen'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.replaceAll(',', '.');
              final value = double.tryParse(text);
              Navigator.pop(context, value);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result == -1.0) {
        // Zurücksetzen auf Standard
        await quotaNotifier.setAnnualEntitlement(stats.year, null);
      } else {
        await quotaNotifier.setAnnualEntitlement(stats.year, result);
      }
    }
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
    // Theme-aware text color
    Color textColor = isOutside
        ? context.subtleText
        : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    // Priorität: Feiertag > Krankheit > Urlaub
    // Feiertag überschreibt Urlaub visuell (außer bei medizinischer Abwesenheit)
    final bool holidayOverridesVacation = isHoliday &&
        (vacation == null || vacation.type.isVacation || vacation.type == AbsenceType.unpaid);

    if (vacation != null && vacation.type.isMedical) {
      // Krankheit/Kind krank hat Priorität
      final vacationColor = vacation.type.getColor(context);
      bgColor = vacationColor.withAlpha(context.isDark ? 80 : 77);
      textColor = vacationColor;
    } else if (holidayOverridesVacation) {
      // Feiertag überschreibt Urlaub visuell
      bgColor = context.holidayBackground;
      textColor = context.holidayForeground;
    } else if (vacation != null) {
      // Andere Abwesenheitstypen
      final vacationColor = vacation.type.getColor(context);
      bgColor = vacationColor.withAlpha(context.isDark ? 80 : 77);
      textColor = vacationColor;
    } else if (isHoliday) {
      bgColor = context.holidayBackground;
      textColor = context.holidayForeground;
    } else if (isWeekend && !isOutside) {
      textColor = context.subtleText;
    }

    if (isSelected) {
      bgColor = context.selectedBackground;
      textColor = Colors.white;
    } else if (isToday && vacation == null) {
      bgColor = context.todayBackground;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
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
                  backgroundColor: vacation.type.getColor(context).withAlpha(context.isDark ? 80 : 51),
                ),
              if (holiday != null)
                Chip(
                  label: Text(holiday.localName),
                  backgroundColor: context.holidayBackground,
                ),
            ],
          ),
          if (vacation != null && vacation.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                vacation.description!,
                style: TextStyle(color: context.subtleText),
              ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: context.subtleText),
            const SizedBox(height: 16),
            Text(
              'Keine Abwesenheiten eingetragen',
              style: TextStyle(color: context.subtleText),
            ),
            const SizedBox(height: 8),
            Text(
              'Tippe auf einen Tag, um Abwesenheit einzutragen',
              style: TextStyle(color: context.subtleText, fontSize: 12),
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
        final vacationColor = vacation.type.getColor(context);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: vacationColor,
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
                  style: TextStyle(color: context.subtleText, fontSize: 12),
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
    bool isPeriodMode = false;
    DateTime fromDate = _selectedDay ?? DateTime.now();
    DateTime toDate = _selectedDay ?? DateTime.now();
    final settings = ref.read(settingsProvider);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Vorschau der Arbeitstage berechnen
          int workingDaysCount = 0;
          if (isPeriodMode) {
            workingDaysCount = notifier.countWorkingDaysInPeriod(
              from: fromDate,
              to: toDate,
              nonWorkingWeekdays: settings.nonWorkingWeekdays,
              holidays: _holidays.keys.toList(),
            );
          }

          return AlertDialog(
            title: Text(isPeriodMode ? 'Abwesenheit eintragen' : 'Abwesenheit am ${_formatDate(_selectedDay!)}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tab-Auswahl
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Einzeltag'),
                          selected: !isPeriodMode,
                          onSelected: (selected) {
                            if (selected) setDialogState(() => isPeriodMode = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Zeitraum'),
                          selected: isPeriodMode,
                          onSelected: (selected) {
                            if (selected) setDialogState(() => isPeriodMode = true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Zeitraum-Auswahl (nur bei Zeitraum-Modus)
                  if (isPeriodMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('Von: ${_formatDate(fromDate)}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: fromDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  fromDate = picked;
                                  if (toDate.isBefore(fromDate)) toDate = fromDate;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('Bis: ${_formatDate(toDate)}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: toDate,
                                firstDate: fromDate,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => toDate = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Info-Box mit Vorschau
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.infoBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: context.infoForeground, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              workingDaysCount == 0
                                  ? 'Keine Arbeitstage im Zeitraum'
                                  : '$workingDaysCount Arbeitstag${workingDaysCount == 1 ? '' : 'e'} werden eingetragen\n(Wochenende/freie Tage übersprungen)',
                              style: TextStyle(color: context.infoForeground, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Typ-Auswahl
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

                  // Beschreibung
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
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: (isPeriodMode && workingDaysCount == 0)
                    ? null
                    : () => Navigator.pop(context, {
                        'isPeriod': isPeriodMode,
                        'type': selectedType,
                        'description': descController.text.isEmpty ? null : descController.text,
                        'fromDate': fromDate,
                        'toDate': toDate,
                      }),
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      if (result['isPeriod'] == true) {
        // Zeitraum hinzufügen
        final addedCount = await notifier.addAbsencePeriod(
          from: result['fromDate'],
          to: result['toDate'],
          type: result['type'],
          description: result['description'],
          nonWorkingWeekdays: settings.nonWorkingWeekdays,
          holidays: _holidays.keys.toList(),
        );
        if (mounted && addedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$addedCount Abwesenheitstag${addedCount == 1 ? '' : 'e'} hinzugefügt')),
          );
        }
      } else {
        // Einzeltag hinzufügen
        await notifier.addVacation(
          _selectedDay!,
          type: result['type'],
          description: result['description'],
        );
      }
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

  void _showLegend(BuildContext dialogContext) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Legende'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...AbsenceType.values.map((type) =>
              _buildLegendItem(
                type.getColor(ctx).withAlpha(ctx.isDark ? 80 : 77),
                type.label,
                icon: type.icon,
                iconColor: type.getColor(ctx),
              )
            ),
            const Divider(),
            _buildLegendItem(ctx.holidayBackground, 'Feiertag'),
            _buildLegendItem(ctx.todayBackground, 'Heute'),
            _buildLegendItem(ctx.selectedBackground, 'Ausgewählt'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {IconData? icon, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: icon != null ? Icon(icon, size: 14, color: iconColor ?? Colors.white) : null,
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
