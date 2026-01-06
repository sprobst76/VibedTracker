import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
part 'vacation.g.dart';

/// Abwesenheitstypen
enum AbsenceType {
  vacation,     // Urlaub (0)
  illness,      // Krankheit (1)
  childSick,    // Kind krank (2)
  specialLeave, // Sonderurlaub (3)
  unpaid,       // Unbezahlt frei (4)
}

extension AbsenceTypeExtension on AbsenceType {
  String get label {
    switch (this) {
      case AbsenceType.vacation:
        return 'Urlaub';
      case AbsenceType.illness:
        return 'Krankheit';
      case AbsenceType.childSick:
        return 'Kind krank';
      case AbsenceType.specialLeave:
        return 'Sonderurlaub';
      case AbsenceType.unpaid:
        return 'Unbezahlt frei';
    }
  }

  Color get color {
    switch (this) {
      case AbsenceType.vacation:
        return Colors.orange;
      case AbsenceType.illness:
        return Colors.purple;
      case AbsenceType.childSick:
        return Colors.pink;
      case AbsenceType.specialLeave:
        return Colors.teal;
      case AbsenceType.unpaid:
        return Colors.grey;
    }
  }

  IconData get icon {
    switch (this) {
      case AbsenceType.vacation:
        return Icons.beach_access;
      case AbsenceType.illness:
        return Icons.local_hospital;
      case AbsenceType.childSick:
        return Icons.child_care;
      case AbsenceType.specialLeave:
        return Icons.event_available;
      case AbsenceType.unpaid:
        return Icons.money_off;
    }
  }

  /// Ob dieser Typ als bezahlte Arbeitszeit gilt (für Soll-Berechnung)
  /// Unbezahlt frei reduziert die Soll-Stunden NICHT
  bool get isPaid => this != AbsenceType.unpaid;
}

@HiveType(typeId: 2)
class Vacation extends HiveObject {
  @HiveField(0)
  DateTime day;
  @HiveField(1)
  String? description;
  @HiveField(2)
  int typeIndex;

  Vacation({
    required this.day,
    this.description,
    AbsenceType type = AbsenceType.vacation,
  }) : typeIndex = type.index;

  AbsenceType get type => AbsenceType.values[typeIndex.clamp(0, 4)];
  set type(AbsenceType value) => typeIndex = value.index;
}
