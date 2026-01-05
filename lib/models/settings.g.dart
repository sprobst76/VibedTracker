// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsAdapter extends TypeAdapter<Settings> {
  @override
  final int typeId = 3;

  @override
  Settings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Settings(
      weeklyHours: fields[0] as double,
      locale: fields[1] as String,
      outlookIcsPath: fields[2] as String?,
      isDarkMode: fields[3] as bool,
      enableLocationTracking: fields[4] as bool,
      googleCalendarEnabled: fields[5] as bool,
      googleCalendarId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.weeklyHours)
      ..writeByte(1)
      ..write(obj.locale)
      ..writeByte(2)
      ..write(obj.outlookIcsPath)
      ..writeByte(3)
      ..write(obj.isDarkMode)
      ..writeByte(4)
      ..write(obj.enableLocationTracking)
      ..writeByte(5)
      ..write(obj.googleCalendarEnabled)
      ..writeByte(6)
      ..write(obj.googleCalendarId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
