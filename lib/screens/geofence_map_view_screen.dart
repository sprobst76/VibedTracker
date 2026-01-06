import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../providers.dart';
import '../models/geofence_zone.dart';

/// Kartenansicht aller Geofence-Zonen
class GeofenceMapViewScreen extends ConsumerStatefulWidget {
  const GeofenceMapViewScreen({super.key});

  @override
  ConsumerState<GeofenceMapViewScreen> createState() => _GeofenceMapViewScreenState();
}

class _GeofenceMapViewScreenState extends ConsumerState<GeofenceMapViewScreen> {
  late MapController _mapController;
  bool _loadingPosition = false;
  Position? _currentPosition;
  GeofenceZone? _selectedZone;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadCurrentPosition();
  }

  Future<void> _loadCurrentPosition() async {
    setState(() => _loadingPosition = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() => _loadingPosition = false);
      }
    } catch (e) {
      debugPrint('Error getting position: $e');
      if (mounted) {
        setState(() => _loadingPosition = false);
      }
    }
  }

  void _fitAllZones(List<GeofenceZone> zones) {
    if (zones.isEmpty) {
      if (_currentPosition != null) {
        _mapController.move(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          15,
        );
      }
      return;
    }

    if (zones.length == 1) {
      _mapController.move(
        LatLng(zones.first.latitude, zones.first.longitude),
        15,
      );
      return;
    }

    // Berechne Bounds für alle Zonen
    double minLat = zones.first.latitude;
    double maxLat = zones.first.latitude;
    double minLng = zones.first.longitude;
    double maxLng = zones.first.longitude;

    for (final zone in zones) {
      if (zone.latitude < minLat) minLat = zone.latitude;
      if (zone.latitude > maxLat) maxLat = zone.latitude;
      if (zone.longitude < minLng) minLng = zone.longitude;
      if (zone.longitude > maxLng) maxLng = zone.longitude;
    }

    // Padding hinzufügen
    final latPadding = (maxLat - minLat) * 0.2;
    final lngPadding = (maxLng - minLng) * 0.2;

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat - latPadding, minLng - lngPadding),
          LatLng(maxLat + latPadding, maxLng + lngPadding),
        ),
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(geofenceZonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbeitsorte Karte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Alle Orte anzeigen',
            onPressed: () => _fitAllZones(zones),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _getInitialCenter(zones),
              initialZoom: 12,
              onTap: (_, __) => setState(() => _selectedZone = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.timetracker',
              ),
              // Circles for all zones
              CircleLayer(
                circles: zones.map((zone) {
                  final isSelected = _selectedZone == zone;
                  return CircleMarker(
                    point: LatLng(zone.latitude, zone.longitude),
                    radius: zone.radius,
                    useRadiusInMeter: true,
                    color: zone.isActive
                        ? (isSelected ? Colors.blue.withAlpha(100) : Colors.green.withAlpha(50))
                        : Colors.grey.withAlpha(50),
                    borderColor: zone.isActive
                        ? (isSelected ? Colors.blue : Colors.green)
                        : Colors.grey,
                    borderStrokeWidth: isSelected ? 3 : 2,
                  );
                }).toList(),
              ),
              // Markers for all zones
              MarkerLayer(
                markers: [
                  ...zones.map((zone) {
                    final isSelected = _selectedZone == zone;
                    return Marker(
                      point: LatLng(zone.latitude, zone.longitude),
                      width: isSelected ? 50 : 40,
                      height: isSelected ? 50 : 40,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedZone = zone),
                        child: Icon(
                          Icons.location_pin,
                          color: zone.isActive ? Colors.green : Colors.grey,
                          size: isSelected ? 50 : 40,
                        ),
                      ),
                    );
                  }),
                  // Current position marker
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withAlpha(100),
                              blurRadius: 10,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 16),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Loading Indicator
          if (_loadingPosition)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          // Zoom Buttons
          Positioned(
            right: 16,
            top: 80,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'mapview_zoom_in',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'mapview_zoom_out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          // My Location Button
          Positioned(
            right: 16,
            bottom: _selectedZone != null ? 180 : 16,
            child: FloatingActionButton(
              heroTag: 'mapview_my_location',
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    15,
                  );
                } else {
                  _loadCurrentPosition();
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),
          // Selected Zone Info Card
          if (_selectedZone != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: _selectedZone!.isActive ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedZone!.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (_selectedZone!.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Aktiv',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _selectedZone = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.radar, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('Radius: ${_selectedZone!.radius.round()}m'),
                          const SizedBox(width: 16),
                          const Icon(Icons.gps_fixed, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${_selectedZone!.latitude.toStringAsFixed(5)}, ${_selectedZone!.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              _mapController.move(
                                LatLng(_selectedZone!.latitude, _selectedZone!.longitude),
                                17,
                              );
                            },
                            icon: const Icon(Icons.center_focus_strong),
                            label: const Text('Zentrieren'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final notifier = ref.read(geofenceZonesProvider.notifier);
                              await notifier.updateZone(
                                _selectedZone!,
                                newIsActive: !_selectedZone!.isActive,
                              );
                              setState(() {});
                            },
                            icon: Icon(_selectedZone!.isActive ? Icons.pause : Icons.play_arrow),
                            label: Text(_selectedZone!.isActive ? 'Deaktivieren' : 'Aktivieren'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Legend
          Positioned(
            left: 16,
            top: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLegendItem(Colors.green, 'Aktiv'),
                    _buildLegendItem(Colors.grey, 'Inaktiv'),
                    _buildLegendItem(Colors.blue, 'Du bist hier'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  LatLng _getInitialCenter(List<GeofenceZone> zones) {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    if (zones.isNotEmpty) {
      return LatLng(zones.first.latitude, zones.first.longitude);
    }
    return const LatLng(51.1657, 10.4515); // Deutschland Mitte
  }
}
