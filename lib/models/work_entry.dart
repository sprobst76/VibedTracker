import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pause.dart';

part 'work_entry.g.dart';

/// Arbeitsmodi für Kategorisierung der Arbeitszeit
enum WorkMode {
  normal,    // 0 - Reguläre Arbeit
  deepWork,  // 1 - Deep Work / Fokuszeit
  meeting,   // 2 - Meeting
  support,   // 3 - Support
  admin,     // 4 - Administration
}

extension WorkModeExtension on WorkMode {
  String get label {
    switch (this) {
      case WorkMode.normal:
        return 'Arbeit';
      case WorkMode.deepWork:
        return 'Deep Work';
      case WorkMode.meeting:
        return 'Meeting';
      case WorkMode.support:
        return 'Support';
      case WorkMode.admin:
        return 'Administration';
    }
  }

  IconData get icon {
    switch (this) {
      case WorkMode.normal:
        return Icons.work;
      case WorkMode.deepWork:
        return Icons.psychology;
      case WorkMode.meeting:
        return Icons.groups;
      case WorkMode.support:
        return Icons.support_agent;
      case WorkMode.admin:
        return Icons.admin_panel_settings;
    }
  }

  Color get color {
    switch (this) {
      case WorkMode.normal:
        return Colors.blue;
      case WorkMode.deepWork:
        return Colors.purple;
      case WorkMode.meeting:
        return Colors.orange;
      case WorkMode.support:
        return Colors.green;
      case WorkMode.admin:
        return Colors.grey;
    }
  }

  /// Theme-aware Farbe
  Color getColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case WorkMode.normal:
        return isDark ? Colors.blue.shade300 : Colors.blue;
      case WorkMode.deepWork:
        return isDark ? Colors.purple.shade300 : Colors.purple;
      case WorkMode.meeting:
        return isDark ? Colors.orange.shade300 : Colors.orange;
      case WorkMode.support:
        return isDark ? Colors.green.shade300 : Colors.green;
      case WorkMode.admin:
        return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }
  }
}

@HiveType(typeId: 0)
class WorkEntry extends HiveObject {
  @HiveField(0)
  DateTime start;

  @HiveField(1)
  DateTime? stop;

  @HiveField(2)
  List<Pause> pauses;

  @HiveField(3)
  String? notes;

  @HiveField(4)
  List<String> tags;

  @HiveField(5)
  String? projectId;

  @HiveField(6)
  int workModeIndex;

  WorkEntry({
    required this.start,
    this.stop,
    List<Pause>? pauses,
    this.notes,
    List<String>? tags,
    this.projectId,
    this.workModeIndex = 0,
  }) : pauses = pauses ?? [],
       tags = tags ?? [];

  WorkMode get workMode => WorkMode.values[workModeIndex.clamp(0, WorkMode.values.length - 1)];
  set workMode(WorkMode mode) => workModeIndex = mode.index;
}
