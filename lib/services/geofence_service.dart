// lib/services/geofence_service.dart
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/models/zone.dart';
import 'package:latlng/latlng.dart';
import 'package:permission_handler/permission_handler.dart';
import 'geofence_callback.dart';

class MyGeofenceService {
  /// Startet den Foreground-Service und fügt einen Kreis-Geofence hinzu.
  Future<void> init({required double lat, required double lng}) async {
    final status = await Permission.locationAlways.request();
    if (!status.isGranted) {
      throw Exception('Standort-Berechtigung verweigert');
    }

    final started = await GeofenceForegroundService().startGeofencingService(
      notificationChannelId: 'time_tracker_channel',
      contentTitle: 'TimeTracker im Hintergrund',
      contentText: 'Zonenüberwachung aktiv',
      serviceId: 1,
      callbackDispatcher: callbackDispatcher,
    );
    if (!started) {
      throw Exception('Geofencing-Service konnte nicht gestartet werden');
    }

    await GeofenceForegroundService().addGeofenceZone(
      zone: Zone(
        id: 'office',
        radius: 150, // Radius in Metern :contentReference[oaicite:7]{index=7}
        coordinates: [
          LatLng(lat, lng)
        ], // Zentrum als Liste mit einem LatLng :contentReference[oaicite:8]{index=8}
        triggers: [
          GeofenceEventType.enter,
          GeofenceEventType.exit,
        ],
      ),
    );
  }
}
