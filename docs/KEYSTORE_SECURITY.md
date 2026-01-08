# Keystore & Secrets Management

Sichere Verwaltung von Android Keystores und Projekt-Secrets.

---

## Inhaltsverzeichnis

1. [Android App Signing](#android-app-signing)
2. [Password Manager Setup](#password-manager-setup)
   - [Option A: Bitwarden](#option-a-bitwarden-empfohlen)
   - [Option B: Proton Pass](#option-b-proton-pass)
3. [Projekt-Secrets verwalten](#projekt-secrets-verwalten)
4. [Self-Hosting](#self-hosting)
5. [Recovery-Szenarien](#recovery-szenarien)

---

## Android App Signing

### Aktuelle Konfiguration

| Datei | Pfad | In Git? | Beschreibung |
|-------|------|---------|--------------|
| Keystore | `android/app/keys/release.jks` | Nein | Signatur-Schlüssel |
| Credentials | `android/key.properties` | Nein | Passwörter |

### Google Play App Signing

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐
│   Upload Key    │  ──►    │  Google Play    │  ──►    │   Nutzer    │
│ (release.jks)   │   AAB   │  App Signing    │   APK   │  Download   │
└─────────────────┘         └─────────────────┘         └─────────────┘
       DU                      GOOGLE'S KEY                  STORE
```

**Wird automatisch aktiviert** beim ersten AAB-Upload in die Play Console.

**Vorteile:**
- Upload Key verloren → Reset über Google Support
- Key kompromittiert → Google kann neuen Key ausstellen
- Kein Single Point of Failure

---

## Password Manager Setup

### Option A: Bitwarden (Empfohlen)

#### Schritt 1: Account erstellen

1. Öffne https://vault.bitwarden.com/#/register
2. Fülle aus:
   - E-Mail-Adresse
   - Master-Passwort (mind. 12 Zeichen, Groß/Klein/Zahl/Sonderzeichen)
   - Passwort-Hinweis (optional)
3. Klicke "Konto erstellen"
4. Bestätige deine E-Mail

#### Schritt 2: Apps installieren

| Plattform | Download |
|-----------|----------|
| Browser Extension | https://bitwarden.com/download/#downloads-web-browser |
| Desktop (Linux) | `sudo snap install bitwarden` |
| Android | Play Store: "Bitwarden" |
| iOS | App Store: "Bitwarden" |

#### Schritt 3: Ordner-Struktur anlegen

1. Einloggen in Bitwarden (Web oder App)
2. Gehe zu "Ordner" (linke Sidebar)
3. Erstelle Ordner:
   ```
   Development/
   ├── VibedTracker/
   ├── [Weitere Projekte]/
   ```

#### Schritt 4: Keystore speichern

1. Klicke "+ Neuer Eintrag"
2. Typ: "Zugangsdaten"
3. Fülle aus:

   | Feld | Wert |
   |------|------|
   | Name | `VibedTracker - Android Keystore` |
   | Benutzername | `vibedtracker` (Key-Alias) |
   | Passwort | `[Dein Keystore-Passwort]` |
   | URI | `com.vibedtracker.app` |
   | Ordner | `Development/VibedTracker` |

4. Notizen hinzufügen:
   ```
   Android Upload Keystore für VibedTracker

   Key-Alias: vibedtracker
   Key-Algorithmus: RSA 2048
   Gültigkeit: 10000 Tage
   Erstellt: [Datum]

   Dateipfad (lokal): android/app/keys/release.jks
   Google Play App Signing: Aktiviert
   ```

5. Dateianhang hinzufügen:
   - Klicke "Anhänge" (unten)
   - "Datei auswählen" → `release.jks` hochladen
   - Klicke "Speichern"

#### Schritt 5: Weitere Projekt-Secrets speichern

Erstelle weitere Einträge für:

**API Keys & Tokens:**
| Name | Benutzername | Passwort | Notizen |
|------|--------------|----------|---------|
| `VibedTracker - Server API` | - | `[API Key]` | Production Server |
| `VibedTracker - Firebase` | - | `[Key]` | Falls verwendet |

**Server-Zugänge:**
| Name | Benutzername | Passwort | URI |
|------|--------------|----------|-----|
| `VibedTracker - Server SSH` | `deploy` | `[SSH Key als Anhang]` | `ssh://server.example.com` |
| `VibedTracker - Database` | `vibedtracker_prod` | `[DB Passwort]` | `postgresql://...` |

#### Schritt 6: Notfall-Zugang einrichten

1. Gehe zu Einstellungen → "Notfallzugang"
2. Füge eine Vertrauensperson hinzu
3. Wähle Wartezeit (z.B. 7 Tage)
4. Bei Notfall kann diese Person nach Wartezeit zugreifen

#### Schritt 7: 2FA aktivieren

1. Einstellungen → Sicherheit → "Zwei-Faktor-Authentifizierung"
2. Wähle Methode:
   - Authenticator App (empfohlen)
   - E-Mail
   - YubiKey (Premium)
3. Recovery Codes sicher aufbewahren!

---

### Option B: Proton Pass

#### Schritt 1: Proton-Account erstellen

1. Öffne https://account.proton.me/signup
2. Wähle "Proton Free" oder "Proton Unlimited"
3. Erstelle Account mit:
   - Benutzername
   - Passwort
   - Recovery-E-Mail (empfohlen)

#### Schritt 2: Proton Pass aktivieren

1. Gehe zu https://pass.proton.me
2. Melde dich mit deinem Proton-Account an
3. Proton Pass wird automatisch aktiviert

#### Schritt 3: Apps installieren

| Plattform | Download |
|-----------|----------|
| Browser Extension | https://proton.me/pass/download |
| Android | Play Store: "Proton Pass" |
| iOS | App Store: "Proton Pass" |
| Desktop | Über Browser Extension |

#### Schritt 4: Vault erstellen

1. Öffne Proton Pass
2. Klicke auf "+ Neuer Vault"
3. Name: `Development`
4. Farbe/Icon wählen

#### Schritt 5: Keystore speichern

1. Im Vault "Development", klicke "+ Neues Element"
2. Typ: "Login"
3. Fülle aus:

   | Feld | Wert |
   |------|------|
   | Titel | `VibedTracker - Android Keystore` |
   | E-Mail/Benutzername | `vibedtracker` |
   | Passwort | `[Keystore-Passwort]` |
   | Website | `play.google.com/console` |

4. Klicke "Notiz hinzufügen":
   ```
   Android Upload Keystore

   App ID: com.vibedtracker.app
   Key-Alias: vibedtracker
   Erstellt: [Datum]

   WICHTIG: Keystore-Datei separat sichern!
   Lokaler Pfad: android/app/keys/release.jks
   ```

5. **Dateianhänge** (Proton Pass Limitierung):

   Proton Pass unterstützt aktuell **keine Dateianhänge**.

   **Workaround:**
   - Keystore in Proton Drive hochladen
   - Link in den Notizen speichern

   Oder:
   - Separaten verschlüsselten Ordner in Proton Drive anlegen
   - Pfad: `Proton Drive / Development / Keystores / VibedTracker /`

#### Schritt 6: Proton Drive für Dateien nutzen

1. Öffne https://drive.proton.me
2. Erstelle Ordnerstruktur:
   ```
   Development/
   └── Keystores/
       └── VibedTracker/
           ├── release.jks
           └── README.txt
   ```
3. Lade `release.jks` hoch
4. Erstelle `README.txt`:
   ```
   VibedTracker Android Keystore

   Passwort: [Siehe Proton Pass]
   Alias: vibedtracker
   ```

#### Schritt 7: Weitere Secrets

Erstelle für jedes Projekt:

| Titel | Typ | Inhalt |
|-------|-----|--------|
| `VibedTracker - Server` | Login | SSH/API Zugänge |
| `VibedTracker - Database` | Login | DB Credentials |
| `VibedTracker - Google Play` | Login | Console Zugang |

---

## Projekt-Secrets verwalten

### Checkliste pro Projekt

Für jedes Entwicklungsprojekt solltest du sichern:

#### Pflicht (Kritisch)

- [ ] **Android Keystore** (.jks/.keystore)
- [ ] **Keystore-Passwort**
- [ ] **Key-Alias und Key-Passwort**
- [ ] **iOS Signing Certificates** (falls iOS)
- [ ] **Provisioning Profiles** (falls iOS)

#### Wichtig

- [ ] **Server SSH Keys**
- [ ] **Datenbank-Credentials**
- [ ] **API Keys** (Google, Firebase, etc.)
- [ ] **OAuth Client Secrets**
- [ ] **Encryption Keys** (z.B. für User-Daten)

#### Optional aber empfohlen

- [ ] **CI/CD Tokens** (GitHub Actions, etc.)
- [ ] **Domain Registrar Login**
- [ ] **Cloud Provider Credentials** (AWS, GCP, etc.)
- [ ] **Monitoring/Analytics Keys**

### Namenskonvention

Verwende einheitliche Namen:

```
[Projektname] - [Service] - [Umgebung]

Beispiele:
- VibedTracker - Android Keystore
- VibedTracker - Server SSH - Production
- VibedTracker - Database - Staging
- VibedTracker - Firebase - Production
```

### Backup-Strategie

```
┌─────────────────────────────────────────────────────────────┐
│                    BACKUP PYRAMIDE                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│     ┌─────────────────────┐                                │
│     │   Password Manager  │  ← Primär (Bitwarden/Proton)   │
│     │   (Cloud, E2E)      │                                │
│     └──────────┬──────────┘                                │
│                │                                            │
│     ┌──────────▼──────────┐                                │
│     │   Cloud Storage     │  ← Sekundär (Proton Drive)     │
│     │   (verschlüsselt)   │                                │
│     └──────────┬──────────┘                                │
│                │                                            │
│     ┌──────────▼──────────┐                                │
│     │   Lokales Backup    │  ← Tertiär (USB im Safe)       │
│     │   (GPG verschlüss.) │                                │
│     └─────────────────────┘                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Lokales verschlüsseltes Backup erstellen

```bash
# Alle Projekt-Secrets in ein Archiv
cd /pfad/zum/projekt

# Backup erstellen
tar czf - \
  android/app/keys/ \
  android/key.properties \
  .env.production \
  | gpg --symmetric --cipher-algo AES256 \
  > ~/backups/projektname-secrets-$(date +%Y%m%d).tar.gz.gpg

# Backup entschlüsseln
gpg --decrypt projektname-secrets-20240108.tar.gz.gpg | tar xzf -
```

---

## Self-Hosting

### Empfehlung: Nein (für die meisten)

| Risiko | Konsequenz |
|--------|------------|
| Server down | Kein Zugriff auf Passwörter |
| Server gehackt | Alle Secrets kompromittiert |
| Backup vergessen | Datenverlust |
| Wartungsaufwand | Updates, SSL, Monitoring |

**Das Paradoxon:** Du brauchst ein Passwort, um auf deinen Password Manager zuzugreifen.

### Wann Self-Hosting Sinn macht

- Du hast bereits robuste Infrastruktur
- Compliance-Anforderungen (DSGVO, etc.)
- Team/Unternehmen mit eigenem IT-Betrieb
- Du willst 100% Kontrolle

### Self-Hosting: Vaultwarden

Leichtgewichtige Bitwarden-Alternative:

```yaml
# docker-compose.yml
version: '3'

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "https://vault.example.com"
      SIGNUPS_ALLOWED: "false"
      ADMIN_TOKEN: "${ADMIN_TOKEN}"
      SMTP_HOST: "smtp.example.com"
      SMTP_FROM: "vault@example.com"
      SMTP_PORT: "587"
      SMTP_SECURITY: "starttls"
      SMTP_USERNAME: "${SMTP_USER}"
      SMTP_PASSWORD: "${SMTP_PASS}"
    volumes:
      - ./vw-data:/data
    ports:
      - "8080:80"

  # Optional: Automatische Backups
  backup:
    image: bruceforce/vaultwarden-backup
    restart: unless-stopped
    depends_on:
      - vaultwarden
    volumes:
      - ./vw-data:/data:ro
      - ./backups:/backups
    environment:
      BACKUP_DIR: "/backups"
      CRON_TIME: "0 3 * * *"  # Täglich um 3 Uhr
      TIMESTAMP: "true"
      DELETE_AFTER: 30
```

**Sicherheits-Checkliste:**

- [ ] HTTPS mit gültigem Zertifikat (Let's Encrypt)
- [ ] Fail2ban konfiguriert
- [ ] Automatische Backups (täglich, off-site)
- [ ] Regelmäßige Updates
- [ ] Monitoring eingerichtet
- [ ] Admin-Panel deaktiviert oder gesichert
- [ ] SIGNUPS_ALLOWED=false

---

## Recovery-Szenarien

### Szenario 1: Upload Key verloren

**Mit Google Play App Signing:**
1. Play Console → Setup → App-Signatur
2. "Upload-Schlüssel zurücksetzen"
3. Neuen Keystore erstellen:
   ```bash
   keytool -genkey -v \
     -keystore new-upload.jks \
     -keyalg RSA -keysize 2048 \
     -validity 10000 \
     -alias vibedtracker
   ```
4. PEM aus neuem Key exportieren:
   ```bash
   keytool -export -rfc \
     -keystore new-upload.jks \
     -alias vibedtracker \
     -file upload_certificate.pem
   ```
5. In Play Console hochladen
6. Warten auf Google-Bestätigung (kann Tage dauern)

### Szenario 2: Keystore-Passwort vergessen

1. **Prüfe Password Manager** (Bitwarden/Proton)
2. **Prüfe lokale Backups**
3. **Wenn nicht gefunden:**
   - Neuen Upload Key bei Google beantragen (siehe oben)

### Szenario 3: Password Manager nicht erreichbar

**Bitwarden:**
1. Prüfe https://status.bitwarden.com
2. Desktop-App hat lokalen Cache
3. Notfall: Export auf anderem Gerät

**Proton:**
1. Prüfe https://status.proton.me
2. Browser Extension hat lokalen Cache
3. Recovery über Proton Account

### Szenario 4: Master-Passwort vergessen

**Bitwarden:**
- Kein Recovery möglich (Zero-Knowledge)
- Account löschen, neu anfangen
- **Prävention:** Notfallzugang einrichten!

**Proton:**
- Recovery-E-Mail nutzen
- Recovery-Phrase nutzen (falls eingerichtet)

---

## Vergleich: Bitwarden vs Proton Pass

| Feature | Bitwarden | Proton Pass |
|---------|-----------|-------------|
| **Preis (Basis)** | Kostenlos | Kostenlos |
| **Dateianhänge** | Ja (1GB Free, mehr Premium) | Nein (Proton Drive nutzen) |
| **Desktop App** | Ja | Nur Browser Extension |
| **Self-Hosting** | Ja (Vaultwarden) | Nein |
| **Open Source** | Ja | Ja |
| **Notfallzugang** | Ja | Nein |
| **2FA integriert** | Ja (Premium) | Ja |
| **E-Mail-Aliase** | Nein | Ja |
| **Ökosystem** | Standalone | Proton (Mail, Drive, VPN) |
| **Audits** | Regelmäßig, öffentlich | Regelmäßig, öffentlich |

**Empfehlung:**
- **Bitwarden** → Wenn du nur Password Manager brauchst
- **Proton Pass** → Wenn du bereits Proton nutzt (Mail, Drive, VPN)

---

## Quick Reference

### Neues Projekt einrichten

```bash
# 1. Keystore erstellen
keytool -genkey -v \
  -keystore android/app/keys/release.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias projektname

# 2. key.properties erstellen
cat > android/key.properties << EOF
storePassword=DEIN_PASSWORT
keyPassword=DEIN_PASSWORT
keyAlias=projektname
storeFile=keys/release.jks
EOF

# 3. .gitignore aktualisieren
echo "android/key.properties" >> .gitignore
echo "android/app/keys/" >> .gitignore

# 4. In Password Manager speichern
# → Siehe Anleitung oben

# 5. Lokales Backup erstellen
tar czf - android/app/keys/ android/key.properties | \
  gpg -c > ~/backups/projektname-keys.tar.gz.gpg
```

### Checkliste vor Release

- [ ] Keystore in Password Manager gespeichert
- [ ] Keystore-Passwort in Password Manager gespeichert
- [ ] Lokales Backup erstellt
- [ ] Google Play App Signing aktiviert
- [ ] 2FA auf Password Manager aktiviert
- [ ] Notfallzugang eingerichtet (Bitwarden)
