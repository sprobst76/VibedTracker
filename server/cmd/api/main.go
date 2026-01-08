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
	totpRepo := repository.NewTOTPRepository(db.Pool)
	passphraseRecoveryRepo := repository.NewPassphraseRecoveryRepository(db.Pool)

	// Create handlers
	authHandler := handlers.NewAuthHandler(cfg, userRepo, tokenRepo, deviceRepo, totpRepo)
	syncHandler := handlers.NewSyncHandler(syncRepo, deviceRepo)
	deviceHandler := handlers.NewDeviceHandler(deviceRepo, tokenRepo)
	adminHandler := handlers.NewAdminHandler(userRepo, tokenRepo)
	totpHandler := handlers.NewTOTPHandler(cfg, userRepo, totpRepo, tokenRepo, deviceRepo)
	webHandler := handlers.NewWebHandler(cfg, userRepo, tokenRepo, totpRepo, syncRepo, deviceRepo, passphraseRecoveryRepo)
	passphraseHandler := handlers.NewPassphraseHandler(userRepo, passphraseRecoveryRepo)

	// Create initial admin if configured
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	if err := authHandler.CreateInitialAdmin(ctx); err != nil {
		log.Printf("Warning: Failed to create initial admin: %v", err)
	}
	cancel()

	// Cleanup expired tokens and attempts periodically
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		for range ticker.C {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			if err := tokenRepo.CleanupExpired(ctx); err != nil {
				log.Printf("Failed to cleanup expired tokens: %v", err)
			}
			if err := totpRepo.CleanupOldAttempts(ctx); err != nil {
				log.Printf("Failed to cleanup old TOTP attempts: %v", err)
			}
			if err := passphraseRecoveryRepo.CleanupOldAttempts(ctx); err != nil {
				log.Printf("Failed to cleanup old passphrase recovery attempts: %v", err)
			}
			totpRepo.CleanupExpiredTempTokens()
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
			// TOTP validation during login (public, uses temp token)
			auth.POST("/totp/validate", totpHandler.Validate)
			auth.POST("/recovery/validate", totpHandler.ValidateRecovery)
		}

		// Protected routes (require JWT)
		protected := v1.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			// User profile
			protected.GET("/me", authHandler.Me)
			protected.POST("/key", passphraseHandler.SetKey)

			// Passphrase recovery management
			passphrase := protected.Group("/passphrase")
			{
				passphrase.GET("/recovery/status", passphraseHandler.GetRecoveryStatus)
				passphrase.POST("/recovery/regenerate", passphraseHandler.RegenerateRecoveryCodes)
				passphrase.POST("/recovery/reset", passphraseHandler.ResetWithRecoveryCode)
			}

			// TOTP management (protected)
			totp := protected.Group("/totp")
			{
				totp.GET("/status", totpHandler.GetStatus)
				totp.POST("/setup", totpHandler.Setup)
				totp.POST("/verify", totpHandler.Verify)
				totp.POST("/disable", totpHandler.Disable)
				totp.GET("/recovery-codes", totpHandler.GetRecoveryCodes)
			}

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

	// Serve static JS files for HTMX frontend
	r.Static("/static", "./static")

	// Web routes (HTMX frontend)
	web := r.Group("/web")
	{
		// Public routes
		web.GET("/login", webHandler.LoginPage)
		web.POST("/auth/login", webHandler.Login)
		web.POST("/auth/totp", webHandler.TOTPVerify)

		// Protected routes
		webProtected := web.Group("/")
		webProtected.Use(middleware.WebAuthMiddleware(tokenRepo, userRepo))
		{
			webProtected.GET("/dashboard", webHandler.Dashboard)
			webProtected.GET("/unlock", webHandler.Unlock)
			webProtected.GET("/vacation", webHandler.Vacation)
			webProtected.GET("/settings", webHandler.Settings)
			webProtected.GET("/api/data", webHandler.GetEncryptedData)
			webProtected.POST("/api/entry", webHandler.SaveEncryptedEntry)
			webProtected.DELETE("/api/entry/:id", webHandler.DeleteEncryptedEntry)
			webProtected.POST("/api/vacation", webHandler.SaveVacation)
			webProtected.DELETE("/api/vacation/:id", webHandler.DeleteVacation)
			webProtected.POST("/api/passphrase/reset", webHandler.PassphraseReset)
			webProtected.POST("/auth/logout", webHandler.Logout)

			// Admin routes (require admin via middleware)
			webAdmin := webProtected.Group("/admin")
			webAdmin.Use(middleware.WebAdminMiddleware())
			{
				webAdmin.GET("", webHandler.Admin)
				webAdmin.GET("/users", webHandler.AdminUsers)
				webAdmin.POST("/users/:id/approve", webHandler.AdminApproveUser)
				webAdmin.POST("/users/:id/block", webHandler.AdminBlockUser)
				webAdmin.POST("/users/:id/unblock", webHandler.AdminUnblockUser)
				webAdmin.DELETE("/users/:id", webHandler.AdminDeleteUser)
				webAdmin.GET("/devices", webHandler.AdminDevices)
				webAdmin.DELETE("/devices/:id", webHandler.AdminDeleteDevice)
				webAdmin.GET("/stats", webHandler.AdminStats)
			}
		}
	}

	// Redirect root to web login
	r.GET("/", func(c *gin.Context) {
		c.Redirect(302, "/web/login")
	})

	// Serve Flutter Web App (SPA)
	r.Static("/assets", "./webapp/assets")
	r.Static("/icons", "./webapp/icons")
	r.Static("/canvaskit", "./webapp/canvaskit")
	r.StaticFile("/flutter.js", "./webapp/flutter.js")
	r.StaticFile("/flutter_bootstrap.js", "./webapp/flutter_bootstrap.js")
	r.StaticFile("/flutter_service_worker.js", "./webapp/flutter_service_worker.js")
	r.StaticFile("/main.dart.js", "./webapp/main.dart.js")
	r.StaticFile("/manifest.json", "./webapp/manifest.json")
	r.StaticFile("/version.json", "./webapp/version.json")
	r.StaticFile("/favicon.png", "./webapp/favicon.png")

	// SPA fallback: alle anderen Routen → index.html
	r.NoRoute(func(c *gin.Context) {
		// Nicht für /api oder /admin Pfade
		path := c.Request.URL.Path
		if len(path) >= 4 && path[:4] == "/api" {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		if len(path) >= 6 && path[:6] == "/admin" {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		c.File("./webapp/index.html")
	})

	log.Printf("VibedTracker API starting on port %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
