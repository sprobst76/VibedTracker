import 'package:flutter/material.dart';

class AppTheme {
  // Light Theme
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );

  // Dark Theme - optimiert für besseren Kontrast
  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF90CAF9),           // Hellblau für primäre Elemente
      onPrimary: Color(0xFF003258),         // Dunkel auf Primär
      primaryContainer: Color(0xFF004880),  // Container-Blau
      onPrimaryContainer: Color(0xFFD1E4FF),
      secondary: Color(0xFF80DEEA),         // Cyan-Akzent
      onSecondary: Color(0xFF003737),
      secondaryContainer: Color(0xFF004F4F),
      onSecondaryContainer: Color(0xFFB2EBF2),
      surface: Color(0xFF121212),           // Dunkler Hintergrund
      onSurface: Color(0xFFE0E0E0),         // Heller Text
      surfaceContainerHighest: Color(0xFF2D2D2D), // Erhöhte Oberflächen
      error: Color(0xFFCF6679),
      onError: Color(0xFF000000),
      outline: Color(0xFF5C5C5C),           // Rahmen
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Color(0xFFE0E0E0),
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      color: const Color(0xFF1E1E1E),       // Dunklere Cards
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF252525),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1E1E),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF3D3D3D),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 4,
      backgroundColor: Color(0xFF90CAF9),
      foregroundColor: Color(0xFF003258),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF2D2D2D),
      selectedColor: const Color(0xFF004880),
      labelStyle: const TextStyle(color: Color(0xFFE0E0E0)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFFB0B0B0),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF5C5C5C)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF5C5C5C)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF90CAF9), width: 2),
      ),
      fillColor: const Color(0xFF2D2D2D),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
      bodyMedium: TextStyle(color: Color(0xFFE0E0E0)),
      bodySmall: TextStyle(color: Color(0xFFB0B0B0)),
      titleLarge: TextStyle(color: Color(0xFFFFFFFF)),
      titleMedium: TextStyle(color: Color(0xFFE0E0E0)),
      titleSmall: TextStyle(color: Color(0xFFE0E0E0)),
      labelLarge: TextStyle(color: Color(0xFFE0E0E0)),
      labelMedium: TextStyle(color: Color(0xFFB0B0B0)),
      labelSmall: TextStyle(color: Color(0xFF909090)),
    ),
    iconTheme: const IconThemeData(
      color: Color(0xFFB0B0B0),
    ),
  );
}
