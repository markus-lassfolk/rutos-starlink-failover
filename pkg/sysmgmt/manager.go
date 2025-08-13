package sysmgmt

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

// Manager represents the system management orchestrator
type Manager struct {
	config  *Config
	logger  logx.Logger
	dryRun  bool
	mu      sync.Mutex
	
	// Health check components
	overlayManager    *OverlayManager
	serviceWatchdog   *ServiceWatchdog
	logFloodDetector  *LogFloodDetector
	timeManager       *TimeManager
	networkManager    *NetworkManager
	starlinkManager   *StarlinkManager
	databaseManager   *DatabaseManager
	notificationMgr   *NotificationManager
	
	// Statistics
	lastCheckTime     time.Time
	issuesFound       int
	issuesFixed       int
	notificationsSent int
}

// NewManager creates a new system manager
func NewManager(config *Config, logger logx.Logger, dryRun bool) *Manager {
	m := &Manager{
		config: config,
		logger: logger,
		dryRun: dryRun,
	}
	
	// Initialize components
	m.overlayManager = NewOverlayManager(config, logger, dryRun)
	m.serviceWatchdog = NewServiceWatchdog(config, logger, dryRun)
	m.logFloodDetector = NewLogFloodDetector(config, logger, dryRun)
	m.timeManager = NewTimeManager(config, logger, dryRun)
	m.networkManager = NewNetworkManager(config, logger, dryRun)
	m.starlinkManager = NewStarlinkManager(config, logger, dryRun)
	m.databaseManager = NewDatabaseManager(config, logger, dryRun)
	m.notificationMgr = NewNotificationManager(config, logger, dryRun)
	
	return m
}

// RunHealthCheck runs a complete health check cycle
func (m *Manager) RunHealthCheck(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	startTime := time.Now()
	m.logger.Info("Starting system health check", "dry_run", m.dryRun)
	
	// Reset statistics
	m.issuesFound = 0
	m.issuesFixed = 0
	m.notificationsSent = 0
	
	// Run all health checks
	checks := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"overlay space", m.overlayManager.Check},
		{"service watchdog", m.serviceWatchdog.Check},
		{"log flood detection", m.logFloodDetector.Check},
		{"time drift", m.timeManager.Check},
		{"network interface", m.networkManager.Check},
		{"starlink script", m.starlinkManager.Check},
		{"database health", m.databaseManager.Check},
	}
	
	for _, check := range checks {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		
		if err := check.fn(ctx); err != nil {
			m.logger.Error("Health check failed", "check", check.name, "error", err)
			m.issuesFound++
		}
	}
	
	// Send summary notification if enabled
	if m.config.NotificationsEnabled && m.issuesFound > 0 {
		m.sendSummaryNotification()
	}
	
	m.lastCheckTime = time.Now()
	duration := time.Since(startTime)
	
	m.logger.Info("System health check completed",
		"duration", duration,
		"issues_found", m.issuesFound,
		"issues_fixed", m.issuesFixed,
		"notifications_sent", m.notificationsSent)
	
	return nil
}

// sendSummaryNotification sends a summary of the health check
func (m *Manager) sendSummaryNotification() {
	if m.notificationsSent >= m.config.MaxNotificationsPerRun {
		m.logger.Debug("Notification limit reached, skipping summary")
		return
	}
	
	summary := fmt.Sprintf("System Health Check Summary\n\n"+
		"Issues Found: %d\n"+
		"Issues Fixed: %d\n"+
		"Check Time: %s",
		m.issuesFound, m.issuesFixed, m.lastCheckTime.Format("2006-01-02 15:04:05"))
	
	if err := m.notificationMgr.SendNotification("System Health Summary", summary, m.config.PushoverPriorityFixed); err != nil {
		m.logger.Error("Failed to send summary notification", "error", err)
	} else {
		m.notificationsSent++
	}
}

// GetStatus returns the current status of the system manager
func (m *Manager) GetStatus() map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	return map[string]interface{}{
		"enabled":             m.config.Enabled,
		"last_check_time":     m.lastCheckTime,
		"issues_found":        m.issuesFound,
		"issues_fixed":        m.issuesFixed,
		"notifications_sent":  m.notificationsSent,
		"dry_run":            m.dryRun,
		"check_interval":     m.config.CheckInterval,
		"auto_fix_enabled":   m.config.AutoFixEnabled,
	}
}
