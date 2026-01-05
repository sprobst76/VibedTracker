import 'dart:math' as math;
import 'package:hive/hive.dart';

part 'geofence_zone.g.dart';

@HiveType(typeId: 5)
class GeofenceZone extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double latitude;

  @HiveField(3)
  double longitude;

  @HiveField(4)
  double radius; // in Metern

  @HiveField(5)
  bool isActive;

  GeofenceZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radius = 150.0,
    this.isActive = true,
  });

  /// Prüft ob ein Punkt innerhalb des Geofence liegt
  bool containsPoint(double lat, double lng) {
    final distance = calculateDistance(latitude, longitude, lat, lng);
    return distance <= radius;
  }

  /// Berechnet die Distanz zwischen zwei Koordinaten in Metern (Haversine)
  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // Erdradius in Metern
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
