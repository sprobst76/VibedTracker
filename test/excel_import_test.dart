import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/services/excel_import_service.dart';
import 'package:time_tracker/models/work_entry.dart';
import 'package:time_tracker/models/vacation.dart';

Uint8List? _loadFile(String name) {
  // Try relative to working directory (test runner sets cwd to project root)
  for (final path in [name, '../$name']) {
    final file = File(path);
    if (file.existsSync()) return file.readAsBytesSync();
  }
  return null;
}

void main() {
  group('ExcelImportService – real files', () {
    test('2025 file: parses and returns work entries + illness', () {
      final bytes = _loadFile('WorkingHours2025.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2025.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes,
        existingEntries: [],
        existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      expect(preview.totalRawRows, greaterThan(200));
      expect(preview.cleanSessions, isNotEmpty);
      expect(preview.workConflicts, isEmpty);
      expect(preview.skippedHolidays, greaterThan(0));
      // 1 "Krank" row in 2025
      expect(preview.cleanVacations.length, greaterThan(0));
      expect(preview.cleanVacations.every((v) => v.type == AbsenceType.illness), isTrue);
    });

    test('2026 file: fragmented day 2026-03-02 (19 rows) merges into ≤5 sessions', () {
      final bytes = _loadFile('WorkingHours2026.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2026.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes,
        existingEntries: [],
        existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      final march2 = preview.cleanSessions
          .where((s) => s.start.year == 2026 && s.start.month == 3 && s.start.day == 2)
          .toList();

      expect(march2.length, inInclusiveRange(1, 5),
          reason: '19 raw rows with 30min threshold → max 5 sessions');
      expect(preview.mergedCount, greaterThan(50),
          reason: 'Many rows should have been merged');
    });

    test('tighter 10-min threshold produces more sessions than 30-min', () {
      final bytes = _loadFile('WorkingHours2026.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2026.xlsx not found');
        return;
      }

      final p30 = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );
      final p10 = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 10,
      );

      expect(p10.cleanSessions.length, greaterThanOrEqualTo(p30.cleanSessions.length));
    });

    test('conflict: existing entry overlapping first session → WorkConflict', () {
      final bytes = _loadFile('WorkingHours2025.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2025.xlsx not found');
        return;
      }

      final first = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );
      if (first.cleanSessions.isEmpty) return;

      final s = first.cleanSessions.first;
      final fakeEntry = WorkEntry(start: s.start, stop: s.end);

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes,
        existingEntries: [fakeEntry],
        existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      expect(preview.workConflicts, isNotEmpty);
      expect(preview.workConflicts.first.overlapping, contains(fakeEntry));
      expect(preview.workConflicts.first.resolution, ConflictResolution.skip);
    });

    test('vacation conflict: illness day already exists → VacationConflict', () {
      final bytes = _loadFile('WorkingHours2025.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2025.xlsx not found');
        return;
      }

      final first = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );
      if (first.cleanVacations.isEmpty) return;

      final vac = first.cleanVacations.first;
      final existing = Vacation(day: vac.day, type: AbsenceType.illness);

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes,
        existingEntries: [],
        existingVacations: [existing],
        mergeThresholdMinutes: 30,
      );

      expect(preview.vacationConflicts, isNotEmpty);
      expect(preview.cleanVacations, isEmpty);
    });
  });

  group('ExcelImportService – session invariants', () {
    test('all sessions: start < end', () {
      final bytes = _loadFile('WorkingHours2026.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2026.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      for (final s in preview.cleanSessions) {
        expect(s.start.isBefore(s.end), isTrue,
            reason: 'Session ${s.start}–${s.end} invalid');
      }
    });

    test('all pauses: start < end and within session bounds', () {
      final bytes = _loadFile('WorkingHours2026.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2026.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      for (final s in preview.cleanSessions) {
        for (final p in s.pauses) {
          expect(p.end, isNotNull);
          expect(p.start.isBefore(p.end!), isTrue,
              reason: 'Pause ${p.start}–${p.end} invalid in session ${s.start}');
          expect(!p.start.isBefore(s.start), isTrue,
              reason: 'Pause start before session start');
          expect(!p.end!.isAfter(s.end), isTrue,
              reason: 'Pause end after session end');
        }
      }
    });

    test('sessions are non-overlapping', () {
      final bytes = _loadFile('WorkingHours2026.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2026.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      final sessions = List<MergedSession>.from(preview.cleanSessions)
        ..sort((a, b) => a.start.compareTo(b.start));

      for (int i = 0; i < sessions.length - 1; i++) {
        final a = sessions[i];
        final b = sessions[i + 1];
        expect(!a.end.isAfter(b.start), isTrue,
            reason: 'Overlap: ${a.start}–${a.end} and ${b.start}–${b.end}');
      }
    });

    test('totalToImport equals clean + non-skip conflict count', () {
      final bytes = _loadFile('WorkingHours2025.xlsx');
      if (bytes == null) {
        markTestSkipped('WorkingHours2025.xlsx not found');
        return;
      }

      final preview = ExcelImportService.parseAndAnalyze(
        bytes: bytes, existingEntries: [], existingVacations: [],
        mergeThresholdMinutes: 30,
      );

      final expected = preview.cleanSessions.length +
          preview.workConflicts.where((c) => c.resolution != ConflictResolution.skip).length +
          preview.cleanVacations.length +
          preview.vacationConflicts.where((c) => c.resolution != ConflictResolution.skip).length;

      expect(preview.totalToImport, equals(expected));
    });
  });
}
