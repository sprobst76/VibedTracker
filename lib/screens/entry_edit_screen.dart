import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/work_entry.dart';
import '../providers.dart';

class EntryEditScreen extends ConsumerStatefulWidget {
  final WorkEntry? entry; // null = neuer Eintrag

  const EntryEditScreen({super.key, this.entry});

  @override
  ConsumerState<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends ConsumerState<EntryEditScreen> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  DateTime? _stopDate;
  TimeOfDay? _stopTime;
  bool _hasStop = false;

  bool get isNewEntry => widget.entry == null;

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      _startDate = widget.entry!.start;
      _startTime = TimeOfDay.fromDateTime(widget.entry!.start);
      if (widget.entry!.stop != null) {
        _stopDate = widget.entry!.stop;
        _stopTime = TimeOfDay.fromDateTime(widget.entry!.stop!);
        _hasStop = true;
      }
    } else {
      // Neuer Eintrag: Heute, jetzt
      final now = DateTime.now();
      _startDate = now;
      _startTime = TimeOfDay.fromDateTime(now);
    }
  }

  DateTime _combineDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDate(bool isStart) async {
    final initialDate = isStart ? _startDate : (_stopDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _stopDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initialTime = isStart ? _startTime : (_stopTime ?? _startTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _stopTime = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final start = _combineDateTime(_startDate, _startTime);
    DateTime? stop;
    if (_hasStop && _stopDate != null && _stopTime != null) {
      stop = _combineDateTime(_stopDate!, _stopTime!);
      if (stop.isBefore(start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endzeit muss nach Startzeit liegen')),
        );
        return;
      }
    }

    final notifier = ref.read(workEntryProvider.notifier);

    if (isNewEntry) {
      await notifier.createManualEntry(start: start, stop: stop);
    } else {
      await notifier.updateEntry(widget.entry!, newStart: start, newStop: stop);
    }

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Dieser Eintrag wird unwiderruflich gelöscht.'),
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

    if (confirmed == true && widget.entry != null) {
      await ref.read(workEntryProvider.notifier).deleteEntry(widget.entry!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNewEntry ? 'Neuer Eintrag' : 'Eintrag bearbeiten'),
        actions: [
          if (!isNewEntry)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _delete,
              tooltip: 'Löschen',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Start Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(true),
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_formatDate(_startDate)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(true),
                          icon: const Icon(Icons.access_time),
                          label: Text(_formatTime(_startTime)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stop Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ende',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _hasStop ? null : Colors.grey,
                          ),
                        ),
                      ),
                      Switch(
                        value: _hasStop,
                        onChanged: (value) {
                          setState(() {
                            _hasStop = value;
                            if (value && _stopDate == null) {
                              _stopDate = _startDate;
                              _stopTime = TimeOfDay.fromDateTime(
                                _combineDateTime(_startDate, _startTime)
                                    .add(const Duration(hours: 8)),
                              );
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_hasStop) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDate(false),
                            icon: const Icon(Icons.calendar_today),
                            label: Text(_formatDate(_stopDate ?? _startDate)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickTime(false),
                            icon: const Icon(Icons.access_time),
                            label: Text(_formatTime(_stopTime ?? _startTime)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!_hasStop)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Eintrag wird als "laufend" gespeichert',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Duration Preview
          if (_hasStop && _stopDate != null && _stopTime != null)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.timer, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Text(
                      'Dauer: ${_calculateDuration()}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Save Button
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(isNewEntry ? 'Eintrag erstellen' : 'Speichern'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  String _calculateDuration() {
    if (!_hasStop || _stopDate == null || _stopTime == null) return '-';
    final start = _combineDateTime(_startDate, _startTime);
    final stop = _combineDateTime(_stopDate!, _stopTime!);
    final duration = stop.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}
