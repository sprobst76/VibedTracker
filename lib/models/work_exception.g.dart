// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_exception.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkExceptionAdapter extends TypeAdapter<WorkException> {
  @override
  final int typeId = 10;

  @override
  WorkException read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkException(
      date: fields[0] as DateTime,
      isWorkingDay: fields[1] as bool,
      reason: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WorkException obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.isWorkingDay)
      ..writeByte(2)
      ..write(obj.reason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkExceptionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
