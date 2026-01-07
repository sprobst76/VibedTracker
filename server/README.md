# VibedTracker Server

Go-basierte REST-API für VibedTracker Cloud-Sync mit Zero-Knowledge Verschlüsselung.

## Features

- **Zero-Knowledge Sync**: Server speichert nur verschlüsselte Blobs
- **Admin-Freischaltung**: Neue User müssen vom Admin freigeschalten werden
- **JWT Authentication**: Access + Refresh Token
- **Multi-Device**: Sync zwischen mehreren Geräten
- **Admin Dashboard**: Web-UI zur User-Verwaltung

## Quick Start

### 1. Konfiguration erstellen

```bash
cp .env.example .env
# .env bearbeiten und sichere Werte setzen
```

### 2. Mit Docker starten

```bash
docker-compose up -d
```

### 3. Admin-Dashboard öffnen

Öffne http://localhost:8080/admin/ und melde dich mit den in `.env` konfigurierten Admin-Credentials an.

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
├── docker-compose.yml
├── Dockerfile
└── go.mod
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
| `DATABASE_URL` | PostgreSQL Connection String | Ja |
| `DB_PASSWORD` | PostgreSQL Passwort | Ja |
| `JWT_SECRET` | Secret für Token-Signierung (min. 32 Zeichen) | Ja |
| `ADMIN_EMAIL` | Email des ersten Admin-Accounts | Ja |
| `ADMIN_PASSWORD` | Passwort des Admin-Accounts | Ja |
| `ALLOW_REGISTRATION` | Registrierung erlauben (default: true) | Nein |
| `PORT` | API Port (default: 8080) | Nein |

## Deployment auf VPS

### Mit Docker Compose

1. Repository klonen:
   ```bash
   git clone https://github.com/sprobst76/VibedTracker.git
   cd VibedTracker/server
   ```

2. `.env` konfigurieren:
   ```bash
   cp .env.example .env
   nano .env
   ```

3. Starten:
   ```bash
   docker-compose up -d
   ```

### Mit HTTPS (Caddy)

1. `Caddyfile` bearbeiten und Domain setzen
2. In `docker-compose.yml` Caddy-Service einkommentieren
3. Ports 80 + 443 freigeben
4. `docker-compose up -d`

## Sicherheit

- [x] Passwort-Hashing mit bcrypt
- [x] JWT mit HMAC-SHA256
- [x] Zero-Knowledge: Nur verschlüsselte Daten gespeichert
- [x] Admin-Freischaltung für neue User
- [x] Refresh Token Rotation
- [x] CORS konfiguriert
- [x] SQL Injection Prevention (prepared statements)

## Tech Stack

- **Go 1.21+**
- **Gin** - HTTP Framework
- **pgx** - PostgreSQL Driver
- **golang-jwt** - JWT Library
- **bcrypt** - Password Hashing
- **PostgreSQL 15**
- **Docker** + Docker Compose

## Lizenz

Proprietär - Alle Rechte vorbehalten.
