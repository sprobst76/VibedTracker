import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/screens/settings_screen.dart';
import 'package:time_tracker/models/settings.dart';
import 'package:time_tracker/providers.dart';

void main() {
  testWidgets('Settings Screen zeigt alle Einstellungen', (WidgetTester tester) async {
    // Mock Settings Provider
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe, dass alle Einstellungs-Sektionen angezeigt werden
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Wöchentliche Arbeitszeit'), findsOneWidget);
    expect(find.text('Sprache / Region'), findsOneWidget);
    expect(find.text('Outlook ICS-Pfad'), findsOneWidget);
  });

  testWidgets('Settings Screen zeigt Slider für Arbeitszeit', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe, dass Slider vorhanden ist
    expect(find.byType(Slider), findsOneWidget);

    // Prüfe, dass der aktuelle Wert angezeigt wird
    expect(find.text('40.0 h'), findsWidgets);
  });
}

/// Mock für SettingsNotifier
class MockSettingsNotifier extends SettingsNotifier {
  MockSettingsNotifier() : super(_MockSettingsBox());

  @override
  Settings get state => Settings(weeklyHours: 40.0, locale: 'de_DE');
}

/// Mock für Hive Box
class _MockSettingsBox extends Fake implements Box<Settings> {
  @override
  Settings? get(dynamic key, {Settings? defaultValue}) => Settings();

  @override
  bool containsKey(dynamic key) => true;

  @override
  Future<void> put(dynamic key, Settings value) async {}
}
