# VibedTracker

Zeiterfassung mit Geofence, Urlaub, Feiertagen & Cloud-Sync.

## Features

### Zeiterfassung
- **Automatische Erfassung** via Geofencing (GPS-basiert)
- **Manuelle Einträge** erstellen, bearbeiten, löschen
- **Pausen** einzeln erfassen
- **Arbeitsmodi**: Normal, Deep Work, Meeting, Support, Administration
- **Projekte** zuordnen (mit Farbkodierung)
- **GPS-Tracking** optional während der Arbeit

### Abwesenheiten
- **Urlaubsverwaltung** mit Jahresanspruch pro Jahr
- **Abwesenheitstypen**: Urlaub, Krankheit, Kind krank, Sonderurlaub, Unbezahlt
- **Feiertage** automatisch (deutschlandweit oder pro Bundesland)
- **Heiligabend & Silvester** konfigurierbar (frei/halber Tag/voll)
- **Resturlaub-Übertrag** ins nächste Jahr

### Berichte
- **Wochenübersicht** mit Soll/Ist-Vergleich und Überstunden
- **Monatsübersicht** mit Excel-Export
- **Jahresübersicht**
- **Kalenderansicht** mit allen Einträgen

### Weitere Features
- **Dark Mode** (System/Hell/Dunkel)
- **Google Kalender** Integration (nur lesen)
- **Erinnerungen** für fehlende Einträge
- **Backup & Restore** als ZIP-Datei
- **App-Sperre** mit PIN/Biometrie

## Installation

### Voraussetzungen
- Flutter SDK (stable channel)
- Android Studio oder VS Code mit Flutter-Erweiterung
- Android SDK (für Android-Builds)

### Setup

```bash
# Repository klonen
git clone https://github.com/sprobst76/VibedTracker.git
cd VibedTracker

# Abhängigkeiten installieren
flutter pub get

# Hive-Adapter generieren
dart run build_runner build --delete-conflicting-outputs

# App starten (Debug)
flutter run

# Release-APK bauen
flutter build apk --release
```

### APK-Download

Fertige APKs sind als [GitHub Releases](https://github.com/sprobst76/VibedTracker/releases) verfügbar.

## CI/CD

### GitHub Actions Workflows

- **Flutter CI** (`flutter_ci.yml`): Läuft bei Push auf `main` und PRs
  - `flutter analyze`
  - `flutter test`

- **Release** (`release.yml`): Läuft bei Tag-Push (`v*`)
  - Baut Release-APK
  - Erstellt GitHub Release mit APK

### Release erstellen

```bash
# Version in pubspec.yaml anpassen
# Dann:
git add pubspec.yaml
git commit -m "chore: bump version to x.y.z"
git push origin main
git tag vx.y.z
git push origin vx.y.z
```

## Projektstruktur

```
lib/
├── main.dart              # App-Einstiegspunkt
├── providers.dart         # Riverpod State Management
├── models/                # Datenmodelle (Hive)
│   ├── work_entry.dart
│   ├── vacation.dart
│   ├── vacation_quota.dart
│   ├── settings.dart
│   ├── project.dart
│   └── ...
├── screens/               # UI Screens
│   ├── home_screen.dart
│   ├── settings_screen.dart
│   ├── vacation_screen.dart
│   ├── report_screen.dart
│   └── ...
├── services/              # Business Logic
│   ├── backup_service.dart
│   ├── geofence_service.dart
│   ├── holiday_service.dart
│   └── ...
└── theme/                 # Theming
    └── theme_colors.dart
```

## Technologie-Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Datenbank**: Hive (lokal, verschlüsselt)
- **Maps**: flutter_map (OpenStreetMap)
- **Geofencing**: geofence_foreground_service
- **Auth**: local_auth (Biometrie)

## Roadmap

Siehe [TODO.md](TODO.md) für geplante Features.

## Lizenz

Proprietär - Alle Rechte vorbehalten.

## Autor

Stefan Probst (@sprobst76)
