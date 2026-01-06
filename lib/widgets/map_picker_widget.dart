import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Ein wiederverwendbares Map-Widget zur Auswahl eines Standorts
class MapPickerWidget extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final double initialRadius;
  final bool showRadius;
  final ValueChanged<LatLng>? onLocationChanged;
  final ValueChanged<double>? onRadiusChanged;
  final double height;

  const MapPickerWidget({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadius = 150,
    this.showRadius = true,
    this.onLocationChanged,
    this.onRadiusChanged,
    this.height = 300,
  });

  @override
  State<MapPickerWidget> createState() => _MapPickerWidgetState();
}

class _MapPickerWidgetState extends State<MapPickerWidget> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  double _radius = 150;
  bool _loadingPosition = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _radius = widget.initialRadius;

    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      _loadCurrentPosition();
    }
  }

  Future<void> _loadCurrentPosition() async {
    setState(() => _loadingPosition = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() {
          _selectedLocation = LatLng(position.latitude, position.longitude);
          _loadingPosition = false;
        });
        _mapController.move(_selectedLocation!, 15);
        widget.onLocationChanged?.call(_selectedLocation!);
      }
    } catch (e) {
      debugPrint('Error getting position: $e');
      if (mounted) {
        setState(() {
          _selectedLocation = const LatLng(51.1657, 10.4515); // Deutschland Mitte als Fallback
          _loadingPosition = false;
        });
      }
    }
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
    widget.onLocationChanged?.call(point);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedLocation ?? const LatLng(51.1657, 10.4515),
                initialZoom: 15,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.timetracker',
                ),
                if (_selectedLocation != null) ...[
                  // Radius Circle
                  if (widget.showRadius)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _selectedLocation!,
                          radius: _radius,
                          useRadiusInMeter: true,
                          color: Colors.blue.withAlpha(50),
                          borderColor: Colors.blue,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  // Marker
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Loading Indicator
          if (_loadingPosition)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          // My Location Button
          Positioned(
            right: 8,
            bottom: 8,
            child: FloatingActionButton.small(
              heroTag: 'map_my_location',
              onPressed: _loadCurrentPosition,
              child: const Icon(Icons.my_location),
            ),
          ),
          // Zoom Buttons
          Positioned(
            right: 8,
            top: 8,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'map_zoom_in',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 4),
                FloatingActionButton.small(
                  heroTag: 'map_zoom_out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vollbild-Map-Picker für die Standortauswahl
class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final double initialRadius;

  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadius = 150,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  double _radius = 150;
  bool _loadingPosition = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _radius = widget.initialRadius;

    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      _loadCurrentPosition();
    }
  }

  Future<void> _loadCurrentPosition() async {
    setState(() => _loadingPosition = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() {
          _selectedLocation = LatLng(position.latitude, position.longitude);
          _loadingPosition = false;
        });
        _mapController.move(_selectedLocation!, 15);
      }
    } catch (e) {
      debugPrint('Error getting position: $e');
      if (mounted) {
        setState(() {
          _selectedLocation = const LatLng(51.1657, 10.4515);
          _loadingPosition = false;
        });
      }
    }
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Standort auswählen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selectedLocation != null
                ? () => Navigator.pop(context, {
                      'lat': _selectedLocation!.latitude,
                      'lng': _selectedLocation!.longitude,
                      'radius': _radius,
                    })
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation ?? const LatLng(51.1657, 10.4515),
                    initialZoom: 15,
                    onTap: _onTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.timetracker',
                    ),
                    if (_selectedLocation != null) ...[
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _selectedLocation!,
                            radius: _radius,
                            useRadiusInMeter: true,
                            color: Colors.blue.withAlpha(50),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation!,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 50,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (_loadingPosition)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    heroTag: 'fullscreen_my_location',
                    onPressed: _loadCurrentPosition,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'fullscreen_zoom_in',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        ),
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'fullscreen_zoom_out',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        ),
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Radius Slider
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar),
                    const SizedBox(width: 8),
                    const Text('Radius:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _radius,
                        min: 50,
                        max: 500,
                        divisions: 45,
                        label: '${_radius.round()}m',
                        onChanged: (value) => setState(() => _radius = value),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${_radius.round()}m',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (_selectedLocation != null)
                  Text(
                    '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
