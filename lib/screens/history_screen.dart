import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/work_entry.dart';
import '../models/project.dart';
import '../models/settings.dart';
import '../providers.dart';
import 'entry_edit_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String _query = '';
  String? _filterProjectId;
  WorkMode? _filterWorkMode;
  bool _onlyCompleted = false;

  // Bulk-Selektion
  bool _isSelecting = false;
  final Set<dynamic> _selectedKeys = {}; // Hive-Keys

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Selektion ──────────────────────────────────────────────────────────────

  void _enterSelection(WorkEntry entry) {
    setState(() {
      _isSelecting = true;
      _selectedKeys.add(entry.key);
    });
  }

  void _toggleSelection(WorkEntry entry) {
    setState(() {
      if (_selectedKeys.contains(entry.key)) {
        _selectedKeys.remove(entry.key);
        if (_selectedKeys.isEmpty) _isSelecting = false;
      } else {
        _selectedKeys.add(entry.key);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedKeys.clear();
    });
  }

  Future<void> _deleteSelected(List<WorkEntry> allEntries, Settings settings) async {
    final selected =
        allEntries.where((e) => _selectedKeys.contains(e.key)).toList();
    final toDelete = selected.where((e) => !settings.isMonthLocked(e.start)).toList();
    final skipped  = selected.length - toDelete.length;
    _cancelSelection();
    for (final e in toDelete) {
      await ref.read(workEntryProvider.notifier).deleteEntry(e);
    }
    if (mounted) {
      final msg = skipped > 0
          ? '${toDelete.length} gelöscht, $skipped gesperrt übersprungen'
          : '${toDelete.length} Eintrag${toDelete.length == 1 ? '' : 'e'} gelöscht';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _deleteEntry(WorkEntry entry) async {
    await ref.read(workEntryProvider.notifier).deleteEntry(entry);
  }

  // ── Filter & Suche ─────────────────────────────────────────────────────────

  List<WorkEntry> _applyFilters(List<WorkEntry> all, List<Project> projects) {
    var list = all.toList()
      ..sort((a, b) => b.start.compareTo(a.start));

    if (_onlyCompleted) list = list.where((e) => e.stop != null).toList();
    if (_filterWorkMode != null) {
      list = list.where((e) => e.workMode == _filterWorkMode).toList();
    }
    if (_filterProjectId != null) {
      list = list.where((e) => e.projectId == _filterProjectId).toList();
    }

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final dateStr = _fmtDate(e.start).toLowerCase();
        if (dateStr.contains(q)) return true;
        if (e.notes?.toLowerCase().contains(q) == true) return true;
        if (e.tags.any((t) => t.toLowerCase().contains(q))) return true;
        if (_filterProjectId == null) {
          final proj = projects.where((p) => p.id == e.projectId).firstOrNull;
          if (proj?.name.toLowerCase().contains(q) == true) return true;
        }
        return false;
      }).toList();
    }
    return list;
  }

  // ── Gruppen (nach Datum) ───────────────────────────────────────────────────

  List<_DateGroup> _groupByDate(List<WorkEntry> sorted) {
    final Map<String, List<WorkEntry>> map = {};
    for (final e in sorted) {
      final key = _fmtDate(e.start);
      (map[key] ??= []).add(e);
    }
    return map.entries
        .map((e) => _DateGroup(label: e.key, entries: e.value))
        .toList();
  }

  // ── Netto-Stunden ──────────────────────────────────────────────────────────

  double _netHours(WorkEntry e) {
    final end = e.stop ?? DateTime.now();
    var secs = end.difference(e.start).inSeconds.toDouble();
    for (final p in e.pauses) {
      if (p.end != null) secs -= p.end!.difference(p.start).inSeconds;
    }
    return (secs / 3600).clamp(0, double.infinity);
  }

  double _sumHours(List<WorkEntry> list) =>
      list.fold(0.0, (s, e) => s + _netHours(e));

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _openEdit(WorkEntry entry) async {
    if (_isSelecting) {
      _toggleSelection(entry);
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditScreen(entry: entry)),
    );
    if (changed == true) {
      ref.invalidate(workEntryProvider);
      ref.invalidate(workListProvider);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(workEntryProvider);
    final projects   = ref.watch(projectsProvider);
    final settings   = ref.watch(settingsProvider);
    final filtered   = _applyFilters(allEntries, projects);
    final groups     = _groupByDate(filtered);
    final totalHours = _sumHours(filtered);

    return Scaffold(
      appBar: _buildAppBar(allEntries, settings),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!_isSelecting) _buildFilterBar(projects),
            if (filtered.isNotEmpty && !_isSelecting)
              _buildSummaryBar(filtered.length, totalHours),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      itemCount:
                          groups.fold(0, (s, g) => s! + 1 + g.entries.length),
                      itemBuilder: (ctx, i) {
                        var remaining = i;
                        for (final group in groups) {
                          if (remaining == 0) {
                            final isLocked = group.entries.isNotEmpty &&
                                settings.isMonthLocked(group.entries.first.start);
                            return _buildDateHeader(group.label, isLocked: isLocked);
                          }
                          remaining--;
                          if (remaining < group.entries.length) {
                            return _buildEntryTile(
                                group.entries[remaining], projects, settings);
                          }
                          remaining -= group.entries.length;
                        }
                        return const SizedBox.shrink();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(List<WorkEntry> allEntries, Settings settings) {
    if (_isSelecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelSelection,
        ),
        title: Text('${_selectedKeys.length} ausgewählt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Auswahl löschen',
            onPressed: _selectedKeys.isNotEmpty
                ? () => _deleteSelected(allEntries, settings)
                : null,
          ),
        ],
      );
    }

    return AppBar(
      title: _showSearch
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Suchen…',
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _query = v),
            )
          : const Text('Verlauf'),
      actions: [
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchController.clear();
              _query = '';
            }
          }),
        ),
      ],
    );
  }

  // ── Filter-Leiste ──────────────────────────────────────────────────────────

  Widget _buildFilterBar(List<Project> projects) {
    final activeProjects = projects.where((p) => p.isActive).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Abgeschlossen'),
            selected: _onlyCompleted,
            onSelected: (v) => setState(() => _onlyCompleted = v),
            avatar: const Icon(Icons.check_circle_outline, size: 16),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Büro'),
            selected: _filterWorkMode == WorkMode.normal,
            onSelected: (v) => setState(
                () => _filterWorkMode = v ? WorkMode.normal : null),
            avatar: const Icon(Icons.business, size: 16),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Homeoffice'),
            selected: _filterWorkMode == WorkMode.homeOffice,
            onSelected: (v) => setState(
                () => _filterWorkMode = v ? WorkMode.homeOffice : null),
            avatar: const Icon(Icons.home_work, size: 16),
          ),
          const SizedBox(width: 8),
          if (activeProjects.isNotEmpty) ...[
            const VerticalDivider(width: 16),
            ...activeProjects.map((p) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(p.name),
                    selected: _filterProjectId == p.id,
                    onSelected: (v) => setState(
                        () => _filterProjectId = v ? p.id : null),
                    avatar: CircleAvatar(
                      backgroundColor: p.color,
                      radius: 6,
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ── Zusammenfassung ────────────────────────────────────────────────────────

  Widget _buildSummaryBar(int count, double hours) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text('$count Einträge',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(_fmtHours(hours),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const Spacer(),
          Text('Lang drücken zum Auswählen',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  // ── Datum-Header ───────────────────────────────────────────────────────────

  Widget _buildDateHeader(String label, {bool isLocked = false}) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withAlpha(180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              letterSpacing: 0.3,
            ),
          ),
          if (isLocked) ...[
            const Spacer(),
            Icon(Icons.lock, size: 12, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text(
              'Abgeschlossen',
              style: TextStyle(
                  fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
        ],
      ),
    );
  }

  // ── Eintrags-Kachel ────────────────────────────────────────────────────────

  Widget _buildEntryTile(WorkEntry entry, List<Project> projects, Settings settings) {
    final Project? project = entry.projectId != null
        ? projects.where((p) => p.id == entry.projectId).firstOrNull
        : null;

    final isRunning = entry.stop == null;
    final isLocked  = settings.isMonthLocked(entry.start);
    final isSelected = _selectedKeys.contains(entry.key);
    final netH  = _netHours(entry);
    final start = _fmtTime(entry.start);
    final stop  = entry.stop != null ? _fmtTime(entry.stop!) : '…';
    final mode  = entry.workMode;

    Widget tile = InkWell(
      onTap: isLocked
          ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Monat abgeschlossen — Bearbeitung gesperrt'),
                duration: Duration(seconds: 2),
              ))
          : () => _openEdit(entry),
      onLongPress: isLocked
          ? null
          : () {
              if (!_isSelecting) _enterSelection(entry);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox in Selektion, sonst Zeit
            if (_isSelecting)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                  size: 22,
                ),
              ),
            // Zeitraum-Säule
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$start – $stop',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    _fmtHours(netH),
                    style: TextStyle(
                      fontSize: 12,
                      color: isRunning
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                      fontWeight: isRunning
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isRunning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Läuft',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold)),
                        ),
                      if (project != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: project.color.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: project.color.withAlpha(80)),
                          ),
                          child: Text(project.name,
                              style: TextStyle(
                                  fontSize: 11, color: project.color)),
                        ),
                      if (mode != WorkMode.normal)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: mode.color.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(mode.icon, size: 11, color: mode.color),
                              const SizedBox(width: 3),
                              Text(mode.label,
                                  style: TextStyle(
                                      fontSize: 10, color: mode.color)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: entry.tags
                          .map((t) => Chip(
                                label: Text(t,
                                    style:
                                        const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ],
                  if (entry.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  if (entry.pauses.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${entry.pauses.length} Pause(n)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ),
            if (!_isSelecting)
              Icon(Icons.chevron_right,
                  size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );

    // Swipe-to-Delete (nur außerhalb Selektionsmodus, nur abgeschlossene + entsperrte Einträge)
    if (!_isSelecting && !isRunning && !isLocked) {
      tile = Dismissible(
        key: ValueKey(entry.key),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red.shade600,
          child: const Icon(Icons.delete_outline,
              color: Colors.white, size: 28),
        ),
        confirmDismiss: (_) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Eintrag löschen?'),
              content: Text(
                  '${_fmtDate(entry.start)}, ${_fmtTime(entry.start)} – '
                  '${_fmtTime(entry.stop!)}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600),
                  child: const Text('Löschen'),
                ),
              ],
            ),
          );
        },
        onDismissed: (_) => _deleteEntry(entry),
        child: tile,
      );
    }

    return ColoredBox(
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withAlpha(20)
          : Colors.transparent,
      child: tile,
    );
  }

  // ── Leer-Zustand ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    final hasFilter = _query.isNotEmpty ||
        _filterProjectId != null ||
        _filterWorkMode != null ||
        _onlyCompleted;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasFilter ? Icons.search_off : Icons.history,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            hasFilter
                ? 'Keine Einträge gefunden.'
                : 'Noch keine Einträge erfasst.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _query = '';
                _searchController.clear();
                _filterProjectId = null;
                _filterWorkMode = null;
                _onlyCompleted = false;
              }),
              child: const Text('Filter zurücksetzen'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Formatierung ───────────────────────────────────────────────────────────

  String _fmtDate(DateTime d) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final wd = weekdays[d.weekday - 1];
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Heute — $wd, ${d.day}.${d.month}.${d.year}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day) {
      return 'Gestern — $wd, ${d.day}.${d.month}.${d.year}';
    }
    return '$wd, ${d.day}.${d.month}.${d.year}';
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtHours(double h) {
    final hrs = h.floor();
    final min = ((h - hrs) * 60).round();
    if (min == 0) return '${hrs}h';
    return '${hrs}h ${min}m';
  }
}

// ── Hilfsdatenklasse ──────────────────────────────────────────────────────────

class _DateGroup {
  final String label;
  final List<WorkEntry> entries;
  const _DateGroup({required this.label, required this.entries});
}
