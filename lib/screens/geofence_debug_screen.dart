import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../models/geofence_zone.dart';
import '../providers.dart';
import '../services/geofence_event_queue.dart';
import '../theme/theme_colors.dart';

class GeofenceDebugScreen extends ConsumerStatefulWidget {
  const GeofenceDebugScreen({super.key});

  @override
  ConsumerState<GeofenceDebugScreen> createState() => _GeofenceDebugScreenState();
}

class _GeofenceDebugScreenState extends ConsumerState<GeofenceDebugScreen> {
  // Permission states
  PermissionStatus? _locationPermission;
  PermissionStatus? _locationAlwaysPermission;
  PermissionStatus? _notificationPermission;
  bool? _locationServiceEnabled;

  // Current position
  Position? _currentPosition;
  bool _loadingPosition = false;
  String? _positionError;

  // Event queue
  List<GeofenceEventData> _allEvents = [];
  List<GeofenceEventData> _pendingEvents = [];
  GeofenceEventData? _lastEvent;
  bool _isInZone = false;

  // Auto-refresh timer
  Timer? _refreshTimer;
  DateTime _lastRefresh = DateTime.now();

  // Logs
  final List<_LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Auto-refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAll());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadPermissions(),
      _loadPosition(),
      _loadEventQueue(),
    ]);
    setState(() => _lastRefresh = DateTime.now());
  }

  Future<void> _loadPermissions() async {
    final results = await Future.wait([
      Permission.location.status,
      Permission.locationAlways.status,
      Permission.notification.status,
      Geolocator.isLocationServiceEnabled(),
    ]);

    if (mounted) {
      setState(() {
        _locationPermission = results[0] as PermissionStatus;
        _locationAlwaysPermission = results[1] as PermissionStatus;
        _notificationPermission = results[2] as PermissionStatus;
        _locationServiceEnabled = results[3] as bool;
      });
    }
  }

  Future<void> _loadPosition() async {
    if (_loadingPosition) return;

    setState(() {
      _loadingPosition = true;
      _positionError = null;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _loadingPosition = false;
        });
        _addLog('Position geladen: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _positionError = e.toString();
          _loadingPosition = false;
        });
        _addLog('Position-Fehler: $e', isError: true);
      }
    }
  }

  Future<void> _loadEventQueue() async {
    final results = await Future.wait([
      GeofenceEventQueue.getQueue(),
      GeofenceEventQueue.getUnprocessedEvents(),
      GeofenceEventQueue.getLastEvent(),
      GeofenceEventQueue.isCurrentlyInZone(),
    ]);

    if (mounted) {
      setState(() {
        _allEvents = results[0] as List<GeofenceEventData>;
        _pendingEvents = results[1] as List<GeofenceEventData>;
        _lastEvent = results[2] as GeofenceEventData?;
        _isInZone = results[3] as bool;
      });
    }
  }

  void _addLog(String message, {bool isError = false}) {
    setState(() {
      _logs.insert(0, _LogEntry(
        timestamp: DateTime.now(),
        message: message,
        isError: isError,
      ));
      // Keep only last 50 logs
      if (_logs.length > 50) {
        _logs.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(geofenceZonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Aktualisieren',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportLog,
            tooltip: 'Log exportieren',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Last Refresh
            Text(
              'Letzte Aktualisierung: ${_formatTime(_lastRefresh)}',
              style: TextStyle(fontSize: 12, color: context.subtleText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Permissions Section
            _buildPermissionsCard(),
            const SizedBox(height: 16),

            // Current Position Section
            _buildPositionCard(),
            const SizedBox(height: 16),

            // Zones Section
            _buildZonesCard(zones),
            const SizedBox(height: 16),

            // Event Queue Section
            _buildEventQueueCard(),
            const SizedBox(height: 16),

            // Event History Section
            _buildEventHistoryCard(),
            const SizedBox(height: 16),

            // Log Section
            _buildLogCard(),
            const SizedBox(height: 16),

            // Actions Section
            _buildActionsCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Berechtigungen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildPermissionRow(
              'Location (WhenInUse)',
              _locationPermission,
              Icons.location_on,
            ),
            _buildPermissionRow(
              'Location (Always)',
              _locationAlwaysPermission,
              Icons.location_on,
              isRequired: true,
            ),
            _buildPermissionRow(
              'Notifications',
              _notificationPermission,
              Icons.notifications,
            ),
            const Divider(),
            _buildStatusRow(
              'Location Service',
              _locationServiceEnabled == true,
              _locationServiceEnabled == true ? 'Aktiviert' : 'Deaktiviert',
              Icons.gps_fixed,
            ),
            const SizedBox(height: 12),
            if (_locationAlwaysPermission != PermissionStatus.granted)
              ElevatedButton.icon(
                onPressed: () async {
                  final status = await Permission.locationAlways.request();
                  _addLog('Location Always angefordert: $status');
                  await _loadPermissions();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Location Always anfordern'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRow(String label, PermissionStatus? status, IconData icon, {bool isRequired = false}) {
    Color statusColor;
    String statusText;

    switch (status) {
      case PermissionStatus.granted:
        statusColor = Colors.green;
        statusText = 'Erteilt';
        break;
      case PermissionStatus.denied:
        statusColor = Colors.orange;
        statusText = 'Verweigert';
        break;
      case PermissionStatus.permanentlyDenied:
        statusColor = Colors.red;
        statusText = 'Dauerhaft verweigert';
        break;
      case PermissionStatus.restricted:
        statusColor = Colors.red;
        statusText = 'Eingeschränkt';
        break;
      case PermissionStatus.limited:
        statusColor = Colors.orange;
        statusText = 'Limitiert';
        break;
      case PermissionStatus.provisional:
        statusColor = Colors.orange;
        statusText = 'Vorläufig';
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Unbekannt';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Text(label),
                if (isRequired)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'WICHTIG',
                      style: TextStyle(fontSize: 8, color: Colors.red.shade700),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(51),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isOk, String statusText, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isOk ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (isOk ? Colors.green : Colors.red).withAlpha(51),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: isOk ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Aktuelle Position',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_loadingPosition)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(),
            if (_positionError != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.errorBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, size: 16, color: context.errorForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _positionError!,
                        style: TextStyle(fontSize: 12, color: context.errorForeground),
                      ),
                    ),
                  ],
                ),
              )
            else if (_currentPosition != null) ...[
              _buildInfoRow('Breitengrad', _currentPosition!.latitude.toStringAsFixed(6)),
              _buildInfoRow('Längengrad', _currentPosition!.longitude.toStringAsFixed(6)),
              _buildInfoRow('Genauigkeit', '${_currentPosition!.accuracy.toStringAsFixed(1)} m'),
              _buildInfoRow('Höhe', '${_currentPosition!.altitude.toStringAsFixed(1)} m'),
              _buildInfoRow('Geschwindigkeit', '${_currentPosition!.speed.toStringAsFixed(1)} m/s'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final text = '${_currentPosition!.latitude}, ${_currentPosition!.longitude}';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Koordinaten kopiert'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Koordinaten kopieren'),
              ),
            ] else
              const Text('Position wird geladen...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildZonesCard(List<GeofenceZone> zones) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Konfigurierte Zonen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isInZone ? Colors.green.withAlpha(51) : Colors.grey.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _isInZone ? 'In Zone' : 'Außerhalb',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isInZone ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            if (zones.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 20, color: context.warningForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keine Zonen konfiguriert! Geofencing kann nicht funktionieren.',
                        style: TextStyle(fontSize: 12, color: context.warningForeground),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...zones.map((zone) => _buildZoneRow(zone)),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneRow(GeofenceZone zone) {
    double? distance;
    if (_currentPosition != null) {
      distance = GeofenceZone.calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        zone.latitude,
        zone.longitude,
      );
    }

    final isNearby = distance != null && distance <= zone.radius;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNearby ? context.successBackground : null,
        border: Border.all(
          color: zone.isActive ? Colors.green : Colors.grey,
          width: zone.isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 20,
                color: zone.isActive ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zone.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (!zone.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Inaktiv', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${zone.latitude.toStringAsFixed(5)}, ${zone.longitude.toStringAsFixed(5)}',
            style: TextStyle(fontSize: 11, color: context.subtleText, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Radius: ${zone.radius.round()}m', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              if (distance != null) ...[
                Icon(
                  isNearby ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: isNearby ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  'Entfernung: ${_formatDistance(distance)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isNearby ? FontWeight.bold : FontWeight.normal,
                    color: isNearby ? Colors.green : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventQueueCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.queue, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Event Queue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_pendingEvents.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(51),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_pendingEvents.length} ausstehend',
                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Gesamt Events', '${_allEvents.length}'),
            _buildInfoRow('Ausstehend', '${_pendingEvents.length}'),
            _buildInfoRow('Verarbeitet', '${_allEvents.length - _pendingEvents.length}'),
            if (_lastEvent != null) ...[
              const Divider(),
              const Text('Letztes Event:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _lastEvent!.event == GeofenceEvent.enter
                      ? context.successBackground
                      : context.errorBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _lastEvent!.event == GeofenceEvent.enter ? Icons.login : Icons.logout,
                      size: 20,
                      color: _lastEvent!.event == GeofenceEvent.enter
                          ? context.successForeground
                          : context.errorForeground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lastEvent!.event == GeofenceEvent.enter ? 'ENTER' : 'EXIT',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _lastEvent!.event == GeofenceEvent.enter
                                  ? context.successForeground
                                  : context.errorForeground,
                            ),
                          ),
                          Text(
                            'Zone: ${_lastEvent!.zoneId}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            _formatDateTime(_lastEvent!.timestamp),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
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

  Widget _buildEventHistoryCard() {
    final recentEvents = _allEvents.reversed.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Event-Historie',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            if (recentEvents.isEmpty)
              const Text('Keine Events vorhanden', style: TextStyle(color: Colors.grey))
            else
              ...recentEvents.map((event) => _buildEventRow(event)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventRow(GeofenceEventData event) {
    final isEnter = event.event == GeofenceEvent.enter;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: event.processed ? Colors.grey.shade100 : (isEnter ? Colors.green.shade50 : Colors.red.shade50),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            isEnter ? Icons.login : Icons.logout,
            size: 16,
            color: isEnter ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            isEnter ? 'ENTER' : 'EXIT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isEnter ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatDateTime(event.timestamp),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          if (event.processed)
            const Icon(Icons.check, size: 14, color: Colors.grey)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'NEU',
                style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Debug Log',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _logs.clear()),
                  child: const Text('Leeren', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const Divider(),
            if (_logs.isEmpty)
              const Text('Keine Log-Einträge', style: TextStyle(color: Colors.grey))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '[${_formatTime(log.timestamp)}] ${log.message}',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: log.isError ? Colors.red : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      color: context.warningBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, color: context.warningForeground),
                const SizedBox(width: 8),
                Text(
                  'Debug-Aktionen',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.warningForeground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await GeofenceEventQueue.clear();
                    _addLog('Event-Queue geleert');
                    await _loadEventQueue();
                  },
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Queue leeren'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    // Simulate ENTER event
                    await GeofenceEventQueue.enqueue(GeofenceEventData(
                      zoneId: 'debug_test',
                      event: GeofenceEvent.enter,
                      timestamp: DateTime.now(),
                    ));
                    _addLog('Test ENTER Event erstellt');
                    await _loadEventQueue();
                  },
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Test ENTER'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    // Simulate EXIT event
                    await GeofenceEventQueue.enqueue(GeofenceEventData(
                      zoneId: 'debug_test',
                      event: GeofenceEvent.exit,
                      timestamp: DateTime.now(),
                    ));
                    _addLog('Test EXIT Event erstellt');
                    await _loadEventQueue();
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Test EXIT'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('App-Einstellungen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.subtleText, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _exportLog() async {
    final buffer = StringBuffer();
    buffer.writeln('=== VibedTracker Geofence Debug Log ===');
    buffer.writeln('Exportiert: ${_formatDateTime(DateTime.now())}');
    buffer.writeln();

    // Permissions
    buffer.writeln('--- Berechtigungen ---');
    buffer.writeln('Location: $_locationPermission');
    buffer.writeln('Location Always: $_locationAlwaysPermission');
    buffer.writeln('Notifications: $_notificationPermission');
    buffer.writeln('Location Service: $_locationServiceEnabled');
    buffer.writeln();

    // Position
    buffer.writeln('--- Position ---');
    if (_currentPosition != null) {
      buffer.writeln('Lat: ${_currentPosition!.latitude}');
      buffer.writeln('Lng: ${_currentPosition!.longitude}');
      buffer.writeln('Accuracy: ${_currentPosition!.accuracy}m');
    } else {
      buffer.writeln('Nicht verfügbar');
    }
    buffer.writeln();

    // Zones
    final zones = ref.read(geofenceZonesProvider);
    buffer.writeln('--- Zonen (${zones.length}) ---');
    for (final zone in zones) {
      buffer.writeln('${zone.name}: ${zone.latitude}, ${zone.longitude} (${zone.radius}m) - ${zone.isActive ? "aktiv" : "inaktiv"}');
    }
    buffer.writeln();

    // Events
    buffer.writeln('--- Events (${_allEvents.length}) ---');
    for (final event in _allEvents.reversed) {
      buffer.writeln('${_formatDateTime(event.timestamp)} - ${event.event.name.toUpperCase()} - Zone: ${event.zoneId} - ${event.processed ? "verarbeitet" : "ausstehend"}');
    }
    buffer.writeln();

    // Logs
    buffer.writeln('--- Debug Log ---');
    for (final log in _logs) {
      buffer.writeln('[${_formatDateTime(log.timestamp)}] ${log.message}');
    }

    await Share.share(
      buffer.toString(),
      subject: 'VibedTracker Geofence Debug Log',
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}. ${_formatTime(dt)}';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}

class _LogEntry {
  final DateTime timestamp;
  final String message;
  final bool isError;

  _LogEntry({required this.timestamp, required this.message, this.isError = false});
}
