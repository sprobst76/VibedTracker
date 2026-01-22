import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/pause.dart';
import '../providers.dart';

/// Screen to merge fragmented work entries
/// Detects consecutive entries on the same day and allows merging them
class MergeEntriesScreen extends ConsumerStatefulWidget {
  const MergeEntriesScreen({super.key});

  @override
  ConsumerState<MergeEntriesScreen> createState() => _MergeEntriesScreenState();
}

class _MergeEntriesScreenState extends ConsumerState<MergeEntriesScreen> {
  List<_MergeGroup> _mergeGroups = [];
  Set<int> _selectedGroups = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _findMergeableEntries();
  }

  void _findMergeableEntries() {
    final entries = ref.read(workListProvider);

    // Sort by start time
    final sorted = List<WorkEntry>.from(entries)
      ..sort((a, b) => a.start.compareTo(b.start));

    final groups = <_MergeGroup>[];
    List<WorkEntry> currentGroup = [];

    for (int i = 0; i < sorted.length; i++) {
      final entry = sorted[i];

      // Skip entries without stop time (still running)
      if (entry.stop == null) continue;

      if (currentGroup.isEmpty) {
        currentGroup.add(entry);
      } else {
        final lastEntry = currentGroup.last;

        // Check if this entry can be merged with the current group
        // Conditions: same day, consecutive (within 5 minutes gap), same work mode
        final sameDay = _isSameDay(lastEntry.start, entry.start);
        final consecutive = lastEntry.stop != null &&
            entry.start.difference(lastEntry.stop!).inMinutes.abs() <= 5;
        final sameMode = lastEntry.workModeIndex == entry.workModeIndex;

        if (sameDay && consecutive && sameMode) {
          currentGroup.add(entry);
        } else {
          // Save current group if it has multiple entries
          if (currentGroup.length > 1) {
            groups.add(_MergeGroup(entries: List.from(currentGroup)));
          }
          currentGroup = [entry];
        }
      }
    }

    // Don't forget the last group
    if (currentGroup.length > 1) {
      groups.add(_MergeGroup(entries: List.from(currentGroup)));
    }

    setState(() {
      _mergeGroups = groups;
      // Pre-select all groups
      _selectedGroups = Set.from(List.generate(groups.length, (i) => i));
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _mergeSelectedGroups() async {
    if (_selectedGroups.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final box = Hive.box<WorkEntry>('work');
      int mergedCount = 0;

      for (final groupIndex in _selectedGroups) {
        final group = _mergeGroups[groupIndex];
        await _mergeGroup(box, group.entries);
        mergedCount++;
      }

      ref.invalidate(workListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$mergedCount Gruppen zusammengeführt'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _mergeGroup(Box<WorkEntry> box, List<WorkEntry> entries) async {
    if (entries.length < 2) return;

    // Sort by start time
    entries.sort((a, b) => a.start.compareTo(b.start));

    final first = entries.first;
    final last = entries.last;

    // Collect all pauses from all entries
    final allPauses = <Pause>[];
    for (final entry in entries) {
      allPauses.addAll(entry.pauses);
    }

    // Add gaps between entries as pauses
    for (int i = 0; i < entries.length - 1; i++) {
      final current = entries[i];
      final next = entries[i + 1];
      if (current.stop != null) {
        final gapMinutes = next.start.difference(current.stop!).inMinutes;
        if (gapMinutes > 0) {
          allPauses.add(Pause(start: current.stop!, end: next.start));
        }
      }
    }

    // Sort pauses by start time
    allPauses.sort((a, b) => a.start.compareTo(b.start));

    // Collect notes
    final notes = entries
        .where((e) => e.notes != null && e.notes!.isNotEmpty)
        .map((e) => e.notes!)
        .toSet()
        .join(' | ');

    // Create merged entry
    final merged = WorkEntry(
      start: first.start,
      stop: last.stop,
      pauses: allPauses,
      notes: notes.isNotEmpty ? notes : null,
      projectId: first.projectId,
      workModeIndex: first.workModeIndex,
      tags: first.tags,
    );

    // Delete old entries (except first, which we'll update)
    for (int i = 1; i < entries.length; i++) {
      await entries[i].delete();
    }

    // Update first entry with merged data
    first.start = merged.start;
    first.stop = merged.stop;
    first.pauses.clear();
    first.pauses.addAll(merged.pauses);
    first.notes = merged.notes;
    first.projectId = merged.projectId;
    first.workModeIndex = merged.workModeIndex;
    await first.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einträge zusammenführen'),
        actions: [
          if (_mergeGroups.isNotEmpty)
            TextButton.icon(
              onPressed: _selectedGroups.isEmpty || _isProcessing
                  ? null
                  : _mergeSelectedGroups,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.merge_type),
              label: Text('Merge (${_selectedGroups.length})'),
            ),
        ],
      ),
      body: _mergeGroups.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'Keine zusammenführbaren Einträge gefunden',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Einträge können zusammengeführt werden wenn sie:\n'
                      '• Am selben Tag sind\n'
                      '• Direkt aufeinander folgen (max. 5 min Lücke)\n'
                      '• Den selben Arbeitsmodus haben',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _mergeGroups.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${_mergeGroups.length} Gruppen mit ${_mergeGroups.fold<int>(0, (sum, g) => sum + g.entries.length)} Einträgen gefunden.\n'
                                'Lücken zwischen Einträgen werden als Pausen erfasst.',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final groupIndex = index - 1;
                final group = _mergeGroups[groupIndex];
                final isSelected = _selectedGroups.contains(groupIndex);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedGroups.remove(groupIndex);
                        } else {
                          _selectedGroups.add(groupIndex);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedGroups.add(groupIndex);
                                    } else {
                                      _selectedGroups.remove(groupIndex);
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: Text(
                                  _formatDate(group.entries.first.start),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${group.entries.length} Einträge',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          ...group.entries.map((entry) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 48),
                                    Text(
                                      '${_formatTime(entry.start)} - ${_formatTime(entry.stop)}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '(${_formatDuration(entry.stop?.difference(entry.start))})',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          const Divider(),
                          Row(
                            children: [
                              const SizedBox(width: 48),
                              const Icon(Icons.arrow_forward, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Wird zu: ${_formatTime(group.entries.first.start)} - ${_formatTime(group.entries.last.stop)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${_formatDuration(group.totalDuration)})',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[date.weekday - 1]}, ${date.day}.${date.month}.${date.year}';
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '-';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }
}

class _MergeGroup {
  final List<WorkEntry> entries;

  _MergeGroup({required this.entries});

  Duration get totalDuration {
    if (entries.isEmpty) return Duration.zero;
    final first = entries.first;
    final last = entries.last;
    if (last.stop == null) return Duration.zero;
    return last.stop!.difference(first.start);
  }
}
