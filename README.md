# Time Tracker

## Setup für Android auf Windows PC

1. Flutter installieren: https://flutter.dev
2. Repository klonen und ins Verzeichnis navigieren.
3. Abhängigkeiten installieren:
   ```bash
   flutter pub get
   ```
4. Hive-Adapter generieren:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
5. Android-Emulator starten oder Gerät verbinden.
6. App starten:
   ```bash
   flutter run
   ```

## Aktuelle Features

- Geofencing (Android & iOS): Start/Stopp der Arbeitszeit anhand von GPS-Zäunen.
- Manuelle Pausen-Erfassung.
- Urlaubsverwaltung: Eintragen ganzer Urlaubstage.
- Wochenarbeitszeit in den Settings festlegbar.
- Feiertags-Integration (deutsche Feiertage).
- ICS-Export/Import für Outlook (inkl. Kategorie "Pause").
- Kartenanzeige der Geofence-Bereiche (Google Maps).

## Push & CI Hinweise

- Remote hinzufügen und pushen (erstmalig):

```bash
git remote add origin https://github.com/sprobst76/VibedTracker.git
git push -u origin main
```

- CI: Es gibt kein konfiguriertes CI-Setup im Repo; bei Bedarf kann ich eine GitHub Actions-Workflow-Datei hinzufügen.
