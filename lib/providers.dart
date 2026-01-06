import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'models/work_entry.dart';
import 'models/vacation.dart';
import 'models/settings.dart';
import 'models/weekly_hours_period.dart';
import 'models/pause.dart';
import 'models/geofence_zone.dart';

// Hive-Box-Provider
final workBoxProvider = Provider((ref) => Hive.box<WorkEntry>('work'));
final vacBoxProvider = Provider((ref) => Hive.box<Vacation>('vacation'));
final setBoxProvider = Provider((ref) => Hive.box<Settings>('settings'));
final weeklyHoursBoxProvider = Provider((ref) => Hive.box<WeeklyHoursPeriod>('weekly_hours_periods'));
final geofenceZonesBoxProvider = Provider((ref) => Hive.box<GeofenceZone>('geofence_zones'));

// Settings-Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>((ref) {
  final box = ref.watch(setBoxProvider);
  return SettingsNotifier(box);
});

class SettingsNotifier extends StateNotifier<Settings> {
  final Box<Settings> box;
  SettingsNotifier(this.box) : super(box.get('prefs') ?? Settings()) {
    if (!box.containsKey('prefs')) box.put('prefs', state);
  }

  void updateWeeklyHours(double h) {
    state = state..weeklyHours = h;
    state.save();
  }

  void updateLocale(String locale) {
    state = state..locale = locale;
    state.save();
  }

  void updateOutlookIcsPath(String? path) {
    state = state..outlookIcsPath = path;
    state.save();
  }

  void updateThemeMode(AppThemeMode mode) {
    state = state..themeMode = mode;
    state.save();
  }

  void updateLocationTracking(bool enabled) {
    state = state..enableLocationTracking = enabled;
    state.save();
  }

  void updateGoogleCalendarEnabled(bool enabled) {
    state = state..googleCalendarEnabled = enabled;
    state.save();
  }

  void updateGoogleCalendarId(String? calendarId) {
    state = state..googleCalendarId = calendarId;
    state.save();
  }

  void updateBundesland(String bundesland) {
    state = state..bundesland = bundesland;
    state.save();
  }
}

// WorkEntry- und Vacation-Listen (legacy, wird durch workEntryProvider ersetzt)
final workListProvider = StateProvider((ref) => ref.watch(workBoxProvider).values.toList());
final vacListProvider = StateProvider((ref) => ref.watch(vacBoxProvider).values.toList());

// WorkEntry-Provider mit CRUD-Operationen
final workEntryProvider = StateNotifierProvider<WorkEntryNotifier, List<WorkEntry>>((ref) {
  final box = ref.watch(workBoxProvider);
  return WorkEntryNotifier(box);
});

class WorkEntryNotifier extends StateNotifier<List<WorkEntry>> {
  final Box<WorkEntry> box;

  WorkEntryNotifier(this.box) : super(box.values.toList());

  void _refresh() {
    state = box.values.toList();
  }

  /// Fügt einen neuen Eintrag hinzu
  Future<void> addEntry(WorkEntry entry) async {
    await box.add(entry);
    _refresh();
  }

  /// Erstellt einen manuellen Eintrag mit Start und Stop
  Future<void> createManualEntry({
    required DateTime start,
    DateTime? stop,
  }) async {
    final entry = WorkEntry(start: start, stop: stop);
    await box.add(entry);
    _refresh();
  }

  /// Aktualisiert Start/Stop eines Eintrags
  Future<void> updateEntry(WorkEntry entry, {
    DateTime? newStart,
    DateTime? newStop,
  }) async {
    if (newStart != null) entry.start = newStart;
    if (newStop != null) entry.stop = newStop;
    await entry.save();
    _refresh();
  }

  /// Löscht einen Eintrag
  Future<void> deleteEntry(WorkEntry entry) async {
    await entry.delete();
    _refresh();
  }

  /// Startet eine neue Arbeitszeit (für Button)
  Future<void> startWork() async {
    // Prüfen ob bereits eine läuft
    final running = state.any((e) => e.stop == null);
    if (running) return;

    await addEntry(WorkEntry(start: DateTime.now()));
  }

  /// Stoppt die laufende Arbeitszeit (für Button)
  Future<void> stopWork() async {
    try {
      final running = state.lastWhere((e) => e.stop == null);
      running.stop = DateTime.now();
      await running.save();
      _refresh();
    } catch (e) {
      // Keine laufende Arbeitszeit
    }
  }

  /// Holt den aktuell laufenden Eintrag
  WorkEntry? getRunningEntry() {
    try {
      return state.lastWhere((e) => e.stop == null);
    } catch (e) {
      return null;
    }
  }

  /// Prüft ob aktuell Arbeit läuft
  bool isWorking() => getRunningEntry() != null;

  /// Kopiert einen Eintrag auf mehrere Tage
  Future<void> copyEntryToDays(WorkEntry source, List<DateTime> targetDays) async {
    for (final targetDay in targetDays) {
      // Berechne die Zeitdifferenz zwischen Quell- und Zieltag
      final sourceDate = DateTime(source.start.year, source.start.month, source.start.day);
      final dayDiff = targetDay.difference(sourceDate);

      // Neue Start- und Endzeit berechnen
      final newStart = source.start.add(dayDiff);
      final newStop = source.stop?.add(dayDiff);

      // Neuen Eintrag erstellen mit kopierten Pausen
      final newEntry = WorkEntry(start: newStart, stop: newStop);

      // Pausen kopieren mit angepassten Zeiten
      for (final pause in source.pauses) {
        newEntry.pauses.add(Pause(
          start: pause.start.add(dayDiff),
          end: pause.end?.add(dayDiff),
        ));
      }

      await box.add(newEntry);
    }
    _refresh();
  }
}

// Vacation-Provider mit CRUD-Operationen
final vacationProvider = StateNotifierProvider<VacationNotifier, List<Vacation>>((ref) {
  final box = ref.watch(vacBoxProvider);
  return VacationNotifier(box);
});

class VacationNotifier extends StateNotifier<List<Vacation>> {
  final Box<Vacation> box;

  VacationNotifier(this.box) : super(box.values.toList());

  void _refresh() {
    state = box.values.toList();
  }

  /// Fügt einen Abwesenheitstag hinzu
  Future<void> addVacation(DateTime day, {String? description, AbsenceType type = AbsenceType.vacation}) async {
    // Prüfen ob Tag bereits existiert
    final exists = state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
    if (!exists) {
      await box.add(Vacation(day: day, description: description, type: type));
      _refresh();
    }
  }

  /// Entfernt einen Abwesenheitstag
  Future<void> removeVacation(DateTime day) async {
    final vacation = state.firstWhere(
      (v) => v.day.year == day.year && v.day.month == day.month && v.day.day == day.day,
      orElse: () => Vacation(day: day),
    );
    if (vacation.isInBox) {
      await vacation.delete();
      _refresh();
    }
  }

  /// Toggle: Fügt hinzu wenn nicht vorhanden, entfernt wenn vorhanden
  Future<void> toggleVacation(DateTime day, {String? description, AbsenceType type = AbsenceType.vacation}) async {
    final exists = state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
    if (exists) {
      await removeVacation(day);
    } else {
      await addVacation(day, description: description, type: type);
    }
  }

  /// Prüft ob ein Tag ein Abwesenheitstag ist
  bool isVacationDay(DateTime day) {
    return state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
  }

  /// Holt den Abwesenheitseintrag für einen Tag (falls vorhanden)
  Vacation? getAbsence(DateTime day) {
    try {
      return state.firstWhere(
        (v) => v.day.year == day.year && v.day.month == day.month && v.day.day == day.day,
      );
    } catch (e) {
      return null;
    }
  }

  /// Aktualisiert die Beschreibung eines Abwesenheitstags
  Future<void> updateDescription(DateTime day, String? description) async {
    final vacation = state.firstWhere(
      (v) => v.day.year == day.year && v.day.month == day.month && v.day.day == day.day,
      orElse: () => Vacation(day: day),
    );
    if (vacation.isInBox) {
      vacation.description = description;
      await vacation.save();
      _refresh();
    }
  }

  /// Aktualisiert den Typ eines Abwesenheitstags
  Future<void> updateType(DateTime day, AbsenceType type) async {
    final vacation = state.firstWhere(
      (v) => v.day.year == day.year && v.day.month == day.month && v.day.day == day.day,
      orElse: () => Vacation(day: day),
    );
    if (vacation.isInBox) {
      vacation.type = type;
      await vacation.save();
      _refresh();
    }
  }

  /// Gibt alle Einträge eines bestimmten Typs zurück
  List<Vacation> getByType(AbsenceType type) {
    return state.where((v) => v.type == type).toList();
  }

  /// Zählt Einträge eines Typs (optional für Jahr/Monat)
  int countByType(AbsenceType type, {int? year, int? month}) {
    return state.where((v) {
      if (v.type != type) return false;
      if (year != null && v.day.year != year) return false;
      if (month != null && v.day.month != month) return false;
      return true;
    }).length;
  }
}

// Weekly Hours Periods Provider
final weeklyHoursPeriodsProvider = StateNotifierProvider<WeeklyHoursPeriodsNotifier, List<WeeklyHoursPeriod>>((ref) {
  final box = ref.watch(weeklyHoursBoxProvider);
  final settings = ref.watch(settingsProvider);
  return WeeklyHoursPeriodsNotifier(box, settings.weeklyHours);
});

class WeeklyHoursPeriodsNotifier extends StateNotifier<List<WeeklyHoursPeriod>> {
  final Box<WeeklyHoursPeriod> box;
  final double defaultWeeklyHours;

  WeeklyHoursPeriodsNotifier(this.box, this.defaultWeeklyHours)
      : super(box.values.toList()..sort((a, b) => a.startDate.compareTo(b.startDate)));

  void _refresh() {
    state = box.values.toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  /// Adds a new period
  Future<void> addPeriod(WeeklyHoursPeriod period) async {
    await box.add(period);
    _refresh();
  }

  /// Updates an existing period
  Future<void> updatePeriod(WeeklyHoursPeriod period, {
    DateTime? newStartDate,
    DateTime? newEndDate,
    double? newWeeklyHours,
    String? newDescription,
  }) async {
    if (newStartDate != null) period.startDate = newStartDate;
    if (newEndDate != null) period.endDate = newEndDate;
    if (newWeeklyHours != null) period.weeklyHours = newWeeklyHours;
    if (newDescription != null) period.description = newDescription;
    await period.save();
    _refresh();
  }

  /// Deletes a period
  Future<void> deletePeriod(WeeklyHoursPeriod period) async {
    await period.delete();
    _refresh();
  }

  /// Gets the weekly hours for a specific date
  /// Returns defaultWeeklyHours if no period covers that date
  double getWeeklyHoursForDate(DateTime date) {
    // Find the most recent period that contains this date
    for (final period in state.reversed) {
      if (period.containsDate(date)) {
        return period.weeklyHours;
      }
    }
    return defaultWeeklyHours;
  }

  /// Gets the daily hours for a specific date (weekly / 5)
  double getDailyHoursForDate(DateTime date) {
    return getWeeklyHoursForDate(date) / 5;
  }
}

// Geofence Zones Provider
final geofenceZonesProvider = StateNotifierProvider<GeofenceZonesNotifier, List<GeofenceZone>>((ref) {
  final box = ref.watch(geofenceZonesBoxProvider);
  return GeofenceZonesNotifier(box);
});

class GeofenceZonesNotifier extends StateNotifier<List<GeofenceZone>> {
  final Box<GeofenceZone> box;

  GeofenceZonesNotifier(this.box) : super(box.values.toList());

  void _refresh() {
    state = box.values.toList();
  }

  /// Fügt eine neue Zone hinzu
  Future<void> addZone(GeofenceZone zone) async {
    await box.add(zone);
    _refresh();
  }

  /// Aktualisiert eine Zone
  Future<void> updateZone(GeofenceZone zone, {
    String? newName,
    double? newLatitude,
    double? newLongitude,
    double? newRadius,
    bool? newIsActive,
  }) async {
    if (newName != null) zone.name = newName;
    if (newLatitude != null) zone.latitude = newLatitude;
    if (newLongitude != null) zone.longitude = newLongitude;
    if (newRadius != null) zone.radius = newRadius;
    if (newIsActive != null) zone.isActive = newIsActive;
    await zone.save();
    _refresh();
  }

  /// Löscht eine Zone
  Future<void> deleteZone(GeofenceZone zone) async {
    await zone.delete();
    _refresh();
  }

  /// Prüft ob eine Position in einer aktiven Zone liegt
  bool isInAnyActiveZone(double lat, double lng) {
    return state.where((z) => z.isActive).any((z) => z.containsPoint(lat, lng));
  }

  /// Gibt alle aktiven Zonen zurück
  List<GeofenceZone> getActiveZones() {
    return state.where((z) => z.isActive).toList();
  }
}
