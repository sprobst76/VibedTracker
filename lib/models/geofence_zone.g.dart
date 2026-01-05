// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geofence_zone.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GeofenceZoneAdapter extends TypeAdapter<GeofenceZone> {
  @override
  final int typeId = 5;

  @override
  GeofenceZone read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GeofenceZone(
      id: fields[0] as String,
      name: fields[1] as String,
      latitude: fields[2] as double,
      longitude: fields[3] as double,
      radius: fields[4] as double,
      isActive: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, GeofenceZone obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.radius)
      ..writeByte(5)
      ..write(obj.isActive);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceZoneAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
