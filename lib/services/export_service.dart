import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/work_entry.dart';
import '../models/project.dart';

/// Service für den Export von Arbeitszeitdaten als Excel-Datei
class ExportService {
  /// Exportiert Arbeitseinträge eines Monats als Excel-Datei
  ///
  /// [entries] - Alle WorkEntry-Objekte (werden nach Monat gefiltert)
  /// [month] - Der zu exportierende Monat
  /// [projects] - Liste aller Projekte für die Namensauflösung
  /// [monthData] - Zusammenfassungsdaten des Monats (optional)
  Future<void> exportMonthToExcel({
    required List<WorkEntry> entries,
    required DateTime month,
    required List<Project> projects,
    MonthExportData? monthData,
  }) async {
    final excel = Excel.createExcel();
    final sheetName = _getMonthName(month.month);

    // Standard-Sheet entfernen und neues erstellen
    excel.delete('Sheet1');
    final sheet = excel[sheetName];

    // Projektlookup erstellen
    final projectMap = {for (final p in projects) p.id: p.name};

    // Header-Stil
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );

    // Header-Zeile
    final headers = [
      'Datum',
      'Wochentag',
      'Start',
      'Ende',
      'Brutto (h)',
      'Pausen (h)',
      'Netto (h)',
      'Modus',
      'Projekt',
      'Notizen',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Einträge des Monats filtern und sortieren
    final monthEntries = entries.where((e) =>
        e.start.year == month.year && e.start.month == month.month).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Datenzeilen
    var row = 1;
    var totalBrutto = 0.0;
    var totalPause = 0.0;
    var totalNetto = 0.0;

    for (final entry in monthEntries) {
      if (entry.stop == null) continue; // Laufende Einträge überspringen

      final brutto = entry.stop!.difference(entry.start).inMinutes / 60.0;
      final pause = _calculatePauseHours(entry);
      final netto = brutto - pause;

      totalBrutto += brutto;
      totalPause += pause;
      totalNetto += netto;

      final projectName = entry.projectId != null
          ? (projectMap[entry.projectId] ?? entry.projectId!)
          : '';

      final rowData = [
        TextCellValue(_formatDate(entry.start)),
        TextCellValue(_getWeekdayName(entry.start.weekday)),
        TextCellValue(_formatTime(entry.start)),
        TextCellValue(_formatTime(entry.stop!)),
        DoubleCellValue(double.parse(brutto.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pause.toStringAsFixed(2))),
        DoubleCellValue(double.parse(netto.toStringAsFixed(2))),
        TextCellValue(entry.workMode.label),
        TextCellValue(projectName),
        TextCellValue(entry.notes ?? ''),
      ];

      for (var i = 0; i < rowData.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row)).value = rowData[i];
      }
      row++;
    }

    // Leerzeile vor Zusammenfassung
    row++;

    // Zusammenfassungszeile
    final summaryStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
    );

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = TextCellValue('Gesamt')
      ..cellStyle = summaryStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
      ..value = DoubleCellValue(double.parse(totalBrutto.toStringAsFixed(2)))
      ..cellStyle = summaryStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
      ..value = DoubleCellValue(double.parse(totalPause.toStringAsFixed(2)))
      ..cellStyle = summaryStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
      ..value = DoubleCellValue(double.parse(totalNetto.toStringAsFixed(2)))
      ..cellStyle = summaryStyle;

    // Zusätzliche Monatsdaten hinzufügen (falls vorhanden)
    if (monthData != null) {
      row += 2;

      final infoStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFF2CC'),
      );

      final infoData = [
        ['Arbeitstage', monthData.workDays.toString()],
        ['Feiertage', monthData.holidayCount.toString()],
        ['Soll-Stunden', monthData.targetHours.toStringAsFixed(2)],
        ['Ist-Stunden', monthData.totalWorked.toStringAsFixed(2)],
        ['Differenz', (monthData.totalWorked - monthData.targetHours).toStringAsFixed(2)],
      ];

      for (final info in infoData) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          ..value = TextCellValue(info[0])
          ..cellStyle = infoStyle;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          ..value = TextCellValue(info[1])
          ..cellStyle = infoStyle;
        row++;
      }
    }

    // Spaltenbreiten anpassen
    sheet.setColumnWidth(0, 12);  // Datum
    sheet.setColumnWidth(1, 12);  // Wochentag
    sheet.setColumnWidth(2, 8);   // Start
    sheet.setColumnWidth(3, 8);   // Ende
    sheet.setColumnWidth(4, 10);  // Brutto
    sheet.setColumnWidth(5, 10);  // Pausen
    sheet.setColumnWidth(6, 10);  // Netto
    sheet.setColumnWidth(7, 14);  // Modus
    sheet.setColumnWidth(8, 20);  // Projekt
    sheet.setColumnWidth(9, 30);  // Notizen

    // Datei speichern und teilen
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel-Datei konnte nicht erstellt werden');

    final dir = await getTemporaryDirectory();
    final fileName = 'Arbeitszeit_${month.year}_${month.month.toString().padLeft(2, '0')}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    // Teilen-Dialog öffnen
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Arbeitszeitbericht ${_getMonthName(month.month)} ${month.year}',
    );
  }

  double _calculatePauseHours(WorkEntry entry) {
    var pauseMinutes = 0.0;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      pauseMinutes += end.difference(pause.start).inMinutes;
    }
    return pauseMinutes / 60.0;
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _getWeekdayName(int weekday) => const [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
    'Freitag', 'Samstag', 'Sonntag'
  ][weekday - 1];

  String _getMonthName(int month) => const [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ][month - 1];
}

/// Zusammenfassungsdaten für den Monatsexport
class MonthExportData {
  final int workDays;
  final int holidayCount;
  final double targetHours;
  final double totalWorked;

  MonthExportData({
    required this.workDays,
    required this.holidayCount,
    required this.targetHours,
    required this.totalWorked,
  });
}
