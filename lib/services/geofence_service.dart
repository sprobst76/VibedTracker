// lib/services/geofence_service.dart
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/models/zone.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:hive/hive.dart';
import 'package:latlng/latlng.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/geofence_zone.dart';
import 'geofence_callback.dart';

class MyGeofenceService {
  /// Startet den Foreground-Service und fügt die konfigurierten Geofence-Zonen hinzu.
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

    // Lade konfigurierte Zonen aus Hive
    await _registerConfiguredZones(lat, lng);
  }

  /// Registriert alle aktiven Zonen aus der Konfiguration
  Future<void> _registerConfiguredZones(double currentLat, double currentLng) async {
    final box = Hive.box<GeofenceZone>('geofence_zones');
    final zones = box.values.where((z) => z.isActive).toList();

    if (zones.isEmpty) {
      // Fallback: Aktuelle Position als Zone verwenden
      await GeofenceForegroundService().addGeofenceZone(
        zone: Zone(
          id: 'current_location',
          radius: 150,
          coordinates: [LatLng.degree(currentLat, currentLng)],
          triggers: [
            GeofenceEventType.enter,
            GeofenceEventType.exit,
          ],
        ),
      );
    } else {
      // Registriere alle aktiven Zonen
      for (final geofenceZone in zones) {
        await GeofenceForegroundService().addGeofenceZone(
          zone: Zone(
            id: geofenceZone.id,
            radius: geofenceZone.radius,
            coordinates: [LatLng.degree(geofenceZone.latitude, geofenceZone.longitude)],
            triggers: [
              GeofenceEventType.enter,
              GeofenceEventType.exit,
            ],
          ),
        );
      }
    }
  }

  /// Aktualisiert die registrierten Zonen
  Future<void> refreshZones() async {
    // Entferne alle Zonen und registriere neu
    // Hinweis: geofence_foreground_service hat keine removeZone-Methode,
    // daher muss der Service neu gestartet werden für Änderungen
  }
}
