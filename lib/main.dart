import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/work_entry.dart';
import 'models/pause.dart';
import 'models/vacation.dart';
import 'models/settings.dart';
import 'models/weekly_hours_period.dart';
import 'models/geofence_zone.dart';
import 'models/location_point.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(WorkEntryAdapter());
  Hive.registerAdapter(PauseAdapter());
  Hive.registerAdapter(VacationAdapter());
  Hive.registerAdapter(SettingsAdapter());
  Hive.registerAdapter(WeeklyHoursPeriodAdapter());
  Hive.registerAdapter(GeofenceZoneAdapter());
  Hive.registerAdapter(LocationPointAdapter());
  await Hive.openBox<WorkEntry>('work');
  await Hive.openBox<Vacation>('vacation');
  await Hive.openBox<Settings>('settings');
  await Hive.openBox<WeeklyHoursPeriod>('weekly_hours_periods');
  await Hive.openBox<GeofenceZone>('geofence_zones');
  await Hive.openBox<LocationPoint>('location_points');
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // Konvertiere AppThemeMode zu Flutter ThemeMode
    ThemeMode themeMode;
    switch (settings.themeMode) {
      case AppThemeMode.system:
        themeMode = ThemeMode.system;
        break;
      case AppThemeMode.light:
        themeMode = ThemeMode.light;
        break;
      case AppThemeMode.dark:
        themeMode = ThemeMode.dark;
        break;
    }

    return MaterialApp(
      title: 'TimeTracker',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
