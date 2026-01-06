import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/work_entry.dart';
import 'models/pause.dart';
import 'models/vacation.dart';
import 'models/settings.dart';
import 'models/weekly_hours_period.dart';
import 'models/geofence_zone.dart';
import 'models/location_point.dart';
import 'models/project.dart';
import 'models/work_exception.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale-Daten für Deutsch initialisieren
  await initializeDateFormatting('de_DE', null);

  await Hive.initFlutter();
  Hive.registerAdapter(WorkEntryAdapter());
  Hive.registerAdapter(PauseAdapter());
  Hive.registerAdapter(VacationAdapter());
  Hive.registerAdapter(SettingsAdapter());
  Hive.registerAdapter(WeeklyHoursPeriodAdapter());
  Hive.registerAdapter(GeofenceZoneAdapter());
  Hive.registerAdapter(LocationPointAdapter());
  Hive.registerAdapter(ProjectAdapter());
  Hive.registerAdapter(WorkExceptionAdapter());
  await Hive.openBox<WorkEntry>('work');
  await Hive.openBox<Vacation>('vacation');
  await Hive.openBox<Settings>('settings');
  await Hive.openBox<WeeklyHoursPeriod>('weekly_hours_periods');
  await Hive.openBox<GeofenceZone>('geofence_zones');
  await Hive.openBox<LocationPoint>('location_points');
  await Hive.openBox<Project>('projects');
  await Hive.openBox<WorkException>('work_exceptions');
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
