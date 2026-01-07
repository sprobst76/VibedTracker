package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/sprobst76/vibedtracker-server/internal/middleware"
	"github.com/sprobst76/vibedtracker-server/internal/models"
	"github.com/sprobst76/vibedtracker-server/internal/repository"
)

type SyncHandler struct {
	sync    *repository.SyncRepository
	devices *repository.DeviceRepository
}

func NewSyncHandler(sync *repository.SyncRepository, devices *repository.DeviceRepository) *SyncHandler {
	return &SyncHandler{
		sync:    sync,
		devices: devices,
	}
}

func (h *SyncHandler) Push(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Check if approved
	isApproved, _ := c.Get("is_approved")
	if !isApproved.(bool) {
		c.JSON(http.StatusForbidden, gin.H{"error": "account not approved for sync", "code": "NOT_APPROVED"})
		return
	}

	var req models.SyncPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	deviceID, err := uuid.Parse(req.DeviceID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device_id"})
		return
	}

	if err := h.sync.PushItems(c.Request.Context(), userID, deviceID, req.Items); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sync push failed"})
		return
	}

	// Update device last sync
	_ = h.devices.UpdateLastSync(c.Request.Context(), deviceID)

	c.JSON(http.StatusOK, gin.H{
		"message":    "sync successful",
		"items_count": len(req.Items),
		"timestamp":  time.Now().Unix(),
	})
}

func (h *SyncHandler) Pull(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Check if approved
	isApproved, _ := c.Get("is_approved")
	if !isApproved.(bool) {
		c.JSON(http.StatusForbidden, gin.H{"error": "account not approved for sync", "code": "NOT_APPROVED"})
		return
	}

	var req models.SyncPullRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	deviceID, err := uuid.Parse(req.DeviceID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device_id"})
		return
	}

	since := time.Unix(req.Since, 0)
	items, err := h.sync.PullItems(c.Request.Context(), userID, since, req.DataType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sync pull failed"})
		return
	}

	if items == nil {
		items = []models.SyncPullItem{}
	}

	// Log the pull
	_ = h.sync.LogPull(c.Request.Context(), userID, deviceID, len(items))
	_ = h.devices.UpdateLastSync(c.Request.Context(), deviceID)

	c.JSON(http.StatusOK, models.SyncPullResponse{
		Items:     items,
		Timestamp: time.Now().Unix(),
	})
}

func (h *SyncHandler) Status(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	isApproved, _ := c.Get("is_approved")

	c.JSON(http.StatusOK, gin.H{
		"user_id":     userID,
		"is_approved": isApproved,
		"timestamp":   time.Now().Unix(),
	})
}
