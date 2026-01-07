# TODO - VibedTracker

## Aktuell: Phase 4 - Cloud-Synchronisation

### 4.1 Server-Backend ✅ DONE

**Go REST API auf VPS mit E2E-Verschlüsselung**

```
/src/VibedTracker/server/
├── cmd/api/main.go           # Einstiegspunkt
├── internal/
│   ├── config/               # Umgebungsvariablen
│   ├── database/             # PostgreSQL Connection
│   ├── handlers/             # HTTP Handler
│   ├── middleware/           # JWT Auth
│   ├── models/               # Datenmodelle
│   └── repository/           # DB-Zugriff
├── admin/index.html          # Admin Dashboard
├── migrations/               # SQL Schema
├── deploy.sh                 # Deploy Script
├── docker-compose.yml        # Development
├── docker-compose.prod.yml   # Traefik/HTTPS
└── Dockerfile
```

#### Implementiert ✅
- [x] Go-Projekt mit Gin Framework
- [x] PostgreSQL Schema (users, devices, encrypted_data, etc.)
- [x] Auth-Endpoints
  - [x] POST /auth/register
  - [x] POST /auth/login (JWT + Refresh Token)
  - [x] POST /auth/refresh
- [x] Sync-Endpoints
  - [x] GET /sync/pull?device_id=...&since=0
  - [x] POST /sync/push
  - [x] GET /sync/status
- [x] Device-Management
  - [x] GET /devices
  - [x] POST /devices
  - [x] DELETE /devices/:id
- [x] Admin-Endpoints
  - [x] GET /admin/users
  - [x] GET /admin/users/:id
  - [x] POST /admin/users/:id/approve
  - [x] POST /admin/users/:id/block
  - [x] DELETE /admin/users/:id
  - [x] GET /admin/stats
- [x] Admin-Dashboard (HTML/JS)
- [x] Docker Compose + Dockerfile
- [x] Traefik-Integration für HTTPS
- [x] Deploy Script

---

### 4.2 Server Deployment

#### Option A: Manuell (Aktuell)

```bash
# Auf VPS
cd /src
git clone https://github.com/sprobst76/VibedTracker.git
cd VibedTracker/server

# Konfiguration
cp .env.example .env
nano .env  # Werte setzen

# Deploy
chmod +x deploy.sh
./deploy.sh prod
```

#### Option B: GitHub Actions Auto-Deploy (Geplant)

```yaml
# .github/workflows/deploy-server.yml
name: Deploy Server
on:
  push:
    branches: [main]
    paths: ['server/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /src/VibedTracker/server
            ./deploy.sh prod
```

**Benötigte Secrets:**
- `VPS_HOST` - VPS IP oder Domain
- `VPS_USER` - SSH User
- `VPS_SSH_KEY` - Private SSH Key

---

### 4.3 App-Integration (TODO)

#### E2E-Verschlüsselung
- [ ] CryptoService implementieren
  - [ ] AES-256-GCM Verschlüsselung
  - [ ] Argon2id Key-Derivation aus Passphrase
  - [ ] Secure Storage für Master Key
- [ ] Passphrase-Screen bei Setup
- [ ] Key-Verification ohne Übertragung

#### CloudSyncService
- [ ] API-Client für Server
- [ ] Push lokaler Änderungen
- [ ] Pull remote Änderungen
- [ ] Konfliktauflösung (Last-Write-Wins)
- [ ] Offline-Queue für ausstehende Syncs
- [ ] Sync-Status-Indicator in UI

#### Auth-Integration
- [ ] Login/Register Screens
- [ ] JWT Token Management (Secure Storage)
- [ ] Auto-Refresh Token
- [ ] "Account nicht freigeschalten" Handling
- [ ] Logout & Account löschen

### 4.4 Cross-Device Features (TODO)

- [ ] Aktive Session auf allen Geräten sichtbar
- [ ] Start auf Gerät A, Stop auf Gerät B
- [ ] Push-Notifications für Sync-Updates

---

## Erledigte Features

### Phase 4.1 - Server (2026-01-07)
- [x] Go REST API mit Gin
- [x] JWT Authentication
- [x] Admin-Freischaltung für User
- [x] Admin-Dashboard
- [x] Docker + Traefik Deployment
- [x] Deploy Script

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
- [ ] GitHub Actions für Server-Deploy

---

## Bekannte Bugs

- [ ] Biometrie-Button auf Lock Screen: Fix angewendet, noch zu testen

---

Zuletzt aktualisiert: 2026-01-07
