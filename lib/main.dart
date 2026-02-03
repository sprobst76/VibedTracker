import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'models/pomodoro_session.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/totp_setup_screen.dart';
import 'theme/app_theme.dart';
import 'providers.dart';
import 'services/secure_storage_service.dart';
import 'services/auth_service.dart';
import 'services/pomodoro_notification_service.dart';

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
  Hive.registerAdapter(PomodoroSessionAdapter());

  // Verschlüsselungsschlüssel laden/erstellen
  final secureStorage = SecureStorageService();
  final encryptionKey = await secureStorage.getOrCreateHiveKey();
  final cipher = HiveAesCipher(encryptionKey);

  // Boxen mit Verschlüsselung öffnen
  // Hinweis: Neue Installationen sind verschlüsselt, Migration für bestehende Daten separat
  await _openBoxes(cipher);

  // Pomodoro Notification Service initialisieren
  await PomodoroNotificationService().init();

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
  await _openBoxSafe<PomodoroSession>('pomodoro', cipher);
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
    final authStatus = ref.watch(authStatusProvider);

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
      title: 'VibedTracker',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: _buildHome(authStatus),
    );
  }

  Widget _buildHome(AuthStatus authStatus) {
    // Loading state
    if (_isCheckingLock || authStatus == AuthStatus.unknown) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Web: Auth + 2FA ist Pflicht
    if (kIsWeb) {
      // Nicht authentifiziert -> direkt Login-Screen
      if (authStatus == AuthStatus.unauthenticated) {
        return const AuthScreen();
      }

      // Pending/Blocked -> Status-Meldung
      if (authStatus != AuthStatus.authenticated) {
        return _WebAuthWrapper(
          authStatus: authStatus,
        );
      }

      // Prüfe ob 2FA aktiviert ist
      final user = ref.watch(authStatusProvider.notifier).currentUser;
      if (user != null && !user.totpEnabled) {
        return const _WebTOTPSetupRequired();
      }

      // Authentifiziert mit 2FA - zeige App
      return const HomeScreen();
    }

    // Mobile: Bestehende Logik (Lock Screen + optional Auth)
    if (_isLocked) {
      return LockScreen(onUnlocked: _onUnlocked);
    }
    return const HomeScreen();
  }
}

/// Web 2FA Setup Required Screen
class _WebTOTPSetupRequired extends ConsumerStatefulWidget {
  const _WebTOTPSetupRequired();

  @override
  ConsumerState<_WebTOTPSetupRequired> createState() => _WebTOTPSetupRequiredState();
}

class _WebTOTPSetupRequiredState extends ConsumerState<_WebTOTPSetupRequired> {
  bool _isSettingUp = false;

  Future<void> _startTOTPSetup() async {
    setState(() => _isSettingUp = true);

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const TOTPSetupScreen(),
        fullscreenDialog: true,
      ),
    );

    if (result == true) {
      // TOTP erfolgreich eingerichtet - User-Daten aktualisieren
      await ref.read(authStatusProvider.notifier).refresh();
    }

    if (mounted) {
      setState(() => _isSettingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.security,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '2-Faktor-Authentifizierung erforderlich',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Für die Nutzung der Web-App ist die Einrichtung der '
                    '2-Faktor-Authentifizierung (2FA) erforderlich. '
                    'Dies schützt deinen Account vor unbefugtem Zugriff.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Du benötigst eine Authenticator-App wie Google Authenticator oder Authy.',
                              style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSettingUp ? null : _startTOTPSetup,
                      icon: _isSettingUp
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shield),
                      label: Text(_isSettingUp ? 'Wird eingerichtet...' : '2FA jetzt einrichten'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.read(authStatusProvider.notifier).logout(),
                    child: const Text('Abmelden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web Auth Wrapper - zeigt Login oder Status-Meldung
class _WebAuthWrapper extends ConsumerWidget {
  final AuthStatus authStatus;

  const _WebAuthWrapper({required this.authStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(context, ref),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    switch (authStatus) {
      case AuthStatus.pendingApproval:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 64,
              color: Colors.orange[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Warte auf Freischaltung',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Dein Account wurde registriert und wartet auf die Freischaltung durch einen Administrator.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.read(authStatusProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Status prüfen'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(authStatusProvider.notifier).logout(),
              child: const Text('Abmelden'),
            ),
          ],
        );

      case AuthStatus.blocked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block,
              size: 64,
              color: Colors.red[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Account gesperrt',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Dein Account wurde gesperrt. Bitte kontaktiere einen Administrator.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => ref.read(authStatusProvider.notifier).logout(),
              child: const Text('Abmelden'),
            ),
          ],
        );

      default:
        return const CircularProgressIndicator();
    }
  }
}
