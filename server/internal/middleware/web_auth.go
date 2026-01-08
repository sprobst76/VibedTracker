package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

// WebAuthMiddleware checks for a valid session cookie
func WebAuthMiddleware(tokenRepo *repository.TokenRepository, userRepo *repository.UserRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		sessionToken, err := c.Cookie("session")
		if err != nil || sessionToken == "" {
			c.Redirect(http.StatusSeeOther, "/web/login")
			c.Abort()
			return
		}

		// Validate token
		token, err := tokenRepo.GetByToken(c.Request.Context(), sessionToken)
		if err != nil || token == nil || token.Revoked {
			// Invalid or expired token
			c.SetCookie("session", "", -1, "/", "", true, true)
			c.Redirect(http.StatusSeeOther, "/web/login")
			c.Abort()
			return
		}

		// Get user
		user, err := userRepo.GetByID(c.Request.Context(), token.UserID)
		if err != nil || user == nil {
			c.SetCookie("session", "", -1, "/", "", true, true)
			c.Redirect(http.StatusSeeOther, "/web/login")
			c.Abort()
			return
		}

		// Check user status
		if !user.IsApproved || user.IsBlocked {
			c.SetCookie("session", "", -1, "/", "", true, true)
			c.Redirect(http.StatusSeeOther, "/web/login")
			c.Abort()
			return
		}

		// Set user info in context
		c.Set("user_id", user.ID)
		c.Set("user_email", user.Email)
		c.Set("user_is_admin", user.IsAdmin)

		c.Next()
	}
}
