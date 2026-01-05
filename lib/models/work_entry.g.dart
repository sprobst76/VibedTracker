// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkEntryAdapter extends TypeAdapter<WorkEntry> {
  @override
  final int typeId = 0;

  @override
  WorkEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkEntry(
      start: fields[0] as DateTime,
      stop: fields[1] as DateTime?,
      pauses: (fields[2] as List?)?.cast<Pause>(),
    );
  }

  @override
  void write(BinaryWriter writer, WorkEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.start)
      ..writeByte(1)
      ..write(obj.stop)
      ..writeByte(2)
      ..write(obj.pauses);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
