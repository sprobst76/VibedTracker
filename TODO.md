# TODO - VibedTracker

## Aktuell: Phase 4 - Cloud-Synchronisation

### 4.1 Server-Backend (Go API)

**Ziel**: Leichtgewichtige REST-API auf VPS mit E2E-Verschlüsselung

#### Architektur
```
VPS (Ubuntu/Debian)
├── vibedtracker-api (Go Binary)
│   ├── /auth          - Email-Registrierung, Login, JWT
│   ├── /sync          - Push/Pull verschlüsselter Daten
│   ├── /devices       - Geräteverwaltung
│   └── /admin         - User-Verwaltung (geschützt)
├── PostgreSQL
│   ├── users          - id, email, password_hash, is_approved, created_at
│   ├── devices        - id, user_id, device_name, last_sync
│   └── encrypted_data - id, user_id, device_id, data_type, blob, updated_at
└── Admin Dashboard (HTML/JS oder Vue)
    ├── User-Liste
    ├── Freischaltung
    └── Statistiken
```

#### Tasks
- [ ] Go-Projekt initialisieren (`server/`)
- [ ] PostgreSQL Schema erstellen
- [ ] Auth-Endpoints implementieren
  - [ ] POST /auth/register (Email, Password)
  - [ ] POST /auth/login (JWT Token)
  - [ ] POST /auth/verify-email
  - [ ] POST /auth/forgot-password
- [ ] Sync-Endpoints implementieren
  - [ ] GET /sync/pull?since=timestamp
  - [ ] POST /sync/push
  - [ ] POST /sync/resolve-conflict
- [ ] Device-Management
  - [ ] GET /devices
  - [ ] POST /devices/register
  - [ ] DELETE /devices/:id
- [ ] Admin-Endpoints
  - [ ] GET /admin/users
  - [ ] POST /admin/users/:id/approve
  - [ ] POST /admin/users/:id/block
  - [ ] DELETE /admin/users/:id
- [ ] Admin-Dashboard (einfaches HTML/JS)
- [ ] Docker-Compose für Deployment
- [ ] HTTPS mit Let's Encrypt

### 4.2 App-Integration

#### E2E-Verschlüsselung
- [ ] CryptoService implementieren
  - [ ] AES-256-GCM Verschlüsselung
  - [ ] Argon2id Key-Derivation aus Passphrase
  - [ ] Secure Storage für Master Key
- [ ] Passphrase-Screen bei Setup
- [ ] Key-Verification ohne Übertragung

#### Sync-Service
- [ ] CloudSyncService implementieren
  - [ ] Push lokaler Änderungen
  - [ ] Pull remote Änderungen
  - [ ] Konfliktauflösung
- [ ] Offline-Queue für ausstehende Syncs
- [ ] Sync-Status-Indicator in UI

#### Auth-Integration
- [ ] Login/Register Screens
- [ ] JWT Token Management
- [ ] Auto-Refresh Token
- [ ] Logout & Account löschen

### 4.3 Cross-Device Features

- [ ] Aktive Session auf allen Geräten sichtbar
- [ ] Start auf Gerät A, Stop auf Gerät B
- [ ] Push-Notifications für Sync-Updates

---

## Erledigte Features

### Phase 3 - Lokale Sicherheit (2026-01-07)
- [x] Backup/Restore als ZIP-Datei
- [x] Urlaubsanspruch pro Jahr (statt global)
- [x] Manuell genommene Urlaubstage für Migration

### Phase 2 - CI/CD & Branding (2026-01-07)
- [x] GitHub Actions (Analyze, Test, Release)
- [x] Automatischer APK-Release bei Tags
- [x] VibedTracker App-Icon und Name

### Phase 1 - Core Features (2026-01-01 bis 2026-01-06)
- [x] Geofence-basierte Zeiterfassung
- [x] Manuelle Einträge (CRUD)
- [x] Pausen-Erfassung
- [x] Arbeitsmodi (Normal, Deep Work, Meeting, etc.)
- [x] Projekte mit Farbkodierung
- [x] Urlaubsverwaltung
- [x] Feiertage (pro Bundesland)
- [x] Heiligabend/Silvester konfigurierbar
- [x] Berichte (Woche, Monat, Jahr)
- [x] Excel-Export
- [x] Dark Mode
- [x] Google Kalender Integration
- [x] Erinnerungen
- [x] App-Sperre (PIN/Biometrie)

---

## Backlog (Ideen)

### Performance
- [ ] Lazy Loading für große Datenmengen
- [ ] Datenbank-Optimierung (Indizes)

### Features
- [ ] iOS-Release im App Store
- [ ] Mehrsprachigkeit (EN, FR)
- [ ] Team-Funktionen (mehrere User sehen)
- [ ] Schichtplanung
- [ ] Zeiterfassung für Freelancer (Stundensätze, Rechnungen)

### Technisch
- [ ] Widget für Android Homescreen
- [ ] Wear OS Companion App
- [ ] Automatische Backups zu Google Drive

---

## Bekannte Bugs

- [ ] Biometrie-Button auf Lock Screen: Fix angewendet, noch zu testen

---

Zuletzt aktualisiert: 2026-01-07
