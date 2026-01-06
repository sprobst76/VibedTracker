import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/screens/settings_screen.dart';
import 'package:time_tracker/models/settings.dart';
import 'package:time_tracker/models/vacation_quota.dart';
import 'package:time_tracker/models/project.dart';
import 'package:time_tracker/providers.dart';

void main() {
  testWidgets('Settings Screen zeigt Titel und Arbeitszeit', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe Titel
    expect(find.text('Einstellungen'), findsOneWidget);

    // Prüfe Arbeitszeit-Sektion (erste Karte)
    expect(find.text('Wöchentliche Arbeitszeit (Standard)'), findsOneWidget);
  });

  testWidgets('Settings Screen zeigt Arbeitszeit-Eingabe mit korrektem Wert', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe, dass TextField für Arbeitszeit vorhanden ist
    expect(find.byType(TextField), findsWidgets);

    // Prüfe, dass der Wert im TextField angezeigt wird (40,0 mit Komma für DE)
    expect(find.text('40,0'), findsOneWidget);

    // Prüfe, dass 'pro Woche' Label vorhanden ist
    expect(find.text('pro Woche'), findsOneWidget);
  });

  testWidgets('Settings Screen ist scrollbar', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe, dass ListView vorhanden ist (scrollbarer Inhalt)
    expect(find.byType(ListView), findsOneWidget);

    // Prüfe, dass mehrere Cards vorhanden sind
    expect(find.byType(Card), findsWidgets);
  });
}

/// Mock VacationStats für Provider
VacationStats _mockVacationStats() {
  return VacationStats(
    year: DateTime.now().year,
    annualEntitlement: 30,
    carryover: 0,
    adjustments: 0,
    trackedDays: 5,
    manualDays: 0,
    vacationEntries: 2,
  );
}

/// Mock für SettingsNotifier
class MockSettingsNotifier extends SettingsNotifier {
  MockSettingsNotifier() : super(_MockSettingsBox());

  @override
  Settings get state => Settings(weeklyHours: 40.0, locale: 'de_DE');
}

/// Mock für ProjectsNotifier
class MockProjectsNotifier extends ProjectsNotifier {
  MockProjectsNotifier() : super(_MockProjectsBox());

  @override
  List<Project> get state => [];
}

/// Mock für Hive Box<Settings>
class _MockSettingsBox extends Fake implements Box<Settings> {
  @override
  Settings? get(dynamic key, {Settings? defaultValue}) => Settings();

  @override
  bool containsKey(dynamic key) => true;

  @override
  Future<void> put(dynamic key, Settings value) async {}
}

/// Mock für Hive Box<Project>
class _MockProjectsBox extends Fake implements Box<Project> {
  @override
  Iterable<Project> get values => [];

  @override
  Future<int> add(Project value) async => 0;

  @override
  Future<void> put(dynamic key, Project value) async {}
}
