# VibedTracker Server

Go-basierte REST-API für VibedTracker Cloud-Sync.

## Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                      VibedTracker API                       │
├─────────────────────────────────────────────────────────────┤
│  Endpoints                                                  │
│  ├── /auth     - Registrierung, Login, Email-Verification  │
│  ├── /sync     - Push/Pull verschlüsselter Daten          │
│  ├── /devices  - Geräteverwaltung                          │
│  └── /admin    - User-Verwaltung (Admin only)              │
├─────────────────────────────────────────────────────────────┤
│  Middleware                                                 │
│  ├── JWT Authentication                                     │
│  ├── Rate Limiting                                          │
│  └── CORS                                                   │
├─────────────────────────────────────────────────────────────┤
│  Database: PostgreSQL                                       │
│  ├── users, devices, encrypted_data                         │
└─────────────────────────────────────────────────────────────┘
```

## Zero-Knowledge Prinzip

Der Server speichert **nur verschlüsselte Blobs**:
- Verschlüsselung erfolgt auf dem Gerät (AES-256-GCM)
- Server kann Daten nicht lesen
- Passphrase wird niemals übertragen
- Key-Verification Hash zur Passphrase-Prüfung

## Tech Stack

- **Sprache**: Go 1.21+
- **Framework**: Gin oder Chi (leichtgewichtig)
- **Datenbank**: PostgreSQL 15+
- **Auth**: JWT (RS256)
- **Deployment**: Docker + Docker Compose

## Projektstruktur

```
server/
├── cmd/
│   └── api/
│       └── main.go           # Einstiegspunkt
├── internal/
│   ├── config/               # Konfiguration
│   ├── handlers/             # HTTP Handler
│   │   ├── auth.go
│   │   ├── sync.go
│   │   ├── devices.go
│   │   └── admin.go
│   ├── middleware/           # JWT, Rate Limit
│   ├── models/               # Datenmodelle
│   ├── repository/           # DB-Zugriff
│   └── services/             # Business Logic
├── migrations/               # SQL Migrationen
├── admin/                    # Admin Dashboard (HTML/JS)
├── docker-compose.yml
├── Dockerfile
├── go.mod
└── README.md
```

## API Endpoints

### Auth

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| POST | `/auth/register` | Neuen Account erstellen |
| POST | `/auth/login` | Login, JWT erhalten |
| POST | `/auth/refresh` | Token erneuern |
| POST | `/auth/verify-email` | Email verifizieren |
| POST | `/auth/forgot-password` | Passwort zurücksetzen |
| POST | `/auth/change-password` | Passwort ändern |

### Sync

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/sync/pull` | Änderungen seit Timestamp holen |
| POST | `/sync/push` | Lokale Änderungen hochladen |
| GET | `/sync/status` | Sync-Status abfragen |

### Devices

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/devices` | Alle registrierten Geräte |
| POST | `/devices` | Neues Gerät registrieren |
| DELETE | `/devices/:id` | Gerät entfernen |

### Admin (nur für Admins)

| Method | Endpoint | Beschreibung |
|--------|----------|--------------|
| GET | `/admin/users` | Alle User auflisten |
| GET | `/admin/users/:id` | User-Details |
| POST | `/admin/users/:id/approve` | User freischalten |
| POST | `/admin/users/:id/block` | User sperren |
| DELETE | `/admin/users/:id` | User löschen |
| GET | `/admin/stats` | Statistiken |

## Datenbank-Schema

```sql
-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    is_approved BOOLEAN DEFAULT FALSE,
    is_admin BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    key_salt BYTEA,                    -- Salt für Schlüsselableitung
    key_verification_hash BYTEA,       -- Hash zur Passphrase-Prüfung
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Devices
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_name VARCHAR(255),
    device_type VARCHAR(50),           -- 'android', 'ios'
    push_token TEXT,
    last_sync TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Encrypted Data (Zero-Knowledge)
CREATE TABLE encrypted_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id),
    data_type VARCHAR(50) NOT NULL,    -- 'work_entry', 'vacation', etc.
    local_id VARCHAR(255),             -- ID auf dem Gerät
    encrypted_blob BYTEA NOT NULL,     -- Verschlüsselte Daten
    nonce BYTEA NOT NULL,              -- IV für AES-GCM
    version INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,            -- Soft-Delete für Sync
    UNIQUE(user_id, data_type, local_id)
);

-- Indices
CREATE INDEX idx_encrypted_data_user_updated ON encrypted_data(user_id, updated_at);
CREATE INDEX idx_encrypted_data_type ON encrypted_data(data_type);
CREATE INDEX idx_devices_user ON devices(user_id);
```

## Setup

### Voraussetzungen

- Go 1.21+
- PostgreSQL 15+
- Docker & Docker Compose (optional)

### Lokale Entwicklung

```bash
# Abhängigkeiten
go mod download

# PostgreSQL starten (Docker)
docker run -d --name vibedtracker-db \
  -e POSTGRES_USER=vibedtracker \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=vibedtracker \
  -p 5432:5432 \
  postgres:15

# Migrationen ausführen
go run cmd/migrate/main.go up

# Server starten
go run cmd/api/main.go
```

### Docker Deployment

```bash
docker-compose up -d
```

## Konfiguration

Umgebungsvariablen:

| Variable | Beschreibung | Default |
|----------|--------------|---------|
| `DATABASE_URL` | PostgreSQL Connection String | - |
| `JWT_SECRET` | Secret für JWT Signierung | - |
| `PORT` | API Port | 8080 |
| `ADMIN_EMAIL` | Erster Admin-Account | - |
| `SMTP_HOST` | Mail-Server für Verification | - |
| `SMTP_PORT` | Mail-Port | 587 |
| `SMTP_USER` | Mail-User | - |
| `SMTP_PASS` | Mail-Passwort | - |

## Sicherheit

- [x] HTTPS erforderlich (Let's Encrypt)
- [x] JWT mit RS256 (asymmetrisch)
- [x] Rate Limiting
- [x] Password Hashing (bcrypt, cost 12)
- [x] SQL Injection Prevention (prepared statements)
- [x] CORS konfiguriert
- [x] Helmet-ähnliche Security Headers
- [x] Verschlüsselte Daten (Zero-Knowledge)

## Admin Dashboard

Einfaches HTML/JS Dashboard unter `/admin/`:
- User-Liste mit Freischaltung
- Statistiken (User-Anzahl, Sync-Status)
- Passwort-geschützt (Admin-JWT)

## Lizenz

Proprietär - Alle Rechte vorbehalten.
