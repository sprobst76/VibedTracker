import 'package:hive/hive.dart';

part 'location_point.g.dart';

@HiveType(typeId: 6)
class LocationPoint extends HiveObject {
  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  double latitude;

  @HiveField(2)
  double longitude;

  @HiveField(3)
  double? accuracy;

  @HiveField(4)
  String? workEntryId; // Verknüpfung zum WorkEntry

  LocationPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.workEntryId,
  });
}
