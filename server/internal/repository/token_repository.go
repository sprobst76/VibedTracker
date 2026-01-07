package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/sprobst76/vibedtracker-server/internal/models"
)

var ErrTokenNotFound = errors.New("token not found")

type TokenRepository struct {
	pool *pgxpool.Pool
}

func NewTokenRepository(pool *pgxpool.Pool) *TokenRepository {
	return &TokenRepository{pool: pool}
}

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func (r *TokenRepository) Create(ctx context.Context, userID, deviceID uuid.UUID, token string, expiresAt time.Time) (*models.RefreshToken, error) {
	rt := &models.RefreshToken{
		ID:        uuid.New(),
		UserID:    userID,
		DeviceID:  deviceID,
		TokenHash: hashToken(token),
		ExpiresAt: expiresAt,
		Revoked:   false,
		CreatedAt: time.Now(),
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO refresh_tokens (id, user_id, device_id, token_hash, expires_at, revoked, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, rt.ID, rt.UserID, rt.DeviceID, rt.TokenHash, rt.ExpiresAt, rt.Revoked, rt.CreatedAt)

	return rt, err
}

func (r *TokenRepository) GetByToken(ctx context.Context, token string) (*models.RefreshToken, error) {
	hash := hashToken(token)
	rt := &models.RefreshToken{}

	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, device_id, token_hash, expires_at, revoked, created_at
		FROM refresh_tokens WHERE token_hash = $1
	`, hash).Scan(&rt.ID, &rt.UserID, &rt.DeviceID, &rt.TokenHash, &rt.ExpiresAt, &rt.Revoked, &rt.CreatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrTokenNotFound
	}
	return rt, err
}

func (r *TokenRepository) Revoke(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE id = $1`, id)
	return err
}

func (r *TokenRepository) RevokeByUserID(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1`, userID)
	return err
}

func (r *TokenRepository) RevokeByDeviceID(ctx context.Context, deviceID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE device_id = $1`, deviceID)
	return err
}

func (r *TokenRepository) CleanupExpired(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE expires_at < $1 OR revoked = true`, time.Now())
	return err
}
