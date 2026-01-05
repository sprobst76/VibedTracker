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
