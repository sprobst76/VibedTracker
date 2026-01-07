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

var ErrDeviceNotFound = errors.New("device not found")

type DeviceRepository struct {
	pool *pgxpool.Pool
}

func NewDeviceRepository(pool *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{pool: pool}
}

func (r *DeviceRepository) Create(ctx context.Context, userID uuid.UUID, req *models.RegisterDeviceRequest) (*models.Device, error) {
	device := &models.Device{
		ID:          uuid.New(),
		UserID:      userID,
		DeviceName:  req.DeviceName,
		DeviceType:  req.DeviceType,
		DeviceModel: req.DeviceModel,
		AppVersion:  req.AppVersion,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO devices (id, user_id, device_name, device_type, device_model, app_version, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, device.ID, device.UserID, device.DeviceName, device.DeviceType, device.DeviceModel, device.AppVersion, device.CreatedAt, device.UpdatedAt)

	return device, err
}

func (r *DeviceRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.Device, error) {
	device := &models.Device{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, device_name, device_type, device_model, app_version, last_sync, created_at, updated_at
		FROM devices WHERE id = $1
	`, id).Scan(
		&device.ID, &device.UserID, &device.DeviceName, &device.DeviceType, &device.DeviceModel,
		&device.AppVersion, &device.LastSync, &device.CreatedAt, &device.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrDeviceNotFound
	}
	return device, err
}

func (r *DeviceRepository) GetByUserID(ctx context.Context, userID uuid.UUID) ([]models.Device, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, device_name, device_type, device_model, app_version, last_sync, created_at, updated_at
		FROM devices WHERE user_id = $1 ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []models.Device
	for rows.Next() {
		var device models.Device
		err := rows.Scan(
			&device.ID, &device.UserID, &device.DeviceName, &device.DeviceType, &device.DeviceModel,
			&device.AppVersion, &device.LastSync, &device.CreatedAt, &device.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		devices = append(devices, device)
	}

	return devices, rows.Err()
}

func (r *DeviceRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM devices WHERE id = $1`, id)
	return err
}

func (r *DeviceRepository) UpdateLastSync(ctx context.Context, id uuid.UUID) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx, `UPDATE devices SET last_sync = $1, updated_at = $1 WHERE id = $2`, now, id)
	return err
}
