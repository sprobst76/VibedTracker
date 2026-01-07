import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/screens/settings_screen.dart';
import 'package:time_tracker/models/settings.dart';
import 'package:time_tracker/models/vacation_quota.dart';
import 'package:time_tracker/models/project.dart';
import 'package:time_tracker/models/weekly_hours_period.dart';
import 'package:time_tracker/providers.dart';

void main() {
  testWidgets('Settings Screen zeigt Titel und Arbeitszeit', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
        weeklyHoursPeriodsProvider.overrideWith((ref) => MockWeeklyHoursPeriodsNotifier()),
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

    // Prüfe Arbeitszeit-Sektion
    expect(find.text('Wöchentliche Arbeitszeit'), findsOneWidget);
  });

  testWidgets('Settings Screen zeigt aktuelle Wochenstunden', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
        weeklyHoursPeriodsProvider.overrideWith((ref) => MockWeeklyHoursPeriodsNotifier()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Prüfe, dass die aktuellen Stunden angezeigt werden (40h Badge)
    expect(find.text('40h'), findsOneWidget);

    // Prüfe, dass der Button zum Verwalten der Perioden vorhanden ist
    expect(find.text('Arbeitszeit-Perioden verwalten'), findsOneWidget);
  });

  testWidgets('Settings Screen ist scrollbar', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        currentYearVacationStatsProvider.overrideWith((ref) => _mockVacationStats()),
        projectsProvider.overrideWith((ref) => MockProjectsNotifier()),
        weeklyHoursPeriodsProvider.overrideWith((ref) => MockWeeklyHoursPeriodsNotifier()),
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

/// Mock für WeeklyHoursPeriodsNotifier
class MockWeeklyHoursPeriodsNotifier extends WeeklyHoursPeriodsNotifier {
  MockWeeklyHoursPeriodsNotifier() : super(_MockWeeklyHoursBox(), 40.0);

  @override
  List<WeeklyHoursPeriod> get state => [];

  @override
  double getWeeklyHoursForDate(DateTime date) => 40.0;
}

/// Mock für Hive Box - Settings
class _MockSettingsBox extends Fake implements Box<Settings> {
  @override
  Settings? get(dynamic key, {Settings? defaultValue}) => Settings();

  @override
  bool containsKey(dynamic key) => true;

  @override
  Future<void> put(dynamic key, Settings value) async {}
}

/// Mock für Hive Box - Project
class _MockProjectsBox extends Fake implements Box<Project> {
  @override
  Iterable<Project> get values => [];

  @override
  Future<int> add(Project value) async => 0;

  @override
  Future<void> put(dynamic key, Project value) async {}
}

/// Mock für Hive Box - WeeklyHoursPeriod
class _MockWeeklyHoursBox extends Fake implements Box<WeeklyHoursPeriod> {
  @override
  Iterable<WeeklyHoursPeriod> get values => [];

  @override
  Future<int> add(WeeklyHoursPeriod value) async => 0;

  @override
  Future<void> put(dynamic key, WeeklyHoursPeriod value) async {}
}
