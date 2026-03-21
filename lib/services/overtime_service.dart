import '../models/work_entry.dart';
import '../models/vacation.dart';
import '../models/settings.dart';
import '../models/weekly_hours_period.dart';

/// Berechnet das Überstundenkonto nach § Soll vs. Ist.
///
/// Berücksichtigt:
/// - Konfigurierte Arbeitstage (nonWorkingWeekdays)
/// - Feiertage (Set von normalisierten Datumsobjekten)
/// - Bezahlte Abwesenheiten (Urlaub, Krank, etc.) → Soll = 0
/// - WeeklyHoursPeriods (wechselnde Soll-Stunden)
/// - Heiligabend / Silvester Arbeitsfaktoren
/// - Nettoarbeitszeit (Brutto minus Pausen)
class OvertimeService {
  // ── Haupt-API ────────────────────────────────────────────────────────────────

  /// Berechnet das Überstunden-Ergebnis für einen Zeitraum.
  ///
  /// Tage nach [today] werden ignoriert (kein spekulativer Soll).
  /// [today] defaults auf DateTime.now() wenn null.
  static OvertimeResult calculate({
    required DateTime from,
    required DateTime to,
    required List<WorkEntry> entries,
    required Settings settings,
    required List<WeeklyHoursPeriod> periods,
    required Set<DateTime> holidays,
    required List<Vacation> absences,
    DateTime? today,
  }) {
    final cutoff = _normalized(today ?? DateTime.now());
    final start = _normalized(from);
    final end = _normalized(to).isAfter(cutoff) ? cutoff : _normalized(to);

    if (start.isAfter(end)) {
      return OvertimeResult(
        from: from,
        to: to,
        totalTarget: 0,
        totalActual: 0,
        days: const [],
      );
    }

    final days = <OvertimeDayResult>[];
    var date = start;
    while (!date.isAfter(end)) {
      days.add(_calculateDay(date, entries, settings, periods, holidays, absences));
      date = date.add(const Duration(days: 1));
    }

    final totalTarget = days.fold(0.0, (s, d) => s + d.targetMinutes);
    final totalActual = days.fold(0.0, (s, d) => s + d.actualMinutes);

    return OvertimeResult(
      from: from,
      to: to,
      totalTarget: totalTarget,
      totalActual: totalActual,
      days: days,
    );
  }

  /// Berechnet das Gesamt-Guthaben aus allen vorhandenen WorkEntries.
  ///
  /// Startdatum = frühester WorkEntry-Start (oder [from] falls angegeben).
  static OvertimeResult calculateAllTime({
    required List<WorkEntry> entries,
    required Settings settings,
    required List<WeeklyHoursPeriod> periods,
    required Set<DateTime> holidays,
    required List<Vacation> absences,
    DateTime? from,
    DateTime? today,
  }) {
    if (entries.isEmpty && from == null) {
      return OvertimeResult(
        from: DateTime.now(),
        to: DateTime.now(),
        totalTarget: 0,
        totalActual: 0,
        days: const [],
      );
    }

    final stoppedEntries = entries.where((e) => e.stop != null);
    DateTime start;
    if (from != null) {
      start = from;
    } else if (stoppedEntries.isNotEmpty) {
      start = stoppedEntries.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
    } else {
      start = entries.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
    }

    return calculate(
      from: start,
      to: today ?? DateTime.now(),
      entries: entries,
      settings: settings,
      periods: periods,
      holidays: holidays,
      absences: absences,
      today: today,
    );
  }

  // ── Tages-Logik ──────────────────────────────────────────────────────────────

  static OvertimeDayResult _calculateDay(
    DateTime date,
    List<WorkEntry> entries,
    Settings settings,
    List<WeeklyHoursPeriod> periods,
    Set<DateTime> holidays,
    List<Vacation> absences,
  ) {
    final normalized = _normalized(date);

    // Prüfe ob Arbeitstag
    final isNonWorkWeekday = settings.nonWorkingWeekdays.contains(date.weekday);
    final isHoliday = holidays.contains(normalized);

    // Abwesenheit suchen
    final absence = _findAbsence(normalized, absences);
    final isPaidAbsence = absence != null && absence.type.isPaid;

    // Soll-Stunden berechnen
    double targetMinutes = 0;
    DayType dayType;

    if (isNonWorkWeekday) {
      dayType = DayType.weekend;
    } else if (isHoliday) {
      dayType = DayType.holiday;
    } else if (isPaidAbsence) {
      dayType = DayType.absent;
    } else {
      // Normaler Arbeitstag
      final dailyHours = _getDailyHours(date, settings, periods);
      final workFactor = settings.getWorkFactorForDate(date);
      targetMinutes = dailyHours * workFactor * 60;
      dayType = workFactor < 1.0 && workFactor > 0.0
          ? DayType.reducedWorkDay
          : DayType.workDay;
    }

    // Ist-Stunden aus WorkEntries
    double actualMinutes = 0;
    for (final entry in entries) {
      if (_isSameDay(entry.start, date) && entry.stop != null) {
        final gross = entry.stop!.difference(entry.start).inSeconds / 60.0;
        var pauseMinutes = 0.0;
        for (final p in entry.pauses) {
          if (p.end != null) {
            pauseMinutes += p.end!.difference(p.start).inSeconds / 60.0;
          }
        }
        actualMinutes += (gross - pauseMinutes).clamp(0, double.infinity);
      }
    }

    return OvertimeDayResult(
      date: date,
      targetMinutes: targetMinutes,
      actualMinutes: actualMinutes,
      dayType: dayType,
      absenceType: absence?.type,
    );
  }

  // ── Hilfsfunktionen ───────────────────────────────────────────────────────────

  static double _getDailyHours(
    DateTime date,
    Settings settings,
    List<WeeklyHoursPeriod> periods,
  ) {
    // Sortiert nach startDate absteigend — neueste Periode zuerst
    final sorted = List<WeeklyHoursPeriod>.from(periods)
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    for (final period in sorted) {
      if (period.containsDate(date)) {
        return period.weeklyHours / settings.workingDaysPerWeek;
      }
    }
    return settings.weeklyHours / settings.workingDaysPerWeek;
  }

  static Vacation? _findAbsence(DateTime normalizedDate, List<Vacation> absences) {
    for (final v in absences) {
      if (v.day.year == normalizedDate.year &&
          v.day.month == normalizedDate.month &&
          v.day.day == normalizedDate.day) {
        return v;
      }
    }
    return null;
  }

  static DateTime _normalized(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Ergebnis-Klassen ─────────────────────────────────────────────────────────

enum DayType { workDay, reducedWorkDay, weekend, holiday, absent }

/// Ergebnis für einen einzelnen Tag
class OvertimeDayResult {
  final DateTime date;

  /// Soll-Minuten (0 für Wochenende / Feiertage / bezahlte Abwesenheit)
  final double targetMinutes;

  /// Ist-Minuten (Netto-Arbeitszeit aus abgeschlossenen WorkEntries)
  final double actualMinutes;

  final DayType dayType;

  /// Abwesenheitstyp (falls absent)
  final AbsenceType? absenceType;

  const OvertimeDayResult({
    required this.date,
    required this.targetMinutes,
    required this.actualMinutes,
    required this.dayType,
    this.absenceType,
  });

  /// Überstunden-Delta in Minuten (positiv = Überstunden, negativ = Unterzeit)
  double get deltaMinutes => actualMinutes - targetMinutes;

  bool get isWorkDay => dayType == DayType.workDay || dayType == DayType.reducedWorkDay;
}

/// Aggregiertes Ergebnis für einen Zeitraum
class OvertimeResult {
  final DateTime from;
  final DateTime to;

  /// Summe Soll-Minuten im Zeitraum
  final double totalTarget;

  /// Summe Ist-Minuten im Zeitraum
  final double totalActual;

  final List<OvertimeDayResult> days;

  const OvertimeResult({
    required this.from,
    required this.to,
    required this.totalTarget,
    required this.totalActual,
    required this.days,
  });

  /// Balance in Minuten (positiv = Überstunden)
  double get balanceMinutes => totalActual - totalTarget;

  /// Balance in Stunden
  double get balanceHours => balanceMinutes / 60;

  /// Soll in Stunden
  double get targetHours => totalTarget / 60;

  /// Ist in Stunden
  double get actualHours => totalActual / 60;

  /// Anzahl regulärer Arbeitstage (excl. Wochenende, Feiertage, Abwesenheiten)
  int get workDays => days.where((d) => d.isWorkDay).length;

  /// Anzahl Tage mit tatsächlicher Arbeit
  int get workedDays => days.where((d) => d.actualMinutes > 0).length;
}
