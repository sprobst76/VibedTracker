-- Migration: 004_passkeys.sql
-- Adds WebAuthn/Passkey support for passwordless authentication

-- Passkey credentials table
CREATE TABLE IF NOT EXISTS passkey_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- WebAuthn credential data
    credential_id BYTEA NOT NULL UNIQUE,
    public_key BYTEA NOT NULL,

    -- Credential metadata
    name VARCHAR(255) NOT NULL DEFAULT 'Passkey',
    aaguid BYTEA,  -- Authenticator Attestation GUID
    sign_count BIGINT NOT NULL DEFAULT 0,

    -- For key wrapping (optional - stores encrypted encryption key)
    wrapped_key TEXT,  -- Base64 encoded, encrypted with PRF-derived key
    wrapped_key_nonce TEXT,  -- Nonce for the wrapped key

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Constraints
    CONSTRAINT unique_credential_per_user UNIQUE (user_id, credential_id)
);

-- Challenge storage for WebAuthn ceremonies (short-lived)
CREATE TABLE IF NOT EXISTS passkey_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    challenge BYTEA NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('registration', 'authentication')),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_passkey_credentials_user_id ON passkey_credentials(user_id);
CREATE INDEX IF NOT EXISTS idx_passkey_challenges_expires ON passkey_challenges(expires_at);

-- Cleanup job for expired challenges (run periodically)
-- DELETE FROM passkey_challenges WHERE expires_at < NOW();

-- Add passkey_enabled flag to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS passkey_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON TABLE passkey_credentials IS 'Stores WebAuthn/Passkey credentials for passwordless authentication';
COMMENT ON COLUMN passkey_credentials.wrapped_key IS 'Optional: Encryption key wrapped with PRF-derived secret for convenience unlock';
