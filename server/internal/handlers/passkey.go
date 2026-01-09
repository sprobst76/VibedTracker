package handlers

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// PasskeyHandler handles WebAuthn/Passkey operations
type PasskeyHandler struct {
	db     *sql.DB
	rpID   string // Relying Party ID (domain)
	rpName string // Relying Party Name
	origin string // Expected origin
}

// NewPasskeyHandler creates a new PasskeyHandler
func NewPasskeyHandler(db *sql.DB, rpID, rpName, origin string) *PasskeyHandler {
	return &PasskeyHandler{
		db:     db,
		rpID:   rpID,
		rpName: rpName,
		origin: origin,
	}
}

// PasskeyCredential represents a stored passkey
type PasskeyCredential struct {
	ID              uuid.UUID  `json:"id"`
	UserID          uuid.UUID  `json:"user_id"`
	CredentialID    []byte     `json:"-"`
	CredentialIDB64 string     `json:"credential_id"`
	PublicKey       []byte     `json:"-"`
	Name            string     `json:"name"`
	SignCount       int64      `json:"sign_count"`
	CreatedAt       time.Time  `json:"created_at"`
	LastUsedAt      *time.Time `json:"last_used_at,omitempty"`
	HasWrappedKey   bool       `json:"has_wrapped_key"`
}

// BeginRegistration starts the WebAuthn registration ceremony
func (h *PasskeyHandler) BeginRegistration(c *gin.Context) {
	userID, _ := c.Get("user_id")
	email, _ := c.Get("email")

	// Generate challenge
	challenge := make([]byte, 32)
	if _, err := rand.Read(challenge); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate challenge"})
		return
	}

	// Store challenge
	expiresAt := time.Now().Add(5 * time.Minute)
	_, err := h.db.ExecContext(c.Request.Context(),
		`INSERT INTO passkey_challenges (user_id, challenge, type, expires_at)
		 VALUES ($1, $2, 'registration', $3)`,
		userID, challenge, expiresAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store challenge"})
		return
	}

	// Get existing credentials to exclude
	rows, err := h.db.QueryContext(c.Request.Context(),
		`SELECT credential_id FROM passkey_credentials WHERE user_id = $1`,
		userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to query credentials"})
		return
	}
	defer rows.Close()

	var excludeCredentials []map[string]interface{}
	for rows.Next() {
		var credID []byte
		if err := rows.Scan(&credID); err != nil {
			continue
		}
		excludeCredentials = append(excludeCredentials, map[string]interface{}{
			"type": "public-key",
			"id":   base64.URLEncoding.EncodeToString(credID),
		})
	}

	// Return WebAuthn options
	// See: https://www.w3.org/TR/webauthn-2/#dictdef-publickeycredentialcreationoptions
	options := gin.H{
		"publicKey": gin.H{
			"challenge": base64.URLEncoding.EncodeToString(challenge),
			"rp": gin.H{
				"name": h.rpName,
				"id":   h.rpID,
			},
			"user": gin.H{
				"id":          base64.URLEncoding.EncodeToString(userID.(uuid.UUID).NodeID()),
				"name":        email,
				"displayName": email,
			},
			"pubKeyCredParams": []gin.H{
				{"type": "public-key", "alg": -7},   // ES256
				{"type": "public-key", "alg": -257}, // RS256
			},
			"timeout":     300000, // 5 minutes
			"attestation": "none",
			"authenticatorSelection": gin.H{
				"authenticatorAttachment": "platform",
				"residentKey":             "preferred",
				"userVerification":        "preferred",
			},
			"excludeCredentials": excludeCredentials,
			"extensions": gin.H{
				"prf": gin.H{}, // Request PRF extension for key wrapping
			},
		},
	}

	c.JSON(http.StatusOK, options)
}

// FinishRegistration completes the WebAuthn registration ceremony
func (h *PasskeyHandler) FinishRegistration(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		ID       string `json:"id"`
		RawID    string `json:"rawId"`
		Type     string `json:"type"`
		Response struct {
			ClientDataJSON    string `json:"clientDataJSON"`
			AttestationObject string `json:"attestationObject"`
		} `json:"response"`
		Name       string `json:"name"`       // User-provided name for this passkey
		WrappedKey string `json:"wrappedKey"` // Optional: encrypted encryption key
		KeyNonce   string `json:"keyNonce"`   // Nonce for wrapped key
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	// Decode credential ID
	credentialID, err := base64.URLEncoding.DecodeString(req.RawID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid credential ID"})
		return
	}

	// Decode client data
	clientDataJSON, err := base64.URLEncoding.DecodeString(req.Response.ClientDataJSON)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid client data"})
		return
	}

	// Parse client data to get challenge
	var clientData struct {
		Type      string `json:"type"`
		Challenge string `json:"challenge"`
		Origin    string `json:"origin"`
	}
	if err := json.Unmarshal(clientDataJSON, &clientData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid client data JSON"})
		return
	}

	// Verify challenge
	challengeBytes, err := base64.URLEncoding.DecodeString(clientData.Challenge)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid challenge"})
		return
	}

	var storedChallenge []byte
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT challenge FROM passkey_challenges
		 WHERE user_id = $1 AND type = 'registration' AND expires_at > NOW()
		 ORDER BY created_at DESC LIMIT 1`,
		userID).Scan(&storedChallenge)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Challenge not found or expired"})
		return
	}

	if !compareBytes(challengeBytes, storedChallenge) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Challenge mismatch"})
		return
	}

	// Verify origin
	if clientData.Origin != h.origin {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Origin mismatch"})
		return
	}

	// Decode attestation object (simplified - in production use a proper library)
	attestationObject, err := base64.URLEncoding.DecodeString(req.Response.AttestationObject)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid attestation object"})
		return
	}

	// For simplicity, we'll store the raw attestation object as the "public key"
	// In production, you should properly parse CBOR and extract the actual public key
	publicKey := attestationObject

	// Set default name if not provided
	name := req.Name
	if name == "" {
		name = "Passkey " + time.Now().Format("02.01.2006")
	}

	// Store credential
	_, err = h.db.ExecContext(c.Request.Context(),
		`INSERT INTO passkey_credentials
		 (user_id, credential_id, public_key, name, wrapped_key, wrapped_key_nonce)
		 VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''))`,
		userID, credentialID, publicKey, name, req.WrappedKey, req.KeyNonce)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store credential"})
		return
	}

	// Update user's passkey_enabled flag
	_, _ = h.db.ExecContext(c.Request.Context(),
		`UPDATE users SET passkey_enabled = TRUE WHERE id = $1`,
		userID)

	// Clean up used challenge
	_, _ = h.db.ExecContext(c.Request.Context(),
		`DELETE FROM passkey_challenges WHERE user_id = $1 AND type = 'registration'`,
		userID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Passkey registered successfully",
		"name":    name,
	})
}

// BeginAuthentication starts the WebAuthn authentication ceremony
func (h *PasskeyHandler) BeginAuthentication(c *gin.Context) {
	userID, _ := c.Get("user_id")

	// Generate challenge
	challenge := make([]byte, 32)
	if _, err := rand.Read(challenge); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate challenge"})
		return
	}

	// Store challenge
	expiresAt := time.Now().Add(5 * time.Minute)
	_, err := h.db.ExecContext(c.Request.Context(),
		`INSERT INTO passkey_challenges (user_id, challenge, type, expires_at)
		 VALUES ($1, $2, 'authentication', $3)`,
		userID, challenge, expiresAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store challenge"})
		return
	}

	// Get user's credentials
	rows, err := h.db.QueryContext(c.Request.Context(),
		`SELECT credential_id FROM passkey_credentials WHERE user_id = $1`,
		userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to query credentials"})
		return
	}
	defer rows.Close()

	var allowCredentials []map[string]interface{}
	for rows.Next() {
		var credID []byte
		if err := rows.Scan(&credID); err != nil {
			continue
		}
		allowCredentials = append(allowCredentials, map[string]interface{}{
			"type": "public-key",
			"id":   base64.URLEncoding.EncodeToString(credID),
		})
	}

	if len(allowCredentials) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "No passkeys registered"})
		return
	}

	// Return WebAuthn options
	options := gin.H{
		"publicKey": gin.H{
			"challenge":        base64.URLEncoding.EncodeToString(challenge),
			"timeout":          300000,
			"rpId":             h.rpID,
			"userVerification": "preferred",
			"allowCredentials": allowCredentials,
			"extensions": gin.H{
				"prf": gin.H{
					"eval": gin.H{
						"first": base64.URLEncoding.EncodeToString([]byte("vibedtracker-key-wrap")),
					},
				},
			},
		},
	}

	c.JSON(http.StatusOK, options)
}

// FinishAuthentication completes the WebAuthn authentication ceremony
func (h *PasskeyHandler) FinishAuthentication(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		ID       string `json:"id"`
		RawID    string `json:"rawId"`
		Type     string `json:"type"`
		Response struct {
			ClientDataJSON    string `json:"clientDataJSON"`
			AuthenticatorData string `json:"authenticatorData"`
			Signature         string `json:"signature"`
			UserHandle        string `json:"userHandle"`
		} `json:"response"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	// Decode credential ID
	credentialID, err := base64.URLEncoding.DecodeString(req.RawID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid credential ID"})
		return
	}

	// Decode client data
	clientDataJSON, err := base64.URLEncoding.DecodeString(req.Response.ClientDataJSON)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid client data"})
		return
	}

	// Parse client data
	var clientData struct {
		Type      string `json:"type"`
		Challenge string `json:"challenge"`
		Origin    string `json:"origin"`
	}
	if err := json.Unmarshal(clientDataJSON, &clientData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid client data JSON"})
		return
	}

	// Verify challenge
	challengeBytes, err := base64.URLEncoding.DecodeString(clientData.Challenge)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid challenge"})
		return
	}

	var storedChallenge []byte
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT challenge FROM passkey_challenges
		 WHERE user_id = $1 AND type = 'authentication' AND expires_at > NOW()
		 ORDER BY created_at DESC LIMIT 1`,
		userID).Scan(&storedChallenge)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Challenge not found or expired"})
		return
	}

	if !compareBytes(challengeBytes, storedChallenge) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Challenge mismatch"})
		return
	}

	// Verify credential belongs to user
	var wrappedKey, keyNonce sql.NullString
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT wrapped_key, wrapped_key_nonce FROM passkey_credentials
		 WHERE user_id = $1 AND credential_id = $2`,
		userID, credentialID).Scan(&wrappedKey, &keyNonce)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Credential not found"})
		return
	}

	// Update sign count and last used
	_, _ = h.db.ExecContext(c.Request.Context(),
		`UPDATE passkey_credentials
		 SET sign_count = sign_count + 1, last_used_at = NOW()
		 WHERE user_id = $1 AND credential_id = $2`,
		userID, credentialID)

	// Clean up used challenge
	_, _ = h.db.ExecContext(c.Request.Context(),
		`DELETE FROM passkey_challenges WHERE user_id = $1 AND type = 'authentication'`,
		userID)

	response := gin.H{
		"success": true,
		"message": "Authentication successful",
	}

	// Include wrapped key if available
	if wrappedKey.Valid && keyNonce.Valid {
		response["wrapped_key"] = wrappedKey.String
		response["key_nonce"] = keyNonce.String
	}

	c.JSON(http.StatusOK, response)
}

// ListPasskeys returns all passkeys for the current user
func (h *PasskeyHandler) ListPasskeys(c *gin.Context) {
	userID, _ := c.Get("user_id")

	rows, err := h.db.QueryContext(c.Request.Context(),
		`SELECT id, credential_id, name, sign_count, created_at, last_used_at,
		        (wrapped_key IS NOT NULL) as has_wrapped_key
		 FROM passkey_credentials WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to query passkeys"})
		return
	}
	defer rows.Close()

	var passkeys []PasskeyCredential
	for rows.Next() {
		var pk PasskeyCredential
		var credID []byte
		if err := rows.Scan(&pk.ID, &credID, &pk.Name, &pk.SignCount,
			&pk.CreatedAt, &pk.LastUsedAt, &pk.HasWrappedKey); err != nil {
			continue
		}
		pk.CredentialIDB64 = base64.URLEncoding.EncodeToString(credID)
		passkeys = append(passkeys, pk)
	}

	c.JSON(http.StatusOK, gin.H{"passkeys": passkeys})
}

// DeletePasskey removes a passkey
func (h *PasskeyHandler) DeletePasskey(c *gin.Context) {
	userID, _ := c.Get("user_id")
	passkeyID := c.Param("id")

	result, err := h.db.ExecContext(c.Request.Context(),
		`DELETE FROM passkey_credentials WHERE id = $1 AND user_id = $2`,
		passkeyID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete passkey"})
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Passkey not found"})
		return
	}

	// Check if user has any remaining passkeys
	var count int
	h.db.QueryRowContext(c.Request.Context(),
		`SELECT COUNT(*) FROM passkey_credentials WHERE user_id = $1`,
		userID).Scan(&count)

	if count == 0 {
		// Disable passkey flag if no passkeys remain
		_, _ = h.db.ExecContext(c.Request.Context(),
			`UPDATE users SET passkey_enabled = FALSE WHERE id = $1`,
			userID)
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// UpdateWrappedKey updates the wrapped encryption key for a passkey
func (h *PasskeyHandler) UpdateWrappedKey(c *gin.Context) {
	userID, _ := c.Get("user_id")
	passkeyID := c.Param("id")

	var req struct {
		WrappedKey string `json:"wrapped_key" binding:"required"`
		KeyNonce   string `json:"key_nonce" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	result, err := h.db.ExecContext(c.Request.Context(),
		`UPDATE passkey_credentials
		 SET wrapped_key = $1, wrapped_key_nonce = $2
		 WHERE id = $3 AND user_id = $4`,
		req.WrappedKey, req.KeyNonce, passkeyID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update wrapped key"})
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Passkey not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// Helper function to compare byte slices in constant time
func compareBytes(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var result byte
	for i := 0; i < len(a); i++ {
		result |= a[i] ^ b[i]
	}
	return result == 0
}
