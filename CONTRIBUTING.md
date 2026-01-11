# Contributing to VibedTracker

Vielen Dank für dein Interesse an VibedTracker! Hier findest du Informationen, wie du zum Projekt beitragen kannst.

## Entwicklungsumgebung einrichten

### Voraussetzungen

- Flutter SDK (stable channel)
- Dart SDK >= 2.18.0
- Android Studio oder VS Code mit Flutter-Extension
- Git

### Setup

```bash
# Repository klonen
git clone https://github.com/sprobst76/VibedTracker.git
cd VibedTracker

# Dependencies installieren
flutter pub get

# Hive-Adapter generieren
flutter pub run build_runner build --delete-conflicting-outputs

# App starten
flutter run
```

## Wie du beitragen kannst

### Bugs melden

1. Prüfe zuerst, ob der Bug bereits gemeldet wurde
2. Erstelle ein neues Issue mit dem **Bug Report** Template
3. Beschreibe das Problem so detailliert wie möglich
4. Füge Screenshots oder Logs hinzu, wenn möglich

### Features vorschlagen

1. Prüfe zuerst, ob das Feature bereits vorgeschlagen wurde
2. Erstelle ein neues Issue mit dem **Feature Request** Template
3. Beschreibe das gewünschte Verhalten und den Nutzen

### Code beitragen

1. Forke das Repository
2. Erstelle einen Feature-Branch: `git checkout -b feature/mein-feature`
3. Entwickle und teste deine Änderungen
4. Committe mit aussagekräftigen Messages: `git commit -m "feat: beschreibung"`
5. Pushe zum Fork: `git push origin feature/mein-feature`
6. Erstelle einen Pull Request

## Code-Standards

### Commit-Messages

Wir verwenden [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - Neue Features
- `fix:` - Bugfixes
- `docs:` - Dokumentationsänderungen
- `style:` - Formatierung (kein Code-Change)
- `refactor:` - Code-Umstrukturierung
- `test:` - Tests hinzufügen/ändern
- `chore:` - Build-Prozess, Dependencies

### Code-Stil

- Führe `flutter analyze` vor dem Commit aus
- Keine Warnungen oder Fehler
- Formatiere mit `dart format .`

### Tests

- Neue Features sollten Tests haben
- Führe `flutter test` vor dem Commit aus
- Alle Tests müssen bestehen

## Pull Request Prozess

1. Aktualisiere die CHANGELOG.md mit deinen Änderungen
2. Stelle sicher, dass CI-Checks bestehen
3. Ein Maintainer wird deinen PR reviewen
4. Nach Approval wird gemergt

## Fragen?

Bei Fragen erstelle gerne ein Issue oder kontaktiere uns direkt.

---

Danke für deinen Beitrag!
