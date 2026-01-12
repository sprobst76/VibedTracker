-- VibedTracker Database Schema
-- Migration: 002_totp
-- Date: 2026-01-07
-- Description: Add TOTP two-factor authentication support

-- Add TOTP columns to users table
ALTER TABLE users ADD COLUMN totp_secret BYTEA;
ALTER TABLE users ADD COLUMN totp_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN totp_verified_at TIMESTAMPTZ;

-- Recovery codes for 2FA backup
CREATE TABLE recovery_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(255) NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup of unused recovery codes
CREATE INDEX idx_recovery_codes_user ON recovery_codes(user_id) WHERE NOT used;

-- TOTP attempt tracking for rate limiting
CREATE TABLE totp_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    attempted_at TIMESTAMPTZ DEFAULT NOW(),
    success BOOLEAN DEFAULT FALSE
);

-- Index for rate limiting queries
CREATE INDEX idx_totp_attempts_user_time ON totp_attempts(user_id, attempted_at DESC);

-- Cleanup old attempts (keep only last 24 hours)
-- This should be run periodically via cron or similar
-- DELETE FROM totp_attempts WHERE attempted_at < NOW() - INTERVAL '24 hours';
