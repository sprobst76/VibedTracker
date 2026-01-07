package repository

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/sprobst76/vibedtracker-server/internal/models"
)

var (
	ErrUserNotFound      = errors.New("user not found")
	ErrUserAlreadyExists = errors.New("user already exists")
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

func (r *UserRepository) Create(ctx context.Context, email, passwordHash string) (*models.User, error) {
	user := &models.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: passwordHash,
		IsApproved:   false,
		IsAdmin:      false,
		IsBlocked:    false,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO users (id, email, password_hash, is_approved, is_admin, is_blocked, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, user.ID, user.Email, user.PasswordHash, user.IsApproved, user.IsAdmin, user.IsBlocked, user.CreatedAt, user.UpdatedAt)

	if err != nil {
		if err.Error() == `ERROR: duplicate key value violates unique constraint "users_email_key" (SQLSTATE 23505)` {
			return nil, ErrUserAlreadyExists
		}
		return nil, err
	}

	return user, nil
}

func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user := &models.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked, key_salt, key_verification_hash, created_at, updated_at
		FROM users WHERE id = $1
	`, id).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
		&user.KeySalt, &user.KeyVerificationHash, &user.CreatedAt, &user.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	return user, err
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	user := &models.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked, key_salt, key_verification_hash, created_at, updated_at
		FROM users WHERE email = $1
	`, email).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
		&user.KeySalt, &user.KeyVerificationHash, &user.CreatedAt, &user.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	return user, err
}

func (r *UserRepository) List(ctx context.Context) ([]models.User, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked, key_salt, key_verification_hash, created_at, updated_at
		FROM users ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var user models.User
		err := rows.Scan(
			&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
			&user.KeySalt, &user.KeyVerificationHash, &user.CreatedAt, &user.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}

	return users, rows.Err()
}

func (r *UserRepository) Approve(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_approved = true, updated_at = $1 WHERE id = $2`, time.Now(), id)
	return err
}

func (r *UserRepository) Block(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_blocked = true, updated_at = $1 WHERE id = $2`, time.Now(), id)
	return err
}

func (r *UserRepository) Unblock(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_blocked = false, updated_at = $1 WHERE id = $2`, time.Now(), id)
	return err
}

func (r *UserRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	return err
}

func (r *UserRepository) SetKeyInfo(ctx context.Context, id uuid.UUID, keySalt, keyVerificationHash []byte) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE users SET key_salt = $1, key_verification_hash = $2, updated_at = $3 WHERE id = $4
	`, keySalt, keyVerificationHash, time.Now(), id)
	return err
}

func (r *UserRepository) MakeAdmin(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_admin = true, is_approved = true, updated_at = $1 WHERE id = $2`, time.Now(), id)
	return err
}

func (r *UserRepository) GetStats(ctx context.Context) (*models.AdminStatsResponse, error) {
	stats := &models.AdminStatsResponse{}

	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&stats.TotalUsers)
	if err != nil {
		return nil, err
	}

	err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_approved = true AND is_blocked = false`).Scan(&stats.ApprovedUsers)
	if err != nil {
		return nil, err
	}

	err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_approved = false AND is_blocked = false`).Scan(&stats.PendingUsers)
	if err != nil {
		return nil, err
	}

	err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_blocked = true`).Scan(&stats.BlockedUsers)
	if err != nil {
		return nil, err
	}

	err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM devices`).Scan(&stats.TotalDevices)
	if err != nil {
		return nil, err
	}

	err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM encrypted_data WHERE deleted_at IS NULL`).Scan(&stats.TotalSyncItems)
	if err != nil {
		return nil, err
	}

	return stats, nil
}
