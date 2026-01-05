import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'models/work_entry.dart';
import 'models/vacation.dart';
import 'models/settings.dart';

// Hive-Box-Provider
final workBoxProvider = Provider((ref) => Hive.box<WorkEntry>('work'));
final vacBoxProvider = Provider((ref) => Hive.box<Vacation>('vacation'));
final setBoxProvider = Provider((ref) => Hive.box<Settings>('settings'));

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
}

// WorkEntry- und Vacation-Listen
final workListProvider = StateProvider((ref) => ref.watch(workBoxProvider).values.toList());
final vacListProvider = StateProvider((ref) => ref.watch(vacBoxProvider).values.toList());

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

  /// Fügt einen Urlaubstag hinzu
  Future<void> addVacation(DateTime day, {String? description}) async {
    // Prüfen ob Tag bereits existiert
    final exists = state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
    if (!exists) {
      await box.add(Vacation(day: day, description: description));
      _refresh();
    }
  }

  /// Entfernt einen Urlaubstag
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
  Future<void> toggleVacation(DateTime day, {String? description}) async {
    final exists = state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
    if (exists) {
      await removeVacation(day);
    } else {
      await addVacation(day, description: description);
    }
  }

  /// Prüft ob ein Tag ein Urlaubstag ist
  bool isVacationDay(DateTime day) {
    return state.any((v) =>
        v.day.year == day.year && v.day.month == day.month && v.day.day == day.day);
  }

  /// Aktualisiert die Beschreibung eines Urlaubstags
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
}
