import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import '../providers.dart';
import '../services/geofence_service.dart';
import '../services/geofence_sync_service.dart';
import '../services/geofence_event_queue.dart';
import '../models/work_entry.dart';
import 'settings_screen.dart';
import 'vacation_screen.dart';
import 'report_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _geoService = MyGeofenceService();
  late final GeofenceSyncService _syncService;
  GeofenceStatus? _geofenceStatus;
  bool _isInitializing = true;
  String? _initError;

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
      // App kam in den Vordergrund - Events synchronisieren
      _syncPendingEvents();
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    try {
      // Zuerst ausstehende Events verarbeiten
      await _syncPendingEvents();

      // Dann Geofence initialisieren
      await _initializeGeofence();

      setState(() => _isInitializing = false);
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });
    }
  }

  Future<void> _initializeGeofence() async {
    try {
      // Standort-Berechtigung prüfen
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          throw Exception('Standort-Berechtigung benötigt');
        }
      }

      // Standort-Service prüfen
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Standort-Dienst ist deaktiviert');
      }

      // Aktuelle Position holen
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      // Geofence initialisieren
      await _geoService.init(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      // Geofence-Fehler nicht als kritisch behandeln
      debugPrint('Geofence init error: $e');
    }
  }

  Future<void> _syncPendingEvents() async {
    final processedCount = await _syncService.syncPendingEvents();
    if (processedCount > 0) {
      // UI aktualisieren wenn Events verarbeitet wurden
      ref.invalidate(workListProvider);
    }
    await _updateStatus();
  }

  Future<void> _updateStatus() async {
    final status = await _syncService.getStatus();
    if (mounted) {
      setState(() => _geofenceStatus = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(workListProvider);
    final last = entries.isEmpty ? null : entries.last;
    final running = last != null && last.stop == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TimeTracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
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
      body: RefreshIndicator(
        onRefresh: _syncPendingEvents,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status Card
            _buildStatusCard(running),
            const SizedBox(height: 24),

            // Start/Stop Button
            _buildMainButton(running, last),
            const SizedBox(height: 24),

            // Geofence Status
            if (_geofenceStatus != null) _buildGeofenceInfo(),

            // Error Display
            if (_initError != null) _buildErrorCard(),

            // Recent Entries
            const SizedBox(height: 24),
            _buildRecentEntries(entries),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool running) {
    return Card(
      color: running ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              running ? Icons.play_circle : Icons.pause_circle,
              size: 48,
              color: running ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              running ? 'Arbeitszeit läuft' : 'Nicht aktiv',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: running ? Colors.green.shade700 : Colors.grey.shade700,
              ),
            ),
            if (running && _geofenceStatus?.lastEvent != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Gestartet: ${_formatTime(_geofenceStatus!.lastEvent!.timestamp)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainButton(bool running, WorkEntry? last) {
    return SizedBox(
      height: 80,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: running ? Colors.red : Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _isInitializing
            ? null
            : () async {
                final now = DateTime.now();
                final box = Hive.box<WorkEntry>('work');

                if (running && last != null) {
                  last.stop = now;
                  await last.save();
                } else {
                  await box.add(WorkEntry(start: now));
                }

                ref.invalidate(workListProvider);
                await _updateStatus();
              },
        child: _isInitializing
            ? const CircularProgressIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(running ? Icons.stop : Icons.play_arrow, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    running ? 'STOP' : 'START',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
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
                    color: status.isInZone ? Colors.green.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.isInZone ? 'Im Bereich' : 'Außerhalb',
                    style: TextStyle(
                      fontSize: 12,
                      color: status.isInZone ? Colors.green.shade700 : Colors.grey.shade700,
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
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _initError!,
                style: TextStyle(color: Colors.red.shade700),
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
          ...recent.map((entry) => ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      entry.stop == null ? Colors.green : Colors.blue,
                  child: Icon(
                    entry.stop == null ? Icons.play_arrow : Icons.check,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(_formatDate(entry.start)),
                subtitle: Text(
                  entry.stop == null
                      ? 'Läuft seit ${_formatTime(entry.start)}'
                      : '${_formatTime(entry.start)} - ${_formatTime(entry.stop!)}',
                ),
                trailing: entry.stop != null
                    ? Text(
                        _formatDuration(entry.stop!.difference(entry.start)),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              )),
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
