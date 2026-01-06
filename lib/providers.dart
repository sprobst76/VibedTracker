import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'models/work_entry.dart';
import 'models/vacation.dart';
import 'models/settings.dart';
import 'models/weekly_hours_period.dart';
import 'models/pause.dart';
import 'models/geofence_zone.dart';
import 'models/project.dart';
import 'models/vacation_quota.dart';

// Hive-Box-Provider
final workBoxProvider = Provider((ref) => Hive.box<WorkEntry>('work'));
final vacBoxProvider = Provider((ref) => Hive.box<Vacation>('vacation'));
final setBoxProvider = Provider((ref) => Hive.box<Settings>('settings'));
final weeklyHoursBoxProvider = Provider((ref) => Hive.box<WeeklyHoursPeriod>('weekly_hours_periods'));
final geofenceZonesBoxProvider = Provider((ref) => Hive.box<GeofenceZone>('geofence_zones'));
final projectsBoxProvider = Provider((ref) => Hive.box<Project>('projects'));
final vacationQuotaBoxProvider = Provider((ref) => Hive.box<VacationQuota>('vacation_quotas'));

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

  void updateEnableReminders(bool enabled) {
    state = state..enableReminders = enabled;
    state.save();
  }

  void updateReminderHour(int hour) {
    state = state..reminderHour = hour.clamp(0, 23);
    state.save();
  }

  void updateNonWorkingWeekdays(List<int> weekdays) {
    state = state..nonWorkingWeekdays = weekdays;
    state.save();
  }

  void toggleNonWorkingWeekday(int weekday) {
    final current = List<int>.from(state.nonWorkingWeekdays);
    if (current.contains(weekday)) {
      current.remove(weekday);
    } else {
      current.add(weekday);
    }
    current.sort();
    state = state..nonWorkingWeekdays = current;
    state.save();
  }

  void updateAnnualVacationDays(int days) {
    state = state..annualVacationDays = days.clamp(0, 365);
    state.save();
  }

  void updateVacationCarryover(bool enabled) {
    state = state..enableVacationCarryover = enabled;
    state.save();
  }

  void updateChristmasEveWorkFactor(double factor) {
    state = state..christmasEveWorkFactor = factor.clamp(0.0, 1.0);
    state.save();
  }

  void updateNewYearsEveWorkFactor(double factor) {
    state = state..newYearsEveWorkFactor = factor.clamp(0.0, 1.0);
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
    WorkMode? workMode,
    String? projectId,
    List<String>? tags,
    String? notes,
  }) async {
    final entry = WorkEntry(
      start: start,
      stop: stop,
      workModeIndex: workMode?.index ?? 0,
      projectId: projectId,
      tags: tags,
      notes: notes,
    );
    await box.add(entry);
    _refresh();
  }

  /// Aktualisiert einen Eintrag
  Future<void> updateEntry(WorkEntry entry, {
    DateTime? newStart,
    DateTime? newStop,
    WorkMode? workMode,
    String? projectId,
    List<String>? tags,
    String? notes,
    List<Pause>? pauses,
  }) async {
    if (newStart != null) entry.start = newStart;
    if (newStop != null) entry.stop = newStop;
    if (workMode != null) entry.workMode = workMode;
    entry.projectId = projectId;  // Erlaubt null zum Entfernen
    if (tags != null) entry.tags = tags;
    entry.notes = notes;  // Erlaubt null zum Entfernen
    if (pauses != null) entry.pauses = pauses;
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

  /// Fügt Abwesenheit für einen Zeitraum hinzu
  /// Überspringt automatisch arbeitsfreie Tage (Wochenende + konfigurierte Tage)
  /// Gibt die Anzahl der hinzugefügten Tage zurück
  Future<int> addAbsencePeriod({
    required DateTime from,
    required DateTime to,
    required AbsenceType type,
    String? description,
    required List<int> nonWorkingWeekdays,
    List<DateTime> holidays = const [],
  }) async {
    int addedCount = 0;

    // Stelle sicher dass from <= to
    final startDate = from.isBefore(to) ? from : to;
    final endDate = from.isBefore(to) ? to : from;

    for (var date = startDate; !date.isAfter(endDate); date = date.add(const Duration(days: 1))) {
      // Prüfe ob arbeitsfreier Wochentag
      if (nonWorkingWeekdays.contains(date.weekday)) continue;

      // Prüfe ob Feiertag
      final isHoliday = holidays.any((h) =>
        h.year == date.year && h.month == date.month && h.day == date.day
      );
      if (isHoliday) continue;

      // Prüfe ob bereits Abwesenheit existiert
      if (isVacationDay(date)) continue;

      // Tag hinzufügen
      await box.add(Vacation(day: date, description: description, type: type));
      addedCount++;
    }

    _refresh();
    return addedCount;
  }

  /// Berechnet die Anzahl der Arbeitstage in einem Zeitraum (Vorschau)
  int countWorkingDaysInPeriod({
    required DateTime from,
    required DateTime to,
    required List<int> nonWorkingWeekdays,
    List<DateTime> holidays = const [],
  }) {
    int count = 0;
    final startDate = from.isBefore(to) ? from : to;
    final endDate = from.isBefore(to) ? to : from;

    for (var date = startDate; !date.isAfter(endDate); date = date.add(const Duration(days: 1))) {
      if (nonWorkingWeekdays.contains(date.weekday)) continue;
      final isHoliday = holidays.any((h) =>
        h.year == date.year && h.month == date.month && h.day == date.day
      );
      if (isHoliday) continue;
      if (isVacationDay(date)) continue;
      count++;
    }
    return count;
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

// Projects Provider
final projectsProvider = StateNotifierProvider<ProjectsNotifier, List<Project>>((ref) {
  final box = ref.watch(projectsBoxProvider);
  return ProjectsNotifier(box);
});

class ProjectsNotifier extends StateNotifier<List<Project>> {
  final Box<Project> box;

  ProjectsNotifier(this.box) : super(box.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

  void _refresh() {
    state = box.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Fügt ein neues Projekt hinzu
  Future<void> addProject(Project project) async {
    await box.add(project);
    _refresh();
  }

  /// Erstellt ein neues Projekt mit generierter ID
  Future<void> createProject({
    required String name,
    String? colorHex,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final sortOrder = state.isEmpty ? 0 : state.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final project = Project(
      id: id,
      name: name,
      colorHex: colorHex,
      sortOrder: sortOrder,
    );
    await box.add(project);
    _refresh();
  }

  /// Aktualisiert ein Projekt
  Future<void> updateProject(Project project, {
    String? newName,
    String? newColorHex,
    bool? newIsActive,
    int? newSortOrder,
  }) async {
    if (newName != null) project.name = newName;
    if (newColorHex != null) project.colorHex = newColorHex;
    if (newIsActive != null) project.isActive = newIsActive;
    if (newSortOrder != null) project.sortOrder = newSortOrder;
    await project.save();
    _refresh();
  }

  /// Löscht ein Projekt
  Future<void> deleteProject(Project project) async {
    await project.delete();
    _refresh();
  }

  /// Archiviert ein Projekt (setzt isActive auf false)
  Future<void> archiveProject(Project project) async {
    project.isActive = false;
    await project.save();
    _refresh();
  }

  /// Gibt alle aktiven Projekte zurück
  List<Project> getActiveProjects() {
    return state.where((p) => p.isActive).toList();
  }

  /// Findet ein Projekt anhand der ID
  Project? getById(String id) {
    try {
      return state.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }
}

// Vacation Quota Provider
final vacationQuotaProvider = StateNotifierProvider<VacationQuotaNotifier, List<VacationQuota>>((ref) {
  final box = ref.watch(vacationQuotaBoxProvider);
  return VacationQuotaNotifier(box);
});

class VacationQuotaNotifier extends StateNotifier<List<VacationQuota>> {
  final Box<VacationQuota> box;

  VacationQuotaNotifier(this.box) : super(box.values.toList());

  void _refresh() {
    state = box.values.toList();
  }

  /// Holt das Kontingent für ein Jahr (erstellt es falls nicht vorhanden)
  VacationQuota getOrCreateForYear(int year) {
    try {
      return state.firstWhere((q) => q.year == year);
    } catch (e) {
      // Erstelle neues Kontingent
      final quota = VacationQuota(year: year);
      box.add(quota);
      _refresh();
      return quota;
    }
  }

  /// Holt das Kontingent für ein Jahr (null falls nicht vorhanden)
  VacationQuota? getForYear(int year) {
    try {
      return state.firstWhere((q) => q.year == year);
    } catch (e) {
      return null;
    }
  }

  /// Setzt den Übertrag für ein Jahr
  Future<void> setCarryover(int year, double days, {String? note}) async {
    final quota = getOrCreateForYear(year);
    quota.carryoverDays = days;
    if (note != null) quota.note = note;
    await quota.save();
    _refresh();
  }

  /// Setzt die Anpassung für ein Jahr
  Future<void> setAdjustment(int year, double days, {String? note}) async {
    final quota = getOrCreateForYear(year);
    quota.adjustmentDays = days;
    if (note != null) quota.note = note;
    await quota.save();
    _refresh();
  }

  /// Berechnet und speichert den Übertrag vom Vorjahr
  Future<void> calculateCarryoverFromPreviousYear(
    int year,
    double remainingDaysLastYear, {
    bool enableCarryover = true,
  }) async {
    if (!enableCarryover) return;
    final quota = getOrCreateForYear(year);
    quota.carryoverDays = remainingDaysLastYear > 0 ? remainingDaysLastYear : 0;
    await quota.save();
    _refresh();
  }

  /// Setzt die manuell genommenen Tage für ein Jahr (für Vorjahre ohne Tracking)
  Future<void> setManualUsedDays(int year, double days) async {
    final quota = getOrCreateForYear(year);
    quota.manualUsedDays = days.clamp(0, 365);
    await quota.save();
    _refresh();
  }
}

// Vacation Stats Provider - berechnet Urlaubsstatistiken
final vacationStatsProvider = Provider.family<VacationStats, int>((ref, year) {
  final settings = ref.watch(settingsProvider);
  final vacations = ref.watch(vacationProvider);
  final quotas = ref.watch(vacationQuotaProvider);

  // Urlaubstage des Jahres zählen (nur Typ "vacation") - erfasste Tage
  final trackedDays = vacations.where((v) =>
    v.day.year == year && v.type == AbsenceType.vacation
  ).length.toDouble();

  final vacationEntries = vacations.where((v) =>
    v.day.year == year && v.type == AbsenceType.vacation
  ).length;

  // Quota für das Jahr holen
  VacationQuota? quota;
  try {
    quota = quotas.firstWhere((q) => q.year == year);
  } catch (e) {
    quota = null;
  }

  return VacationStats(
    year: year,
    annualEntitlement: settings.annualVacationDays.toDouble(),
    carryover: quota?.carryoverDays ?? 0.0,
    adjustments: quota?.adjustmentDays ?? 0.0,
    trackedDays: trackedDays,
    manualDays: quota?.manualUsedDays ?? 0.0,
    vacationEntries: vacationEntries,
  );
});

// Vacation Stats für aktuelles Jahr
final currentYearVacationStatsProvider = Provider<VacationStats>((ref) {
  final year = DateTime.now().year;
  return ref.watch(vacationStatsProvider(year));
});
