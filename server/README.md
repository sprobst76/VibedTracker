# VibedTracker Server

Go-basierte REST-API für VibedTracker Cloud-Sync mit Zero-Knowledge Verschlüsselung.

## Features

- **Zero-Knowledge Sync**: Server speichert nur verschlüsselte Blobs
- **Admin-Freischaltung**: Neue User müssen vom Admin freigeschalten werden
- **JWT Authentication**: Access + Refresh Token
- **Multi-Device**: Sync zwischen mehreren Geräten
- **Admin Dashboard**: Web-UI zur User-Verwaltung
- **Traefik-Ready**: Automatisches HTTPS mit Let's Encrypt

## Quick Start

### 1. Repository klonen

```bash
cd /src
git clone https://github.com/sprobst76/VibedTracker.git
cd VibedTracker/server
```

### 2. Konfiguration erstellen

```bash
cp .env.example .env
nano .env
```

**Wichtige Werte setzen:**
```bash
# Sichere Passwörter generieren:
openssl rand -base64 24  # für DB_PASSWORD
openssl rand -base64 32  # für JWT_SECRET
```

### 3. Deploy

```bash
# Script ausführbar machen
chmod +x deploy.sh

# Production mit Traefik
./deploy.sh prod

# ODER Development (Port 8080)
./deploy.sh dev
```

### 4. Admin-Dashboard

Öffne `https://your-domain.com/admin/` und melde dich mit den konfigurierten Admin-Credentials an.

---

## Deployment

### Option A: Mit Traefik (Empfohlen)

Voraussetzungen:
- Traefik läuft mit `traefik-public` Netzwerk
- Let's Encrypt Resolver namens `letsencrypt`
- Entrypoints: `web` (80), `websecure` (443)

```bash
# .env konfigurieren (inkl. DOMAIN)
nano .env

# Deploy
./deploy.sh prod
```

### Option B: Standalone (Development)

```bash
./deploy.sh dev
# API erreichbar unter http://localhost:8080
```

### Manuelles Deployment

```bash
# Production
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# Development
docker-compose up -d --build
```

---

## Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                      VibedTracker API                       │
├─────────────────────────────────────────────────────────────┤
│  Endpoints                                                  │
│  ├── /auth     - Register, Login, Token Refresh            │
│  ├── /sync     - Push/Pull verschlüsselter Daten          │
│  ├── /devices  - Geräteverwaltung                          │
│  └── /admin    - User-Verwaltung (Admin only)              │
├─────────────────────────────────────────────────────────────┤
│  Middleware: JWT Auth, CORS                                 │
├─────────────────────────────────────────────────────────────┤
│  Database: PostgreSQL 15                                    │
└─────────────────────────────────────────────────────────────┘
```

## Projektstruktur

```
server/
├── cmd/api/main.go           # Einstiegspunkt
├── internal/
│   ├── config/               # Konfiguration
│   ├── database/             # DB-Connection
│   ├── handlers/             # HTTP Handler
│   ├── middleware/           # JWT Auth
│   ├── models/               # Datenmodelle
│   └── repository/           # DB-Zugriff
├── migrations/               # SQL Migrationen
├── admin/                    # Admin Dashboard (HTML/JS)
├── deploy.sh                 # Deploy Script
├── docker-compose.yml        # Base Config
├── docker-compose.prod.yml   # Traefik Override
├── Dockerfile
└── .env.example
```

## API Endpoints

### Auth (Public)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| POST | `/api/v1/auth/register` | Account erstellen (wartet auf Freischaltung) |
| POST | `/api/v1/auth/login` | Login, JWT + Refresh Token |
| POST | `/api/v1/auth/refresh` | Access Token erneuern |

### User (Auth Required)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/api/v1/me` | Eigene User-Daten |
| POST | `/api/v1/key` | Key-Salt + Verification-Hash setzen |

### Sync (Auth + Approved Required)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/api/v1/sync/pull?device_id=...&since=0` | Änderungen holen |
| POST | `/api/v1/sync/push` | Änderungen hochladen |
| GET | `/api/v1/sync/status` | Sync-Status |

### Devices (Auth Required)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/api/v1/devices` | Eigene Geräte auflisten |
| POST | `/api/v1/devices` | Gerät registrieren |
| DELETE | `/api/v1/devices/:id` | Gerät entfernen |

### Admin (Admin Required)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/api/v1/admin/users` | Alle User |
| GET | `/api/v1/admin/users/:id` | User-Details |
| POST | `/api/v1/admin/users/:id/approve` | User freischalten |
| POST | `/api/v1/admin/users/:id/block` | User sperren |
| POST | `/api/v1/admin/users/:id/unblock` | User entsperren |
| DELETE | `/api/v1/admin/users/:id` | User löschen |
| GET | `/api/v1/admin/stats` | Statistiken |

## Konfiguration

Umgebungsvariablen in `.env`:

| Variable | Beschreibung | Pflicht |
|----------|--------------|---------|
| `DB_PASSWORD` | PostgreSQL Passwort | Ja |
| `JWT_SECRET` | Secret für Token-Signierung (min. 32 Zeichen) | Ja |
| `ADMIN_EMAIL` | Email des ersten Admin-Accounts | Ja |
| `ADMIN_PASSWORD` | Passwort des Admin-Accounts | Ja |
| `DOMAIN` | Domain für Traefik (ohne https://) | Prod |
| `ALLOW_REGISTRATION` | Registrierung erlauben (default: true) | Nein |
| `PORT` | API Port (default: 8080) | Nein |

## Wartung

### Logs anzeigen
```bash
docker-compose logs -f api
docker-compose logs -f db
```

### Neustart
```bash
docker-compose restart api
```

### Update deployen
```bash
./deploy.sh prod
```

### Datenbank Backup
```bash
docker-compose exec db pg_dump -U vibedtracker vibedtracker > backup.sql
```

### Datenbank Restore
```bash
cat backup.sql | docker-compose exec -T db psql -U vibedtracker vibedtracker
```

## Sicherheit

- [x] Passwort-Hashing mit bcrypt
- [x] JWT mit HMAC-SHA256
- [x] Zero-Knowledge: Nur verschlüsselte Daten gespeichert
- [x] Admin-Freischaltung für neue User
- [x] Refresh Token Rotation
- [x] CORS konfiguriert
- [x] SQL Injection Prevention (prepared statements)
- [x] HTTPS via Traefik/Let's Encrypt

## Tech Stack

- **Go 1.23+** - API Server
- **Gin** - HTTP Framework
- **pgx** - PostgreSQL Driver
- **golang-jwt** - JWT Library
- **bcrypt** - Password Hashing
- **PostgreSQL 15** - Datenbank
- **Docker** + Docker Compose
- **Traefik** - Reverse Proxy (optional)

## Flutter App Integration (TODO)

Die Flutter-App muss erweitert werden um Cloud-Sync zu nutzen:

### 1. Auth Service
- Login/Register Screen
- JWT Token Management (Access + Refresh)
- Secure Storage für Tokens

### 2. Encryption Service
- Key Derivation aus User-Passwort (PBKDF2/Argon2)
- AES-256-GCM Verschlüsselung
- Key-Salt beim Server speichern

### 3. Sync Service
- Änderungen lokal tracken (last_modified)
- Push: Lokale Änderungen verschlüsseln und hochladen
- Pull: Server-Änderungen holen und entschlüsseln
- Konflikt-Handling (last-write-wins oder merge)

### 4. Device Management
- Gerät beim ersten Start registrieren
- Device-ID persistent speichern

### Empfohlene Packages
```yaml
dependencies:
  http: ^1.1.0              # API Calls
  flutter_secure_storage: ^9.0.0  # Token Storage
  cryptography: ^2.7.0      # AES-256-GCM
  uuid: ^4.0.0              # Device IDs
```

## Lizenz

Proprietär - Alle Rechte vorbehalten.
