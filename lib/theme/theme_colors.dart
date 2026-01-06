import 'package:flutter/material.dart';

/// Helper-Extension für theme-aware Farben
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // Status-Farben (angepasst für Dark Mode)
  Color get successBackground => isDark ? const Color(0xFF1B3D1B) : Colors.green.shade50;
  Color get successForeground => isDark ? Colors.green.shade300 : Colors.green.shade700;

  Color get warningBackground => isDark ? const Color(0xFF3D3520) : Colors.amber.shade50;
  Color get warningForeground => isDark ? Colors.amber.shade300 : Colors.amber.shade700;

  Color get errorBackground => isDark ? const Color(0xFF3D1B1B) : Colors.red.shade50;
  Color get errorForeground => isDark ? Colors.red.shade300 : Colors.red.shade700;

  Color get infoBackground => isDark ? const Color(0xFF1B2D3D) : Colors.blue.shade50;
  Color get infoForeground => isDark ? Colors.blue.shade300 : Colors.blue.shade700;

  Color get neutralBackground => isDark ? const Color(0xFF2D2D2D) : Colors.grey.shade100;
  Color get neutralForeground => isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  // Spezifische UI-Farben
  Color get cardHighlight => isDark ? const Color(0xFF252525) : Colors.white;
  Color get subtleText => isDark ? Colors.grey.shade400 : Colors.grey.shade600;
  Color get dividerColor => isDark ? const Color(0xFF3D3D3D) : Colors.grey.shade300;

  // Aktiv/Inaktiv Status
  Color get activeBackground => isDark ? const Color(0xFF1B3D1B) : Colors.green.shade50;
  Color get inactiveBackground => isDark ? const Color(0xFF2D2D2D) : Colors.grey.shade100;

  // Kalender-spezifisch
  Color get holidayBackground => isDark ? const Color(0xFF3D1B1B) : Colors.red.shade100;
  Color get holidayForeground => isDark ? Colors.red.shade300 : Colors.red.shade700;
  Color get todayBackground => isDark ? const Color(0xFF1B2D3D) : Colors.blue.shade100;
  Color get selectedBackground => isDark ? Colors.blue.shade700 : Colors.blue.shade300;

  // Orange für Pausen
  Color get pauseBackground => isDark ? const Color(0xFF3D2D1B) : Colors.orange.shade50;
  Color get pauseForeground => isDark ? Colors.orange.shade300 : Colors.orange.shade700;
}

/// Statische Farb-Hilfsmethoden
class AppColors {
  static Color statusBackground(BuildContext context, StatusType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case StatusType.success:
        return isDark ? const Color(0xFF1B3D1B) : Colors.green.shade50;
      case StatusType.warning:
        return isDark ? const Color(0xFF3D3520) : Colors.amber.shade50;
      case StatusType.error:
        return isDark ? const Color(0xFF3D1B1B) : Colors.red.shade50;
      case StatusType.info:
        return isDark ? const Color(0xFF1B2D3D) : Colors.blue.shade50;
      case StatusType.neutral:
        return isDark ? const Color(0xFF2D2D2D) : Colors.grey.shade100;
    }
  }

  static Color statusForeground(BuildContext context, StatusType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case StatusType.success:
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      case StatusType.warning:
        return isDark ? Colors.amber.shade300 : Colors.amber.shade700;
      case StatusType.error:
        return isDark ? Colors.red.shade300 : Colors.red.shade700;
      case StatusType.info:
        return isDark ? Colors.blue.shade300 : Colors.blue.shade700;
      case StatusType.neutral:
        return isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    }
  }
}

enum StatusType { success, warning, error, info, neutral }
