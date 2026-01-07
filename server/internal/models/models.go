package models

import (
	"time"

	"github.com/google/uuid"
)

// User represents a registered user
type User struct {
	ID                  uuid.UUID  `json:"id"`
	Email               string     `json:"email"`
	PasswordHash        string     `json:"-"`
	IsApproved          bool       `json:"is_approved"`
	IsAdmin             bool       `json:"is_admin"`
	IsBlocked           bool       `json:"is_blocked"`
	KeySalt             []byte     `json:"-"`
	KeyVerificationHash []byte     `json:"-"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

// Device represents a registered app instance
type Device struct {
	ID          uuid.UUID  `json:"id"`
	UserID      uuid.UUID  `json:"user_id"`
	DeviceName  string     `json:"device_name"`
	DeviceType  string     `json:"device_type"`
	DeviceModel string     `json:"device_model,omitempty"`
	AppVersion  string     `json:"app_version,omitempty"`
	LastSync    *time.Time `json:"last_sync,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// EncryptedData represents a zero-knowledge encrypted blob
type EncryptedData struct {
	ID            uuid.UUID  `json:"id"`
	UserID        uuid.UUID  `json:"user_id"`
	DeviceID      *uuid.UUID `json:"device_id,omitempty"`
	DataType      string     `json:"data_type"`
	LocalID       string     `json:"local_id"`
	EncryptedBlob []byte     `json:"encrypted_blob"`
	Nonce         []byte     `json:"nonce"`
	SchemaVersion int        `json:"schema_version"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	DeletedAt     *time.Time `json:"deleted_at,omitempty"`
}

// RefreshToken for JWT refresh
type RefreshToken struct {
	ID        uuid.UUID `json:"id"`
	UserID    uuid.UUID `json:"user_id"`
	DeviceID  uuid.UUID `json:"device_id"`
	TokenHash string    `json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	Revoked   bool      `json:"revoked"`
	CreatedAt time.Time `json:"created_at"`
}

// SyncLog for audit trail
type SyncLog struct {
	ID         uuid.UUID  `json:"id"`
	UserID     uuid.UUID  `json:"user_id"`
	DeviceID   *uuid.UUID `json:"device_id,omitempty"`
	Action     string     `json:"action"`
	DataType   string     `json:"data_type,omitempty"`
	ItemsCount int        `json:"items_count"`
	CreatedAt  time.Time  `json:"created_at"`
}

// Request/Response types

type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

type LoginRequest struct {
	Email      string `json:"email" binding:"required,email"`
	Password   string `json:"password" binding:"required"`
	DeviceName string `json:"device_name"`
	DeviceType string `json:"device_type"`
}

type LoginResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
	User         User   `json:"user"`
	DeviceID     string `json:"device_id"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type RefreshResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int64  `json:"expires_in"`
}

type SyncPushRequest struct {
	DeviceID string         `json:"device_id" binding:"required"`
	Items    []SyncPushItem `json:"items" binding:"required"`
}

type SyncPushItem struct {
	DataType      string `json:"data_type" binding:"required"`
	LocalID       string `json:"local_id" binding:"required"`
	EncryptedBlob string `json:"encrypted_blob" binding:"required"` // Base64
	Nonce         string `json:"nonce" binding:"required"`          // Base64
	SchemaVersion int    `json:"schema_version"`
	Deleted       bool   `json:"deleted"`
}

type SyncPullRequest struct {
	DeviceID string `form:"device_id" binding:"required"`
	Since    int64  `form:"since"` // Unix timestamp
	DataType string `form:"data_type,omitempty"`
}

type SyncPullResponse struct {
	Items     []SyncPullItem `json:"items"`
	Timestamp int64          `json:"timestamp"`
}

type SyncPullItem struct {
	ID            string `json:"id"`
	DataType      string `json:"data_type"`
	LocalID       string `json:"local_id"`
	EncryptedBlob string `json:"encrypted_blob"` // Base64
	Nonce         string `json:"nonce"`          // Base64
	SchemaVersion int    `json:"schema_version"`
	UpdatedAt     int64  `json:"updated_at"`
	Deleted       bool   `json:"deleted"`
}

type RegisterDeviceRequest struct {
	DeviceName  string `json:"device_name" binding:"required"`
	DeviceType  string `json:"device_type" binding:"required"`
	DeviceModel string `json:"device_model,omitempty"`
	AppVersion  string `json:"app_version,omitempty"`
}

type AdminUserListResponse struct {
	Users      []User `json:"users"`
	TotalCount int    `json:"total_count"`
}

type AdminStatsResponse struct {
	TotalUsers     int `json:"total_users"`
	ApprovedUsers  int `json:"approved_users"`
	PendingUsers   int `json:"pending_users"`
	BlockedUsers   int `json:"blocked_users"`
	TotalDevices   int `json:"total_devices"`
	TotalSyncItems int `json:"total_sync_items"`
}

type SetKeyRequest struct {
	KeySalt             string `json:"key_salt" binding:"required"`              // Base64
	KeyVerificationHash string `json:"key_verification_hash" binding:"required"` // Base64
}
