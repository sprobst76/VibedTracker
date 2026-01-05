# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
flutter pub get                                                    # Install dependencies
flutter pub run build_runner build --delete-conflicting-outputs   # Generate Hive adapters (required after model changes)
flutter analyze                                                    # Run static analysis/linting
flutter test --coverage                                            # Run all tests
flutter test test/widget_test.dart                                 # Run single test file
flutter run                                                        # Run on connected device/emulator
flutter build apk                                                  # Build Android APK
```

After modifying any `@HiveType` model in `lib/models/`, regenerate adapters with build_runner.

## Architecture

**Flutter time tracking app** with geofence-based automatic time entry, vacation management, and Outlook ICS sync.

### State Management Pattern
- **Riverpod** for reactive state management
- `providers.dart` exposes Hive box providers and state notifiers
- Screens consume providers via `ConsumerWidget` or `ref.watch()`

### Data Layer
- **Hive** offline-first database with typed boxes
- Three boxes: `work` (WorkEntry), `vacation` (Vacation), `settings` (Settings)
- Models in `lib/models/` use `@HiveType` annotations; generated adapters in `.g.dart` files

### Key Services (`lib/services/`)
- `geofence_service.dart` + `geofence_callback.dart`: Background location monitoring for auto start/stop
- `holiday_service.dart`: German holiday lookup via flutter_holiday
- `ics_service.dart`: Export work entries and vacations to iCalendar format
- `ics_import_service.dart`: Parse ICS files for Outlook sync

### Screen Structure (`lib/screens/`)
- `home_screen.dart`: Main UI with Start/Stop button, geofence status
- `settings_screen.dart`: Weekly hours, locale, ICS export path
- `vacation_screen.dart`: Calendar-based vacation day management
- `report_screen.dart`: Weekly work hours summary

## Key Dependencies

- `flutter_riverpod`: State management
- `hive`/`hive_flutter`: Local database
- `geofence_foreground_service`: Background geofencing (Android/iOS)
- `geolocator`: GPS location
- `google_maps_flutter`: Map display
- `enough_icalendar`/`icalendar_parser`: ICS export/import
- `table_calendar`: Calendar widget

## CI/CD

GitHub Actions runs on push/PR to main:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test --coverage`

Workflow: `.github/workflows/flutter_ci.yml`
