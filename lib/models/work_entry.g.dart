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
    // Handle workModeIndex type conversion (may be String in old data)
    int workModeIndex = 0;
    final rawWorkModeIndex = fields[6];
    if (rawWorkModeIndex is int) {
      workModeIndex = rawWorkModeIndex;
    } else if (rawWorkModeIndex is String) {
      workModeIndex = int.tryParse(rawWorkModeIndex) ?? 0;
    }
    return WorkEntry(
      start: fields[0] as DateTime,
      stop: fields[1] as DateTime?,
      pauses: (fields[2] as List?)?.cast<Pause>(),
      notes: fields[3] as String?,
      tags: (fields[4] as List?)?.cast<String>(),
      projectId: fields[5] as String?,
      workModeIndex: workModeIndex,
    );
  }

  @override
  void write(BinaryWriter writer, WorkEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.start)
      ..writeByte(1)
      ..write(obj.stop)
      ..writeByte(2)
      ..write(obj.pauses)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.tags)
      ..writeByte(5)
      ..write(obj.projectId)
      ..writeByte(6)
      ..write(obj.workModeIndex);
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
