package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrRecoveryCodeNotFound = errors.New("recovery code not found")
	ErrRecoveryCodeUsed     = errors.New("recovery code already used")
	ErrTooManyAttempts      = errors.New("too many TOTP attempts")
)

const (
	MaxTOTPAttempts     = 5
	TOTPAttemptWindow   = 5 * time.Minute
	RecoveryCodeCount   = 10
	RecoveryCodeLength  = 8
)

type TOTPRepository struct {
	pool *pgxpool.Pool
}

func NewTOTPRepository(pool *pgxpool.Pool) *TOTPRepository {
	return &TOTPRepository{pool: pool}
}

// Recovery Codes

func hashRecoveryCode(code string) string {
	hash, _ := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	return string(hash)
}

func verifyRecoveryCode(code, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(code))
	return err == nil
}

func (r *TOTPRepository) CreateRecoveryCodes(ctx context.Context, userID uuid.UUID, codes []string) error {
	// Delete existing unused codes first
	_, err := r.pool.Exec(ctx, `DELETE FROM recovery_codes WHERE user_id = $1 AND NOT used`, userID)
	if err != nil {
		return err
	}

	// Insert new codes
	for _, code := range codes {
		_, err := r.pool.Exec(ctx, `
			INSERT INTO recovery_codes (user_id, code_hash, created_at)
			VALUES ($1, $2, $3)
		`, userID, hashRecoveryCode(code), time.Now())
		if err != nil {
			return err
		}
	}

	return nil
}

func (r *TOTPRepository) ValidateRecoveryCode(ctx context.Context, userID uuid.UUID, code string) error {
	rows, err := r.pool.Query(ctx, `
		SELECT id, code_hash FROM recovery_codes
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

		if verifyRecoveryCode(code, codeHash) {
			matchedID = id
			break
		}
	}

	if matchedID == uuid.Nil {
		return ErrRecoveryCodeNotFound
	}

	// Mark code as used
	_, err = r.pool.Exec(ctx, `
		UPDATE recovery_codes SET used = true, used_at = $1 WHERE id = $2
	`, time.Now(), matchedID)

	return err
}

func (r *TOTPRepository) GetRecoveryCodesCount(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM recovery_codes WHERE user_id = $1 AND NOT used
	`, userID).Scan(&count)
	return count, err
}

func (r *TOTPRepository) DeleteRecoveryCodes(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM recovery_codes WHERE user_id = $1`, userID)
	return err
}

// TOTP Attempts (Rate Limiting)

func (r *TOTPRepository) RecordAttempt(ctx context.Context, userID uuid.UUID, success bool) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO totp_attempts (user_id, attempted_at, success)
		VALUES ($1, $2, $3)
	`, userID, time.Now(), success)
	return err
}

func (r *TOTPRepository) GetRecentFailedAttempts(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	cutoff := time.Now().Add(-TOTPAttemptWindow)
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM totp_attempts
		WHERE user_id = $1 AND attempted_at > $2 AND NOT success
	`, userID, cutoff).Scan(&count)
	return count, err
}

func (r *TOTPRepository) CheckRateLimit(ctx context.Context, userID uuid.UUID) error {
	count, err := r.GetRecentFailedAttempts(ctx, userID)
	if err != nil {
		return err
	}
	if count >= MaxTOTPAttempts {
		return ErrTooManyAttempts
	}
	return nil
}

func (r *TOTPRepository) CleanupOldAttempts(ctx context.Context) error {
	cutoff := time.Now().Add(-24 * time.Hour)
	_, err := r.pool.Exec(ctx, `DELETE FROM totp_attempts WHERE attempted_at < $1`, cutoff)
	return err
}

// Temp Token for TOTP validation during login

type TempToken struct {
	Token     string
	UserID    uuid.UUID
	DeviceID  uuid.UUID
	ExpiresAt time.Time
}

// In-memory store for temp tokens (for simplicity; could use Redis in production)
var tempTokens = make(map[string]*TempToken)

func generateTempToken() string {
	hash := sha256.Sum256([]byte(uuid.New().String() + time.Now().String()))
	return hex.EncodeToString(hash[:])
}

func (r *TOTPRepository) CreateTempToken(userID, deviceID uuid.UUID) string {
	token := generateTempToken()
	tempTokens[token] = &TempToken{
		Token:     token,
		UserID:    userID,
		DeviceID:  deviceID,
		ExpiresAt: time.Now().Add(5 * time.Minute),
	}
	return token
}

func (r *TOTPRepository) GetTempToken(token string) (*TempToken, error) {
	t, ok := tempTokens[token]
	if !ok {
		return nil, errors.New("temp token not found")
	}
	if time.Now().After(t.ExpiresAt) {
		delete(tempTokens, token)
		return nil, errors.New("temp token expired")
	}
	return t, nil
}

func (r *TOTPRepository) DeleteTempToken(token string) {
	delete(tempTokens, token)
}

// Cleanup expired temp tokens (should be called periodically)
func (r *TOTPRepository) CleanupExpiredTempTokens() {
	now := time.Now()
	for token, t := range tempTokens {
		if now.After(t.ExpiresAt) {
			delete(tempTokens, token)
		}
	}
}
