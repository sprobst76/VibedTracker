// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_hours_period.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WeeklyHoursPeriodAdapter extends TypeAdapter<WeeklyHoursPeriod> {
  @override
  final int typeId = 4;

  @override
  WeeklyHoursPeriod read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WeeklyHoursPeriod(
      startDate: fields[0] as DateTime,
      endDate: fields[1] as DateTime?,
      weeklyHours: fields[2] as double,
      description: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WeeklyHoursPeriod obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.startDate)
      ..writeByte(1)
      ..write(obj.endDate)
      ..writeByte(2)
      ..write(obj.weeklyHours)
      ..writeByte(3)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyHoursPeriodAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
