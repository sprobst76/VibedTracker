import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weekly_hours_period.dart';
import '../providers.dart';

class WeeklyHoursScreen extends ConsumerStatefulWidget {
  const WeeklyHoursScreen({super.key});

  @override
  ConsumerState<WeeklyHoursScreen> createState() => _WeeklyHoursScreenState();
}

class _WeeklyHoursScreenState extends ConsumerState<WeeklyHoursScreen> {
  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(weeklyHoursPeriodsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbeitszeit-Perioden'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Standard-Arbeitszeit: ${settings.weeklyHours.toStringAsFixed(1)}h/Woche',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hier können Sie Zeiträume mit abweichender Arbeitszeit definieren (z.B. Teilzeit ab einem bestimmten Datum).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Periods List
          if (periods.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.schedule, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Keine Perioden definiert',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Es gilt die Standard-Arbeitszeit.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            ...periods.map((period) => _buildPeriodCard(period)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(null),
        icon: const Icon(Icons.add),
        label: const Text('Neue Periode'),
      ),
    );
  }

  Widget _buildPeriodCard(WeeklyHoursPeriod period) {
    final isActive = period.containsDate(DateTime.now());

    return Card(
      color: isActive ? Colors.green.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green : Colors.grey,
          child: Text(
            '${period.weeklyHours.round()}h',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        title: Text(
          period.description ?? '${period.weeklyHours}h/Woche',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Ab ${_formatDate(period.startDate)}${period.endDate != null ? ' bis ${_formatDate(period.endDate!)}' : ' (unbegrenzt)'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Aktiv',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showAddEditDialog(period),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(period),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _showAddEditDialog(WeeklyHoursPeriod? period) async {
    final isEdit = period != null;
    DateTime startDate = period?.startDate ?? DateTime.now();
    DateTime? endDate = period?.endDate;
    double weeklyHours = period?.weeklyHours ?? 40.0;
    String description = period?.description ?? '';
    bool hasEndDate = endDate != null;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Periode bearbeiten' : 'Neue Periode'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Start Date
                const Text('Startdatum', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_formatDate(startDate)),
                ),
                const SizedBox(height: 16),

                // End Date Toggle
                Row(
                  children: [
                    const Expanded(
                      child: Text('Enddatum', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Switch(
                      value: hasEndDate,
                      onChanged: (value) {
                        setDialogState(() {
                          hasEndDate = value;
                          if (value && endDate == null) {
                            endDate = startDate.add(const Duration(days: 365));
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (hasEndDate) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? startDate.add(const Duration(days: 365)),
                        firstDate: startDate,
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => endDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_formatDate(endDate ?? startDate)),
                  ),
                ],
                const SizedBox(height: 16),

                // Weekly Hours
                const Text('Wochenstunden', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: weeklyHours.toStringAsFixed(1).replaceAll('.', ','),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixText: 'h / Woche',
                    hintText: 'z.B. 38,5',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                  ],
                  onChanged: (value) {
                    // Komma durch Punkt ersetzen für Parsing
                    final normalized = value.replaceAll(',', '.');
                    final parsed = double.tryParse(normalized);
                    if (parsed != null && parsed >= 1 && parsed <= 80) {
                      weeklyHours = parsed;
                    }
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Gültiger Bereich: 1 - 80 Stunden',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // Description
                const Text('Beschreibung (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'z.B. Teilzeit',
                  ),
                  controller: TextEditingController(text: description),
                  onChanged: (value) => description = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final notifier = ref.read(weeklyHoursPeriodsProvider.notifier);
                if (isEdit) {
                  await notifier.updatePeriod(
                    period,
                    newStartDate: startDate,
                    newEndDate: hasEndDate ? endDate : null,
                    newWeeklyHours: weeklyHours,
                    newDescription: description.isEmpty ? null : description,
                  );
                } else {
                  await notifier.addPeriod(WeeklyHoursPeriod(
                    startDate: startDate,
                    endDate: hasEndDate ? endDate : null,
                    weeklyHours: weeklyHours,
                    description: description.isEmpty ? null : description,
                  ));
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(WeeklyHoursPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Periode löschen?'),
        content: const Text('Diese Periode wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(weeklyHoursPeriodsProvider.notifier).deletePeriod(period);
    }
  }
}
