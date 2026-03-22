import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/work_entry.dart';
import '../models/project.dart';
import '../models/settings.dart';

/// Erzeugt einen monatlichen Arbeitszeitnachweis als PDF.
///
/// Inhalt:
///   • Kopfzeile: "Arbeitszeitnachweis" + Monat/Jahr
///   • Tabelle: Datum | Beginn | Ende | Pause | Netto | Projekt | Notizen
///   • Summenzeile
///   • Zusammenfassung: Soll / Ist / Saldo
///   • Unterschriftenfeld: Mitarbeiter + Vorgesetzter
class PdfExportService {
  /// Generiert den PDF-Arbeitszeitnachweis für einen Monat.
  ///
  /// [entries]  — alle WorkEntry-Objekte des Monats (bereits gefiltert)
  /// [month]    — erster Tag des Monats (z.B. DateTime(2026, 2, 1))
  /// [settings] — App-Einstellungen (für Soll-Stunden)
  /// [projects] — Projektliste zum Nachschlagen von Projektnamen
  /// [targetHours] — Soll-Stunden des Monats (bereits berechnet)
  Future<Uint8List> generateMonthlyTimesheet({
    required List<WorkEntry> entries,
    required DateTime month,
    required Settings settings,
    required List<Project> projects,
    required double targetHours,
  }) async {
    final pdf = pw.Document();

    // Einträge nach Datum sortieren
    final sorted = entries.where((e) => e.stop != null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Gesamtwerte berechnen
    double totalNetMinutes = 0;
    double totalPauseMinutes = 0;
    for (final e in sorted) {
      totalNetMinutes += _netMinutes(e);
      totalPauseMinutes += _pauseMinutes(e);
    }
    final totalNetHours = totalNetMinutes / 60.0;
    final balance = totalNetHours - targetHours;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        header: (ctx) => _buildHeader(ctx, month),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          _buildSummaryRow(targetHours, totalNetHours, balance),
          pw.SizedBox(height: 16),
          _buildTable(sorted, projects),
          pw.SizedBox(height: 8),
          _buildTotalsRow(totalNetMinutes, totalPauseMinutes),
          pw.SizedBox(height: 24),
          _buildSignatureFields(),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  pw.Widget _buildHeader(pw.Context ctx, DateTime month) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Arbeitszeitnachweis',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _monthLabel(month),
              style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColors.blueGrey700),
      ],
    );
  }

  pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Erstellt mit VibedTracker',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
        ),
        pw.Text(
          'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
        ),
      ],
    );
  }

  // ── Zusammenfassung ──────────────────────────────────────────────────────────

  pw.Widget _buildSummaryRow(double target, double actual, double balance) {
    final balanceColor = balance >= 0 ? PdfColors.green800 : PdfColors.red800;
    final balanceSign  = balance >= 0 ? '+' : '';
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryCell('Soll', _fmtHours(target), PdfColors.blueGrey800),
          _summaryCell('Ist',  _fmtHours(actual), PdfColors.blueGrey800),
          _summaryCell('Saldo', '$balanceSign${_fmtHours(balance)}', balanceColor),
        ],
      ),
    );
  }

  pw.Widget _summaryCell(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  // ── Tabelle ──────────────────────────────────────────────────────────────────

  pw.Widget _buildTable(List<WorkEntry> sorted, List<Project> projects) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle   = pw.TextStyle(fontSize: 9);
    const headerBg    = PdfColors.blueGrey700;

    final headers = ['Datum', 'Beginn', 'Ende', 'Pause', 'Netto', 'Projekt', 'Notizen'];
    final widths  = [
      const pw.FixedColumnWidth(56),
      const pw.FixedColumnWidth(36),
      const pw.FixedColumnWidth(36),
      const pw.FixedColumnWidth(34),
      const pw.FixedColumnWidth(38),
      const pw.FixedColumnWidth(70),
      const pw.FlexColumnWidth(),
    ];

    return pw.TableHelper.fromTextArray(
      columnWidths: {for (var i = 0; i < widths.length; i++) i: widths[i]},
      headers: headers,
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: headerBg),
      cellStyle: cellStyle,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerLeft,
        6: pw.Alignment.centerLeft,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
      data: sorted.map((e) {
        final project = e.projectId != null
            ? projects.where((p) => p.id == e.projectId).firstOrNull
            : null;
        final pauseMin = _pauseMinutes(e);
        final netMin   = _netMinutes(e);
        return [
          _fmtDate(e.start),
          _fmtTime(e.start),
          _fmtTime(e.stop!),
          pauseMin > 0 ? _fmtMin(pauseMin) : '–',
          _fmtMin(netMin),
          project?.name ?? '–',
          e.notes ?? '',
        ];
      }).toList(),
    );
  }

  pw.Widget _buildTotalsRow(double netMin, double pauseMin) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 1.5, color: PdfColors.blueGrey700)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            'Gesamt Pause: ${_fmtMin(pauseMin)}   '
            'Gesamt Netto: ${_fmtMin(netMin)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ── Unterschrift ─────────────────────────────────────────────────────────────

  pw.Widget _buildSignatureFields() {
    return pw.Row(
      children: [
        _signatureBox('Mitarbeiter/in'),
        pw.SizedBox(width: 40),
        _signatureBox('Vorgesetzte/r'),
      ],
    );
  }

  pw.Widget _signatureBox(String label) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 40), // Platz für Unterschrift
          pw.Divider(thickness: 0.8),
          pw.Text(
            '$label, Datum',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  // ── Hilfsfunktionen ──────────────────────────────────────────────────────────

  double _netMinutes(WorkEntry e) {
    final end = e.stop ?? DateTime.now();
    var gross = end.difference(e.start).inSeconds / 60.0;
    for (final p in e.pauses) {
      if (p.end != null) gross -= p.end!.difference(p.start).inSeconds / 60.0;
    }
    return gross.clamp(0, double.infinity);
  }

  double _pauseMinutes(WorkEntry e) {
    var total = 0.0;
    for (final p in e.pauses) {
      if (p.end != null) total += p.end!.difference(p.start).inSeconds / 60.0;
    }
    return total;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtMin(double minutes) {
    final h = (minutes ~/ 60);
    final m = (minutes % 60).round();
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}min';
  }

  String _fmtHours(double hours) {
    final sign = hours < 0 ? '-' : '';
    final abs  = hours.abs();
    final h    = abs.truncate();
    final m    = ((abs - h) * 60).round();
    return '$sign${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _monthLabel(DateTime month) {
    const names = [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    return '${names[month.month]} ${month.year}';
  }
}
