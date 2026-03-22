# Changelog

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt folgt [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

### Geplant
- Cloud-Backup (Google Drive / iCloud)
- Mehrsprachigkeit (i18n / l10n)
- iOS Geofence-Parität

---

## [0.1.0-beta.69] - 2026-03-22

### Tests
- **Monatsabschluss** (31 Tests): `Settings.monthKey`, `isMonthLocked`, `lockMonth`/`unlockMonth` inkl. Idempotenz, kombinierte Sequenzen, Schaltjahr, Jahreswechsel
- **PDF-Export + Stundensatz** (35 Tests): PDF-Magic-Bytes, Netto-Berechnung mit/ohne Pausen, Eintrags-Filterung, Projekt-Referenzen, Saldo-Szenarien, Grenzwerte

---

## [0.1.0-beta.68] - 2026-03-22

### Hinzugefügt
- **PDF-Arbeitszeitnachweis**: Monatlicher Nachweis als A4-PDF (Tabelle: Datum/Beginn/Ende/Pause/Netto/Projekt/Notizen, Soll/Ist/Saldo-Übersicht, Unterschriftenfelder). Export via System-Sharesheet (Druck, Mail, …). Report-Screen Monat-Tab: Download-Icon öffnet Popup "Excel / PDF".
- **Stundensatz pro Projekt**: Neues Feld `hourlyRate (€/h)` im Projekt-Dialog (Anlegen + Bearbeiten). Report → Projekte-Tab zeigt `Xh × Y€/h = Z€` pro Projekt und Gesamtsumme "Abrechenbar" in der Summary-Card.

---

## [0.1.0-beta.67] - 2026-03-22

### Hinzugefügt
- **Monatsabschluss**: Monate im Report-Screen (Monat-Tab) abschließen und wieder entsperren. Gesperrte Monate: nicht editierbar/löschbar in History und EntryEdit (oranges Banner, gesperrte Buttons), 🔒-Icon auf Gruppen-Headern in der History. Bulk-Delete überspringt gesperrte Einträge mit Hinweis. Persistenz als `List<String>` in Settings (HiveField 31), Backup-kompatibel.

---

## [0.1.0-beta.66] - 2026-03-22

### Behoben
- **Ongoing Notification Chronometer**: Ankerpunkt `when = entry.start + completedPauseDuration` — native Android-Chronometer zeigt korrekte Netto-Arbeitszeit (Pausen ausgeschlossen) live ohne Flutter-Timer. Während Pause: statischer Pause-Start-Timestamp. Body-Text-Refresh jede Minute für alle Zustände.

---

## [0.1.0-beta.65] - 2026-03-21

### Hinzugefügt
- **PC-Präsenzerkennung**: TCP-Probe auf konfigurierbaren Host/Port erkennt ob der Arbeits-PC im Netzwerk aktiv ist. Periodischer Watcher während laufender Session. SnackBar-Aktionen "Pause starten/beenden". Port-Presets (SMB 445, RDP 3389, VNC 5900, SSH 22). Test-Button in Einstellungen. Energieverbrauch: ~1ms TCP-Handshake pro Prüfung.

---

## [0.1.0-beta.64] - 2026-03-20

### Hinzugefügt
- **BSSID-basierte Raumerkennung**: Geofence-Zonen können zusätzlich zum SSID auch einen BSSID (MAC-Adresse des Access Points) zugewiesen bekommen. "Aktuelles Netz anzeigen"-Button im Zonen-Dialog lädt SSID + BSSID live und bietet "Übernehmen"-Buttons. Matching-Priorität: BSSID > SSID.

---

## [0.1.0-beta.63] - 2026-03-20

### Hinzugefügt
- **WiFi-SSID-Zonen-Erkennung**: Geofence-Zonen können einem WiFi-SSID zugeordnet werden. Event-driven via `connectivity_plus`-Stream (near-zero Energieverbrauch). Bei ENTER/EXIT gleicher Verarbeitungspfad wie GPS-Geofencing (Re-Entry-Merge, WorkMode, Notifications).

---

## [0.1.0-beta.62] - 2026-03-19

### Hinzugefügt
- **Swipe-to-Delete + Bulk-Selektion** in der History: Einträge einzeln via Swipe löschen (mit Bestätigung) oder per Long-Press in Bulk-Selektion wechseln und mehrere gleichzeitig löschen.
- **Automatische Pausenerkennung**: Wenn die App X Minuten im Hintergrund war (konfigurierbar, Standard 15 min) und eine Session lief, wird beim Wiederkehren ein Pause-Dialog angeboten.

---

## [0.1.0-beta.61] - 2026-03-18

### Hinzugefügt
- **Überstunden-Warnungen**: Push-Notifications wenn das Überstundenkonto konfigurierbare Schwellenwerte über- oder unterschreitet (Standard: +40h / -8h). Zone-basiert (nur bei Zonenübergang, kein Spam).

---

## [0.1.0-beta.35] - 2026-01-22

### Hinzugefügt
- **Einträge zusammenführen**: Neuer Screen zum Mergen fragmentierter Arbeitszeiten
  - Erkennt automatisch zusammenführbare Einträge (gleicher Tag, gleicher Modus, max. 5 min Lücke)
  - Zeigt Vorschau der Zusammenführung mit Zeitspannen
  - Lücken zwischen Einträgen werden als Pausen erfasst
  - Zugang über Einstellungen → Daten & Backup

---

## [0.1.0-beta.34] - 2026-01-22

### Hinzugefügt
- **Hilfe-Dialog im Geofence Debug**: Erklärt häufige Probleme und Lösungen
  - Warum Arbeitszeit nicht automatisch erfasst wird
  - Bedeutung der Akkuoptimierung
  - Bekanntes Package-Problem dokumentiert
  - Debug-Informationen erklärt

### Dokumentation
- Bug Report für geofence_foreground_service Package erstellt
- Alternativen-Analyse dokumentiert (native_geofence, flutter_background_geolocation)

---

## [0.1.0-beta.33] - 2026-01-22

### Hinzugefügt
- **Akkuoptimierung-Check**: Diagnose und Einstellungen im Geofence Debug Screen
  - Zeigt ob Akkuoptimierung deaktiviert ist (erforderlich für zuverlässiges Geofencing)
  - Button zum direkten Öffnen der Android-Einstellungen
  - Erklärt warum der Geofence-Service von Android gekillt werden kann

### Bekanntes Problem (extern)
- **Geofence Service Crash**: Bug im `geofence_foreground_service` Package
  - Wenn Android den Service wegen Speicherdruck killt, crasht er beim Neustart
  - Workaround: Akkuoptimierung für VibedTracker deaktivieren
  - Issue wurde an Package-Maintainer gemeldet

---

## [0.1.0-beta.32] - 2026-01-19

### Hinzugefügt
- **Sofortige Notification bei Geofence-Events**: Push-Benachrichtigung auch bei geschlossener App
  - "▶️ Arbeitszeit automatisch gestartet" beim Betreten der Zone
  - "⏹️ Arbeitszeit automatisch gestoppt" beim Verlassen der Zone
  - Erscheint sofort in der Statusleiste, auch wenn App nicht geöffnet ist
  - Keine Notification bei ignorierten Events (Bounce-Protection)

---

## [0.1.0-beta.31] - 2026-01-19

### Behoben
- **Geofence-Status wird nicht angezeigt**: Home Screen zeigt jetzt immer Zone-Status
  - Auto-Refresh alle 10 Sekunden für Geofence-Status und laufende Arbeitszeit
  - Robustere Initialisierung - einzelne Service-Fehler blockieren nicht die UI
  - Status wird immer geladen, auch wenn andere Services fehlschlagen
  - UI erkennt automatisch wenn Arbeitszeit im Hintergrund gestartet wurde

---

## [0.1.0-beta.30] - 2026-01-19

### Behoben
- **Zerstückelte Einträge bei Geofence**: Bounce-Protection hinzugefügt
  - EXIT→ENTER oder ENTER→EXIT Events innerhalb von 5 Minuten werden ignoriert
  - Verhindert fragmentierte Einträge bei GPS-Fluktuation an der Zonengrenze

---

## [0.1.0-beta.29] - 2026-01-15

### Behoben
- **Einträge werden nicht angezeigt**: Type Error bei workModeIndex behoben
  - Hive-Adapter kann jetzt String und Int für workModeIndex verarbeiten
  - Fehler "Type string is not a subtype of type 'int'" behoben

---

## [0.1.0-beta.28] - 2026-01-14

### Behoben
- **Geofence Service nicht gefunden**: Kritischer Fix für automatische Zeiterfassung
  - Service-Deklaration in AndroidManifest.xml hinzugefügt
  - ProGuard-Regel hinzugefügt um Obfuscation des Services zu verhindern
  - Fehler "Unable to start service R0.d not found" behoben

---

## [0.1.0-beta.27] - 2026-01-13

### Hinzugefügt
- **Statusleisten-Anzeige**: Persistente Notification in der Android-Statusleiste
  - Zeigt "▶️ Arbeitszeit läuft" mit Netto-Arbeitszeit und Startzeit
  - Zeigt "⏸️ Pause" mit Pausendauer bei aktiver Pause
  - Aktualisiert sich automatisch alle 30 Sekunden
  - Kann nicht weggewischt werden (ongoing notification)
  - Verschwindet automatisch beim Stoppen der Arbeitszeit

---

## [0.1.0-beta.26] - 2026-01-12

### Verbessert
- **Geofence Debug Screen**: Erweiterte Diagnose-Funktionen
  - Neuer "Events jetzt verarbeiten" Button (Force Sync)
  - Arbeitszeit-Status Anzeige (läuft/gestoppt)
  - Laufzeit-Anzeige bei aktiver Arbeitszeit
  - Letzter Sync-Ergebnis Anzeige
  - Test-Events nutzen jetzt echte Zone-IDs
  - Bessere Hinweise warum Events nicht verarbeitet werden

---

## [0.1.0-beta.25] - 2026-01-12

### Hinzugefügt
- **Geofence Debug Screen**: Umfangreicher Diagnose-Bildschirm für GPS/Geofencing
  - Berechtigungsstatus (Location, Notifications, etc.)
  - Aktuelle GPS-Position mit Genauigkeit
  - Konfigurierte Zonen mit Entfernungsberechnung
  - Event-Queue Status und Historie
  - Debug-Log mit Export-Funktion
  - Test-Aktionen (ENTER/EXIT Events simulieren)
- Link zum Debug-Screen in Einstellungen → Arbeitsorte

---

## [0.1.0-beta.24] - 2026-01-12

### Behoben
- **Geofence funktioniert nicht**: Fehlende Android-Berechtigungen im Manifest hinzugefügt
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`
  - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`
  - `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`

### Hinzugefügt
- GitHub Community-Dateien: LICENSE (MIT), CONTRIBUTING.md, CODE_OF_CONDUCT.md, Issue-Templates

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
