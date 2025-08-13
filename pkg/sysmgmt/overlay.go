package sysmgmt

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

// OverlayManager manages overlay filesystem space
type OverlayManager struct {
	config *Config
	logger logx.Logger
	dryRun bool
}

// NewOverlayManager creates a new overlay manager
func NewOverlayManager(config *Config, logger logx.Logger, dryRun bool) *OverlayManager {
	return &OverlayManager{
		config: config,
		logger: logger,
		dryRun: dryRun,
	}
}

// Check monitors overlay space and performs cleanup if needed
func (om *OverlayManager) Check(ctx context.Context) error {
	usage, err := om.getOverlayUsage()
	if err != nil {
		return fmt.Errorf("failed to get overlay usage: %w", err)
	}

	om.logger.Debug("Overlay space check", "usage_percent", usage)

	if usage >= om.config.OverlayCriticalThreshold {
		om.logger.Warn("Critical overlay space usage", "usage_percent", usage, "threshold", om.config.OverlayCriticalThreshold)
		if om.config.NotificationsEnabled && om.config.NotifyOnCritical {
			om.sendCriticalNotification(usage)
		}
		return om.performEmergencyCleanup(ctx)
	} else if usage >= om.config.OverlaySpaceThreshold {
		om.logger.Warn("High overlay space usage", "usage_percent", usage, "threshold", om.config.OverlaySpaceThreshold)
		return om.performCleanup(ctx)
	}

	return nil
}

// getOverlayUsage returns the overlay filesystem usage percentage
func (om *OverlayManager) getOverlayUsage() (int, error) {
	cmd := exec.Command("df", "/overlay")
	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	lines := strings.Split(string(output), "\n")
	if len(lines) < 2 {
		return 0, fmt.Errorf("unexpected df output format")
	}

	// Parse the usage percentage from df output
	fields := strings.Fields(lines[1])
	if len(fields) < 5 {
		return 0, fmt.Errorf("unexpected df output format")
	}

	usageStr := strings.TrimSuffix(fields[4], "%")
	usage, err := strconv.Atoi(usageStr)
	if err != nil {
		return 0, fmt.Errorf("failed to parse usage percentage: %w", err)
	}

	return usage, nil
}

// performCleanup performs routine cleanup of stale files
func (om *OverlayManager) performCleanup(ctx context.Context) error {
	om.logger.Info("Starting overlay cleanup", "dry_run", om.dryRun)

	cleanupTasks := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"stale backup files", om.cleanupStaleBackups},
		{"old log files", om.cleanupOldLogs},
		{"temporary files", om.cleanupTempFiles},
		{"maintenance logs", om.cleanupMaintenanceLogs},
	}

	var totalFreed int64
	for _, task := range cleanupTasks {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		if freed, err := task.fn(ctx); err != nil {
			om.logger.Error("Cleanup task failed", "task", task.name, "error", err)
		} else {
			totalFreed += freed
		}
	}

	if totalFreed > 0 {
		om.logger.Info("Overlay cleanup completed", "bytes_freed", totalFreed, "dry_run", om.dryRun)
		if om.config.NotificationsEnabled && om.config.NotifyOnFixes {
			om.sendFixNotification("Overlay cleanup", fmt.Sprintf("Freed %d bytes", totalFreed))
		}
	}

	return nil
}

// performEmergencyCleanup performs aggressive cleanup for critical space situations
func (om *OverlayManager) performEmergencyCleanup(ctx context.Context) error {
	om.logger.Warn("Performing emergency overlay cleanup", "dry_run", om.dryRun)

	// More aggressive cleanup for emergency situations
	emergencyTasks := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"all backup files", om.cleanupAllBackups},
		{"all log files", om.cleanupAllLogs},
		{"all temporary files", om.cleanupAllTempFiles},
		{"system cache", om.cleanupSystemCache},
	}

	var totalFreed int64
	for _, task := range emergencyTasks {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		if freed, err := task.fn(ctx); err != nil {
			om.logger.Error("Emergency cleanup task failed", "task", task.name, "error", err)
		} else {
			totalFreed += freed
		}
	}

	if totalFreed > 0 {
		om.logger.Warn("Emergency overlay cleanup completed", "bytes_freed", totalFreed, "dry_run", om.dryRun)
		if om.config.NotificationsEnabled && om.config.NotifyOnCritical {
			om.sendCriticalNotification(0, "Emergency cleanup completed", fmt.Sprintf("Freed %d bytes", totalFreed))
		}
	}

	return nil
}

// cleanupStaleBackups removes old backup files
func (om *OverlayManager) cleanupStaleBackups(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	cutoff := time.Now().AddDate(0, 0, -om.config.CleanupRetentionDays)
	patterns := []string{"*.old", "*.bak", "*.tmp", "*.backup"}

	var totalFreed int64
	for _, pattern := range patterns {
		matches, err := filepath.Glob(filepath.Join("/overlay", "**", pattern))
		if err != nil {
			continue
		}

		for _, file := range matches {
			select {
			case <-ctx.Done():
				return totalFreed, ctx.Err()
			default:
			}

			info, err := os.Stat(file)
			if err != nil {
				continue
			}

			if info.ModTime().Before(cutoff) {
				if err := os.Remove(file); err == nil {
					totalFreed += info.Size()
					om.logger.Debug("Removed stale backup file", "file", file, "size", info.Size())
				}
			}
		}
	}

	return totalFreed, nil
}

// cleanupOldLogs removes old log files
func (om *OverlayManager) cleanupOldLogs(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	cutoff := time.Now().AddDate(0, 0, -om.config.CleanupRetentionDays)
	logDirs := []string{"/var/log", "/tmp/log", "/overlay/var/log"}

	var totalFreed int64
	for _, logDir := range logDirs {
		if err := filepath.Walk(logDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}

			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if !info.IsDir() && info.ModTime().Before(cutoff) {
				if strings.HasSuffix(path, ".log") || strings.HasSuffix(path, ".gz") {
					if err := os.Remove(path); err == nil {
						totalFreed += info.Size()
						om.logger.Debug("Removed old log file", "file", path, "size", info.Size())
					}
				}
			}
			return nil
		}); err != nil {
			om.logger.Debug("Error walking log directory", "dir", logDir, "error", err)
		}
	}

	return totalFreed, nil
}

// cleanupTempFiles removes temporary files
func (om *OverlayManager) cleanupTempFiles(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	cutoff := time.Now().Add(-24 * time.Hour) // Remove temp files older than 24 hours
	tempDirs := []string{"/tmp", "/var/tmp"}

	var totalFreed int64
	for _, tempDir := range tempDirs {
		if err := filepath.Walk(tempDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}

			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if !info.IsDir() && info.ModTime().Before(cutoff) {
				if err := os.Remove(path); err == nil {
					totalFreed += info.Size()
					om.logger.Debug("Removed temp file", "file", path, "size", info.Size())
				}
			}
			return nil
		}); err != nil {
			om.logger.Debug("Error walking temp directory", "dir", tempDir, "error", err)
		}
	}

	return totalFreed, nil
}

// cleanupMaintenanceLogs removes old maintenance logs
func (om *OverlayManager) cleanupMaintenanceLogs(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	cutoff := time.Now().AddDate(0, 0, -om.config.CleanupRetentionDays)
	maintenanceLog := "/var/log/system-maintenance.log"

	info, err := os.Stat(maintenanceLog)
	if err != nil {
		return 0, nil // File doesn't exist
	}

	if info.ModTime().Before(cutoff) {
		if err := os.Remove(maintenanceLog); err == nil {
			om.logger.Debug("Removed old maintenance log", "file", maintenanceLog, "size", info.Size())
			return info.Size(), nil
		}
	}

	return 0, nil
}

// cleanupAllBackups removes all backup files regardless of age
func (om *OverlayManager) cleanupAllBackups(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	patterns := []string{"*.old", "*.bak", "*.tmp", "*.backup"}
	var totalFreed int64

	for _, pattern := range patterns {
		matches, err := filepath.Glob(filepath.Join("/overlay", "**", pattern))
		if err != nil {
			continue
		}

		for _, file := range matches {
			select {
			case <-ctx.Done():
				return totalFreed, ctx.Err()
			default:
			}

			if info, err := os.Stat(file); err == nil {
				if err := os.Remove(file); err == nil {
					totalFreed += info.Size()
					om.logger.Debug("Emergency: removed backup file", "file", file, "size", info.Size())
				}
			}
		}
	}

	return totalFreed, nil
}

// cleanupAllLogs removes all log files regardless of age
func (om *OverlayManager) cleanupAllLogs(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	logDirs := []string{"/var/log", "/tmp/log", "/overlay/var/log"}
	var totalFreed int64

	for _, logDir := range logDirs {
		if err := filepath.Walk(logDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}

			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if !info.IsDir() {
				if strings.HasSuffix(path, ".log") || strings.HasSuffix(path, ".gz") {
					if err := os.Remove(path); err == nil {
						totalFreed += info.Size()
						om.logger.Debug("Emergency: removed log file", "file", path, "size", info.Size())
					}
				}
			}
			return nil
		}); err != nil {
			om.logger.Debug("Error walking log directory", "dir", logDir, "error", err)
		}
	}

	return totalFreed, nil
}

// cleanupAllTempFiles removes all temporary files regardless of age
func (om *OverlayManager) cleanupAllTempFiles(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	tempDirs := []string{"/tmp", "/var/tmp"}
	var totalFreed int64

	for _, tempDir := range tempDirs {
		if err := filepath.Walk(tempDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}

			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if !info.IsDir() {
				if err := os.Remove(path); err == nil {
					totalFreed += info.Size()
					om.logger.Debug("Emergency: removed temp file", "file", path, "size", info.Size())
				}
			}
			return nil
		}); err != nil {
			om.logger.Debug("Error walking temp directory", "dir", tempDir, "error", err)
		}
	}

	return totalFreed, nil
}

// cleanupSystemCache removes system cache files
func (om *OverlayManager) cleanupSystemCache(ctx context.Context) (int64, error) {
	if om.dryRun {
		return 0, nil
	}

	// Clear various system caches
	cacheDirs := []string{"/var/cache", "/tmp/cache"}
	var totalFreed int64

	for _, cacheDir := range cacheDirs {
		if err := filepath.Walk(cacheDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}

			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if !info.IsDir() {
				if err := os.Remove(path); err == nil {
					totalFreed += info.Size()
					om.logger.Debug("Emergency: removed cache file", "file", path, "size", info.Size())
				}
			}
			return nil
		}); err != nil {
			om.logger.Debug("Error walking cache directory", "dir", cacheDir, "error", err)
		}
	}

	return totalFreed, nil
}

// sendCriticalNotification sends a critical notification
func (om *OverlayManager) sendCriticalNotification(usage int, args ...interface{}) {
	// This would be implemented by the notification manager
	om.logger.Warn("Critical overlay space notification", "usage_percent", usage)
}

// sendFixNotification sends a fix notification
func (om *OverlayManager) sendFixNotification(action, details string) {
	// This would be implemented by the notification manager
	om.logger.Info("Fix notification", "action", action, "details", details)
}
