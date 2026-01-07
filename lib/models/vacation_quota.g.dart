// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vacation_quota.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VacationQuotaAdapter extends TypeAdapter<VacationQuota> {
  @override
  final int typeId = 12;

  @override
  VacationQuota read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VacationQuota(
      year: fields[0] as int,
      carryoverDays: fields[1] as double,
      adjustmentDays: fields[2] as double,
      note: fields[3] as String?,
      manualUsedDays: fields[4] as double,
      annualEntitlementDays: fields[5] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, VacationQuota obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.year)
      ..writeByte(1)
      ..write(obj.carryoverDays)
      ..writeByte(2)
      ..write(obj.adjustmentDays)
      ..writeByte(3)
      ..write(obj.note)
      ..writeByte(4)
      ..write(obj.manualUsedDays)
      ..writeByte(5)
      ..write(obj.annualEntitlementDays);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VacationQuotaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
