package handlers

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"html/template"
	"log"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedtracker-server/internal/config"
	"github.com/sprobst76/vibedtracker-server/internal/models"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

type WebHandler struct {
	cfg                     *config.Config
	templates               *template.Template
	userRepo                *repository.UserRepository
	tokenRepo               *repository.TokenRepository
	totpRepo                *repository.TOTPRepository
	syncRepo                *repository.SyncRepository
	deviceRepo              *repository.DeviceRepository
	passphraseRecoveryRepo  *repository.PassphraseRecoveryRepository
}

func NewWebHandler(
	cfg *config.Config,
	userRepo *repository.UserRepository,
	tokenRepo *repository.TokenRepository,
	totpRepo *repository.TOTPRepository,
	syncRepo *repository.SyncRepository,
	deviceRepo *repository.DeviceRepository,
	passphraseRecoveryRepo *repository.PassphraseRecoveryRepository,
) *WebHandler {
	// Custom template functions
	funcMap := template.FuncMap{
		"upper": strings.ToUpper,
		"lower": strings.ToLower,
	}

	// Collect all template files
	var allTemplates []string

	// Main templates
	mainTemplates, err := filepath.Glob(filepath.Join("templates", "*.html"))
	if err != nil {
		log.Printf("Warning: Failed to find main templates: %v", err)
	} else {
		allTemplates = append(allTemplates, mainTemplates...)
	}

	// Partial templates
	partialTemplates, err := filepath.Glob(filepath.Join("templates", "partials", "*.html"))
	if err != nil {
		log.Printf("Warning: Failed to find partial templates: %v", err)
	} else {
		allTemplates = append(allTemplates, partialTemplates...)
	}

	// Parse all templates together with custom functions
	var tmpl *template.Template
	if len(allTemplates) > 0 {
		tmpl, err = template.New("").Funcs(funcMap).ParseFiles(allTemplates...)
		if err != nil {
			log.Printf("Warning: Failed to parse templates: %v", err)
		} else {
			log.Printf("Loaded %d templates", len(allTemplates))
		}
	}

	// Log loaded templates for debugging
	if tmpl != nil {
		var names []string
		for _, t := range tmpl.Templates() {
			names = append(names, t.Name())
		}
		log.Printf("Available templates: %v", names)
	}

	return &WebHandler{
		cfg:                    cfg,
		templates:              tmpl,
		userRepo:               userRepo,
		tokenRepo:              tokenRepo,
		totpRepo:               totpRepo,
		syncRepo:               syncRepo,
		deviceRepo:             deviceRepo,
		passphraseRecoveryRepo: passphraseRecoveryRepo,
	}
}

// LoginPage renders the login page
func (h *WebHandler) LoginPage(c *gin.Context) {
	h.renderTemplate(c, "login.html", gin.H{})
}

// Login handles login form submission
func (h *WebHandler) Login(c *gin.Context) {
	email := strings.ToLower(strings.TrimSpace(c.PostForm("email")))
	password := c.PostForm("password")

	// Validate input
	if email == "" || password == "" {
		h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
			"Error": "E-Mail und Passwort sind erforderlich",
			"Email": email,
		})
		return
	}

	// Find user
	user, err := h.userRepo.GetByEmail(c.Request.Context(), email)
	if err != nil || user == nil {
		h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
			"Error": "Ungültige Anmeldedaten",
			"Email": email,
		})
		return
	}

	// Check password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
			"Error": "Ungültige Anmeldedaten",
			"Email": email,
		})
		return
	}

	// Check if user is approved
	if !user.IsApproved {
		h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
			"Error": "Dein Account wartet noch auf Freischaltung",
			"Email": email,
		})
		return
	}

	if user.IsBlocked {
		h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
			"Error": "Dein Account wurde gesperrt",
			"Email": email,
		})
		return
	}

	// Check if TOTP is enabled
	if user.TOTPEnabled {
		// Generate temp token for TOTP verification
		// We need a device ID - create a web device
		device, err := h.deviceRepo.Create(c.Request.Context(), user.ID, &models.RegisterDeviceRequest{
			DeviceName: "Web Browser",
			DeviceType: "web",
		})
		if err != nil {
			h.renderFormOrFull(c, "login-form.html", "login.html", gin.H{
				"Error": "Fehler beim Anmelden",
				"Email": email,
			})
			return
		}
		tempToken := h.totpRepo.CreateTempToken(user.ID, device.ID)
		h.renderTemplate(c, "totp.html", gin.H{
			"TempToken": tempToken,
		})
		return
	}

	// No TOTP - create session and redirect to dashboard
	h.createSessionAndRedirect(c, user.ID, user.Email)
}

// TOTPVerify handles TOTP verification
func (h *WebHandler) TOTPVerify(c *gin.Context) {
	tempTokenStr := c.PostForm("temp_token")
	code := c.PostForm("code")

	if tempTokenStr == "" || code == "" {
		h.renderTemplate(c, "totp.html", gin.H{
			"Error":     "Code ist erforderlich",
			"TempToken": tempTokenStr,
		})
		return
	}

	// Validate temp token
	tempToken, err := h.totpRepo.GetTempToken(tempTokenStr)
	if err != nil {
		// Token expired or invalid - back to login
		h.renderTemplate(c, "login.html", gin.H{
			"Error": "Sitzung abgelaufen, bitte erneut anmelden",
		})
		return
	}

	// Get user
	user, err := h.userRepo.GetByID(c.Request.Context(), tempToken.UserID)
	if err != nil || user == nil {
		h.renderTemplate(c, "login.html", gin.H{
			"Error": "Benutzer nicht gefunden",
		})
		return
	}

	// Verify TOTP code
	if !totp.Validate(code, string(user.TOTPSecret)) {
		h.renderTemplate(c, "totp.html", gin.H{
			"Error":     "Ungültiger Code",
			"TempToken": tempTokenStr,
		})
		return
	}

	// TOTP valid - delete temp token and create session
	h.totpRepo.DeleteTempToken(tempTokenStr)
	h.createSessionAndRedirect(c, user.ID, user.Email)
}

// Dashboard renders the dashboard
func (h *WebHandler) Dashboard(c *gin.Context) {
	userID, _ := c.Get("user_id")
	email, _ := c.Get("user_email")
	isAdmin, _ := c.Get("user_is_admin")

	// Check if user has encryption set up
	hasEncryption := false
	if uid, ok := userID.(uuid.UUID); ok {
		user, err := h.userRepo.GetByID(c.Request.Context(), uid)
		if err == nil && user != nil {
			hasEncryption = len(user.KeySalt) > 0 && len(user.KeyVerificationHash) > 0
		}
	}

	h.renderTemplate(c, "dashboard.html", gin.H{
		"User": gin.H{
			"Email":   email,
			"IsAdmin": isAdmin,
		},
		"HasEncryption": hasEncryption,
		"Stats": gin.H{
			"TodayHours": "0:00",
			"WeekHours":  "0:00",
			"MonthHours": "0:00",
		},
	})
}

// Unlock renders the unlock page for entering passphrase
func (h *WebHandler) Unlock(c *gin.Context) {
	userID, _ := c.Get("user_id")
	email, _ := c.Get("user_email")

	// Get user to check for encryption keys
	user, err := h.userRepo.GetByID(c.Request.Context(), userID.(uuid.UUID))
	if err != nil || user == nil {
		c.Redirect(http.StatusSeeOther, "/web/login")
		return
	}

	// Check if user has encryption set up
	hasEncryption := len(user.KeySalt) > 0 && len(user.KeyVerificationHash) > 0

	data := gin.H{
		"User": gin.H{
			"Email": email,
		},
		"HasEncryption": hasEncryption,
	}

	if hasEncryption {
		data["Salt"] = base64.StdEncoding.EncodeToString(user.KeySalt)
		data["VerificationHash"] = base64.StdEncoding.EncodeToString(user.KeyVerificationHash)
	}

	h.renderTemplate(c, "unlock.html", data)
}

// GetEncryptedData returns encrypted time entries as JSON for client-side decryption
func (h *WebHandler) GetEncryptedData(c *gin.Context) {
	userID, _ := c.Get("user_id")
	dataType := c.Query("type")
	if dataType == "" {
		dataType = "work_entry" // Default to work entries
	}

	// Get all items (since epoch)
	items, err := h.syncRepo.PullItems(c.Request.Context(), userID.(uuid.UUID), time.Unix(0, 0), dataType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load data"})
		return
	}

	// Filter out deleted items
	var activeItems []models.SyncPullItem
	for _, item := range items {
		if !item.Deleted {
			activeItems = append(activeItems, item)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"items": activeItems,
		"count": len(activeItems),
	})
}

// SaveEncryptedEntry saves a new or updated encrypted entry
func (h *WebHandler) SaveEncryptedEntry(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		LocalID       string `json:"local_id" binding:"required"`
		EncryptedBlob string `json:"encrypted_blob" binding:"required"`
		Nonce         string `json:"nonce" binding:"required"`
		DataType      string `json:"data_type"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	if req.DataType == "" {
		req.DataType = "work_entry"
	}

	// Create a web device ID for this operation
	device, err := h.deviceRepo.Create(c.Request.Context(), userID.(uuid.UUID), &models.RegisterDeviceRequest{
		DeviceName: "Web Browser",
		DeviceType: "web",
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		return
	}

	// Push the item
	items := []models.SyncPushItem{{
		DataType:      req.DataType,
		LocalID:       req.LocalID,
		EncryptedBlob: req.EncryptedBlob,
		Nonce:         req.Nonce,
		SchemaVersion: 1,
		Deleted:       false,
	}}

	if err := h.syncRepo.PushItems(c.Request.Context(), userID.(uuid.UUID), device.ID, items); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save entry"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"local_id": req.LocalID,
	})
}

// DeleteEncryptedEntry soft-deletes an encrypted entry
func (h *WebHandler) DeleteEncryptedEntry(c *gin.Context) {
	userID, _ := c.Get("user_id")
	localID := c.Param("id")

	if localID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Missing entry ID"})
		return
	}

	// Create a web device ID for this operation
	device, err := h.deviceRepo.Create(c.Request.Context(), userID.(uuid.UUID), &models.RegisterDeviceRequest{
		DeviceName: "Web Browser",
		DeviceType: "web",
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		return
	}

	// Push a delete operation (we need to provide dummy encrypted data for soft delete)
	items := []models.SyncPushItem{{
		DataType:      "work_entry",
		LocalID:       localID,
		EncryptedBlob: "", // Empty for delete
		Nonce:         "",
		SchemaVersion: 1,
		Deleted:       true,
	}}

	if err := h.syncRepo.PushItems(c.Request.Context(), userID.(uuid.UUID), device.ID, items); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete entry"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"local_id": localID,
	})
}

// Logout handles logout
func (h *WebHandler) Logout(c *gin.Context) {
	// Clear session cookie
	c.SetCookie("session", "", -1, "/", "", true, true)
	c.Redirect(http.StatusSeeOther, "/web/login")
}

// generateSessionToken creates a random session token
func generateSessionToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// createSessionAndRedirect creates a session cookie and redirects to dashboard
func (h *WebHandler) createSessionAndRedirect(c *gin.Context, userID uuid.UUID, email string) {
	// Create or get a web device for this user
	device, err := h.deviceRepo.Create(c.Request.Context(), userID, &models.RegisterDeviceRequest{
		DeviceName: "Web Browser",
		DeviceType: "web",
	})
	if err != nil {
		h.renderTemplate(c, "login.html", gin.H{
			"Error": "Fehler beim Erstellen der Sitzung",
		})
		return
	}

	// Generate session token
	sessionToken := generateSessionToken()

	// Store in database
	_, err = h.tokenRepo.Create(c.Request.Context(), userID, device.ID, sessionToken, time.Now().Add(24*time.Hour))
	if err != nil {
		h.renderTemplate(c, "login.html", gin.H{
			"Error": "Fehler beim Erstellen der Sitzung",
		})
		return
	}

	// Set secure cookie
	c.SetCookie("session", sessionToken, 86400, "/", "", true, true)

	// Redirect to dashboard (HX-Redirect for HTMX)
	if c.GetHeader("HX-Request") == "true" {
		c.Header("HX-Redirect", "/web/dashboard")
		c.Status(http.StatusOK)
		return
	}
	c.Redirect(http.StatusSeeOther, "/web/dashboard")
}

// renderTemplate renders a full HTML template
func (h *WebHandler) renderTemplate(c *gin.Context, name string, data gin.H) {
	if h.templates == nil {
		c.String(http.StatusInternalServerError, "Templates not loaded")
		return
	}

	c.Header("Content-Type", "text/html; charset=utf-8")
	err := h.templates.ExecuteTemplate(c.Writer, name, data)
	if err != nil {
		log.Printf("Template error (%s): %v", name, err)
		c.String(http.StatusInternalServerError, "Template error: %v", err)
	}
}

// renderFormOrFull renders partial for HTMX or full page for normal requests
func (h *WebHandler) renderFormOrFull(c *gin.Context, partialName, fullName string, data gin.H) {
	if c.GetHeader("HX-Request") == "true" {
		h.renderTemplate(c, partialName, data)
	} else {
		h.renderTemplate(c, fullName, data)
	}
}

// ============================================================
// Admin Handlers
// ============================================================

// Admin renders the admin dashboard
func (h *WebHandler) Admin(c *gin.Context) {
	email, _ := c.Get("user_email")
	h.renderTemplate(c, "admin.html", gin.H{
		"User": gin.H{
			"Email": email,
		},
	})
}

// AdminStats returns the stats partial
func (h *WebHandler) AdminStats(c *gin.Context) {
	stats, err := h.userRepo.GetStats(c.Request.Context())
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading stats")
		return
	}
	h.renderTemplate(c, "admin-stats.html", gin.H{
		"Stats": stats,
	})
}

// AdminUsers returns the users list partial
func (h *WebHandler) AdminUsers(c *gin.Context) {
	users, err := h.userRepo.List(c.Request.Context())
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading users")
		return
	}
	h.renderTemplate(c, "admin-users.html", gin.H{
		"Users": users,
	})
}

// AdminApproveUser approves a user
func (h *WebHandler) AdminApproveUser(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.String(http.StatusBadRequest, "Invalid user ID")
		return
	}

	if err := h.userRepo.Approve(c.Request.Context(), id); err != nil {
		c.String(http.StatusInternalServerError, "Error approving user")
		return
	}

	// Return updated user row
	user, err := h.userRepo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading user")
		return
	}
	h.renderTemplate(c, "admin-user-row.html", gin.H{
		"ID":          user.ID,
		"Email":       user.Email,
		"IsApproved":  user.IsApproved,
		"IsAdmin":     user.IsAdmin,
		"IsBlocked":   user.IsBlocked,
		"TOTPEnabled": user.TOTPEnabled,
		"CreatedAt":   user.CreatedAt,
	})
}

// AdminBlockUser blocks a user
func (h *WebHandler) AdminBlockUser(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.String(http.StatusBadRequest, "Invalid user ID")
		return
	}

	if err := h.userRepo.Block(c.Request.Context(), id); err != nil {
		c.String(http.StatusInternalServerError, "Error blocking user")
		return
	}

	// Revoke all tokens for this user
	if err := h.tokenRepo.RevokeByUserID(c.Request.Context(), id); err != nil {
		// Log but don't fail
	}

	// Return updated user row
	user, err := h.userRepo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading user")
		return
	}
	h.renderTemplate(c, "admin-user-row.html", gin.H{
		"ID":          user.ID,
		"Email":       user.Email,
		"IsApproved":  user.IsApproved,
		"IsAdmin":     user.IsAdmin,
		"IsBlocked":   user.IsBlocked,
		"TOTPEnabled": user.TOTPEnabled,
		"CreatedAt":   user.CreatedAt,
	})
}

// AdminUnblockUser unblocks a user
func (h *WebHandler) AdminUnblockUser(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.String(http.StatusBadRequest, "Invalid user ID")
		return
	}

	if err := h.userRepo.Unblock(c.Request.Context(), id); err != nil {
		c.String(http.StatusInternalServerError, "Error unblocking user")
		return
	}

	// Return updated user row
	user, err := h.userRepo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading user")
		return
	}
	h.renderTemplate(c, "admin-user-row.html", gin.H{
		"ID":          user.ID,
		"Email":       user.Email,
		"IsApproved":  user.IsApproved,
		"IsAdmin":     user.IsAdmin,
		"IsBlocked":   user.IsBlocked,
		"TOTPEnabled": user.TOTPEnabled,
		"CreatedAt":   user.CreatedAt,
	})
}

// AdminDeleteUser deletes a user
func (h *WebHandler) AdminDeleteUser(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.String(http.StatusBadRequest, "Invalid user ID")
		return
	}

	// Don't allow deleting admins
	user, err := h.userRepo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading user")
		return
	}
	if user.IsAdmin {
		c.String(http.StatusForbidden, "Cannot delete admin users")
		return
	}

	// Revoke all tokens first
	h.tokenRepo.RevokeByUserID(c.Request.Context(), id)

	if err := h.userRepo.Delete(c.Request.Context(), id); err != nil {
		c.String(http.StatusInternalServerError, "Error deleting user")
		return
	}

	// Return empty response (row will be removed)
	c.String(http.StatusOK, "")
}

// AdminDevices returns the devices list partial
func (h *WebHandler) AdminDevices(c *gin.Context) {
	devices, err := h.deviceRepo.ListAll(c.Request.Context())
	if err != nil {
		c.String(http.StatusInternalServerError, "Error loading devices")
		return
	}
	h.renderTemplate(c, "admin-devices.html", gin.H{
		"Devices": devices,
	})
}

// AdminDeleteDevice deletes a device
func (h *WebHandler) AdminDeleteDevice(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.String(http.StatusBadRequest, "Invalid device ID")
		return
	}

	// Revoke all tokens for this device
	h.tokenRepo.RevokeByDeviceID(c.Request.Context(), id)

	if err := h.deviceRepo.Delete(c.Request.Context(), id); err != nil {
		c.String(http.StatusInternalServerError, "Error deleting device")
		return
	}

	// Return empty response (row will be removed)
	c.String(http.StatusOK, "")
}

// ============================================================
// Vacation Handlers
// ============================================================

// Vacation renders the vacation/absence management page
func (h *WebHandler) Vacation(c *gin.Context) {
	userID, _ := c.Get("user_id")
	email, _ := c.Get("user_email")
	isAdmin, _ := c.Get("user_is_admin")

	// Check if user has encryption set up
	hasEncryption := false
	if uid, ok := userID.(uuid.UUID); ok {
		user, err := h.userRepo.GetByID(c.Request.Context(), uid)
		if err == nil && user != nil {
			hasEncryption = len(user.KeySalt) > 0 && len(user.KeyVerificationHash) > 0
		}
	}

	h.renderTemplate(c, "vacation.html", gin.H{
		"User": gin.H{
			"Email":   email,
			"IsAdmin": isAdmin,
		},
		"HasEncryption": hasEncryption,
	})
}

// SaveVacation saves a new or updated vacation entry
func (h *WebHandler) SaveVacation(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		LocalID       string `json:"local_id" binding:"required"`
		EncryptedBlob string `json:"encrypted_blob" binding:"required"`
		Nonce         string `json:"nonce" binding:"required"`
		DataType      string `json:"data_type"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	if req.DataType == "" {
		req.DataType = "vacation"
	}

	// Create a web device ID for this operation
	device, err := h.deviceRepo.Create(c.Request.Context(), userID.(uuid.UUID), &models.RegisterDeviceRequest{
		DeviceName: "Web Browser",
		DeviceType: "web",
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		return
	}

	// Push the item
	items := []models.SyncPushItem{{
		DataType:      req.DataType,
		LocalID:       req.LocalID,
		EncryptedBlob: req.EncryptedBlob,
		Nonce:         req.Nonce,
		SchemaVersion: 1,
		Deleted:       false,
	}}

	if err := h.syncRepo.PushItems(c.Request.Context(), userID.(uuid.UUID), device.ID, items); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save vacation"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"local_id": req.LocalID,
	})
}

// DeleteVacation soft-deletes a vacation entry
func (h *WebHandler) DeleteVacation(c *gin.Context) {
	userID, _ := c.Get("user_id")
	localID := c.Param("id")

	if localID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Missing vacation ID"})
		return
	}

	// Create a web device ID for this operation
	device, err := h.deviceRepo.Create(c.Request.Context(), userID.(uuid.UUID), &models.RegisterDeviceRequest{
		DeviceName: "Web Browser",
		DeviceType: "web",
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get device"})
		return
	}

	// Push a delete operation
	items := []models.SyncPushItem{{
		DataType:      "vacation",
		LocalID:       localID,
		EncryptedBlob: "",
		Nonce:         "",
		SchemaVersion: 1,
		Deleted:       true,
	}}

	if err := h.syncRepo.PushItems(c.Request.Context(), userID.(uuid.UUID), device.ID, items); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete vacation"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"local_id": localID,
	})
}

// ============================================================
// Settings Handler
// ============================================================

// Settings renders the settings page
func (h *WebHandler) Settings(c *gin.Context) {
	email, _ := c.Get("user_email")
	isAdmin, _ := c.Get("user_is_admin")

	h.renderTemplate(c, "settings.html", gin.H{
		"User": gin.H{
			"Email":   email,
			"IsAdmin": isAdmin,
		},
	})
}

// ============================================================
// Passphrase Recovery Handler
// ============================================================

// PassphraseReset resets the passphrase using a recovery code
func (h *WebHandler) PassphraseReset(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
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
	if err := h.passphraseRecoveryRepo.CheckRateLimit(c.Request.Context(), userID.(uuid.UUID), clientIP); err != nil {
		if err == repository.ErrPassphraseTooManyAttempts {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many attempts, please try again later"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check rate limit"})
		return
	}

	// Validate recovery code
	if err := h.passphraseRecoveryRepo.ValidateRecoveryCode(c.Request.Context(), userID.(uuid.UUID), req.RecoveryCode); err != nil {
		// Record failed attempt
		h.passphraseRecoveryRepo.RecordAttempt(c.Request.Context(), userID.(uuid.UUID), clientIP, false)

		if err == repository.ErrPassphraseRecoveryCodeNotFound {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid recovery code"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to validate recovery code"})
		return
	}

	// Record successful attempt
	h.passphraseRecoveryRepo.RecordAttempt(c.Request.Context(), userID.(uuid.UUID), clientIP, true)

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
	if err := h.userRepo.SetKeyInfo(c.Request.Context(), userID.(uuid.UUID), newKeySalt, newKeyHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update key info"})
		return
	}

	// Generate new recovery codes
	codes, err := repository.GeneratePassphraseRecoveryCodes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate new recovery codes"})
		return
	}
	if err := h.passphraseRecoveryRepo.CreateRecoveryCodes(c.Request.Context(), userID.(uuid.UUID), codes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store new recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.SetKeyResponse{
		Message:       "passphrase reset successful",
		RecoveryCodes: codes,
	})
}
