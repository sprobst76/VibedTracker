import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'project.g.dart';

@HiveType(typeId: 11)
class Project extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? colorHex;

  @HiveField(3)
  bool isActive;

  @HiveField(4)
  int sortOrder;

  Project({
    required this.id,
    required this.name,
    this.colorHex,
    this.isActive = true,
    this.sortOrder = 0,
  });

  Color get color {
    if (colorHex != null && colorHex!.isNotEmpty) {
      try {
        return Color(int.parse(colorHex!.replaceFirst('#', '0xFF')));
      } catch (_) {
        return Colors.blue;
      }
    }
    return Colors.blue;
  }

  set color(Color value) {
    colorHex = '#${value.value.toRadixString(16).substring(2).toUpperCase()}';
  }
}
