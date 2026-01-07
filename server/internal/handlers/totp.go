package handlers

import (
	"crypto/rand"
	"encoding/base32"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedtracker-server/internal/config"
	"github.com/sprobst76/vibedtracker-server/internal/middleware"
	"github.com/sprobst76/vibedtracker-server/internal/models"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

const (
	TOTPIssuer         = "VibedTracker"
	RecoveryCodeCount  = 10
	RecoveryCodeLength = 8
)

type TOTPHandler struct {
	cfg       *config.Config
	users     *repository.UserRepository
	totpRepo  *repository.TOTPRepository
	tokens    *repository.TokenRepository
	devices   *repository.DeviceRepository
}

func NewTOTPHandler(
	cfg *config.Config,
	users *repository.UserRepository,
	totpRepo *repository.TOTPRepository,
	tokens *repository.TokenRepository,
	devices *repository.DeviceRepository,
) *TOTPHandler {
	return &TOTPHandler{
		cfg:      cfg,
		users:    users,
		totpRepo: totpRepo,
		tokens:   tokens,
		devices:  devices,
	}
}

// Setup initiates TOTP setup and returns QR code data
func (h *TOTPHandler) Setup(c *gin.Context) {
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

	if user.TOTPEnabled {
		c.JSON(http.StatusConflict, gin.H{"error": "TOTP already enabled"})
		return
	}

	// Generate new TOTP secret
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      TOTPIssuer,
		AccountName: user.Email,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate TOTP secret"})
		return
	}

	// Store secret (not yet enabled)
	if err := h.users.SetTOTPSecret(c.Request.Context(), userID, []byte(key.Secret())); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save TOTP secret"})
		return
	}

	c.JSON(http.StatusOK, models.TOTPSetupResponse{
		Secret:    key.Secret(),
		QRCodeURL: key.URL(),
		Issuer:    TOTPIssuer,
	})
}

// Verify validates the first TOTP code and enables 2FA
func (h *TOTPHandler) Verify(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.TOTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if user.TOTPEnabled {
		c.JSON(http.StatusConflict, gin.H{"error": "TOTP already enabled"})
		return
	}

	if len(user.TOTPSecret) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP not set up yet"})
		return
	}

	// Validate the code
	if !totp.Validate(req.Code, string(user.TOTPSecret)) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Enable TOTP
	if err := h.users.EnableTOTP(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to enable TOTP"})
		return
	}

	// Generate recovery codes
	codes, err := h.generateRecoveryCodes(c, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate recovery codes"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        "TOTP enabled successfully",
		"recovery_codes": codes,
	})
}

// Disable disables TOTP after validating code and password
func (h *TOTPHandler) Disable(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.TOTPDisableRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if !user.TOTPEnabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP not enabled"})
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid password"})
		return
	}

	// Verify TOTP code
	if !totp.Validate(req.Code, string(user.TOTPSecret)) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Disable TOTP
	if err := h.users.DisableTOTP(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to disable TOTP"})
		return
	}

	// Delete recovery codes
	if err := h.totpRepo.DeleteRecoveryCodes(c.Request.Context(), userID); err != nil {
		// Log but don't fail
	}

	c.JSON(http.StatusOK, gin.H{"message": "TOTP disabled successfully"})
}

// Validate validates TOTP during login
func (h *TOTPHandler) Validate(c *gin.Context) {
	var req models.TOTPValidateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get temp token
	tempToken, err := h.totpRepo.GetTempToken(req.TempToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired temp token"})
		return
	}

	// Check rate limit
	if err := h.totpRepo.CheckRateLimit(c.Request.Context(), tempToken.UserID); err != nil {
		if err == repository.ErrTooManyAttempts {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many failed attempts, please try again later"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rate limit check failed"})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), tempToken.UserID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	// Validate TOTP
	if !totp.Validate(req.Code, string(user.TOTPSecret)) {
		// Record failed attempt
		h.totpRepo.RecordAttempt(c.Request.Context(), tempToken.UserID, false)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Record successful attempt
	h.totpRepo.RecordAttempt(c.Request.Context(), tempToken.UserID, true)

	// Delete temp token
	h.totpRepo.DeleteTempToken(req.TempToken)

	// Generate access and refresh tokens
	accessToken, err := middleware.GenerateAccessToken(user.ID, user.Email, user.IsAdmin, user.IsApproved, h.cfg.JWTExpiry)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken := middleware.GenerateRefreshToken()
	_, err = h.tokens.Create(c.Request.Context(), user.ID, tempToken.DeviceID, refreshToken, time.Now().Add(h.cfg.RefreshExpiry))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create refresh token"})
		return
	}

	c.JSON(http.StatusOK, models.LoginResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(h.cfg.JWTExpiry.Seconds()),
		User:         *user,
		DeviceID:     tempToken.DeviceID.String(),
	})
}

// ValidateRecovery validates a recovery code during login
func (h *TOTPHandler) ValidateRecovery(c *gin.Context) {
	var req models.RecoveryValidateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get temp token
	tempToken, err := h.totpRepo.GetTempToken(req.TempToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired temp token"})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), tempToken.UserID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	// Validate recovery code
	if err := h.totpRepo.ValidateRecoveryCode(c.Request.Context(), tempToken.UserID, req.Code); err != nil {
		if err == repository.ErrRecoveryCodeNotFound {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid recovery code"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to validate recovery code"})
		return
	}

	// Delete temp token
	h.totpRepo.DeleteTempToken(req.TempToken)

	// Generate access and refresh tokens
	accessToken, err := middleware.GenerateAccessToken(user.ID, user.Email, user.IsAdmin, user.IsApproved, h.cfg.JWTExpiry)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	refreshToken := middleware.GenerateRefreshToken()
	_, err = h.tokens.Create(c.Request.Context(), user.ID, tempToken.DeviceID, refreshToken, time.Now().Add(h.cfg.RefreshExpiry))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create refresh token"})
		return
	}

	// Get remaining recovery codes count
	remainingCodes, _ := h.totpRepo.GetRecoveryCodesCount(c.Request.Context(), tempToken.UserID)

	c.JSON(http.StatusOK, gin.H{
		"access_token":           accessToken,
		"refresh_token":          refreshToken,
		"expires_in":             int64(h.cfg.JWTExpiry.Seconds()),
		"user":                   user,
		"device_id":              tempToken.DeviceID.String(),
		"remaining_recovery_codes": remainingCodes,
	})
}

// GetRecoveryCodes generates new recovery codes
func (h *TOTPHandler) GetRecoveryCodes(c *gin.Context) {
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

	if !user.TOTPEnabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP not enabled"})
		return
	}

	codes, err := h.generateRecoveryCodes(c, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.RecoveryCodesResponse{
		Codes: codes,
	})
}

// GetStatus returns current TOTP status
func (h *TOTPHandler) GetStatus(c *gin.Context) {
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

	remainingCodes := 0
	if user.TOTPEnabled {
		remainingCodes, _ = h.totpRepo.GetRecoveryCodesCount(c.Request.Context(), userID)
	}

	c.JSON(http.StatusOK, gin.H{
		"totp_enabled":           user.TOTPEnabled,
		"remaining_recovery_codes": remainingCodes,
	})
}

// Helper functions

func (h *TOTPHandler) generateRecoveryCodes(c *gin.Context, userID uuid.UUID) ([]string, error) {
	codes := make([]string, RecoveryCodeCount)
	for i := 0; i < RecoveryCodeCount; i++ {
		code, err := generateRandomCode(RecoveryCodeLength)
		if err != nil {
			return nil, err
		}
		codes[i] = code
	}

	// Store codes
	if err := h.totpRepo.CreateRecoveryCodes(c.Request.Context(), userID, codes); err != nil {
		return nil, err
	}

	return codes, nil
}

func generateRandomCode(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base32.StdEncoding.EncodeToString(bytes)[:length], nil
}
