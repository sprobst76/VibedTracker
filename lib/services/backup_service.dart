import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/work_entry.dart';
import '../models/pause.dart';
import '../models/vacation.dart';
import '../models/vacation_quota.dart';
import '../models/settings.dart';
import '../models/project.dart';
import '../models/weekly_hours_period.dart';
import '../models/geofence_zone.dart';

/// Service für lokales Backup und Restore
class BackupService {
  static const String backupVersion = '1.0';

  /// Erstellt ein Backup aller Daten als ZIP-Datei
  Future<File> createBackup() async {
    final archive = Archive();

    // Metadata
    final metadata = {
      'version': backupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'appVersion': '0.1.0',
    };
    archive.addFile(_createJsonFile('metadata.json', metadata));

    // Work Entries
    final workBox = Hive.box<WorkEntry>('work');
    final workEntries = workBox.values.map((e) => _workEntryToJson(e)).toList();
    archive.addFile(_createJsonFile('work_entries.json', workEntries));

    // Vacations
    final vacationBox = Hive.box<Vacation>('vacations');
    final vacations = vacationBox.values.map((v) => _vacationToJson(v)).toList();
    archive.addFile(_createJsonFile('vacations.json', vacations));

    // Vacation Quotas
    final quotaBox = Hive.box<VacationQuota>('vacation_quotas');
    final quotas = quotaBox.values.map((q) => _quotaToJson(q)).toList();
    archive.addFile(_createJsonFile('vacation_quotas.json', quotas));

    // Settings
    final settingsBox = Hive.box<Settings>('settings');
    if (settingsBox.isNotEmpty) {
      final settings = _settingsToJson(settingsBox.getAt(0)!);
      archive.addFile(_createJsonFile('settings.json', settings));
    }

    // Projects
    final projectBox = Hive.box<Project>('projects');
    final projects = projectBox.values.map((p) => _projectToJson(p)).toList();
    archive.addFile(_createJsonFile('projects.json', projects));

    // Weekly Hours Periods
    final periodsBox = Hive.box<WeeklyHoursPeriod>('weekly_hours_periods');
    final periods = periodsBox.values.map((p) => _periodToJson(p)).toList();
    archive.addFile(_createJsonFile('weekly_hours_periods.json', periods));

    // Geofence Zones
    final zonesBox = Hive.box<GeofenceZone>('geofence_zones');
    final zones = zonesBox.values.map((z) => _zoneToJson(z)).toList();
    archive.addFile(_createJsonFile('geofence_zones.json', zones));

    // ZIP erstellen
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('Failed to create ZIP archive');

    // Datei speichern
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/vibedtracker_backup_$timestamp.zip');
    await file.writeAsBytes(zipData);

    return file;
  }

  /// Teilt das Backup über Share-Dialog
  Future<void> shareBackup() async {
    final file = await createBackup();
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'VibedTracker Backup',
      text: 'VibedTracker Daten-Backup',
    );
  }

  /// Stellt Daten aus einem Backup wieder her
  Future<BackupRestoreResult> restoreFromFile(File zipFile) async {
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Metadata prüfen
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile == null) {
        return BackupRestoreResult(success: false, error: 'Ungültiges Backup: metadata.json fehlt');
      }

      final metadata = jsonDecode(utf8.decode(metadataFile.content as List<int>));
      final version = metadata['version'] as String?;
      if (version == null) {
        return BackupRestoreResult(success: false, error: 'Ungültige Backup-Version');
      }

      int entriesRestored = 0;
      int vacationsRestored = 0;
      int quotasRestored = 0;
      int projectsRestored = 0;
      int periodsRestored = 0;
      int zonesRestored = 0;

      // Work Entries
      final workFile = archive.findFile('work_entries.json');
      if (workFile != null) {
        final workBox = Hive.box<WorkEntry>('work');
        final entries = jsonDecode(utf8.decode(workFile.content as List<int>)) as List;
        for (final json in entries) {
          final entry = _workEntryFromJson(json);
          await workBox.add(entry);
          entriesRestored++;
        }
      }

      // Vacations
      final vacationFile = archive.findFile('vacations.json');
      if (vacationFile != null) {
        final vacationBox = Hive.box<Vacation>('vacations');
        final vacations = jsonDecode(utf8.decode(vacationFile.content as List<int>)) as List;
        for (final json in vacations) {
          final vacation = _vacationFromJson(json);
          await vacationBox.add(vacation);
          vacationsRestored++;
        }
      }

      // Vacation Quotas
      final quotaFile = archive.findFile('vacation_quotas.json');
      if (quotaFile != null) {
        final quotaBox = Hive.box<VacationQuota>('vacation_quotas');
        final quotas = jsonDecode(utf8.decode(quotaFile.content as List<int>)) as List;
        for (final json in quotas) {
          final quota = _quotaFromJson(json);
          // Prüfen ob Jahr schon existiert
          final existing = quotaBox.values.where((q) => q.year == quota.year);
          if (existing.isEmpty) {
            await quotaBox.add(quota);
            quotasRestored++;
          }
        }
      }

      // Settings
      final settingsFile = archive.findFile('settings.json');
      if (settingsFile != null) {
        final settingsBox = Hive.box<Settings>('settings');
        final json = jsonDecode(utf8.decode(settingsFile.content as List<int>));
        final settings = _settingsFromJson(json);
        if (settingsBox.isEmpty) {
          await settingsBox.add(settings);
        } else {
          final existing = settingsBox.getAt(0)!;
          _mergeSettings(existing, settings);
          await existing.save();
        }
      }

      // Projects
      final projectFile = archive.findFile('projects.json');
      if (projectFile != null) {
        final projectBox = Hive.box<Project>('projects');
        final projects = jsonDecode(utf8.decode(projectFile.content as List<int>)) as List;
        for (final json in projects) {
          final project = _projectFromJson(json);
          // Prüfen ob Projekt mit gleichem Namen existiert
          final existing = projectBox.values.where((p) => p.name == project.name);
          if (existing.isEmpty) {
            await projectBox.add(project);
            projectsRestored++;
          }
        }
      }

      // Weekly Hours Periods
      final periodsFile = archive.findFile('weekly_hours_periods.json');
      if (periodsFile != null) {
        final periodsBox = Hive.box<WeeklyHoursPeriod>('weekly_hours_periods');
        final periods = jsonDecode(utf8.decode(periodsFile.content as List<int>)) as List;
        for (final json in periods) {
          final period = _periodFromJson(json);
          await periodsBox.add(period);
          periodsRestored++;
        }
      }

      // Geofence Zones
      final zonesFile = archive.findFile('geofence_zones.json');
      if (zonesFile != null) {
        final zonesBox = Hive.box<GeofenceZone>('geofence_zones');
        final zones = jsonDecode(utf8.decode(zonesFile.content as List<int>)) as List;
        for (final json in zones) {
          final zone = _zoneFromJson(json);
          // Prüfen ob Zone mit gleichem Namen existiert
          final existing = zonesBox.values.where((z) => z.name == zone.name);
          if (existing.isEmpty) {
            await zonesBox.add(zone);
            zonesRestored++;
          }
        }
      }

      return BackupRestoreResult(
        success: true,
        entriesRestored: entriesRestored,
        vacationsRestored: vacationsRestored,
        quotasRestored: quotasRestored,
        projectsRestored: projectsRestored,
        periodsRestored: periodsRestored,
        zonesRestored: zonesRestored,
      );
    } catch (e) {
      return BackupRestoreResult(success: false, error: e.toString());
    }
  }

  // === JSON Serialization Helpers ===

  ArchiveFile _createJsonFile(String name, dynamic data) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(jsonString);
    return ArchiveFile(name, bytes.length, bytes);
  }

  // Work Entry
  Map<String, dynamic> _workEntryToJson(WorkEntry e) => {
    'start': e.start.toIso8601String(),
    'stop': e.stop?.toIso8601String(),
    'pauses': e.pauses.map((p) => {
      'start': p.start.toIso8601String(),
      'end': p.end?.toIso8601String(),
    }).toList(),
    'workModeIndex': e.workModeIndex,
    'notes': e.notes,
    'projectId': e.projectId,
    'tags': e.tags,
  };

  WorkEntry _workEntryFromJson(Map<String, dynamic> json) {
    final entry = WorkEntry(
      start: DateTime.parse(json['start']),
      stop: json['stop'] != null ? DateTime.parse(json['stop']) : null,
      notes: json['notes'],
      projectId: json['projectId'],
      workModeIndex: json['workModeIndex'] ?? 0,
      tags: (json['tags'] as List?)?.cast<String>(),
    );
    // Pauses hinzufügen
    if (json['pauses'] != null) {
      for (final p in json['pauses'] as List) {
        entry.pauses.add(Pause(
          start: DateTime.parse(p['start']),
          end: p['end'] != null ? DateTime.parse(p['end']) : null,
        ));
      }
    }
    return entry;
  }

  // Vacation
  Map<String, dynamic> _vacationToJson(Vacation v) => {
    'day': v.day.toIso8601String(),
    'typeIndex': v.typeIndex,
    'description': v.description,
  };

  Vacation _vacationFromJson(Map<String, dynamic> json) => Vacation(
    day: DateTime.parse(json['day']),
    type: AbsenceType.values[(json['typeIndex'] ?? 0).clamp(0, 4)],
    description: json['description'],
  );

  // Vacation Quota
  Map<String, dynamic> _quotaToJson(VacationQuota q) => {
    'year': q.year,
    'carryoverDays': q.carryoverDays,
    'adjustmentDays': q.adjustmentDays,
    'note': q.note,
    'manualUsedDays': q.manualUsedDays,
    'annualEntitlementDays': q.annualEntitlementDays,
  };

  VacationQuota _quotaFromJson(Map<String, dynamic> json) => VacationQuota(
    year: json['year'],
    carryoverDays: (json['carryoverDays'] ?? 0.0).toDouble(),
    adjustmentDays: (json['adjustmentDays'] ?? 0.0).toDouble(),
    note: json['note'],
    manualUsedDays: (json['manualUsedDays'] ?? 0.0).toDouble(),
    annualEntitlementDays: json['annualEntitlementDays']?.toDouble(),
  );

  // Settings
  Map<String, dynamic> _settingsToJson(Settings s) => {
    'weeklyHours': s.weeklyHours,
    'annualVacationDays': s.annualVacationDays,
    'outlookIcsPath': s.outlookIcsPath,
    'locale': s.locale,
    'bundesland': s.bundesland,
    'nonWorkingWeekdays': s.nonWorkingWeekdays,
    'enableVacationCarryover': s.enableVacationCarryover,
    'christmasEveWorkFactor': s.christmasEveWorkFactor,
    'newYearsEveWorkFactor': s.newYearsEveWorkFactor,
    'enableLocationTracking': s.enableLocationTracking,
    'themeModeIndex': s.themeModeIndex,
    'googleCalendarEnabled': s.googleCalendarEnabled,
    'enableReminders': s.enableReminders,
    'reminderHour': s.reminderHour,
  };

  Settings _settingsFromJson(Map<String, dynamic> json) => Settings(
    weeklyHours: (json['weeklyHours'] ?? 40.0).toDouble(),
    annualVacationDays: json['annualVacationDays'] ?? 30,
    outlookIcsPath: json['outlookIcsPath'],
    locale: json['locale'] ?? 'de_DE',
    bundesland: json['bundesland'] ?? 'DE',
    nonWorkingWeekdays: (json['nonWorkingWeekdays'] as List?)?.cast<int>() ?? [6, 7],
    enableVacationCarryover: json['enableVacationCarryover'] ?? true,
    christmasEveWorkFactor: (json['christmasEveWorkFactor'] ?? 0.5).toDouble(),
    newYearsEveWorkFactor: (json['newYearsEveWorkFactor'] ?? 0.5).toDouble(),
    enableLocationTracking: json['enableLocationTracking'] ?? false,
    themeModeIndex: json['themeModeIndex'] ?? 0,
    googleCalendarEnabled: json['googleCalendarEnabled'] ?? false,
    enableReminders: json['enableReminders'] ?? true,
    reminderHour: json['reminderHour'] ?? 18,
  );

  void _mergeSettings(Settings existing, Settings imported) {
    // Nur bestimmte Settings übernehmen, nicht alles überschreiben
    existing.annualVacationDays = imported.annualVacationDays;
    existing.bundesland = imported.bundesland;
    existing.nonWorkingWeekdays = imported.nonWorkingWeekdays;
    existing.enableVacationCarryover = imported.enableVacationCarryover;
    existing.christmasEveWorkFactor = imported.christmasEveWorkFactor;
    existing.newYearsEveWorkFactor = imported.newYearsEveWorkFactor;
  }

  // Project
  Map<String, dynamic> _projectToJson(Project p) => {
    'id': p.id,
    'name': p.name,
    'colorHex': p.colorHex,
    'isActive': p.isActive,
    'sortOrder': p.sortOrder,
  };

  Project _projectFromJson(Map<String, dynamic> json) => Project(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'],
    colorHex: json['colorHex'],
    isActive: json['isActive'] ?? true,
    sortOrder: json['sortOrder'] ?? 0,
  );

  // Weekly Hours Period
  Map<String, dynamic> _periodToJson(WeeklyHoursPeriod p) => {
    'startDate': p.startDate.toIso8601String(),
    'endDate': p.endDate?.toIso8601String(),
    'weeklyHours': p.weeklyHours,
    'description': p.description,
  };

  WeeklyHoursPeriod _periodFromJson(Map<String, dynamic> json) => WeeklyHoursPeriod(
    startDate: DateTime.parse(json['startDate']),
    endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
    weeklyHours: (json['weeklyHours']).toDouble(),
    description: json['description'],
  );

  // Geofence Zone
  Map<String, dynamic> _zoneToJson(GeofenceZone z) => {
    'id': z.id,
    'name': z.name,
    'latitude': z.latitude,
    'longitude': z.longitude,
    'radius': z.radius,
    'isActive': z.isActive,
  };

  GeofenceZone _zoneFromJson(Map<String, dynamic> json) => GeofenceZone(
    id: json['id'],
    name: json['name'],
    latitude: (json['latitude']).toDouble(),
    longitude: (json['longitude']).toDouble(),
    radius: (json['radius'] ?? 150.0).toDouble(),
    isActive: json['isActive'] ?? true,
  );
}

/// Ergebnis eines Backup-Restore-Vorgangs
class BackupRestoreResult {
  final bool success;
  final String? error;
  final int entriesRestored;
  final int vacationsRestored;
  final int quotasRestored;
  final int projectsRestored;
  final int periodsRestored;
  final int zonesRestored;

  BackupRestoreResult({
    required this.success,
    this.error,
    this.entriesRestored = 0,
    this.vacationsRestored = 0,
    this.quotasRestored = 0,
    this.projectsRestored = 0,
    this.periodsRestored = 0,
    this.zonesRestored = 0,
  });

  int get totalRestored =>
      entriesRestored + vacationsRestored + quotasRestored +
      projectsRestored + periodsRestored + zonesRestored;

  String get summary {
    if (!success) return 'Fehler: $error';
    final parts = <String>[];
    if (entriesRestored > 0) parts.add('$entriesRestored Einträge');
    if (vacationsRestored > 0) parts.add('$vacationsRestored Urlaubstage');
    if (quotasRestored > 0) parts.add('$quotasRestored Jahreskontingente');
    if (projectsRestored > 0) parts.add('$projectsRestored Projekte');
    if (periodsRestored > 0) parts.add('$periodsRestored Arbeitszeit-Perioden');
    if (zonesRestored > 0) parts.add('$zonesRestored Geofence-Zonen');
    if (parts.isEmpty) return 'Keine neuen Daten importiert';
    return parts.join(', ');
  }
}
