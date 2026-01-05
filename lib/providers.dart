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
