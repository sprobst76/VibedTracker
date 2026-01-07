# Changelog

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt folgt [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

### Geplant
- Flutter CloudSyncService für App-Integration
- CryptoService für E2E-Verschlüsselung
- GitHub Actions für automatisches Server-Deployment

---

## [Server 1.0.0] - 2026-01-07

### Hinzugefügt
- **Go REST API** für Cloud-Sync
  - Auth: Register, Login, JWT + Refresh Token
  - Sync: Push/Pull verschlüsselter Daten (Zero-Knowledge)
  - Devices: Geräteverwaltung
  - Admin: User-Freischaltung, Sperren, Löschen
- **Admin Dashboard** (HTML/JS)
  - User-Liste mit Status (ausstehend, freigeschalten, gesperrt)
  - Statistiken (User, Geräte, Sync-Items)
  - Ein-Klick Freischaltung/Sperrung
- **Docker Deployment**
  - `docker-compose.yml` für Development
  - `docker-compose.prod.yml` für Traefik/HTTPS
  - `deploy.sh` Script für einfaches Deployment
- **PostgreSQL** Datenbank mit Migrationen
- **Traefik-Integration** für automatisches HTTPS

---

## [0.1.0-beta.12] - 2026-01-07

### Hinzugefügt
- **Backup-System**: Export/Import aller Daten als ZIP-Datei
  - Enthält: Einträge, Urlaub, Kontingente, Projekte, Perioden, Zonen, Settings
  - Teilen über Share-Dialog
- **Urlaubsanspruch pro Jahr**: Dedizierter Screen zur Verwaltung
  - Nur 3 Jahre anzeigen (Vorjahr, aktuell, nächstes)
  - Manuell genommene Tage für Migration aus anderen Systemen
- Navigation zu Urlaubsanspruch aus Einstellungen

### Geändert
- Urlaubsanspruch-Anzeige verbessert (Eingetragen vs. Manuell)

---

## [0.1.0-beta.11] - 2026-01-07

### Behoben
- CI Release-Workflow Permissions (workflow-level `contents: write`)
- Doppelte Release-Erstellung durch CI entfernt

---

## [0.1.0-beta.9] - 2026-01-07

### Hinzugefügt
- **VibedTracker App-Icon**: Neues adaptives Icon
  - Lila-blauer Gradient-Hintergrund
  - Weißes Design: Uhr + V-Checkmark + Vibrations-Wellen
- App-Name geändert von "time_tracker" zu "VibedTracker"

---

## [0.1.0-beta.8] - 2026-01-07

### Hinzugefügt
- **Urlaubsanspruch pro Jahr**: Individueller Anspruch statt globalem Wert
  - `VacationQuotaScreen` für Jahr-für-Jahr-Verwaltung
  - Settings zeigt nur noch Resturlaub (read-only)
- **Arbeitszeit-Perioden**: Automatisches Beenden alter Perioden
  - Neue Periode beendet automatisch vorherige unbefristete
- ProGuard-Regeln für flutter_local_notifications (R8 TypeToken Fix)

### Geändert
- Wöchentliche Arbeitszeit nur noch über Perioden einstellbar
- Settings-Screen zeigt Badge mit aktueller Stundenzahl

---

## [0.1.0-beta.7] - 2026-01-06

### Hinzugefügt
- GitHub Actions CI/CD Pipeline
  - `flutter_ci.yml`: Analyze & Test bei Push/PR
  - `release.yml`: Automatischer Release-Build bei Tags

---

## [0.1.0-beta.6] - 2026-01-06

### Hinzugefügt
- **Excel-Export**: Monatlicher Arbeitszeitbericht als .xlsx
  - Spalten: Datum, Wochentag, Start, Ende, Brutto, Pausen, Netto, Modus, Projekt, Notizen
  - Zusammenfassung mit Soll/Ist-Vergleich
- **Geofence-Benachrichtigungen**: Einspruch-Button zum Rückgängigmachen
- **Abwesenheits-Prioritäten**: Feiertag überschreibt Urlaub visuell
- **Heiligabend & Silvester**: Konfigurierbar als frei/halber Tag/voller Tag
- **Urlaubsverwaltung**:
  - Jahresanspruch konfigurierbar
  - Resturlaub-Übertrag optional
  - Statistik-Karte im Abwesenheits-Screen

### Geändert
- Arbeitszeit-Eingabe: Textfeld statt Slider (z.B. "38,5")

---

## [0.1.0-beta.5] - 2026-01-05

### Hinzugefügt
- **App-Sperre**: PIN und Biometrie (Fingerabdruck/Face ID)
- **Security Settings Screen**: Konfiguration der Sicherheitsoptionen
- **Auto-Lock**: Nach Inaktivität oder App-Wechsel

### Behoben
- Biometrie-Button auf Lock Screen

---

## [0.1.0-beta.4] - 2026-01-04

### Hinzugefügt
- **Google Kalender Integration**: Termine anzeigen (nur lesen)
- **Erinnerungen**: Tägliche Benachrichtigung für fehlende Einträge
- **Bundesland-Auswahl**: Regionale Feiertage

---

## [0.1.0-beta.3] - 2026-01-03

### Hinzugefügt
- **Arbeitsmodi**: Normal, Deep Work, Meeting, Support, Administration
- **Projekte**: Zuordnung von Einträgen zu Projekten
- **Dark Mode**: System/Hell/Dunkel wählbar

---

## [0.1.0-beta.2] - 2026-01-02

### Hinzugefügt
- **Wochenberichte**: Soll/Ist-Vergleich mit Überstunden
- **Monatsübersicht**: Aggregierte Statistiken
- **Kalenderansicht**: Alle Einträge im Überblick

---

## [0.1.0-beta.1] - 2026-01-01

### Hinzugefügt
- **Initiale Version**
- Geofence-basierte automatische Zeiterfassung
- Manuelle Arbeitszeiteinträge (Start/Stop/Pausen)
- Urlaubsverwaltung (Urlaubstage eintragen)
- Feiertage (deutsche Feiertage via API)
- Hive-Datenbank für lokale Speicherung
- Grundlegende Einstellungen

---

[Unreleased]: https://github.com/sprobst76/VibedTracker/compare/v0.1.0-beta.12...HEAD
[0.1.0-beta.12]: https://github.com/sprobst76/VibedTracker/compare/v0.1.0-beta.11...v0.1.0-beta.12
[0.1.0-beta.11]: https://github.com/sprobst76/VibedTracker/compare/v0.1.0-beta.9...v0.1.0-beta.11
[0.1.0-beta.9]: https://github.com/sprobst76/VibedTracker/compare/v0.1.0-beta.8...v0.1.0-beta.9
[0.1.0-beta.8]: https://github.com/sprobst76/VibedTracker/releases/tag/v0.1.0-beta.8
