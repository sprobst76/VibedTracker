package handlers

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedtracker-server/internal/config"
	"github.com/sprobst76/vibedtracker-server/internal/middleware"
	"github.com/sprobst76/vibedtracker-server/internal/models"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

type AuthHandler struct {
	cfg       *config.Config
	users     *repository.UserRepository
	tokens    *repository.TokenRepository
	devices   *repository.DeviceRepository
}

func NewAuthHandler(cfg *config.Config, users *repository.UserRepository, tokens *repository.TokenRepository, devices *repository.DeviceRepository) *AuthHandler {
	return &AuthHandler{
		cfg:     cfg,
		users:   users,
		tokens:  tokens,
		devices: devices,
	}
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if !h.cfg.AllowRegistration {
		c.JSON(http.StatusForbidden, gin.H{"error": "registration is currently disabled"})
		return
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	user, err := h.users.Create(c.Request.Context(), req.Email, string(hash))
	if err != nil {
		if errors.Is(err, repository.ErrUserAlreadyExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "registration successful, waiting for admin approval",
		"user_id": user.ID,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.users.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if user.IsBlocked {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is blocked", "code": "BLOCKED"})
		return
	}

	// Register device (always create one)
	deviceName := req.DeviceName
	if deviceName == "" {
		deviceName = "Unknown Device"
	}
	deviceType := req.DeviceType
	if deviceType == "" {
		deviceType = "unknown"
	}
	device, err := h.devices.Create(c.Request.Context(), user.ID, &models.RegisterDeviceRequest{
		DeviceName: deviceName,
		DeviceType: deviceType,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register device"})
		return
	}
	deviceID := device.ID

	// Generate tokens
	accessToken, err := middleware.GenerateAccessToken(user.ID, user.Email, user.IsAdmin, user.IsApproved, h.cfg.JWTExpiry)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken := middleware.GenerateRefreshToken()
	_, err = h.tokens.Create(c.Request.Context(), user.ID, deviceID, refreshToken, time.Now().Add(h.cfg.RefreshExpiry))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create refresh token"})
		return
	}

	c.JSON(http.StatusOK, models.LoginResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(h.cfg.JWTExpiry.Seconds()),
		User:         *user,
		DeviceID:     deviceID.String(),
	})
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, err := h.tokens.GetByToken(c.Request.Context(), req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	if token.Revoked || token.ExpiresAt.Before(time.Now()) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token expired or revoked"})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), token.UserID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	if user.IsBlocked {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is blocked", "code": "BLOCKED"})
		return
	}

	accessToken, err := middleware.GenerateAccessToken(user.ID, user.Email, user.IsAdmin, user.IsApproved, h.cfg.JWTExpiry)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, models.RefreshResponse{
		AccessToken: accessToken,
		ExpiresIn:   int64(h.cfg.JWTExpiry.Seconds()),
	})
}

func (h *AuthHandler) SetKey(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.SetKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Decode base64
	keySalt, err := decodeBase64(req.KeySalt)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key_salt format"})
		return
	}
	keyHash, err := decodeBase64(req.KeyVerificationHash)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key_verification_hash format"})
		return
	}

	if err := h.users.SetKeyInfo(c.Request.Context(), userID, keySalt, keyHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to set key info"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "key info saved"})
}

func (h *AuthHandler) Me(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// CreateInitialAdmin creates the first admin user if ADMIN_EMAIL and ADMIN_PASSWORD are set
func (h *AuthHandler) CreateInitialAdmin(ctx context.Context) error {
	if h.cfg.AdminEmail == "" || h.cfg.AdminPassword == "" {
		return nil
	}

	// Check if admin already exists
	_, err := h.users.GetByEmail(ctx, h.cfg.AdminEmail)
	if err == nil {
		return nil // Admin already exists
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(h.cfg.AdminPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user, err := h.users.Create(ctx, h.cfg.AdminEmail, string(hash))
	if err != nil {
		return err
	}

	return h.users.MakeAdmin(ctx, user.ID)
}
