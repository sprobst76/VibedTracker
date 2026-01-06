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
import 'models/vacation_quota.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'theme/app_theme.dart';
import 'providers.dart';
import 'services/secure_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale-Daten für Deutsch initialisieren
  await initializeDateFormatting('de_DE', null);

  // Hive initialisieren
  await Hive.initFlutter();

  // Adapter registrieren
  Hive.registerAdapter(WorkEntryAdapter());
  Hive.registerAdapter(PauseAdapter());
  Hive.registerAdapter(VacationAdapter());
  Hive.registerAdapter(SettingsAdapter());
  Hive.registerAdapter(WeeklyHoursPeriodAdapter());
  Hive.registerAdapter(GeofenceZoneAdapter());
  Hive.registerAdapter(LocationPointAdapter());
  Hive.registerAdapter(ProjectAdapter());
  Hive.registerAdapter(WorkExceptionAdapter());
  Hive.registerAdapter(VacationQuotaAdapter());

  // Verschlüsselungsschlüssel laden/erstellen
  final secureStorage = SecureStorageService();
  final encryptionKey = await secureStorage.getOrCreateHiveKey();
  final cipher = HiveAesCipher(encryptionKey);

  // Boxen mit Verschlüsselung öffnen
  // Hinweis: Neue Installationen sind verschlüsselt, Migration für bestehende Daten separat
  await _openBoxes(cipher);

  runApp(const ProviderScope(child: MyApp()));
}

/// Öffnet alle Hive-Boxen mit optionaler Verschlüsselung
Future<void> _openBoxes(HiveAesCipher cipher) async {
  // Versuche verschlüsselt zu öffnen, bei Fehler unverschlüsselt (für Migration)
  await _openBoxSafe<WorkEntry>('work', cipher);
  await _openBoxSafe<Vacation>('vacation', cipher);
  await _openBoxSafe<Settings>('settings', cipher);
  await _openBoxSafe<WeeklyHoursPeriod>('weekly_hours_periods', cipher);
  await _openBoxSafe<GeofenceZone>('geofence_zones', cipher);
  await _openBoxSafe<LocationPoint>('location_points', cipher);
  await _openBoxSafe<Project>('projects', cipher);
  await _openBoxSafe<WorkException>('work_exceptions', cipher);
  await _openBoxSafe<VacationQuota>('vacation_quotas', cipher);
}

/// Öffnet eine Box sicher - versucht verschlüsselt, fällt auf unverschlüsselt zurück
Future<void> _openBoxSafe<T>(String name, HiveAesCipher cipher) async {
  try {
    // Versuche verschlüsselt zu öffnen
    await Hive.openBox<T>(name, encryptionCipher: cipher);
  } catch (e) {
    // Falls Fehler (z.B. alte unverschlüsselte Daten), öffne ohne Verschlüsselung
    debugPrint('Box $name: Fallback zu unverschlüsselt (Migration benötigt)');
    await Hive.openBox<T>(name);
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final _secureStorage = SecureStorageService();
  bool _isLocked = false;
  bool _isCheckingLock = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App geht in den Hintergrund - Aktivitätszeit speichern
      _secureStorage.updateLastActivity();
    } else if (state == AppLifecycleState.resumed) {
      // App kommt zurück - prüfen ob Lock nötig
      _checkAutoLock();
    }
  }

  Future<void> _checkInitialLock() async {
    final isEnabled = await _secureStorage.isAppLockEnabled();
    final hasPin = await _secureStorage.hasPin();

    setState(() {
      _isLocked = isEnabled && hasPin;
      _isCheckingLock = false;
    });
  }

  Future<void> _checkAutoLock() async {
    final shouldLock = await _secureStorage.shouldAutoLock();
    final hasPin = await _secureStorage.hasPin();

    if (shouldLock && hasPin) {
      setState(() => _isLocked = true);
    }
  }

  void _onUnlocked() {
    setState(() => _isLocked = false);
  }

  @override
  Widget build(BuildContext context) {
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
      home: _isCheckingLock
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isLocked
              ? LockScreen(onUnlocked: _onUnlocked)
              : const HomeScreen(),
    );
  }
}
