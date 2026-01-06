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
- Status: Offen, erste Fixes (visuelles Feedback, Größe) haben nicht geholfen
- Datei: `lib/screens/lock_screen.dart`

---

## Feature-Ideen (Backlog)

### 1. Excel Export (Monat)
- Monatlichen Arbeitszeitbericht als Excel-Datei exportieren
- Spalten: Datum, Start, Ende, Pausen, Arbeitszeit, Projekt, etc.

### 2. Geofence-Benachrichtigungen mit Einspruch
- Benachrichtigung anzeigen wenn automatisch gestartet/gestoppt wird
- "Einspruch"-Button: Aktion rückgängig machen oder anpassen
- Wichtig für Transparenz und Kontrolle bei automatischer Erfassung

### 3. Arbeitszeitperioden: Manueller Wert statt Schieber
- Der große Schieber wird selten verändert
- Stattdessen: Perioden mit Komma-Wert direkt eingeben (z.B. "38,5")
- Bessere Präzision und weniger versehentliche Änderungen

### 4. Prioritäten bei Abwesenheiten
- Feiertage überschreiben Urlaub (kein Urlaubstag verbraucht)
- Krankheit überschreibt Urlaub (Urlaubstag bleibt erhalten)
- Kalenderanzeigen entsprechend anpassen/klarstellen
- Logik: Feiertag > Krankheit > Urlaub

### 5. Arbeitszeit gemäß Arbeitsgesetzen
- Monats- und Wochenarbeitszeit korrekt berechnen
- Klare Verrechnung von Urlaub, Feiertagen, Krankheit mit Sollzeit
- Dokumentieren wie die Berechnung funktioniert

### 6. Urlaubstageverwaltung
- Jahresurlaub erfassen (meist 30 Tage)
- Verbrauchte und verbleibende Urlaubstage anzeigen
- Übertrag ins nächste Jahr (optional)

### 7. Heiligabend & Silvester
- Klarstellen wie 24.12. und 31.12. im Arbeitszeitkonto gelten
- Oft halbe Arbeitstage oder frei nach Tarif/Vertrag
- Einstellbar machen oder dokumentieren

Datum: 2026-01-06
