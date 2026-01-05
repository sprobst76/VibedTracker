// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_point.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocationPointAdapter extends TypeAdapter<LocationPoint> {
  @override
  final int typeId = 6;

  @override
  LocationPoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocationPoint(
      timestamp: fields[0] as DateTime,
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      accuracy: fields[3] as double?,
      workEntryId: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LocationPoint obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.accuracy)
      ..writeByte(4)
      ..write(obj.workEntryId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationPointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
