-- VibedTracker Database Schema
-- Migration: 001_initial
-- Date: 2026-01-07

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    is_approved BOOLEAN DEFAULT FALSE,
    is_admin BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    key_salt BYTEA,                         -- Salt für Client-seitige Key-Derivation
    key_verification_hash BYTEA,            -- Hash zur Passphrase-Verifizierung (ohne Passphrase zu kennen)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Email verification tokens
CREATE TABLE email_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Password reset tokens
CREATE TABLE password_resets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Devices (registered app instances)
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_name VARCHAR(255),
    device_type VARCHAR(50),                -- 'android', 'ios', 'web'
    device_model VARCHAR(255),
    app_version VARCHAR(50),
    push_token TEXT,                        -- For push notifications
    last_sync TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Encrypted data blobs (Zero-Knowledge)
-- Server kann diese Daten NICHT lesen!
CREATE TABLE encrypted_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    data_type VARCHAR(50) NOT NULL,         -- 'work_entry', 'vacation', 'vacation_quota', 'project', 'settings', etc.
    local_id VARCHAR(255),                  -- ID auf dem Client für Mapping
    encrypted_blob BYTEA NOT NULL,          -- AES-256-GCM verschlüsselte Daten
    nonce BYTEA NOT NULL,                   -- 12-byte IV für AES-GCM
    schema_version INT DEFAULT 1,           -- Für zukünftige Migrationen
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,                 -- Soft-Delete für Sync (NULL = aktiv)

    UNIQUE(user_id, data_type, local_id)
);

-- Sync log for conflict resolution
CREATE TABLE sync_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,            -- 'push', 'pull', 'conflict_resolved'
    data_type VARCHAR(50),
    items_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Active sessions (for cross-device tracking)
CREATE TABLE active_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    work_entry_local_id VARCHAR(255),       -- Lokale ID des laufenden Eintrags
    started_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id)                         -- Nur eine aktive Session pro User
);

-- Refresh tokens for JWT
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indices for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_approved ON users(is_approved) WHERE NOT is_blocked;

CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_push_token ON devices(push_token) WHERE push_token IS NOT NULL;

CREATE INDEX idx_encrypted_data_user_type ON encrypted_data(user_id, data_type);
CREATE INDEX idx_encrypted_data_user_updated ON encrypted_data(user_id, updated_at);
CREATE INDEX idx_encrypted_data_deleted ON encrypted_data(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE INDEX idx_sync_log_user ON sync_log(user_id, created_at DESC);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) WHERE NOT revoked;

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_encrypted_data_updated_at
    BEFORE UPDATE ON encrypted_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_active_sessions_updated_at
    BEFORE UPDATE ON active_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Initial admin user (password: changeme - CHANGE IMMEDIATELY!)
-- Password hash for 'changeme' using bcrypt cost 12
-- INSERT INTO users (email, password_hash, email_verified, is_approved, is_admin)
-- VALUES ('admin@example.com', '$2a$12$...', true, true, true);
