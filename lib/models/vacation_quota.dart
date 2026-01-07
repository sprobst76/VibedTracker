import 'package:hive/hive.dart';
part 'vacation_quota.g.dart';

/// Urlaubskontingent pro Jahr
/// Speichert Übertrag und Anpassungen für jedes Jahr
@HiveType(typeId: 12)
class VacationQuota extends HiveObject {
  @HiveField(0)
  int year;

  @HiveField(1)
  double carryoverDays; // Übertrag aus Vorjahr

  @HiveField(2)
  double adjustmentDays; // Anpassungen (+/- Tage, z.B. Sonderurlaub)

  @HiveField(3)
  String? note; // Notiz zur Anpassung

  @HiveField(4)
  double manualUsedDays; // Manuell eingetragene genommene Tage (für Vorjahre)

  @HiveField(5)
  double? annualEntitlementDays; // Jahresanspruch (überschreibt globale Settings wenn gesetzt)

  VacationQuota({
    required this.year,
    this.carryoverDays = 0.0,
    this.adjustmentDays = 0.0,
    this.note,
    this.manualUsedDays = 0.0,
    this.annualEntitlementDays,
  });
}

/// Berechnete Urlaubsstatistik für ein Jahr
class VacationStats {
  final int year;
  final double annualEntitlement;  // Jahresanspruch aus Settings
  final double carryover;          // Übertrag aus Vorjahr
  final double adjustments;        // Anpassungen
  final double totalEntitlement;   // Gesamtanspruch
  final double trackedDays;        // Erfasste Tage (aus Kalender)
  final double manualDays;         // Manuell eingetragene Tage
  final double usedDays;           // Verbrauchte Tage gesamt (tracked + manual)
  final double remainingDays;      // Verbleibende Tage
  final int vacationEntries;       // Anzahl Urlaubseinträge

  VacationStats({
    required this.year,
    required this.annualEntitlement,
    required this.carryover,
    required this.adjustments,
    required this.trackedDays,
    required this.manualDays,
    required this.vacationEntries,
  }) : totalEntitlement = annualEntitlement + carryover + adjustments,
       usedDays = trackedDays + manualDays,
       remainingDays = annualEntitlement + carryover + adjustments - trackedDays - manualDays;

  /// Prozent des Urlaubs verbraucht
  double get usedPercentage =>
      totalEntitlement > 0 ? (usedDays / totalEntitlement * 100).clamp(0, 100) : 0;

  /// Ob noch Resturlaub vorhanden ist
  bool get hasRemaining => remainingDays > 0;

  /// Ob Urlaub überzogen wurde
  bool get isOverdrawn => remainingDays < 0;
}
