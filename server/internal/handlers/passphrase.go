package handlers

import (
	"encoding/base64"
	"net/http"
	"regexp"
	"unicode"

	"github.com/gin-gonic/gin"

	"github.com/sprobst76/vibedtracker-server/internal/middleware"
	"github.com/sprobst76/vibedtracker-server/internal/models"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

type PassphraseHandler struct {
	users            *repository.UserRepository
	recoveryRepo     *repository.PassphraseRecoveryRepository
}

func NewPassphraseHandler(users *repository.UserRepository, recoveryRepo *repository.PassphraseRecoveryRepository) *PassphraseHandler {
	return &PassphraseHandler{
		users:        users,
		recoveryRepo: recoveryRepo,
	}
}

// SetKey stores the encryption key info and generates recovery codes
func (h *PassphraseHandler) SetKey(c *gin.Context) {
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
	keySalt, err := base64.StdEncoding.DecodeString(req.KeySalt)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key_salt format"})
		return
	}
	keyHash, err := base64.StdEncoding.DecodeString(req.KeyVerificationHash)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key_verification_hash format"})
		return
	}

	// Check if user already has key info (update vs first setup)
	user, err := h.users.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user"})
		return
	}
	isFirstSetup := user.KeySalt == nil || len(user.KeySalt) == 0

	// Store key info
	if err := h.users.SetKeyInfo(c.Request.Context(), userID, keySalt, keyHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to set key info"})
		return
	}

	// Generate recovery codes on first setup
	var recoveryCodes []string
	if isFirstSetup {
		codes, err := repository.GeneratePassphraseRecoveryCodes()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate recovery codes"})
			return
		}
		if err := h.recoveryRepo.CreateRecoveryCodes(c.Request.Context(), userID, codes); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store recovery codes"})
			return
		}
		recoveryCodes = codes
	}

	c.JSON(http.StatusOK, models.SetKeyResponse{
		Message:       "key info saved",
		RecoveryCodes: recoveryCodes,
	})
}

// RegenerateRecoveryCodes generates new recovery codes (invalidates old ones)
func (h *PassphraseHandler) RegenerateRecoveryCodes(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Check if user has encryption set up
	user, err := h.users.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user"})
		return
	}
	if user.KeySalt == nil || len(user.KeySalt) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "encryption not set up"})
		return
	}

	// Generate new codes
	codes, err := repository.GeneratePassphraseRecoveryCodes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate recovery codes"})
		return
	}
	if err := h.recoveryRepo.CreateRecoveryCodes(c.Request.Context(), userID, codes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.RecoveryCodesResponse{
		Codes: codes,
	})
}

// GetRecoveryStatus returns the status of recovery codes
func (h *PassphraseHandler) GetRecoveryStatus(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	count, err := h.recoveryRepo.GetRecoveryCodesCount(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get recovery status"})
		return
	}

	c.JSON(http.StatusOK, models.PassphraseRecoveryStatusResponse{
		HasRecoveryCodes: count > 0,
		RemainingCodes:   count,
	})
}

// ResetWithRecoveryCode validates a recovery code and allows setting new key info
func (h *PassphraseHandler) ResetWithRecoveryCode(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.PassphraseResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get client IP for rate limiting
	clientIP := c.ClientIP()

	// Check rate limit
	if err := h.recoveryRepo.CheckRateLimit(c.Request.Context(), userID, clientIP); err != nil {
		if err == repository.ErrPassphraseTooManyAttempts {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many attempts, please try again later"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check rate limit"})
		return
	}

	// Validate recovery code
	if err := h.recoveryRepo.ValidateRecoveryCode(c.Request.Context(), userID, req.RecoveryCode); err != nil {
		// Record failed attempt
		h.recoveryRepo.RecordAttempt(c.Request.Context(), userID, clientIP, false)

		if err == repository.ErrPassphraseRecoveryCodeNotFound {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid recovery code"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to validate recovery code"})
		return
	}

	// Record successful attempt
	h.recoveryRepo.RecordAttempt(c.Request.Context(), userID, clientIP, true)

	// Decode new key info
	newKeySalt, err := base64.StdEncoding.DecodeString(req.NewKeySalt)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid new_key_salt format"})
		return
	}
	newKeyHash, err := base64.StdEncoding.DecodeString(req.NewKeyVerificationHash)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid new_key_verification_hash format"})
		return
	}

	// Update key info
	if err := h.users.SetKeyInfo(c.Request.Context(), userID, newKeySalt, newKeyHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update key info"})
		return
	}

	// Generate new recovery codes
	codes, err := repository.GeneratePassphraseRecoveryCodes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate new recovery codes"})
		return
	}
	if err := h.recoveryRepo.CreateRecoveryCodes(c.Request.Context(), userID, codes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store new recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.SetKeyResponse{
		Message:       "passphrase reset successful",
		RecoveryCodes: codes,
	})
}

// ValidatePassphraseStrength validates passphrase meets requirements
// This is a helper used by the client - not an API endpoint
func ValidatePassphraseStrength(passphrase string) (bool, []string) {
	var errors []string

	// Minimum length: 12 characters
	if len(passphrase) < 12 {
		errors = append(errors, "mindestens 12 Zeichen")
	}

	// At least one uppercase letter
	hasUpper := false
	for _, r := range passphrase {
		if unicode.IsUpper(r) {
			hasUpper = true
			break
		}
	}
	if !hasUpper {
		errors = append(errors, "mindestens ein Großbuchstabe")
	}

	// At least one lowercase letter
	hasLower := false
	for _, r := range passphrase {
		if unicode.IsLower(r) {
			hasLower = true
			break
		}
	}
	if !hasLower {
		errors = append(errors, "mindestens ein Kleinbuchstabe")
	}

	// At least one digit
	hasDigit := false
	for _, r := range passphrase {
		if unicode.IsDigit(r) {
			hasDigit = true
			break
		}
	}
	if !hasDigit {
		errors = append(errors, "mindestens eine Zahl")
	}

	// At least one special character
	specialChars := regexp.MustCompile(`[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~]`)
	if !specialChars.MatchString(passphrase) {
		errors = append(errors, "mindestens ein Sonderzeichen")
	}

	return len(errors) == 0, errors
}
