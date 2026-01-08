-- VibedTracker Database Schema
-- Migration: 003_passphrase_recovery
-- Date: 2026-01-08
-- Description: Add passphrase recovery codes for zero-knowledge encryption

-- Passphrase recovery codes (separate from 2FA recovery codes)
-- These allow users to reset their passphrase if forgotten
CREATE TABLE passphrase_recovery_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(255) NOT NULL,  -- bcrypt hash of the code
    used BOOLEAN DEFAULT FALSE,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup of unused recovery codes
CREATE INDEX idx_passphrase_recovery_codes_user ON passphrase_recovery_codes(user_id) WHERE NOT used;

-- Track passphrase recovery attempts for rate limiting
CREATE TABLE passphrase_recovery_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    attempted_at TIMESTAMPTZ DEFAULT NOW(),
    success BOOLEAN DEFAULT FALSE,
    ip_address VARCHAR(45)  -- IPv4 or IPv6
);

-- Index for rate limiting queries
CREATE INDEX idx_passphrase_recovery_attempts_user_time ON passphrase_recovery_attempts(user_id, attempted_at DESC);
CREATE INDEX idx_passphrase_recovery_attempts_ip_time ON passphrase_recovery_attempts(ip_address, attempted_at DESC);
