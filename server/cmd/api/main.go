package main

import (
	"context"
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"github.com/sprobst76/vibedtracker-server/internal/config"
	"github.com/sprobst76/vibedtracker-server/internal/database"
	"github.com/sprobst76/vibedtracker-server/internal/handlers"
	"github.com/sprobst76/vibedtracker-server/internal/middleware"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

func main() {
	// Load .env file if exists
	godotenv.Load()

	// Load config
	cfg := config.Load()

	// Set JWT secret
	middleware.SetJWTSecret(cfg.JWTSecret)

	// Connect to database
	db, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()
	log.Println("Connected to database")

	// Create repositories
	userRepo := repository.NewUserRepository(db.Pool)
	tokenRepo := repository.NewTokenRepository(db.Pool)
	deviceRepo := repository.NewDeviceRepository(db.Pool)
	syncRepo := repository.NewSyncRepository(db.Pool)

	// Create handlers
	authHandler := handlers.NewAuthHandler(cfg, userRepo, tokenRepo, deviceRepo)
	syncHandler := handlers.NewSyncHandler(syncRepo, deviceRepo)
	deviceHandler := handlers.NewDeviceHandler(deviceRepo, tokenRepo)
	adminHandler := handlers.NewAdminHandler(userRepo, tokenRepo)

	// Create initial admin if configured
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	if err := authHandler.CreateInitialAdmin(ctx); err != nil {
		log.Printf("Warning: Failed to create initial admin: %v", err)
	}
	cancel()

	// Cleanup expired tokens periodically
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		for range ticker.C {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			if err := tokenRepo.CleanupExpired(ctx); err != nil {
				log.Printf("Failed to cleanup expired tokens: %v", err)
			}
			cancel()
		}
	}()

	// Create Gin router
	r := gin.Default()

	// CORS middleware
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

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
		// Auth routes (public)
		auth := v1.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.Refresh)
		}

		// Protected routes (require JWT)
		protected := v1.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			// User profile
			protected.GET("/me", authHandler.Me)
			protected.POST("/key", authHandler.SetKey)

			// Sync routes (require approval)
			sync := protected.Group("/sync")
			{
				sync.GET("/pull", syncHandler.Pull)
				sync.POST("/push", syncHandler.Push)
				sync.GET("/status", syncHandler.Status)
			}

			// Device routes
			devices := protected.Group("/devices")
			{
				devices.GET("", deviceHandler.List)
				devices.POST("", deviceHandler.Register)
				devices.DELETE("/:id", deviceHandler.Delete)
			}
		}

		// Admin routes (require admin role)
		admin := v1.Group("/admin")
		admin.Use(middleware.AuthMiddleware(), middleware.AdminMiddleware())
		{
			admin.GET("/users", adminHandler.ListUsers)
			admin.GET("/users/:id", adminHandler.GetUser)
			admin.POST("/users/:id/approve", adminHandler.ApproveUser)
			admin.POST("/users/:id/block", adminHandler.BlockUser)
			admin.POST("/users/:id/unblock", adminHandler.UnblockUser)
			admin.DELETE("/users/:id", adminHandler.DeleteUser)
			admin.GET("/stats", adminHandler.Stats)
		}
	}

	// Serve admin dashboard
	r.Static("/admin", "./admin")
	r.GET("/", func(c *gin.Context) {
		c.Redirect(302, "/admin/")
	})

	log.Printf("VibedTracker API starting on port %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
