package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// Load .env file if exists
	godotenv.Load()

	// Get port from environment or default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Create Gin router
	r := gin.Default()

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"service": "vibedtracker-api",
		})
	})

	// API v1 routes
	v1 := r.Group("/api/v1")
	{
		// Auth routes
		auth := v1.Group("/auth")
		{
			auth.POST("/register", handleRegister)
			auth.POST("/login", handleLogin)
			auth.POST("/refresh", handleRefresh)
		}

		// Protected routes (require JWT)
		protected := v1.Group("/")
		protected.Use(authMiddleware())
		{
			// Sync routes
			sync := protected.Group("/sync")
			{
				sync.GET("/pull", handleSyncPull)
				sync.POST("/push", handleSyncPush)
				sync.GET("/status", handleSyncStatus)
			}

			// Device routes
			devices := protected.Group("/devices")
			{
				devices.GET("", handleGetDevices)
				devices.POST("", handleRegisterDevice)
				devices.DELETE("/:id", handleDeleteDevice)
			}
		}

		// Admin routes (require admin role)
		admin := v1.Group("/admin")
		admin.Use(authMiddleware(), adminMiddleware())
		{
			admin.GET("/users", handleListUsers)
			admin.GET("/users/:id", handleGetUser)
			admin.POST("/users/:id/approve", handleApproveUser)
			admin.POST("/users/:id/block", handleBlockUser)
			admin.DELETE("/users/:id", handleDeleteUser)
			admin.GET("/stats", handleStats)
		}
	}

	// Serve admin dashboard
	r.Static("/admin", "./admin")

	log.Printf("VibedTracker API starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// Placeholder handlers - to be implemented

func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// TODO: Implement JWT verification
		c.Next()
	}
}

func adminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// TODO: Check admin role
		c.Next()
	}
}

func handleRegister(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleLogin(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleRefresh(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleSyncPull(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleSyncPush(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleSyncStatus(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleGetDevices(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleRegisterDevice(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleDeleteDevice(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleListUsers(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleGetUser(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleApproveUser(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleBlockUser(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleDeleteUser(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}

func handleStats(c *gin.Context) {
	c.JSON(501, gin.H{"error": "not implemented"})
}
