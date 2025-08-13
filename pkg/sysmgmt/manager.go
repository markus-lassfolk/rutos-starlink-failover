// Package sysmgmt provides system health monitoring and auto-recovery functionality
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

	"starfail/pkg/logx"
)

// Config holds system management configuration
type Config struct {
	Enable                 bool          `uci:"enable" default:"true"`
	OverlayCleanupDays     int           `uci:"overlay_cleanup_days" default:"7"`
	LogCleanupDays         int           `uci:"log_cleanup_days" default:"3"`
	ServiceCheckInterval   time.Duration `uci:"service_check_interval" default:"300s"`
	TimeDriftThreshold     time.Duration `uci:"time_drift_threshold" default:"30s"`
	InterfaceFlapThreshold int           `uci:"interface_flap_threshold" default:"5"`
	DryRun                 bool          `uci:"dry_run" default:"false"`
}

// Manager handles system health monitoring and maintenance
type Manager struct {
	config Config
	logger logx.Logger
}

// CheckResult represents the result of a health check or maintenance task
type CheckResult struct {
	Check    string        `json:"check"`
	Success  bool          `json:"success"`
	Error    error         `json:"error,omitempty"`
	Duration time.Duration `json:"duration"`
}

// MaintenanceResult represents the result of a maintenance operation
type MaintenanceResult struct {
	Task     string        `json:"task"`
	Success  bool          `json:"success"`
	Error    error         `json:"error,omitempty"`
	Actions  []string      `json:"actions"`
	Duration time.Duration `json:"duration"`
}

// NewManager creates a new system management manager
func NewManager(config Config, logger logx.Logger) (*Manager, error) {
	if !config.Enable {
		return nil, fmt.Errorf("system management is disabled")
	}

	return &Manager{
		config: config,
		logger: logger,
	}, nil
}

// QuickHealthCheck performs fast health checks
func (m *Manager) QuickHealthCheck(ctx context.Context) []CheckResult {
	checks := []func(context.Context) CheckResult{
		m.checkOverlaySpace,
		m.checkMemoryUsage,
		m.checkCriticalServices,
		m.checkTimeSync,
		m.checkLogFlood,
	}

	results := make([]CheckResult, len(checks))
	for i, check := range checks {
		start := time.Now()
		results[i] = check(ctx)
		results[i].Duration = time.Since(start)
	}

	return results
}

// FullMaintenance performs comprehensive system maintenance
func (m *Manager) FullMaintenance(ctx context.Context) []MaintenanceResult {
	tasks := []func(context.Context) MaintenanceResult{
		m.cleanupOverlaySpace,
		m.cleanupLogs,
		m.restartHungServices,
		m.fixTimeSync,
		m.stabilizeInterfaces,
		m.optimizeDatabase,
	}

	results := make([]MaintenanceResult, len(tasks))
	for i, task := range tasks {
		start := time.Now()
		results[i] = task(ctx)
		results[i].Duration = time.Since(start)
	}

	return results
}

// checkOverlaySpace checks available overlay space
func (m *Manager) checkOverlaySpace(ctx context.Context) CheckResult {
	result := CheckResult{Check: "overlay_space"}

	// Check /overlay space usage
	cmd := exec.CommandContext(ctx, "df", "/overlay")
	output, err := cmd.Output()
	if err != nil {
		result.Error = fmt.Errorf("failed to check overlay space: %w", err)
		return result
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) < 2 {
		result.Error = fmt.Errorf("invalid df output format")
		return result
	}

	fields := strings.Fields(lines[1])
	if len(fields) < 5 {
		result.Error = fmt.Errorf("invalid df output fields")
		return result
	}

	// Parse usage percentage
	usageStr := strings.TrimSuffix(fields[4], "%")
	usage, err := strconv.Atoi(usageStr)
	if err != nil {
		result.Error = fmt.Errorf("failed to parse usage percentage: %w", err)
		return result
	}

	// Warn if usage > 85%
	if usage > 85 {
		result.Error = fmt.Errorf("overlay space usage high: %d%%", usage)
		return result
	}

	result.Success = true
	return result
}

// checkMemoryUsage checks system memory usage
func (m *Manager) checkMemoryUsage(ctx context.Context) CheckResult {
	result := CheckResult{Check: "memory_usage"}

	// Read /proc/meminfo
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		result.Error = fmt.Errorf("failed to read meminfo: %w", err)
		return result
	}

	var memTotal, memFree, memAvailable int
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}

		switch fields[0] {
		case "MemTotal:":
			memTotal, _ = strconv.Atoi(fields[1])
		case "MemFree:":
			memFree, _ = strconv.Atoi(fields[1])
		case "MemAvailable:":
			memAvailable, _ = strconv.Atoi(fields[1])
		}
	}

	if memTotal == 0 {
		result.Error = fmt.Errorf("failed to parse memory info")
		return result
	}

	// Calculate usage percentage
	usedMem := memTotal - memAvailable
	if memAvailable == 0 {
		usedMem = memTotal - memFree
	}
	
	usagePct := (usedMem * 100) / memTotal

	// Warn if usage > 90%
	if usagePct > 90 {
		result.Error = fmt.Errorf("memory usage high: %d%%", usagePct)
		return result
	}

	result.Success = true
	return result
}

// checkCriticalServices checks if critical services are running
func (m *Manager) checkCriticalServices(ctx context.Context) CheckResult {
	result := CheckResult{Check: "critical_services"}

	criticalServices := []string{
		"mwan3",
		"network",
		"dnsmasq",
		"dropbear",
	}

	var failedServices []string
	for _, service := range criticalServices {
		cmd := exec.CommandContext(ctx, "/etc/init.d/"+service, "status")
		if err := cmd.Run(); err != nil {
			failedServices = append(failedServices, service)
		}
	}

	if len(failedServices) > 0 {
		result.Error = fmt.Errorf("critical services not running: %v", failedServices)
		return result
	}

	result.Success = true
	return result
}

// checkTimeSync checks NTP synchronization
func (m *Manager) checkTimeSync(ctx context.Context) CheckResult {
	result := CheckResult{Check: "time_sync"}

	// Check if ntpd is running and synchronized
	cmd := exec.CommandContext(ctx, "ntpq", "-p")
	output, err := cmd.Output()
	if err != nil {
		result.Error = fmt.Errorf("ntpd not running or not responding: %w", err)
		return result
	}

	// Look for synchronized peer (marked with *)
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "*") {
			result.Success = true
			return result
		}
	}

	result.Error = fmt.Errorf("no synchronized NTP peers found")
	return result
}

// checkLogFlood detects log flooding
func (m *Manager) checkLogFlood(ctx context.Context) CheckResult {
	result := CheckResult{Check: "log_flood"}

	// Check recent log growth
	logPaths := []string{
		"/var/log/messages",
		"/var/log/system.log",
		"/tmp/log/messages",
	}

	for _, logPath := range logPaths {
		if stat, err := os.Stat(logPath); err == nil {
			// Check if log file is very large (>10MB)
			if stat.Size() > 10*1024*1024 {
				result.Error = fmt.Errorf("large log file detected: %s (%d bytes)", logPath, stat.Size())
				return result
			}
		}
	}

	result.Success = true
	return result
}

// cleanupOverlaySpace performs overlay space cleanup
func (m *Manager) cleanupOverlaySpace(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "cleanup_overlay"}

	var actions []string

	// Clean temp files older than configured days
	tempDirs := []string{"/tmp", "/var/tmp", "/overlay/tmp"}
	for _, dir := range tempDirs {
		if _, err := os.Stat(dir); err == nil {
			cmd := exec.CommandContext(ctx, "find", dir, "-type", "f", "-mtime", 
				fmt.Sprintf("+%d", m.config.OverlayCleanupDays), "-delete")
			
			if !m.config.DryRun {
				if err := cmd.Run(); err == nil {
					actions = append(actions, fmt.Sprintf("cleaned old files from %s", dir))
				}
			} else {
				actions = append(actions, fmt.Sprintf("would clean old files from %s", dir))
			}
		}
	}

	// Clean package cache
	if _, err := os.Stat("/tmp/opkg-lists"); err == nil {
		if !m.config.DryRun {
			os.RemoveAll("/tmp/opkg-lists")
			actions = append(actions, "cleaned opkg cache")
		} else {
			actions = append(actions, "would clean opkg cache")
		}
	}

	result.Success = true
	result.Actions = actions
	return result
}

// cleanupLogs performs log cleanup and rotation
func (m *Manager) cleanupLogs(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "cleanup_logs"}

	var actions []string

	// Rotate large log files
	logPaths := []string{
		"/var/log/messages",
		"/var/log/system.log",
		"/tmp/log/messages",
	}

	for _, logPath := range logPaths {
		if stat, err := os.Stat(logPath); err == nil {
			// Rotate if file is larger than 5MB
			if stat.Size() > 5*1024*1024 {
				if !m.config.DryRun {
					// Simple rotation: move current to .old and truncate
					oldPath := logPath + ".old"
					os.Rename(logPath, oldPath)
					
					// Create new empty log file
					file, err := os.Create(logPath)
					if err == nil {
						file.Close()
						actions = append(actions, fmt.Sprintf("rotated %s", logPath))
					}
				} else {
					actions = append(actions, fmt.Sprintf("would rotate %s", logPath))
				}
			}
		}
	}

	// Clean old rotated logs
	cmd := exec.CommandContext(ctx, "find", "/var/log", "/tmp/log", "-name", "*.old", 
		"-mtime", fmt.Sprintf("+%d", m.config.LogCleanupDays), "-delete")
	
	if !m.config.DryRun {
		if err := cmd.Run(); err == nil {
			actions = append(actions, "cleaned old rotated logs")
		}
	} else {
		actions = append(actions, "would clean old rotated logs")
	}

	result.Success = true
	result.Actions = actions
	return result
}

// restartHungServices restarts services that appear hung
func (m *Manager) restartHungServices(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "restart_hung_services"}

	var actions []string

	// Services to check for responsiveness
	services := map[string]func() bool{
		"mwan3":     m.checkMwan3Responsive,
		"dnsmasq":   m.checkDnsmasqResponsive,
		"nlbwmon":   m.checkNlbwmonResponsive,
	}

	for service, checkFunc := range services {
		if !checkFunc() {
			if !m.config.DryRun {
				cmd := exec.CommandContext(ctx, "/etc/init.d/"+service, "restart")
				if err := cmd.Run(); err == nil {
					actions = append(actions, fmt.Sprintf("restarted hung service: %s", service))
				}
			} else {
				actions = append(actions, fmt.Sprintf("would restart hung service: %s", service))
			}
		}
	}

	result.Success = true
	result.Actions = actions
	return result
}

// fixTimeSync fixes NTP synchronization issues
func (m *Manager) fixTimeSync(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "fix_time_sync"}

	var actions []string

	// Check time drift by comparing with a reliable source
	// For now, just restart ntpd if it's not synchronized
	if checkResult := m.checkTimeSync(ctx); !checkResult.Success {
		if !m.config.DryRun {
			// Restart ntpd
			cmd := exec.CommandContext(ctx, "/etc/init.d/sysntpd", "restart")
			if err := cmd.Run(); err == nil {
				actions = append(actions, "restarted ntpd")
			}
			
			// Force immediate sync
			cmd = exec.CommandContext(ctx, "ntpd", "-q", "-n", "-p", "pool.ntp.org")
			if err := cmd.Run(); err == nil {
				actions = append(actions, "forced NTP sync")
			}
		} else {
			actions = append(actions, "would restart ntpd and force sync")
		}
	}

	result.Success = true
	result.Actions = actions
	return result
}

// stabilizeInterfaces fixes flapping network interfaces
func (m *Manager) stabilizeInterfaces(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "stabilize_interfaces"}

	var actions []string

	// Check for interface state changes in recent logs
	// This is a simplified implementation - in practice would track interface events
	if !m.config.DryRun {
		// Restart network service to stabilize interfaces
		cmd := exec.CommandContext(ctx, "/etc/init.d/network", "reload")
		if err := cmd.Run(); err == nil {
			actions = append(actions, "reloaded network configuration")
		}
	} else {
		actions = append(actions, "would reload network configuration")
	}

	result.Success = true
	result.Actions = actions
	return result
}

// optimizeDatabase optimizes system databases (if any)
func (m *Manager) optimizeDatabase(ctx context.Context) MaintenanceResult {
	result := MaintenanceResult{Task: "optimize_database"}

	var actions []string

	// Check for and optimize any SQLite databases
	dbPaths := []string{
		"/etc/config",
		"/tmp",
		"/var",
	}

	for _, dbPath := range dbPaths {
		filepath.Walk(dbPath, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}
			
			if strings.HasSuffix(path, ".db") || strings.HasSuffix(path, ".sqlite") {
				if !m.config.DryRun {
					cmd := exec.CommandContext(ctx, "sqlite3", path, "VACUUM;")
					if err := cmd.Run(); err == nil {
						actions = append(actions, fmt.Sprintf("optimized database: %s", path))
					}
				} else {
					actions = append(actions, fmt.Sprintf("would optimize database: %s", path))
				}
			}
			return nil
		})
	}

	result.Success = true
	result.Actions = actions
	return result
}

// Helper functions for service responsiveness checks
func (m *Manager) checkMwan3Responsive() bool {
	cmd := exec.Command("mwan3", "status")
	return cmd.Run() == nil
}

func (m *Manager) checkDnsmasqResponsive() bool {
	cmd := exec.Command("nslookup", "localhost", "127.0.0.1")
	return cmd.Run() == nil
}

func (m *Manager) checkNlbwmonResponsive() bool {
	// Check if nlbwmon is responding (simple PID check)
	cmd := exec.Command("pgrep", "nlbwmon")
	return cmd.Run() == nil
}
