import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import '../models/location_point.dart';

/// Service für GPS-Tracking während der Arbeitszeit
class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  StreamSubscription<Position>? _positionStream;
  String? _currentWorkEntryId;
  bool _isTracking = false;

  bool get isTracking => _isTracking;

  /// Startet das GPS-Tracking für einen Arbeitseintrag
  Future<void> startTracking(String workEntryId) async {
    if (_isTracking) {
      debugPrint('Location tracking already active');
      return;
    }

    // Berechtigungen prüfen
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested != LocationPermission.always && requested != LocationPermission.whileInUse) {
        debugPrint('Location permission denied');
        return;
      }
    }

    _currentWorkEntryId = workEntryId;
    _isTracking = true;

    // Initiale Position speichern
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _saveLocation(position);
    } catch (e) {
      debugPrint('Error getting initial position: $e');
    }

    // Position-Stream starten (alle 5 Minuten oder bei 100m Bewegung)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100, // Mindestens 100m Bewegung
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _saveLocation(position);
    }, onError: (error) {
      debugPrint('Location stream error: $error');
    });

    // Zusätzlich: Timer für regelmäßige Updates alle 5 Minuten
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        await _saveLocation(position);
      } catch (e) {
        debugPrint('Timer position error: $e');
      }
    });

    debugPrint('Location tracking started for entry: $workEntryId');
  }

  /// Stoppt das GPS-Tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    // Finale Position speichern
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _saveLocation(position);
    } catch (e) {
      debugPrint('Error getting final position: $e');
    }

    await _positionStream?.cancel();
    _positionStream = null;
    _currentWorkEntryId = null;
    _isTracking = false;

    debugPrint('Location tracking stopped');
  }

  /// Speichert eine Position in Hive
  Future<void> _saveLocation(Position position) async {
    if (_currentWorkEntryId == null) return;

    try {
      final box = Hive.box<LocationPoint>('location_points');
      final point = LocationPoint(
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        workEntryId: _currentWorkEntryId,
      );
      await box.add(point);
      debugPrint('Saved location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error saving location: $e');
    }
  }

  /// Gibt alle Location Points für einen Arbeitseintrag zurück
  List<LocationPoint> getLocationsForEntry(String workEntryId) {
    final box = Hive.box<LocationPoint>('location_points');
    return box.values.where((p) => p.workEntryId == workEntryId).toList();
  }

  /// Löscht alle Location Points für einen Arbeitseintrag
  Future<void> deleteLocationsForEntry(String workEntryId) async {
    final box = Hive.box<LocationPoint>('location_points');
    final toDelete = box.values.where((p) => p.workEntryId == workEntryId).toList();
    for (final point in toDelete) {
      await point.delete();
    }
  }
}
