# Google Play Store Automatisches Deployment

Diese Anleitung beschreibt, wie du automatische Releases zu Google Play via GitHub Actions einrichtest.

## Übersicht

Nach dem Setup kannst du neue Versionen so veröffentlichen:

```bash
# 1. Version in pubspec.yaml erhöhen
# version: 1.0.1+2

# 2. Committen und taggen
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.1"
git tag v1.0.1
git push origin main --tags

# → GitHub Action baut automatisch und lädt zu Play Store hoch
```

---

## Schritt 1: Google Cloud Service Account erstellen

### 1.1 Google Cloud Console öffnen

1. Gehe zu: https://console.cloud.google.com/
2. Melde dich mit dem Google-Konto an, das auch für Google Play Console verwendet wird
3. Erstelle ein neues Projekt oder wähle ein bestehendes:
   - Klicke oben auf das Projekt-Dropdown
   - "Neues Projekt" → Name: `VibedTracker CI/CD`

### 1.2 Google Play Developer API aktivieren

1. Im linken Menü: **APIs & Dienste** → **Bibliothek**
2. Suche nach: `Google Play Android Developer API`
3. Klicke auf das Ergebnis und dann **Aktivieren**

### 1.3 Service Account erstellen

1. Im linken Menü: **APIs & Dienste** → **Anmeldedaten**
2. Klicke **+ Anmeldedaten erstellen** → **Dienstkonto**
3. Fülle aus:
   - **Name**: `github-play-deploy`
   - **Dienstkonto-ID**: wird automatisch generiert
   - **Beschreibung**: `GitHub Actions Play Store Deployment`
4. Klicke **Erstellen und fortfahren**
5. Bei "Rolle" kannst du überspringen (wird in Play Console konfiguriert)
6. Klicke **Fertig**

### 1.4 JSON-Schlüssel herunterladen

1. Klicke auf den erstellten Service Account (`github-play-deploy@...`)
2. Tab **Schlüssel** → **Schlüssel hinzufügen** → **Neuen Schlüssel erstellen**
3. Format: **JSON**
4. Klicke **Erstellen**
5. Die JSON-Datei wird automatisch heruntergeladen
6. **WICHTIG**: Speichere diese Datei sicher! Du brauchst sie für GitHub Secrets.

---

## Schritt 2: Zugriff in Google Play Console gewähren

### 2.1 Play Console öffnen

1. Gehe zu: https://play.google.com/console
2. Wähle dein Entwicklerkonto

### 2.2 API-Zugriff einrichten

1. Im linken Menü: **Einstellungen** (Zahnrad) → **API-Zugriff**
2. Falls noch nicht geschehen: Verknüpfe das Google Cloud-Projekt
   - Klicke **Projekt verknüpfen**
   - Wähle das Projekt `VibedTracker CI/CD`
3. Unter **Dienstkonten** sollte dein Service Account erscheinen
4. Klicke auf **Zugriff verwalten** neben dem Service Account

### 2.3 Berechtigungen setzen

1. Unter **App-Berechtigungen**:
   - Klicke **App hinzufügen**
   - Wähle **VibedTracker** (deine App)

2. Setze folgende Berechtigungen:
   - ✅ **Releases auf Produktions-, Test- und interne Test-Tracks verwalten**
   - ✅ **Release auf interne Test-Tracks beschränken** (optional, für mehr Sicherheit)

3. Unter **Kontoberechtigungen** (optional):
   - Keine zusätzlichen Berechtigungen nötig

4. Klicke **Nutzer einladen** / **Speichern**

---

## Schritt 3: GitHub Secrets einrichten

### 3.1 Keystore als Base64 kodieren

```bash
# Im VibedTracker-Verzeichnis:
base64 -w 0 android/app/keys/release.jks > keystore_base64.txt
cat keystore_base64.txt
# Kopiere den Output
```

### 3.2 Secrets in GitHub hinzufügen

1. Gehe zu: https://github.com/sprobst76/VibedTracker/settings/secrets/actions
2. Klicke **New repository secret** für jedes:

| Secret Name | Wert |
|-------------|------|
| `KEYSTORE_BASE64` | Der Base64-String aus Schritt 3.1 |
| `KEYSTORE_PASSWORD` | `Trackerwurst1!` |
| `KEY_PASSWORD` | `Trackerwurst1!` |
| `KEY_ALIAS` | `vibedtracker` |
| `PLAY_STORE_JSON` | Der gesamte Inhalt der JSON-Datei aus Schritt 1.4 |

### 3.3 Repository Variable setzen

1. Gehe zu: https://github.com/sprobst76/VibedTracker/settings/variables/actions
2. Klicke **New repository variable**:

| Variable Name | Wert |
|---------------|------|
| `ENABLE_PLAY_STORE_DEPLOY` | `true` |

---

## Schritt 4: Testen

### 4.1 Ersten Release erstellen

```bash
# Aktuelle Version prüfen
grep "version:" pubspec.yaml

# Version erhöhen (z.B. von 1.0.0+1 auf 1.0.1+2)
# Editiere pubspec.yaml

# Committen und taggen
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.1"
git tag v1.0.1
git push origin main --tags
```

### 4.2 Build verfolgen

1. Gehe zu: https://github.com/sprobst76/VibedTracker/actions
2. Klicke auf den laufenden "Release" Workflow
3. Verfolge die einzelnen Jobs:
   - **Build Android**: Baut APK und AAB
   - **Deploy to Google Play**: Lädt zu Internal Testing hoch
   - **Create GitHub Release**: Erstellt GitHub Release mit Downloads

### 4.3 In Play Console prüfen

1. Gehe zu Play Console → VibedTracker → **Release** → **Interner Test**
2. Du solltest die neue Version sehen

---

## Fehlerbehebung

### "The caller does not have permission"

- Prüfe, ob der Service Account in Play Console die richtigen Berechtigungen hat
- Warte 24h nach Erstellung des Service Accounts (Google-Latenz)

### "Package not found"

- Du musst zuerst **manuell** eine Version hochladen, bevor die API funktioniert
- Gehe zu Play Console und lade einmal manuell ein AAB hoch

### "Invalid request - Package name not found"

- Prüfe, ob `packageName` im Workflow mit der `applicationId` in `build.gradle.kts` übereinstimmt

### Build schlägt fehl wegen Keystore

- Prüfe, ob `KEYSTORE_BASE64` korrekt kodiert ist (keine Zeilenumbrüche)
- Prüfe, ob Passwörter in Secrets korrekt sind

---

## Tracks

Du kannst den Track im Workflow ändern:

| Track | Beschreibung |
|-------|--------------|
| `internal` | Interner Test (Standard) |
| `alpha` | Geschlossener Test |
| `beta` | Offener Test |
| `production` | Produktion (Live) |

Ändere in `.github/workflows/release.yml`:
```yaml
track: internal  # → alpha, beta, oder production
```

---

## Sicherheitshinweise

1. **JSON-Schlüssel niemals committen!** Nur als GitHub Secret
2. **Keystore sicher aufbewahren** (siehe docs/KEYSTORE_SECURITY.md)
3. **Minimal notwendige Berechtigungen** für Service Account verwenden
4. **Regelmäßig Schlüssel rotieren** (alle 6-12 Monate)
