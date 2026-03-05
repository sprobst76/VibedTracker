import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:hive/hive.dart';
import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../models/pause.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

/// A raw row parsed from the Excel file (before merging)
class ExcelRow {
  final DateTime day;
  final DateTime start;
  final DateTime end;
  final String? description;
  final ExcelRowType type;

  ExcelRow({
    required this.day,
    required this.start,
    required this.end,
    this.description,
    required this.type,
  });
}

enum ExcelRowType { work, illness, holiday, unknown }

/// A merged session: consecutive Excel rows combined into one WorkEntry
class MergedSession {
  final DateTime start;
  final DateTime end;
  final List<Pause> pauses;
  final String? notes;
  final int rawRowCount;

  MergedSession({
    required this.start,
    required this.end,
    required this.pauses,
    this.notes,
    required this.rawRowCount,
  });

  Duration get duration => end.difference(start);

  Duration get netDuration {
    final pauseTotal = pauses.fold<Duration>(
      Duration.zero,
      (sum, p) =>
          sum + (p.end != null ? p.end!.difference(p.start) : Duration.zero),
    );
    return duration - pauseTotal;
  }
}

/// How to resolve a conflict
enum ConflictResolution {
  skip,     // Don't import the new entry
  replace,  // Delete existing, import new
  keepBoth, // Import new alongside existing
}

/// A conflict between a MergedSession and existing WorkEntries
class WorkConflict {
  final MergedSession incoming;
  final List<WorkEntry> overlapping;
  ConflictResolution resolution;

  WorkConflict({
    required this.incoming,
    required this.overlapping,
    this.resolution = ConflictResolution.skip,
  });

  String get description {
    if (overlapping.length == 1) {
      final e = overlapping.first;
      return 'Überschneidung mit ${_fmtTime(e.start)}–${_fmtTime(e.stop)}';
    }
    return 'Überschneidung mit ${overlapping.length} Einträgen';
  }

  static String _fmtTime(DateTime? dt) {
    if (dt == null) return '?';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// A conflict for a vacation/absence entry
class VacationConflict {
  final DateTime day;
  final AbsenceType type;
  final String? description;
  final Vacation? existingVacation;
  ConflictResolution resolution;

  VacationConflict({
    required this.day,
    required this.type,
    this.description,
    this.existingVacation,
    this.resolution = ConflictResolution.skip,
  });
}

/// Simple holder for a clean vacation to import (no conflict)
class ImportVacation {
  final DateTime day;
  final AbsenceType type;
  final String? description;

  const ImportVacation({
    required this.day,
    required this.type,
    this.description,
  });
}

/// The full preview of what an import would do
class ImportPreview {
  final List<MergedSession> cleanSessions;
  final List<WorkConflict> workConflicts;
  final List<ImportVacation> cleanVacations;
  final List<VacationConflict> vacationConflicts;
  final int skippedHolidays;
  final int totalRawRows;
  final int mergedCount;

  ImportPreview({
    required this.cleanSessions,
    required this.workConflicts,
    required this.cleanVacations,
    required this.vacationConflicts,
    required this.skippedHolidays,
    required this.totalRawRows,
    required this.mergedCount,
  });

  int get totalToImport =>
      cleanSessions.length +
      workConflicts
          .where((c) => c.resolution != ConflictResolution.skip)
          .length +
      cleanVacations.length +
      vacationConflicts
          .where((c) => c.resolution != ConflictResolution.skip)
          .length;

  bool get hasConflicts =>
      workConflicts.isNotEmpty || vacationConflicts.isNotEmpty;
}

/// Result after applying the import
class ImportResult {
  final int addedWorkEntries;
  final int replacedWorkEntries;
  final int addedVacations;
  final int replacedVacations;
  final int skipped;
  final List<String> errors;

  ImportResult({
    required this.addedWorkEntries,
    required this.replacedWorkEntries,
    required this.addedVacations,
    required this.replacedVacations,
    required this.skipped,
    required this.errors,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class ExcelImportService {
  /// Parse an Excel file and return an [ImportPreview].
  ///
  /// [mergeThresholdMinutes] – gaps shorter than this are treated as pauses
  /// inside one session. Default 30 min.
  static ImportPreview parseAndAnalyze({
    required Uint8List bytes,
    required List<WorkEntry> existingEntries,
    required List<Vacation> existingVacations,
    int mergeThresholdMinutes = 30,
  }) {
    final rows = _parseRows(bytes);
    log('ExcelImportService: parsed ${rows.length} rows');

    final workRows = rows.where((r) => r.type == ExcelRowType.work).toList();
    final illnessRows =
        rows.where((r) => r.type == ExcelRowType.illness).toList();
    final holidayCount =
        rows.where((r) => r.type == ExcelRowType.holiday).length;

    final sessions = _mergeRows(workRows, mergeThresholdMinutes);
    final mergedCount = workRows.length - sessions.length;
    log('ExcelImportService: ${workRows.length} rows → ${sessions.length} sessions '
        '(merged $mergedCount)');

    // ── Detect work conflicts ─────────────────────────────────────────────────
    final cleanSessions = <MergedSession>[];
    final workConflicts = <WorkConflict>[];

    for (final session in sessions) {
      final overlapping = existingEntries
          .where((e) => e.stop != null && _overlaps(session, e))
          .toList();

      if (overlapping.isEmpty) {
        cleanSessions.add(session);
      } else {
        workConflicts
            .add(WorkConflict(incoming: session, overlapping: overlapping));
      }
    }

    // ── Detect vacation conflicts ─────────────────────────────────────────────
    final cleanVacations = <ImportVacation>[];
    final vacationConflicts = <VacationConflict>[];

    // Deduplicate illness entries by day
    final illnessDays = <String, ExcelRow>{};
    for (final row in illnessRows) {
      final key =
          '${row.day.year}-${row.day.month.toString().padLeft(2, '0')}-${row.day.day.toString().padLeft(2, '0')}';
      illnessDays[key] = row;
    }

    for (final row in illnessDays.values) {
      final existing = existingVacations
          .where((v) =>
              v.day.year == row.day.year &&
              v.day.month == row.day.month &&
              v.day.day == row.day.day)
          .toList();

      if (existing.isEmpty) {
        cleanVacations.add(ImportVacation(
          day: row.day,
          type: AbsenceType.illness,
          description: row.description,
        ));
      } else {
        vacationConflicts.add(VacationConflict(
          day: row.day,
          type: AbsenceType.illness,
          description: row.description,
          existingVacation: existing.first,
        ));
      }
    }

    return ImportPreview(
      cleanSessions: cleanSessions,
      workConflicts: workConflicts,
      cleanVacations: cleanVacations,
      vacationConflicts: vacationConflicts,
      skippedHolidays: holidayCount,
      totalRawRows: rows.length,
      mergedCount: mergedCount,
    );
  }

  /// Apply the import based on user-resolved conflicts.
  static Future<ImportResult> applyImport({
    required ImportPreview preview,
    required Box<WorkEntry> workBox,
    required Box<Vacation> vacBox,
  }) async {
    int addedWork = 0;
    int replacedWork = 0;
    int addedVac = 0;
    int replacedVac = 0;
    int skipped = 0;
    final errors = <String>[];

    // ── Import clean sessions ─────────────────────────────────────────────────
    for (final session in preview.cleanSessions) {
      try {
        await workBox.add(_sessionToEntry(session));
        addedWork++;
      } catch (e) {
        errors.add('Fehler beim Import ${_fmtDt(session.start)}: $e');
      }
    }

    // ── Apply resolved work conflicts ─────────────────────────────────────────
    for (final conflict in preview.workConflicts) {
      try {
        switch (conflict.resolution) {
          case ConflictResolution.skip:
            skipped++;
            break;
          case ConflictResolution.replace:
            for (final e in conflict.overlapping) {
              await e.delete();
            }
            await workBox.add(_sessionToEntry(conflict.incoming));
            replacedWork++;
            break;
          case ConflictResolution.keepBoth:
            await workBox.add(_sessionToEntry(conflict.incoming));
            addedWork++;
            break;
        }
      } catch (e) {
        errors.add(
            'Fehler bei Konflikteintrag ${_fmtDt(conflict.incoming.start)}: $e');
      }
    }

    // ── Import clean vacations ────────────────────────────────────────────────
    for (final vac in preview.cleanVacations) {
      try {
        await vacBox.add(Vacation(
          day: vac.day,
          description: vac.description,
          type: vac.type,
        ));
        addedVac++;
      } catch (e) {
        errors.add('Fehler beim Urlaubsimport ${vac.day}: $e');
      }
    }

    // ── Apply resolved vacation conflicts ─────────────────────────────────────
    for (final conflict in preview.vacationConflicts) {
      try {
        switch (conflict.resolution) {
          case ConflictResolution.skip:
            skipped++;
            break;
          case ConflictResolution.replace:
            if (conflict.existingVacation != null) {
              await conflict.existingVacation!.delete();
            }
            await vacBox.add(Vacation(
              day: conflict.day,
              description: conflict.description,
              type: conflict.type,
            ));
            replacedVac++;
            break;
          case ConflictResolution.keepBoth:
            await vacBox.add(Vacation(
              day: conflict.day,
              description: conflict.description,
              type: conflict.type,
            ));
            addedVac++;
            break;
        }
      } catch (e) {
        errors.add('Fehler bei Urlaubskonflikt ${conflict.day}: $e');
      }
    }

    log('ExcelImportService: added=$addedWork replaced=$replacedWork '
        'vacAdded=$addedVac vacReplaced=$replacedVac skipped=$skipped');

    return ImportResult(
      addedWorkEntries: addedWork,
      replacedWorkEntries: replacedWork,
      addedVacations: addedVac,
      replacedVacations: replacedVac,
      skipped: skipped,
      errors: errors,
    );
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  /// Parse Excel rows from the WorkingHours export format.
  /// Columns: Tag(0), Start(1), Ende(2), Beschreibung(3), Dauer(4, ignored), Aufgabe(5)
  static List<ExcelRow> _parseRows(Uint8List bytes) {
    final excelFile = Excel.decodeBytes(_fixXlsxBytes(bytes));
    final rows = <ExcelRow>[];

    Sheet? sheet;
    for (final key in excelFile.tables.keys) {
      final candidate = excelFile.tables[key]!;
      if (candidate.maxRows > 1) {
        sheet = candidate;
        break;
      }
    }
    if (sheet == null) {
      log('ExcelImportService: no sheet found');
      return [];
    }

    bool firstRow = true;
    for (final row in sheet.rows) {
      if (firstRow) {
        firstRow = false;
        continue;
      }
      if (row.isEmpty || row[0] == null) continue;

      try {
        final dayDt = _parseCellAsDateTime(row[0]?.value);
        final startDt = _parseCellAsDateTime(row[1]?.value);
        final endDt = _parseCellAsDateTime(row[2]?.value);
        final desc = _parseCellAsString(row[3]?.value);
        final taskStr = _parseCellAsString(row[5]?.value);

        if (dayDt == null || startDt == null || endDt == null) continue;
        if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
          continue;
        }

        rows.add(ExcelRow(
          day: DateTime(dayDt.year, dayDt.month, dayDt.day),
          start: startDt,
          end: endDt,
          description:
              (desc != null && desc.trim().isNotEmpty) ? desc.trim() : null,
          type: _parseTaskType(taskStr),
        ));
      } catch (e) {
        log('ExcelImportService: skipping row due to error: $e');
      }
    }

    return rows;
  }

  /// Smart-merge: groups consecutive rows with gaps ≤ [thresholdMinutes] into
  /// one session. Gaps become Pause objects.
  static List<MergedSession> _mergeRows(
      List<ExcelRow> rows, int thresholdMinutes) {
    if (rows.isEmpty) return [];

    final sorted = List<ExcelRow>.from(rows)
      ..sort((a, b) => a.start.compareTo(b.start));

    final sessions = <MergedSession>[];
    DateTime sessionStart = sorted.first.start;
    DateTime sessionEnd = sorted.first.end;
    final pauses = <Pause>[];
    final notes = <String>[];
    int rawCount = 1;

    if (sorted.first.description != null) {
      notes.add(sorted.first.description!);
    }

    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      final gapSeconds = curr.start.difference(prev.end).inSeconds;
      final gapMinutes = gapSeconds / 60.0;

      if (gapMinutes <= thresholdMinutes) {
        // Merge: extend session, record gap as pause if gap > 0
        if (gapSeconds > 0) {
          pauses.add(Pause(start: prev.end, end: curr.start));
        }
        sessionEnd = curr.end;
        rawCount++;
        if (curr.description != null &&
            !notes.contains(curr.description!)) {
          notes.add(curr.description!);
        }
      } else {
        // Gap too large: finalize session
        sessions.add(MergedSession(
          start: sessionStart,
          end: sessionEnd,
          pauses: List.from(pauses),
          notes: notes.isNotEmpty ? notes.join(' | ') : null,
          rawRowCount: rawCount,
        ));
        sessionStart = curr.start;
        sessionEnd = curr.end;
        pauses.clear();
        notes.clear();
        rawCount = 1;
        if (curr.description != null) notes.add(curr.description!);
      }
    }

    // Add last session
    sessions.add(MergedSession(
      start: sessionStart,
      end: sessionEnd,
      pauses: List.from(pauses),
      notes: notes.isNotEmpty ? notes.join(' | ') : null,
      rawRowCount: rawCount,
    ));

    return sessions;
  }

  static bool _overlaps(MergedSession session, WorkEntry entry) {
    if (entry.stop == null) return false;
    return session.start.isBefore(entry.stop!) &&
        session.end.isAfter(entry.start);
  }

  static WorkEntry _sessionToEntry(MergedSession session) {
    return WorkEntry(
      start: session.start,
      stop: session.end,
      pauses: session.pauses,
      notes: session.notes,
    );
  }

  /// Parse a cell value as DateTime.
  /// - DateTimeCellValue: full date+time (what Start/Ende columns produce)
  /// - DateCellValue: date only (what Tag column may produce)
  /// - DoubleCellValue/IntCellValue: Excel serial date number
  static DateTime? _parseCellAsDateTime(CellValue? value) {
    if (value == null) return null;

    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal();
    }
    if (value is DateCellValue) {
      // Date-only: no time component
      return DateTime(value.year, value.month, value.day);
    }
    if (value is DoubleCellValue) {
      return _excelSerialToDateTime(value.value);
    }
    if (value is IntCellValue) {
      return _excelSerialToDateTime(value.value.toDouble());
    }
    if (value is TextCellValue) {
      try {
        return DateTime.parse(value.value.text ?? '');
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Convert Excel serial date (days since 1900-01-00, fractional=time) to DateTime.
  static DateTime _excelSerialToDateTime(double serial) {
    const excelEpoch = 25569; // 1970-01-01 in Excel serial
    final daysSince1970 = serial - excelEpoch;
    final ms = (daysSince1970 * 86400 * 1000).round();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static String? _parseCellAsString(CellValue? value) {
    if (value == null) return null;
    if (value is TextCellValue) {
      // TextCellValue.value is a TextSpan; .text gives the plain string
      return value.value.text;
    }
    return value.toString();
  }

  static ExcelRowType _parseTaskType(String? task) {
    if (task == null) return ExcelRowType.unknown;
    final normalized = task.trim().toLowerCase();
    if (normalized.contains('reine arbeitszeit') ||
        normalized == 'arbeit') {
      return ExcelRowType.work;
    }
    if (normalized.contains('krank') || normalized == 'krankheit') {
      return ExcelRowType.illness;
    }
    if (normalized.contains('feiertag')) {
      return ExcelRowType.holiday;
    }
    return ExcelRowType.unknown;
  }

  static String _fmtDt(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Fix xlsx bytes before passing to Excel.decodeBytes.
  ///
  /// Some xlsx exports use absolute paths in `xl/_rels/workbook.xml.rels`,
  /// e.g. `Target="/xl/styles.xml"`. The Dart excel package builds the lookup
  /// key as `xl/$target`, producing `xl//xl/styles.xml` which fails to find
  /// the file → "Damaged Excel file: styles" error.
  ///
  /// This method rewrites absolute targets to relative ones by rebuilding the
  /// archive with a corrected .rels entry.
  static Uint8List _fixXlsxBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      final relsEntry = archive.findFile('xl/_rels/workbook.xml.rels');
      if (relsEntry == null) return bytes;

      relsEntry.decompress();
      final original = utf8.decode(relsEntry.content as List<int>);

      // Replace absolute `Target="/xl/something"` with relative `Target="something"`
      final fixed = original.replaceAllMapped(
        RegExp(r'Target="\/xl\/([^"]+)"'),
        (m) => 'Target="${m.group(1)}"',
      );

      if (fixed == original) return bytes; // No change needed

      log('ExcelImportService: patching absolute paths in workbook.xml.rels');

      // Build new archive, replacing the .rels entry
      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.name == 'xl/_rels/workbook.xml.rels') {
          final fixedBytes = utf8.encode(fixed);
          newArchive.addFile(ArchiveFile(
            'xl/_rels/workbook.xml.rels',
            fixedBytes.length,
            fixedBytes,
          ));
        } else {
          newArchive.addFile(file);
        }
      }

      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) {
        return Uint8List.fromList(encoded);
      }
    } catch (e) {
      log('ExcelImportService: _fixXlsxBytes error (using original): $e');
    }
    return bytes;
  }
}
