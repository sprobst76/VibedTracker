import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import '../providers.dart';
import '../services/geofence_service.dart';
import '../services/geofence_sync_service.dart';
import '../services/geofence_event_queue.dart';
import '../services/geofence_notification_service.dart';
import '../services/work_status_notification_service.dart';
import '../services/reminder_service.dart';
import '../services/cloud_sync_service.dart';
import '../models/work_entry.dart';
import '../models/pause.dart';
import '../theme/theme_colors.dart';
import 'settings_screen.dart';
import 'vacation_screen.dart';
import 'report_screen.dart';
import 'entry_edit_screen.dart';
import '../widgets/copy_entry_dialog.dart';
import '../services/location_tracking_service.dart';
import 'calendar_overview_screen.dart';
import '../widgets/responsive_shell.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _geoService = MyGeofenceService();
  late final GeofenceSyncService _syncService;
  final _locationService = LocationTrackingService();
  final _reminderService = ReminderService();
  final _geofenceNotificationService = GeofenceNotificationService();
  final _workStatusNotificationService = WorkStatusNotificationService();
  GeofenceStatus? _geofenceStatus;
  bool _isInitializing = true;
  String? _initError;
  List<DateTime> _missingDays = [];

  // Cloud Sync für Web
  SyncStatus _cloudSyncStatus = SyncStatus.idle;
  String? _cloudSyncError;
  bool _isCloudSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncService = GeofenceSyncService(Hive.box<WorkEntry>('work'));
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPendingEvents();
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    try {
      // Web: Cloud Sync statt Geofence
      if (kIsWeb) {
        // Automatischer Cloud-Sync beim Start
        await _performCloudSync();
      } else {
        // Mobile: Platform-specific features
        await _reminderService.init();
        await _geofenceNotificationService.init();
        await _workStatusNotificationService.init();
        // Pending Einsprüche verarbeiten (aus Background-Aktionen)
        final objectionCount =
            await _geofenceNotificationService.processPendingObjections();
        if (objectionCount > 0) {
          ref.invalidate(workListProvider);
        }
        await _syncPendingEvents();
        await _initializeGeofence();
        await _setupReminders();
        // Status-Notification aktualisieren
        await _updateWorkStatusNotification();
      }
      await _loadMissingDays();
      setState(() => _isInitializing = false);
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });
    }
  }

  /// Cloud Sync für Web-User
  Future<void> _performCloudSync() async {
    if (_isCloudSyncing) return;

    setState(() {
      _isCloudSyncing = true;
      _cloudSyncError = null;
    });

    try {
      final syncService = ref.read(cloudSyncServiceProvider);
      final result = await syncService.sync();

      if (mounted) {
        setState(() {
          _cloudSyncStatus = result.status;
          _cloudSyncError = result.errorMessage;
          _isCloudSyncing = false;
        });

        // Bei Erfolg: Daten neu laden
        if (result.status == SyncStatus.success) {
          ref.invalidate(workListProvider);
          ref.invalidate(workEntryProvider);
          ref.invalidate(vacationProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cloudSyncStatus = SyncStatus.error;
          _cloudSyncError = e.toString();
          _isCloudSyncing = false;
        });
      }
    }
  }

  Future<void> _setupReminders() async {
    final settings = ref.read(settingsProvider);
    if (settings.enableReminders) {
      await _reminderService.scheduleDailyReminder(settings.reminderHour);
    } else {
      await _reminderService.cancelAllReminders();
    }
  }

  Future<void> _loadMissingDays() async {
    final settings = ref.read(settingsProvider);
    final workEntries = ref.read(workListProvider);
    final vacations = ref.read(vacationProvider);

    final missing = await _reminderService.getMissingDays(
      workEntries: workEntries,
      vacations: vacations,
      bundesland: settings.bundesland,
      daysToCheck: 14, // Letzte 2 Wochen prüfen
    );

    if (mounted) {
      setState(() {
        _missingDays = missing;
      });
    }
  }

  Future<void> _initializeGeofence() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          throw Exception('Standort-Berechtigung benötigt');
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Standort-Dienst ist deaktiviert');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      await _geoService.init(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      debugPrint('Geofence init error: $e');
    }
  }

  Future<void> _syncPendingEvents() async {
    final processedCount = await _syncService.syncPendingEvents();
    if (processedCount > 0) {
      ref.invalidate(workListProvider);
    }
    await _updateStatus();
    await _updateWorkStatusNotification();
  }

  /// Aktualisiert die Status-Notification in der Symbolleiste
  Future<void> _updateWorkStatusNotification() async {
    if (kIsWeb) return; // Nur für Mobile

    try {
      final workBox = Hive.box<WorkEntry>('work');
      final runningEntries = workBox.values.where((e) => e.stop == null).toList();
      final runningEntry = runningEntries.isNotEmpty ? runningEntries.last : null;
      await _workStatusNotificationService.updateStatus(runningEntry);
    } catch (e) {
      debugPrint('Error updating work status notification: $e');
    }
  }

  Future<void> _updateStatus() async {
    final status = await _syncService.getStatus();
    if (mounted) {
      setState(() => _geofenceStatus = status);
    }
  }

  // Pause-Hilfsmethoden
  Pause? _getActivePause(WorkEntry? entry) {
    if (entry == null) return null;
    try {
      return entry.pauses.lastWhere((p) => p.end == null);
    } catch (e) {
      return null;
    }
  }

  Future<void> _startPause(WorkEntry entry) async {
    entry.pauses.add(Pause(start: DateTime.now()));
    await entry.save();
    ref.invalidate(workListProvider);
    await _updateWorkStatusNotification();
  }

  Future<void> _endPause(WorkEntry entry, Pause pause) async {
    pause.end = DateTime.now();
    await entry.save();
    ref.invalidate(workListProvider);
    await _updateWorkStatusNotification();
  }

  Duration _getTotalPauseDuration(WorkEntry entry) {
    var total = Duration.zero;
    for (final pause in entry.pauses) {
      final end = pause.end ?? DateTime.now();
      total += end.difference(pause.start);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(workListProvider);
    final last = entries.isEmpty ? null : entries.last;
    final running = last != null && last.stop == null;
    final activePause = _getActivePause(last);
    final isPaused = activePause != null;
    final isWideScreen = MediaQuery.of(context).size.width >= 800;

    // Content (shared between web and mobile)
    final content = RefreshIndicator(
      onRefresh: kIsWeb ? () async {} : _syncPendingEvents,
      child: ListView(
        padding: EdgeInsets.all(kIsWeb && isWideScreen ? 24 : 16),
        children: [
          // Web: Cards in responsive grid
          if (kIsWeb && isWideScreen) ...[
            _buildWebDashboard(running, isPaused, last, activePause, entries),
          ] else ...[
            // Mobile: Vertical layout
            _buildStatusCard(running, isPaused, last),
            const SizedBox(height: 16),
            if (_missingDays.isNotEmpty) ...[
              _buildMissingDaysCard(),
              const SizedBox(height: 16),
            ],
            _buildButtonRow(running, isPaused, last, activePause),
            const SizedBox(height: 16),
            if (running && last.pauses.isNotEmpty)
              _buildPauseCard(last, activePause),
            // Geofence Status (nur Mobile)
            if (!kIsWeb && _geofenceStatus != null) ...[
              const SizedBox(height: 16),
              _buildGeofenceInfo(),
            ],
            if (_initError != null) _buildErrorCard(),
            const SizedBox(height: 16),
            _buildRecentEntries(entries),
          ],
        ],
      ),
    );

    // Web: Use ResponsiveShell
    if (kIsWeb && isWideScreen) {
      return ResponsiveShell(
        title: 'Dashboard',
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEntryEditor(null),
          icon: const Icon(Icons.add),
          label: const Text('Neuer Eintrag'),
        ),
        child: content,
      );
    }

    // Mobile: Standard Scaffold
    return Scaffold(
      appBar: AppBar(
        title: const Text('VibedTracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Kalenderübersicht',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalendarOverviewScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.event_available),
            tooltip: 'Abwesenheiten',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VacationScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntryEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('Neuer Eintrag'),
      ),
    );
  }

  /// Web Dashboard Layout mit Grid
  Widget _buildWebDashboard(
    bool running,
    bool isPaused,
    WorkEntry? last,
    Pause? activePause,
    List<WorkEntry> entries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Status + Actions + Sync
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card (wider)
            Expanded(
              flex: 2,
              child: _buildStatusCard(running, isPaused, last),
            ),
            const SizedBox(width: 16),
            // Action Buttons + Sync Status
            Expanded(
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Aktionen',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          _buildWebActionButtons(running, isPaused, last, activePause),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cloud Sync Status
                  _buildCloudSyncStatus(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Missing Days Warning
        if (_missingDays.isNotEmpty) ...[
          _buildMissingDaysCard(),
          const SizedBox(height: 16),
        ],

        // Pause Info
        if (running && last != null && last.pauses.isNotEmpty) ...[
          _buildPauseCard(last, activePause),
          const SizedBox(height: 16),
        ],

        // Error Display
        if (_initError != null) _buildErrorCard(),

        // Recent Entries
        _buildRecentEntries(entries),
      ],
    );
  }

  /// Cloud Sync Status Widget für Web
  Widget _buildCloudSyncStatus() {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_cloudSyncStatus) {
      case SyncStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.cloud_done;
        statusText = 'Synchronisiert';
        break;
      case SyncStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.cloud_off;
        statusText = _cloudSyncError ?? 'Sync-Fehler';
        break;
      case SyncStatus.offline:
        statusColor = Colors.orange;
        statusIcon = Icons.cloud_off;
        statusText = 'Offline';
        break;
      case SyncStatus.notApproved:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        statusText = 'Nicht freigeschaltet';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.cloud_queue;
        statusText = 'Bereit';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cloud-Sync',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                ],
              ),
            ),
            if (_isCloudSyncing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: _performCloudSync,
                tooltip: 'Jetzt synchronisieren',
              ),
          ],
        ),
      ),
    );
  }

  /// Web-optimierte Action Buttons
  Widget _buildWebActionButtons(
    bool running,
    bool isPaused,
    WorkEntry? last,
    Pause? activePause,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.read(settingsProvider);

    if (!running) {
      return FilledButton.icon(
        onPressed: _isInitializing
            ? null
            : () async {
                final now = DateTime.now();
                final box = Hive.box<WorkEntry>('work');
                final entry = WorkEntry(start: now);
                await box.add(entry);
                // GPS-Tracking nur auf Mobile
                if (!kIsWeb && settings.enableLocationTracking) {
                  await _locationService.startTracking(entry.key.toString());
                }
                ref.invalidate(workListProvider);
                await _updateStatus();
                await _updateWorkStatusNotification();
              },
        icon: const Icon(Icons.play_arrow),
        label: const Text('Arbeit starten'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: colorScheme.primary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isPaused)
          OutlinedButton.icon(
            onPressed: () => _startPause(last!),
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )
        else
          FilledButton.icon(
            onPressed: () => _endPause(last!, activePause!),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Pause beenden'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.orange,
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            // Aktive Pause beenden falls vorhanden
            if (activePause != null) {
              activePause.end = now;
            }
            last!.stop = now;
            await last.save();
            // GPS-Tracking nur auf Mobile
            if (!kIsWeb && settings.enableLocationTracking) {
              await _locationService.stopTracking();
            }
            ref.invalidate(workListProvider);
            await _updateStatus();
            await _updateWorkStatusNotification();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Arbeit beenden'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: colorScheme.error,
          ),
        ),
      ],
    );
  }

  Future<void> _openEntryEditor(WorkEntry? entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditScreen(entry: entry),
      ),
    );
    if (result == true) {
      ref.invalidate(workListProvider);
      ref.invalidate(workEntryProvider);
    }
  }

  Future<void> _showCopyDialog(WorkEntry entry) async {
    final selectedDays = await showDialog<List<DateTime>>(
      context: context,
      builder: (_) => CopyEntryDialog(sourceDate: entry.start),
    );

    if (selectedDays != null && selectedDays.isNotEmpty) {
      await ref.read(workEntryProvider.notifier).copyEntryToDays(entry, selectedDays);
      ref.invalidate(workListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eintrag auf ${selectedDays.length} Tag(e) kopiert'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildStatusCard(bool running, bool isPaused, WorkEntry? entry) {
    final settings = ref.watch(settingsProvider);
    Color bgColor;
    Color iconColor;
    IconData icon;
    String statusText;

    if (!running) {
      bgColor = context.neutralBackground;
      iconColor = context.neutralForeground;
      icon = Icons.pause_circle;
      statusText = 'Nicht aktiv';
    } else if (isPaused) {
      bgColor = context.pauseBackground;
      iconColor = context.pauseForeground;
      icon = Icons.coffee;
      statusText = 'Pause';
    } else {
      bgColor = context.successBackground;
      iconColor = context.successForeground;
      icon = Icons.play_circle;
      statusText = 'Arbeitszeit läuft';
    }

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            if (running && entry != null) ...[
              const SizedBox(height: 8),
              // Aktueller Arbeitsmodus mit Wechsel-Option
              _buildWorkModeChips(entry),
              const SizedBox(height: 8),
              Text(
                'Gestartet: ${_formatTime(entry.start)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (entry.pauses.isNotEmpty)
                Text(
                  'Pausen: ${_formatDuration(_getTotalPauseDuration(entry))}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              if (settings.enableLocationTracking && _locationService.isTracking)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gps_fixed, size: 14, color: Colors.blue.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'GPS-Tracking aktiv',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkModeChips(WorkEntry entry) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: WorkMode.values.map((mode) {
        final isSelected = entry.workMode == mode;
        final modeColor = mode.getColor(context);
        return FilterChip(
          avatar: Icon(
            mode.icon,
            size: 16,
            color: isSelected ? Colors.white : modeColor,
          ),
          label: Text(
            mode.label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.white : null,
            ),
          ),
          selected: isSelected,
          selectedColor: modeColor,
          checkmarkColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          onSelected: isSelected ? null : (_) => _switchWorkMode(entry, mode),
        );
      }).toList(),
    );
  }

  Future<void> _switchWorkMode(WorkEntry currentEntry, WorkMode newMode) async {
    final now = DateTime.now();
    final box = Hive.box<WorkEntry>('work');
    final settings = ref.read(settingsProvider);

    // Aktive Pause beenden falls vorhanden
    final activePause = currentEntry.pauses.cast<Pause?>().firstWhere(
      (p) => p?.end == null,
      orElse: () => null,
    );
    if (activePause != null) {
      activePause.end = now;
    }

    // Aktuellen Eintrag stoppen
    currentEntry.stop = now;
    await currentEntry.save();

    // Neuen Eintrag mit neuem Modus starten
    final newEntry = WorkEntry(
      start: now,
      workModeIndex: newMode.index,
      projectId: currentEntry.projectId, // Projekt beibehalten
    );
    await box.add(newEntry);

    // GPS-Tracking auf neuen Eintrag übertragen
    if (settings.enableLocationTracking && _locationService.isTracking) {
      await _locationService.stopTracking();
      await _locationService.startTracking(newEntry.key.toString());
    }

    ref.invalidate(workListProvider);
    await _updateStatus();
    await _updateWorkStatusNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modus gewechselt zu: ${newMode.label}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildButtonRow(bool running, bool isPaused, WorkEntry? last, Pause? activePause) {
    return Row(
      children: [
        // Start/Stop Button
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 64,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: running ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isInitializing
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final box = Hive.box<WorkEntry>('work');
                      final settings = ref.read(settingsProvider);

                      if (running && last != null) {
                        // Aktive Pause beenden falls vorhanden
                        if (activePause != null) {
                          activePause.end = now;
                        }
                        last.stop = now;
                        await last.save();

                        // GPS-Tracking stoppen
                        if (settings.enableLocationTracking) {
                          await _locationService.stopTracking();
                        }
                      } else {
                        final entry = WorkEntry(start: now);
                        await box.add(entry);

                        // GPS-Tracking starten wenn aktiviert
                        if (settings.enableLocationTracking) {
                          await _locationService.startTracking(entry.key.toString());
                        }
                      }

                      ref.invalidate(workListProvider);
                      await _updateStatus();
                      await _updateWorkStatusNotification();
                    },
              child: _isInitializing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(running ? Icons.stop : Icons.play_arrow, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          running ? 'STOP' : 'START',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),
        ),

        // Pause Button (nur wenn Arbeit läuft)
        if (running && last != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPaused ? Colors.green : Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (isPaused && activePause != null) {
                    await _endPause(last, activePause);
                  } else {
                    await _startPause(last);
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isPaused ? Icons.play_arrow : Icons.coffee, size: 24),
                    Text(
                      isPaused ? 'Weiter' : 'Pause',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPauseCard(WorkEntry entry, Pause? activePause) {
    final totalPause = _getTotalPauseDuration(entry);

    return Card(
      color: activePause != null ? context.pauseBackground : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.coffee,
                  color: activePause != null ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Pausen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Gesamt: ${_formatDuration(totalPause)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            if (entry.pauses.isNotEmpty) ...[
              const Divider(),
              ...entry.pauses.map((pause) {
                final isActive = pause.end == null;
                final duration = (pause.end ?? DateTime.now()).difference(pause.start);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? Colors.orange : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatTime(pause.start),
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        ' - ${isActive ? 'läuft' : _formatTime(pause.end!)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isActive ? Colors.orange : Colors.grey.shade600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? Colors.orange : Colors.grey.shade600,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGeofenceInfo() {
    final status = _geofenceStatus!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: status.isInZone ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Geofence Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.isInZone ? context.successBackground : context.neutralBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.isInZone ? 'Im Bereich' : 'Außerhalb',
                    style: TextStyle(
                      fontSize: 12,
                      color: status.isInZone ? context.successForeground : context.neutralForeground,
                    ),
                  ),
                ),
              ],
            ),
            if (status.lastEvent != null) ...[
              const Divider(),
              Text(
                'Letztes Event: ${status.lastEvent!.event == GeofenceEvent.enter ? 'Betreten' : 'Verlassen'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              Text(
                _formatDateTime(status.lastEvent!.timestamp),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            if (status.pendingEventsCount > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.sync, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '${status.pendingEventsCount} Event(s) ausstehend',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: context.errorBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.errorForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _initError!,
                style: TextStyle(color: context.errorForeground),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _initialize,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingDaysCard() {
    return Card(
      color: context.warningBackground,
      child: InkWell(
        onTap: _showMissingDaysDialog,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.amber.shade700 : Colors.amber.shade600,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${_missingDays.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _missingDays.length == 1
                          ? '1 Tag ohne Eintrag'
                          : '${_missingDays.length} Tage ohne Eintrag',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.warningForeground,
                      ),
                    ),
                    Text(
                      'Tippe hier um Details zu sehen',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.warningForeground.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.warningForeground),
            ],
          ),
        ),
      ),
    );
  }

  void _showMissingDaysDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            const Text('Fehlende Einträge'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Für folgende Tage fehlt ein Arbeitszeit-Eintrag oder eine Abwesenheit:',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _missingDays.length,
                  itemBuilder: (context, index) {
                    final day = _missingDays[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_busy, color: Colors.orange),
                      title: Text(_formatDate(day)),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          Navigator.pop(context);
                          // Zum Vacation-Screen navigieren mit vorausgewähltem Tag
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const VacationScreen()),
                          );
                        },
                        tooltip: 'Eintrag hinzufügen',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VacationScreen()),
              );
            },
            child: const Text('Abwesenheit eintragen'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEntries(List<WorkEntry> entries) {
    final recent = entries.reversed.take(5).toList();

    if (recent.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.history, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Keine Einträge vorhanden',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Letzte Einträge',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ...recent.map((entry) {
            final isRunning = entry.stop == null;
            final pauseDuration = _getTotalPauseDuration(entry);
            final hasPauses = entry.pauses.isNotEmpty;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isRunning ? Colors.green : Colors.blue,
                child: Icon(
                  isRunning ? Icons.play_arrow : Icons.check,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(_formatDate(entry.start)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRunning
                        ? 'Läuft seit ${_formatTime(entry.start)}'
                        : '${_formatTime(entry.start)} - ${_formatTime(entry.stop!)}',
                  ),
                  if (hasPauses)
                    Text(
                      'Pausen: ${_formatDuration(pauseDuration)} (${entry.pauses.length}x)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.stop != null)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDuration(entry.stop!.difference(entry.start) - pauseDuration),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (hasPauses)
                          Text(
                            'netto',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  if (entry.stop != null)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () => _showCopyDialog(entry),
                      tooltip: 'Kopieren',
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _openEntryEditor(entry),
                    tooltip: 'Bearbeiten',
                  ),
                ],
              ),
              isThreeLine: hasPauses,
              onTap: () => _openEntryEditor(entry),
            );
          }),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[dt.weekday - 1]}, ${dt.day}.${dt.month}.${dt.year}';
  }

  String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)} ${_formatTime(dt)}';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
