# Todo (Ideen / Aufgaben)

## CI / GitHub Actions (Idee)

- Ziel: Automatische Prüfungen bei `push` und `pull_request`.
- Vorschlag: einfacher Workflow, der ausführt:
  - `flutter pub get`
  - `flutter analyze`
  - `flutter test`
  - optional: `flutter build apk` (nur für Release-Checks)
- Plattform: Linux-Runner ist ausreichend für `analyze` und `test`.
- Extras: Pub-Cache-Caching, Build-Matrix (z. B. verschiedene Flutter-Kanäle), Cache für `~/.pub-cache`.
- Nutzen: frühzeitiges Erkennen von Analyse-Warnungen, test-Ausfällen und fehlenden Abhängigkeiten.

Datum: 2026-01-05

---

## Bekannte Bugs

### Biometrie-Button auf Lock Screen
- Problem: Button funktioniert nicht richtig, lässt sich nicht korrekt nutzen
- Status: Fix angewendet (USE_BIOMETRIC Permission, FlutterFragmentActivity, ElevatedButton)
- Datei: `lib/screens/lock_screen.dart`, `AndroidManifest.xml`, `MainActivity.kt`
- Muss noch getestet werden

---

## Erledigte Features

### ✅ 1. Excel Export (Monat) (2026-01-06)
- Monatlichen Arbeitszeitbericht als Excel-Datei exportieren
- Spalten: Datum, Wochentag, Start, Ende, Brutto, Pausen, Netto, Modus, Projekt, Notizen
- Zusammenfassung mit Soll/Ist-Vergleich
- Export über Download-Button im Monat-Tab
- Dateien: `lib/services/export_service.dart`, `lib/screens/report_screen.dart`

### ✅ 2. Geofence-Benachrichtigungen mit Einspruch (2026-01-06)
- Benachrichtigung bei automatischem Start/Stop
- "Einspruch"-Button zum Rückgängigmachen
- Datei: `lib/services/geofence_notification_service.dart`

### ✅ 3. Arbeitszeitperioden: Manueller Wert statt Schieber (2026-01-06)
- Slider durch Textfeld ersetzt (z.B. "38,5")
- In Settings und Perioden-Dialog
- Dateien: `lib/screens/settings_screen.dart`, `lib/screens/weekly_hours_screen.dart`

### ✅ 4. Prioritäten bei Abwesenheiten (2026-01-06)
- Feiertag überschreibt Urlaub visuell im Kalender
- Krankheit/Kind krank hat Priorität über Urlaub
- Hinweis "Feiertag – kein Urlaubstag wird verbraucht"
- Dateien: `lib/models/vacation.dart`, `lib/screens/calendar_overview_screen.dart`, `lib/screens/vacation_screen.dart`

### ✅ 6. Urlaubstageverwaltung (2026-01-06)
- Jahresurlaub in Settings konfigurierbar (Standard: 30 Tage)
- Übertragsoption für Resturlaub ins nächste Jahr
- Urlaubsstatistik-Karte im Abwesenheits-Screen (Anspruch, Genommen, Verbleibend)
- Übertrag pro Jahr manuell editierbar
- Dateien: `lib/models/vacation_quota.dart`, `lib/providers.dart`, `lib/screens/vacation_screen.dart`, `lib/screens/settings_screen.dart`

### ✅ 7. Heiligabend & Silvester (2026-01-06)
- Einstellbar in Settings: Frei / Halber Tag / Voller Tag
- Beeinflusst Soll-Arbeitszeit an 24.12. und 31.12.
- Standard: Halber Tag (0.5)
- Integration in Berichte (Wochen-, Monats-, Jahresansicht)
- Dateien: `lib/models/settings.dart`, `lib/providers.dart`, `lib/screens/settings_screen.dart`, `lib/screens/report_screen.dart`

### ✅ 5. Arbeitszeit gemäß Arbeitsgesetzen (2026-01-06)
- Info-Button im Bericht-Screen mit detaillierter Dokumentation
- Erklärt Soll-Arbeitszeit-Berechnung (Wochenstunden / Arbeitstage)
- Dokumentiert was als Arbeitstag zählt (kein Wochenende, Feiertag, bezahlte Abwesenheit)
- Bezahlte Abwesenheiten (Urlaub, Krankheit, etc.) reduzieren Soll-Zeit
- Unbezahlte Abwesenheit reduziert Soll-Zeit NICHT
- Heiligabend/Silvester-Faktor wird berücksichtigt
- Dateien: `lib/screens/report_screen.dart`

---

## Feature-Ideen (Backlog)

(Keine offenen Features)

Datum: 2026-01-06
