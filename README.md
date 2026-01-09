# VibedTracker

Zeiterfassung mit Geofence, Urlaub, Feiertagen & Cloud-Sync.

**Zero-Knowledge verschlüsselt** - Nur du kannst deine Daten lesen.

---

## Highlights

| Feature | Beschreibung |
|---------|--------------|
| **Automatische Erfassung** | GPS-Geofencing stempelt automatisch ein/aus |
| **Zero-Knowledge** | Ende-zu-Ende-Verschlüsselung (AES-256-GCM) |
| **Offline-First** | Funktioniert ohne Internet |
| **Cloud-Sync** | Verschlüsselte Synchronisation zwischen Geräten |
| **Self-Hosting** | Volle Kontrolle über deine Daten |
| **Passkey-Support** | Passwordlose Anmeldung (Touch ID, Face ID, Windows Hello) |

---

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

### Sicherheit
- **Zero-Knowledge Verschlüsselung** - Server kann Daten nicht lesen
- **Passphrase-geschützt** - Starke Verschlüsselung mit AES-256-GCM
- **2FA** - Zwei-Faktor-Authentifizierung mit TOTP
- **Passkeys** - Passwordlose Anmeldung (optional)
- **App-Sperre** - PIN oder Biometrie
- **Recovery Codes** - Passphrase-Wiederherstellung

### Weitere Features
- **Dark Mode** (System/Hell/Dunkel)
- **Web-Interface** - Zugriff vom Browser
- **Google Kalender** Integration (nur lesen)
- **Erinnerungen** für fehlende Einträge
- **Backup & Restore** als ZIP-Datei

---

## Sicherheitsarchitektur

VibedTracker verwendet **Zero-Knowledge Verschlüsselung**:

```
┌─────────────────┐         ┌─────────────────┐
│     CLIENT      │         │     SERVER      │
│  (App / Web)    │         │                 │
├─────────────────┤         ├─────────────────┤
│                 │         │                 │
│  Passphrase ────┼─PBKDF2─►│  Salt (public)  │
│       │         │         │                 │
│       ▼         │         │                 │
│  AES-256 Key    │         │  ✗ Kein Key     │
│       │         │         │                 │
│       ▼         │         │                 │
│  Klartext ──────┼─────────►  Encrypted Blob │
│       │         │         │  (unlesbar)     │
│       ▼         │         │                 │
│  Entschlüsselt  │◄────────┼─ Encrypted Blob │
│                 │         │                 │
└─────────────────┘         └─────────────────┘
```

**Der Server kann deine Daten niemals lesen** - selbst bei einem Hack.

Für Details siehe [SECURITY.md](SECURITY.md).

---

## Installation

### Android App

1. **Play Store** (bald verfügbar)
2. **APK Download**: [GitHub Releases](https://github.com/sprobst76/VibedTracker/releases)

### Web-Interface

Nach der App-Einrichtung erreichbar unter deinem Server.

### Self-Hosting (Server)

```bash
# Docker Compose
git clone https://github.com/sprobst76/VibedTracker.git
cd VibedTracker/server

# Konfiguration anpassen
cp .env.example .env
nano .env

# Starten
docker-compose up -d
```

Siehe [Server-Dokumentation](server/README.md) für Details.

---

## Entwicklung

### Voraussetzungen
- Flutter SDK (stable channel)
- Go 1.21+ (für Server)
- PostgreSQL 14+ (für Server)
- Android Studio oder VS Code

### Flutter App

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

# Release App Bundle (Play Store)
flutter build appbundle --release
```

### Go Server

```bash
cd server

# Abhängigkeiten
go mod download

# Entwicklung starten
go run cmd/api/main.go

# Production Build
go build -o vibedtracker-server cmd/api/main.go
```

---

## Projektstruktur

```
VibedTracker/
├── lib/                       # Flutter App
│   ├── main.dart              # App-Einstiegspunkt
│   ├── providers.dart         # Riverpod State Management
│   ├── models/                # Datenmodelle (Hive)
│   ├── screens/               # UI Screens
│   ├── services/              # Business Logic
│   │   ├── encryption_service.dart  # Zero-Knowledge Crypto
│   │   ├── geofence_service.dart    # GPS Geofencing
│   │   └── cloud_sync_service.dart  # Verschlüsselter Sync
│   └── theme/                 # Theming
│
├── server/                    # Go Backend
│   ├── cmd/api/               # Server Entry Point
│   ├── internal/
│   │   ├── handlers/          # API Handlers
│   │   ├── middleware/        # Auth, Rate Limiting
│   │   └── repository/        # Database Access
│   ├── static/js/             # Web Crypto (Client-Side)
│   ├── templates/             # HTMX Web Templates
│   └── migrations/            # PostgreSQL Migrations
│
├── docs/                      # Dokumentation
│   ├── KEYSTORE_SECURITY.md   # Keystore & Secrets
│   └── BUSINESS_ANALYSIS.md   # Business Model
│
├── SECURITY.md                # Sicherheitsarchitektur
└── README.md                  # Diese Datei
```

---

## Technologie-Stack

### Flutter App
| Komponente | Technologie |
|------------|-------------|
| **Framework** | Flutter 3.x |
| **State Management** | Riverpod |
| **Lokale Datenbank** | Hive (verschlüsselt) |
| **Maps** | flutter_map (OpenStreetMap) |
| **Geofencing** | geofence_foreground_service |
| **Verschlüsselung** | cryptography (AES-256-GCM, PBKDF2) |
| **Auth** | local_auth (Biometrie) |

### Go Server
| Komponente | Technologie |
|------------|-------------|
| **Framework** | Gin |
| **Datenbank** | PostgreSQL |
| **Auth** | JWT + TOTP |
| **WebAuthn** | Custom (WebAuthn Level 2) |
| **Templates** | Go html/template + HTMX |

### Kryptographie
| Zweck | Algorithmus |
|-------|-------------|
| **Key Derivation** | PBKDF2-HMAC-SHA256 (100k iter) |
| **Verschlüsselung** | AES-256-GCM |
| **Password Hashing** | bcrypt (cost 12) |
| **2FA** | TOTP (RFC 6238) |
| **Passkeys** | WebAuthn + PRF Extension |

---

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [SECURITY.md](SECURITY.md) | Sicherheitsarchitektur, Kryptographie, Bedrohungsmodell |
| [CLAUDE.md](CLAUDE.md) | Entwickler-Anweisungen |
| [docs/KEYSTORE_SECURITY.md](docs/KEYSTORE_SECURITY.md) | Keystore & Secrets Management |
| [docs/BUSINESS_ANALYSIS.md](docs/BUSINESS_ANALYSIS.md) | Business Model & Marktanalyse |

---

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

---

## Sicherheit melden

Sicherheitslücke gefunden? Bitte **nicht** öffentlich posten.

1. E-Mail an: security@vibedtracker.com
2. Oder: GitHub Issue mit `[SECURITY]` Prefix

Siehe [SECURITY.md](SECURITY.md#responsible-disclosure) für Details.

---

## Lizenz

Proprietär - Alle Rechte vorbehalten.

---

## Autor

Stefan Probst ([@sprobst76](https://github.com/sprobst76))
