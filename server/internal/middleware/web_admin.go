package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// WebAdminMiddleware checks if the current web user is admin
// Must be used after WebAuthMiddleware
func WebAdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		isAdmin, exists := c.Get("user_is_admin")
		if !exists || !isAdmin.(bool) {
			c.Redirect(http.StatusSeeOther, "/web/dashboard")
			c.Abort()
			return
		}
		c.Next()
	}
}
