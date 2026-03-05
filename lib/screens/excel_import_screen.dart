import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../providers.dart';
import '../services/excel_import_service.dart';

class ExcelImportScreen extends ConsumerStatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  ConsumerState<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends ConsumerState<ExcelImportScreen> {
  ImportPreview? _preview;
  String? _fileName;
  bool _isLoading = false;
  bool _isImporting = false;
  String? _errorMessage;
  int _mergeThreshold = 30; // minutes

  // ─── File picker ────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _preview = null;
      _fileName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      if (file.bytes == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Datei konnte nicht gelesen werden.';
        });
        return;
      }

      final existingEntries = ref.read(workListProvider);
      final existingVacations = ref.read(vacListProvider);

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: file.bytes!,
        existingEntries: existingEntries,
        existingVacations: existingVacations,
        mergeThresholdMinutes: _mergeThreshold,
      );

      setState(() {
        _preview = preview;
        _fileName = file.name;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Fehler beim Lesen der Datei: $e';
      });
    }
  }

  Future<void> _doImport() async {
    final preview = _preview;
    if (preview == null) return;

    setState(() => _isImporting = true);

    try {
      final workBox = Hive.box<WorkEntry>('work');
      final vacBox = Hive.box<Vacation>('vacation');

      final result = await ExcelImportService.applyImport(
        preview: preview,
        workBox: workBox,
        vacBox: vacBox,
      );

      ref.invalidate(workListProvider);
      ref.invalidate(vacListProvider);

      if (mounted) {
        _showResultDialog(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showResultDialog(ImportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import abgeschlossen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.addedWorkEntries > 0)
              _resultRow(Icons.add_circle, Colors.green,
                  '${result.addedWorkEntries} Arbeitseinträge hinzugefügt'),
            if (result.replacedWorkEntries > 0)
              _resultRow(Icons.swap_horiz, Colors.orange,
                  '${result.replacedWorkEntries} Einträge ersetzt'),
            if (result.addedVacations > 0)
              _resultRow(Icons.add_circle, Colors.purple,
                  '${result.addedVacations} Abwesenheiten hinzugefügt'),
            if (result.replacedVacations > 0)
              _resultRow(Icons.swap_horiz, Colors.orange,
                  '${result.replacedVacations} Abwesenheiten ersetzt'),
            if (result.skipped > 0)
              _resultRow(Icons.skip_next, Colors.grey,
                  '${result.skipped} Einträge übersprungen'),
            if (result.errors.isNotEmpty)
              _resultRow(Icons.error_outline, Colors.red,
                  '${result.errors.length} Fehler'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel importieren'),
        actions: [
          if (_preview != null && !_isImporting)
            TextButton.icon(
              onPressed: _doImport,
              icon: const Icon(Icons.file_download),
              label: const Text('Importieren'),
            ),
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildFilePickerCard(),
            const SizedBox(height: 16),
            _buildThresholdCard(),
            if (_isLoading) ...[
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(_errorMessage!),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 16),
              _buildSummaryCard(_preview!),
              if (_preview!.workConflicts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildWorkConflictsCard(_preview!.workConflicts),
              ],
              if (_preview!.vacationConflicts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildVacationConflictsCard(_preview!.vacationConflicts),
              ],
              if (_preview!.cleanSessions.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildCleanSessionsCard(_preview!.cleanSessions),
              ],
              if (_preview!.cleanVacations.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildCleanVacationsCard(_preview!.cleanVacations),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Excel-Datei auswählen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Unterstütztes Format: WorkingHours-Export (.xlsx)\n'
              'Spalten: Tag, Start, Ende, Beschreibung, Dauer, Aufgabe',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (_fileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fileName!,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(_fileName == null ? 'Datei auswählen' : 'Andere Datei'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Zusammenführ-Schwelle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Einträge mit weniger als $_mergeThreshold Minuten Lücke werden '
              'zu einem Eintrag zusammengefasst. Größere Lücken bleiben als Pause.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('15 min'),
                Expanded(
                  child: Slider(
                    value: _mergeThreshold.toDouble(),
                    min: 10,
                    max: 90,
                    divisions: 16,
                    label: '$_mergeThreshold min',
                    onChanged: (v) => setState(() => _mergeThreshold = v.round()),
                  ),
                ),
                const Text('90 min'),
              ],
            ),
            Center(
              child: Text(
                '$_mergeThreshold Minuten',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (_preview != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Neu analysieren'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(error, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ImportPreview preview) {
    final totalImportable = preview.cleanSessions.length +
        preview.workConflicts.where((c) => c.resolution != ConflictResolution.skip).length +
        preview.cleanVacations.length +
        preview.vacationConflicts.where((c) => c.resolution != ConflictResolution.skip).length;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Colors.blue),
                const SizedBox(width: 12),
                Text(
                  'Analyse: ${_fileName ?? ""}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow('Zeilen in Datei', preview.totalRawRows.toString()),
            _summaryRow('Erkannte Sessions', '${preview.cleanSessions.length + preview.workConflicts.length}'),
            if (preview.mergedCount > 0)
              _summaryRow('Zusammengeführt', '${preview.mergedCount} Zeilen → weniger Einträge'),
            if (preview.skippedHolidays > 0)
              _summaryRow('Feiertage', '${preview.skippedHolidays} übersprungen'),
            if (preview.workConflicts.isNotEmpty)
              _summaryRowColored(
                  'Konflikte (Arbeit)', '${preview.workConflicts.length}', Colors.orange),
            if (preview.vacationConflicts.isNotEmpty)
              _summaryRowColored(
                  'Konflikte (Abwesenheit)', '${preview.vacationConflicts.length}', Colors.orange),
            const Divider(),
            _summaryRowColored(
              'Bereit zum Import',
              '$totalImportable Einträge',
              Colors.green.shade700,
            ),
            if (preview.hasConflicts) ...[
              const SizedBox(height: 8),
              Text(
                'Löse die Konflikte unten auf, bevor du importierst.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _summaryRowColored(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: color)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        ],
      ),
    );
  }

  Widget _buildWorkConflictsCard(List<WorkConflict> conflicts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Text(
                  '${conflicts.length} Konflikte – Arbeitseinträge',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Diese Excel-Einträge überschneiden sich mit vorhandenen Daten.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            // Global resolution buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      for (final c in conflicts) {
                        c.resolution = ConflictResolution.skip;
                      }
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('Alle überspringen', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      for (final c in conflicts) {
                        c.resolution = ConflictResolution.replace;
                      }
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('Alle ersetzen', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      for (final c in conflicts) {
                        c.resolution = ConflictResolution.keepBoth;
                      }
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('Alle behalten', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const Divider(),
            ...conflicts.map((c) => _buildWorkConflictTile(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkConflictTile(WorkConflict conflict) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Incoming entry
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('NEU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(
                '${_fmtDate(conflict.incoming.start)}  '
                '${_fmtTime(conflict.incoming.start)} – ${_fmtTime(conflict.incoming.end)}  '
                '(${_fmtDuration(conflict.incoming.duration)})',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          if (conflict.incoming.rawRowCount > 1)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 2),
              child: Text(
                '${conflict.incoming.rawRowCount} Zeilen zusammengeführt',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          const SizedBox(height: 4),
          // Existing entries
          ...conflict.overlapping.map((e) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('VORHANDEN',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_fmtTime(e.start)} – ${_fmtTime(e.stop)}  '
                      '(${_fmtDuration(e.stop?.difference(e.start))})',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          // Resolution selector
          SegmentedButton<ConflictResolution>(
            segments: const [
              ButtonSegment(
                value: ConflictResolution.skip,
                label: Text('Überspringen', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.skip_next, size: 14),
              ),
              ButtonSegment(
                value: ConflictResolution.replace,
                label: Text('Ersetzen', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.swap_horiz, size: 14),
              ),
              ButtonSegment(
                value: ConflictResolution.keepBoth,
                label: Text('Behalten', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.add, size: 14),
              ),
            ],
            selected: {conflict.resolution},
            onSelectionChanged: (selection) {
              setState(() => conflict.resolution = selection.first);
            },
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _buildVacationConflictsCard(List<VacationConflict> conflicts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Text(
                  '${conflicts.length} Konflikte – Abwesenheiten',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...conflicts.map((c) => _buildVacationConflictTile(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildVacationConflictTile(VacationConflict conflict) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _fmtDate(conflict.day),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(conflict.type.label),
              if (conflict.existingVacation != null) ...[
                const Text(' ← bereits: '),
                Text(conflict.existingVacation!.type.label,
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<ConflictResolution>(
            segments: const [
              ButtonSegment(
                value: ConflictResolution.skip,
                label: Text('Überspringen', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: ConflictResolution.replace,
                label: Text('Ersetzen', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {conflict.resolution},
            onSelectionChanged: (selection) {
              setState(() => conflict.resolution = selection.first);
            },
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }

  Widget _buildCleanSessionsCard(List<MergedSession> sessions) {
    // Show summary + first 5 entries
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  '${sessions.length} Arbeitseinträge ohne Konflikt',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...sessions.take(5).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(_fmtDate(s.start),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      Text(
                        '${_fmtTime(s.start)} – ${_fmtTime(s.end)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_fmtDuration(s.duration)})',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      if (s.rawRowCount > 1) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${s.rawRowCount}×',
                            style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
            if (sessions.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '... und ${sessions.length - 5} weitere',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanVacationsCard(List<ImportVacation> vacations) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.purple),
                const SizedBox(width: 12),
                Text(
                  '${vacations.length} Abwesenheiten ohne Konflikt',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...vacations.map((v) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(_fmtDate(v.day), style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      Text(v.type.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ─── Formatters ──────────────────────────────────────────────────────────────

  String _fmtDate(DateTime dt) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[dt.weekday - 1]} ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '-';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }
}
