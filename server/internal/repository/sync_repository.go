package repository

import (
	"context"
	"encoding/base64"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/sprobst76/vibedtracker-server/internal/models"
)

type SyncRepository struct {
	pool *pgxpool.Pool
}

func NewSyncRepository(pool *pgxpool.Pool) *SyncRepository {
	return &SyncRepository{pool: pool}
}

func (r *SyncRepository) PushItems(ctx context.Context, userID, deviceID uuid.UUID, items []models.SyncPushItem) error {
	for _, item := range items {
		blob, err := base64.StdEncoding.DecodeString(item.EncryptedBlob)
		if err != nil {
			return err
		}
		nonce, err := base64.StdEncoding.DecodeString(item.Nonce)
		if err != nil {
			return err
		}

		schemaVersion := item.SchemaVersion
		if schemaVersion == 0 {
			schemaVersion = 1
		}

		if item.Deleted {
			// Soft delete
			_, err = r.pool.Exec(ctx, `
				UPDATE encrypted_data
				SET deleted_at = $1, updated_at = $1, device_id = $2
				WHERE user_id = $3 AND data_type = $4 AND local_id = $5
			`, time.Now(), deviceID, userID, item.DataType, item.LocalID)
		} else {
			// Upsert
			_, err = r.pool.Exec(ctx, `
				INSERT INTO encrypted_data (id, user_id, device_id, data_type, local_id, encrypted_blob, nonce, schema_version, created_at, updated_at)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
				ON CONFLICT (user_id, data_type, local_id)
				DO UPDATE SET encrypted_blob = $6, nonce = $7, schema_version = $8, device_id = $3, updated_at = $9, deleted_at = NULL
			`, uuid.New(), userID, deviceID, item.DataType, item.LocalID, blob, nonce, schemaVersion, time.Now())
		}

		if err != nil {
			return err
		}
	}

	// Log sync action
	_, err := r.pool.Exec(ctx, `
		INSERT INTO sync_log (id, user_id, device_id, action, data_type, items_count, created_at)
		VALUES ($1, $2, $3, 'push', NULL, $4, $5)
	`, uuid.New(), userID, deviceID, len(items), time.Now())

	return err
}

func (r *SyncRepository) PullItems(ctx context.Context, userID uuid.UUID, since time.Time, dataType string) ([]models.SyncPullItem, error) {
	var query string
	var args []interface{}

	if dataType != "" {
		query = `
			SELECT id, data_type, local_id, encrypted_blob, nonce, schema_version, updated_at, deleted_at
			FROM encrypted_data
			WHERE user_id = $1 AND updated_at > $2 AND data_type = $3
			ORDER BY updated_at ASC
		`
		args = []interface{}{userID, since, dataType}
	} else {
		query = `
			SELECT id, data_type, local_id, encrypted_blob, nonce, schema_version, updated_at, deleted_at
			FROM encrypted_data
			WHERE user_id = $1 AND updated_at > $2
			ORDER BY updated_at ASC
		`
		args = []interface{}{userID, since}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.SyncPullItem
	for rows.Next() {
		var item models.SyncPullItem
		var id uuid.UUID
		var blob, nonce []byte
		var updatedAt time.Time
		var deletedAt *time.Time

		err := rows.Scan(&id, &item.DataType, &item.LocalID, &blob, &nonce, &item.SchemaVersion, &updatedAt, &deletedAt)
		if err != nil {
			return nil, err
		}

		item.ID = id.String()
		item.EncryptedBlob = base64.StdEncoding.EncodeToString(blob)
		item.Nonce = base64.StdEncoding.EncodeToString(nonce)
		item.UpdatedAt = updatedAt.Unix()
		item.Deleted = deletedAt != nil

		items = append(items, item)
	}

	return items, rows.Err()
}

func (r *SyncRepository) LogPull(ctx context.Context, userID, deviceID uuid.UUID, itemsCount int) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO sync_log (id, user_id, device_id, action, data_type, items_count, created_at)
		VALUES ($1, $2, $3, 'pull', NULL, $4, $5)
	`, uuid.New(), userID, deviceID, itemsCount, time.Now())
	return err
}
