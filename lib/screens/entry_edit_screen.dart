import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/project.dart';
import '../models/pause.dart';
import '../providers.dart';
import '../theme/theme_colors.dart';

class EntryEditScreen extends ConsumerStatefulWidget {
  final WorkEntry? entry; // null = neuer Eintrag
  final DateTime? initialDate; // Optionales Startdatum für neue Einträge

  const EntryEditScreen({super.key, this.entry, this.initialDate});

  @override
  ConsumerState<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends ConsumerState<EntryEditScreen> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  DateTime? _stopDate;
  TimeOfDay? _stopTime;
  bool _hasStop = false;

  // Neue Felder
  WorkMode _workMode = WorkMode.normal;
  String? _projectId;
  List<String> _tags = [];
  List<Pause> _pauses = [];
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

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
      // Neue Felder laden
      _workMode = widget.entry!.workMode;
      _projectId = widget.entry!.projectId;
      _tags = List.from(widget.entry!.tags);
      _pauses = widget.entry!.pauses.map((p) => Pause(start: p.start, end: p.end)).toList();
      _notesController.text = widget.entry!.notes ?? '';
    } else {
      // Neuer Eintrag: initialDate oder heute, jetzt
      final date = widget.initialDate ?? DateTime.now();
      _startDate = date;
      _startTime = widget.initialDate != null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay.fromDateTime(DateTime.now());
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _tagController.dispose();
    super.dispose();
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

  void _addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
      setState(() {
        _tags.add(trimmed);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
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
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    if (isNewEntry) {
      await notifier.createManualEntry(
        start: start,
        stop: stop,
        workMode: _workMode,
        projectId: _projectId,
        tags: _tags,
        notes: notes,
      );
    } else {
      await notifier.updateEntry(
        widget.entry!,
        newStart: start,
        newStop: stop,
        workMode: _workMode,
        projectId: _projectId,
        tags: _tags,
        notes: notes,
        pauses: _pauses,
      );
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
    // Projekte aus Hive laden
    final projectBox = Hive.box<Project>('projects');
    final projects = projectBox.values.where((p) => p.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          // Extra Padding unten für System-Navigation (Samsung, etc.)
          bottom: 16 + MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          // Start Section
          _buildTimeSection(true),
          const SizedBox(height: 16),

          // Stop Section
          _buildTimeSection(false),
          const SizedBox(height: 16),

          // Pauses Section (nur bei bestehenden Einträgen)
          if (!isNewEntry) ...[
            _buildPausesSection(),
            const SizedBox(height: 16),
          ],

          // Work Mode Section
          _buildWorkModeSection(),
          const SizedBox(height: 16),

          // Project Section
          if (projects.isNotEmpty) ...[
            _buildProjectSection(projects),
            const SizedBox(height: 16),
          ],

          // Tags Section
          _buildTagsSection(),
          const SizedBox(height: 16),

          // Notes Section
          _buildNotesSection(),
          const SizedBox(height: 24),

          // Duration Preview
          if (_hasStop && _stopDate != null && _stopTime != null)
            _buildDurationPreview(),
          const SizedBox(height: 24),

          // Save Button - prominent und gut sichtbar
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(isNewEntry ? 'Eintrag erstellen' : 'Speichern'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              minimumSize: const Size(double.infinity, 56),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pausen',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: _addPause,
                  tooltip: 'Pause hinzufügen',
                ),
              ],
            ),
            if (_pauses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Keine Pausen eingetragen',
                  style: TextStyle(color: context.subtleText, fontSize: 12),
                ),
              )
            else
              ..._pauses.asMap().entries.map((entry) {
                final index = entry.key;
                final pause = entry.value;
                return _buildPauseItem(index, pause);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseItem(int index, Pause pause) {
    final startTime = TimeOfDay.fromDateTime(pause.start);
    final endTime = pause.end != null ? TimeOfDay.fromDateTime(pause.end!) : null;
    final duration = pause.end != null
        ? pause.end!.difference(pause.start)
        : DateTime.now().difference(pause.start);
    final durationStr = '${duration.inHours}h ${duration.inMinutes % 60}m';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.neutralBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.coffee, size: 20, color: context.subtleText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _editPauseTime(index, true),
                        child: Text(
                          _formatTime(startTime),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Text(' - '),
                      GestureDetector(
                        onTap: () => _editPauseTime(index, false),
                        child: Text(
                          endTime != null ? _formatTime(endTime) : 'läuft',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: endTime == null ? Colors.orange : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Dauer: $durationStr',
                    style: TextStyle(fontSize: 12, color: context.subtleText),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _removePause(index),
              tooltip: 'Pause entfernen',
            ),
          ],
        ),
      ),
    );
  }

  void _addPause() {
    final now = DateTime.now();
    final entryStart = _combineDateTime(_startDate, _startTime);
    final entryStop = _hasStop && _stopDate != null && _stopTime != null
        ? _combineDateTime(_stopDate!, _stopTime!)
        : now;

    // Default: 12:00-12:30 oder Mitte des Eintrags
    final midpoint = entryStart.add(Duration(
      minutes: entryStop.difference(entryStart).inMinutes ~/ 2,
    ));
    final pauseStart = DateTime(
      midpoint.year, midpoint.month, midpoint.day,
      12, 0,
    ).isBefore(entryStart) ? entryStart.add(const Duration(hours: 1)) : midpoint;
    final pauseEnd = pauseStart.add(const Duration(minutes: 30));

    setState(() {
      _pauses.add(Pause(start: pauseStart, end: pauseEnd));
      _pauses.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  void _removePause(int index) {
    setState(() {
      _pauses.removeAt(index);
    });
  }

  Future<void> _editPauseTime(int index, bool isStart) async {
    final pause = _pauses[index];
    final currentTime = isStart
        ? TimeOfDay.fromDateTime(pause.start)
        : (pause.end != null ? TimeOfDay.fromDateTime(pause.end!) : TimeOfDay.now());

    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _pauses[index] = Pause(
            start: DateTime(
              pause.start.year, pause.start.month, pause.start.day,
              picked.hour, picked.minute,
            ),
            end: pause.end,
          );
        } else {
          _pauses[index] = Pause(
            start: pause.start,
            end: DateTime(
              pause.start.year, pause.start.month, pause.start.day,
              picked.hour, picked.minute,
            ),
          );
        }
        _pauses.sort((a, b) => a.start.compareTo(b.start));
      });
    }
  }

  Widget _buildTimeSection(bool isStart) {
    if (isStart) {
      return Card(
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
      );
    }

    return Card(
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
                      color: _hasStop ? null : context.subtleText,
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
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Eintrag wird als "laufend" gespeichert',
                  style: TextStyle(color: context.subtleText, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkModeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arbeitsmodus',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WorkMode.values.map((mode) {
                final isSelected = _workMode == mode;
                final modeColor = mode.getColor(context);
                return ChoiceChip(
                  avatar: Icon(
                    mode.icon,
                    size: 18,
                    color: isSelected ? Colors.white : modeColor,
                  ),
                  label: Text(mode.label),
                  selected: isSelected,
                  selectedColor: modeColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _workMode = mode);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectSection(List<Project> projects) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Projekt (optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _projectId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Kein Projekt'),
                ),
                ...projects.map((project) => DropdownMenuItem<String?>(
                  value: project.id,
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: project.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(project.name),
                    ],
                  ),
                )),
              ],
              onChanged: (value) => setState(() => _projectId = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tags',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Bestehende Tags
            if (_tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((tag) => Chip(
                  label: Text(tag),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeTag(tag),
                )).toList(),
              ),
              const SizedBox(height: 12),
            ],
            // Neuen Tag hinzufügen
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      hintText: 'Neuen Tag hinzufügen...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: _addTag,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: () => _addTag(_tagController.text),
                  tooltip: 'Tag hinzufügen',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notizen',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Notizen zur Arbeitszeit...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationPreview() {
    return Card(
      color: context.infoBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.timer, color: context.infoForeground),
            const SizedBox(width: 12),
            Text(
              'Dauer: ${_calculateDuration()}',
              style: TextStyle(
                color: context.infoForeground,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
