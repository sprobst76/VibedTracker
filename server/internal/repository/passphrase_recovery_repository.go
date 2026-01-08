package repository

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrPassphraseRecoveryCodeNotFound = errors.New("passphrase recovery code not found")
	ErrPassphraseRecoveryCodeUsed     = errors.New("passphrase recovery code already used")
	ErrPassphraseTooManyAttempts      = errors.New("too many passphrase recovery attempts")
)

const (
	MaxPassphraseRecoveryAttempts = 5
	PassphraseRecoveryWindow      = 15 * time.Minute
	PassphraseRecoveryCodeCount   = 10
	PassphraseRecoveryCodeLength  = 16 // Longer than TOTP recovery codes
)

type PassphraseRecoveryRepository struct {
	pool *pgxpool.Pool
}

func NewPassphraseRecoveryRepository(pool *pgxpool.Pool) *PassphraseRecoveryRepository {
	return &PassphraseRecoveryRepository{pool: pool}
}

// GenerateRecoveryCodes generates random recovery codes
func GeneratePassphraseRecoveryCodes() ([]string, error) {
	codes := make([]string, PassphraseRecoveryCodeCount)
	for i := 0; i < PassphraseRecoveryCodeCount; i++ {
		bytes := make([]byte, PassphraseRecoveryCodeLength/2)
		if _, err := rand.Read(bytes); err != nil {
			return nil, err
		}
		codes[i] = hex.EncodeToString(bytes)
	}
	return codes, nil
}

func hashPassphraseRecoveryCode(code string) string {
	hash, _ := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	return string(hash)
}

func verifyPassphraseRecoveryCode(code, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(code))
	return err == nil
}

// CreateRecoveryCodes stores new recovery codes for a user
func (r *PassphraseRecoveryRepository) CreateRecoveryCodes(ctx context.Context, userID uuid.UUID, codes []string) error {
	// Delete existing unused codes first
	_, err := r.pool.Exec(ctx, `DELETE FROM passphrase_recovery_codes WHERE user_id = $1 AND NOT used`, userID)
	if err != nil {
		return err
	}

	// Insert new codes
	for _, code := range codes {
		_, err := r.pool.Exec(ctx, `
			INSERT INTO passphrase_recovery_codes (user_id, code_hash, created_at)
			VALUES ($1, $2, $3)
		`, userID, hashPassphraseRecoveryCode(code), time.Now())
		if err != nil {
			return err
		}
	}

	return nil
}

// ValidateRecoveryCode checks if a recovery code is valid and marks it as used
func (r *PassphraseRecoveryRepository) ValidateRecoveryCode(ctx context.Context, userID uuid.UUID, code string) error {
	rows, err := r.pool.Query(ctx, `
		SELECT id, code_hash FROM passphrase_recovery_codes
		WHERE user_id = $1 AND NOT used
	`, userID)
	if err != nil {
		return err
	}
	defer rows.Close()

	var matchedID uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		var codeHash string
		if err := rows.Scan(&id, &codeHash); err != nil {
			return err
		}

		if verifyPassphraseRecoveryCode(code, codeHash) {
			matchedID = id
			break
		}
	}

	if matchedID == uuid.Nil {
		return ErrPassphraseRecoveryCodeNotFound
	}

	// Mark code as used
	_, err = r.pool.Exec(ctx, `
		UPDATE passphrase_recovery_codes SET used = true, used_at = $1 WHERE id = $2
	`, time.Now(), matchedID)

	return err
}

// GetRecoveryCodesCount returns the number of unused recovery codes
func (r *PassphraseRecoveryRepository) GetRecoveryCodesCount(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM passphrase_recovery_codes WHERE user_id = $1 AND NOT used
	`, userID).Scan(&count)
	return count, err
}

// HasRecoveryCodes checks if user has any recovery codes set up
func (r *PassphraseRecoveryRepository) HasRecoveryCodes(ctx context.Context, userID uuid.UUID) (bool, error) {
	count, err := r.GetRecoveryCodesCount(ctx, userID)
	return count > 0, err
}

// DeleteRecoveryCodes removes all recovery codes for a user
func (r *PassphraseRecoveryRepository) DeleteRecoveryCodes(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM passphrase_recovery_codes WHERE user_id = $1`, userID)
	return err
}

// Rate Limiting

// RecordAttempt records a passphrase recovery attempt
func (r *PassphraseRecoveryRepository) RecordAttempt(ctx context.Context, userID uuid.UUID, ipAddress string, success bool) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO passphrase_recovery_attempts (user_id, ip_address, attempted_at, success)
		VALUES ($1, $2, $3, $4)
	`, userID, ipAddress, time.Now(), success)
	return err
}

// GetRecentFailedAttempts returns the number of failed attempts in the time window
func (r *PassphraseRecoveryRepository) GetRecentFailedAttempts(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	cutoff := time.Now().Add(-PassphraseRecoveryWindow)
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM passphrase_recovery_attempts
		WHERE user_id = $1 AND attempted_at > $2 AND NOT success
	`, userID, cutoff).Scan(&count)
	return count, err
}

// GetRecentFailedAttemptsByIP returns the number of failed attempts from an IP in the time window
func (r *PassphraseRecoveryRepository) GetRecentFailedAttemptsByIP(ctx context.Context, ipAddress string) (int, error) {
	var count int
	cutoff := time.Now().Add(-PassphraseRecoveryWindow)
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM passphrase_recovery_attempts
		WHERE ip_address = $1 AND attempted_at > $2 AND NOT success
	`, ipAddress, cutoff).Scan(&count)
	return count, err
}

// CheckRateLimit checks if the user/IP has exceeded the rate limit
func (r *PassphraseRecoveryRepository) CheckRateLimit(ctx context.Context, userID uuid.UUID, ipAddress string) error {
	userCount, err := r.GetRecentFailedAttempts(ctx, userID)
	if err != nil {
		return err
	}
	if userCount >= MaxPassphraseRecoveryAttempts {
		return ErrPassphraseTooManyAttempts
	}

	ipCount, err := r.GetRecentFailedAttemptsByIP(ctx, ipAddress)
	if err != nil {
		return err
	}
	if ipCount >= MaxPassphraseRecoveryAttempts*2 { // Higher limit for IP (shared IPs)
		return ErrPassphraseTooManyAttempts
	}

	return nil
}

// CleanupOldAttempts removes old attempt records
func (r *PassphraseRecoveryRepository) CleanupOldAttempts(ctx context.Context) error {
	cutoff := time.Now().Add(-24 * time.Hour)
	_, err := r.pool.Exec(ctx, `DELETE FROM passphrase_recovery_attempts WHERE attempted_at < $1`, cutoff)
	return err
}
