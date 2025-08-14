package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

const (
	version = "1.0.0-dev"
	appName = "starfail-sysmgmt"
)

// isValidServiceName validates service names to prevent command injection
func isValidServiceName(service string) bool {
	// Only allow alphanumeric characters, hyphens, and underscores
	validPattern := regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
	return validPattern.MatchString(service) && len(service) <= 50
}

var (
	configFile = flag.String("config", "/etc/config/starfail", "UCI config file path")
	logLevel   = flag.String("log-level", "info", "Log level (debug|info|warn|error)")
	dryRun     = flag.Bool("dry-run", false, "Check only, don't fix issues")
	version_   = flag.Bool("version", false, "Show version and exit")
)

// SystemHealth represents overall system health status
type SystemHealth struct {
	OverlaySpaceUsed     int      `json:"overlay_space_used"`
	MemoryUsedPct        int      `json:"memory_used_pct"`
	CriticalServices     []string `json:"critical_services"`
	HungServices         []string `json:"hung_services"`
	LogFloodDetected     bool     `json:"log_flood_detected"`
	TimeSync             bool     `json:"time_sync"`
	InterfaceFlapping    bool     `json:"interface_flapping"`
	StarlinkScriptHealth bool     `json:"starlink_script_health"`
	DatabaseIssues       []string `json:"database_issues"`
}

// SystemManager manages RUTOS system health
type SystemManager struct {
	logger *logx.Logger
	dryRun bool
}

func main() {
	flag.Parse()

	if *version_ {
		fmt.Printf("%s %s\n", appName, version)
		os.Exit(0)
	}

	logger := logx.New(*logLevel)
	logger.Info("starting starfail system management",
		"version", version,
		"dry_run", *dryRun,
	)

	mgr := &SystemManager{
		logger: logger,
		dryRun: *dryRun,
	}

	ctx := context.Background()
	health := mgr.CheckSystemHealth(ctx)

	issuesFound := mgr.AnalyzeHealth(health)
	if issuesFound > 0 {
		logger.Warn("system health issues detected", "issues", issuesFound)
		if !*dryRun {
			mgr.FixIssues(ctx, health)
		}
		os.Exit(1)
	} else {
		logger.Info("system health check passed")
		os.Exit(0)
	}
}

// CheckSystemHealth performs comprehensive system health checks
func (sm *SystemManager) CheckSystemHealth(ctx context.Context) SystemHealth {
	health := SystemHealth{}

	// Check overlay space usage
	health.OverlaySpaceUsed = sm.checkOverlaySpace()

	// Check memory usage
	health.MemoryUsedPct = sm.checkMemoryUsage()

	// Check critical services
	health.CriticalServices = sm.checkCriticalServices()

	// Check for hung services
	health.HungServices = sm.checkHungServices()

	// Check for log flooding
	health.LogFloodDetected = sm.checkLogFlooding()

	// Check time synchronization
	health.TimeSync = sm.checkTimeSync()

	// Check interface flapping
	health.InterfaceFlapping = sm.checkInterfaceFlapping()

	// Check Starlink script health
	health.StarlinkScriptHealth = sm.checkStarlinkScriptHealth()

	// Check database issues
	health.DatabaseIssues = sm.checkDatabaseIssues()

	return health
}

// checkOverlaySpace checks overlay filesystem usage
func (sm *SystemManager) checkOverlaySpace() int {
	cmd := exec.Command("df", "/overlay")
	output, err := cmd.Output()
	if err != nil {
		sm.logger.Warn("failed to check overlay space", "error", err)
		return 0
	}

	lines := strings.Split(string(output), "\n")
	if len(lines) < 2 {
		return 0
	}

	fields := strings.Fields(lines[1])
	if len(fields) < 5 {
		return 0
	}

	usedPct := strings.TrimSuffix(fields[4], "%")
	pct, err := strconv.Atoi(usedPct)
	if err != nil {
		return 0
	}

	sm.logger.Debug("overlay space usage", "percentage", pct)
	return pct
}

// checkMemoryUsage checks system memory usage
func (sm *SystemManager) checkMemoryUsage() int {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		sm.logger.Warn("failed to read meminfo", "error", err)
		return 0
	}

	var memTotal, memAvailable int
	lines := strings.Split(string(data), "\n")

	for _, line := range lines {
		if strings.HasPrefix(line, "MemTotal:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				memTotal, _ = strconv.Atoi(fields[1])
			}
		}
		if strings.HasPrefix(line, "MemAvailable:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				memAvailable, _ = strconv.Atoi(fields[1])
			}
		}
	}

	if memTotal == 0 {
		return 0
	}

	usedPct := int((float64(memTotal-memAvailable) / float64(memTotal)) * 100)
	sm.logger.Debug("memory usage", "percentage", usedPct)
	return usedPct
}

// checkCriticalServices checks if critical services are running
func (sm *SystemManager) checkCriticalServices() []string {
	services := []string{"network", "system", "mwan3", "cron"}
	var failed []string

	for _, service := range services {
		if !isValidServiceName(service) {
			sm.logger.Warn("invalid service name", "service", service)
			continue
		}
		cmd := exec.Command("/etc/init.d/"+service, "status")
		if err := cmd.Run(); err != nil {
			failed = append(failed, service)
			sm.logger.Warn("critical service not running", "service", service)
		}
	}

	return failed
}

// checkHungServices detects services that appear running but are unresponsive
func (sm *SystemManager) checkHungServices() []string {
	var hung []string

	// Check for services with no recent log activity
	services := []string{"nlbwmon", "mdcollectd", "connchecker", "hostapd"}

	for _, service := range services {
		if sm.isServiceHung(service) {
			hung = append(hung, service)
			sm.logger.Warn("service appears hung", "service", service)
		}
	}

	return hung
}

// isServiceHung checks if a service hasn't logged recently
func (sm *SystemManager) isServiceHung(service string) bool {
	cmd := exec.Command("logread")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	lines := strings.Split(string(output), "\n")
	cutoff := time.Now().Add(-30 * time.Minute)

	for i := len(lines) - 1; i >= 0; i-- {
		line := lines[i]
		if strings.Contains(line, service) {
			// Parse timestamp and check if recent
			if sm.parseLogTime(line).After(cutoff) {
				return false // Recent activity found
			}
		}
	}

	return true // No recent activity
}

// parseLogTime extracts timestamp from syslog line
func (sm *SystemManager) parseLogTime(line string) time.Time {
	// Simple timestamp parsing for syslog format
	fields := strings.Fields(line)
	if len(fields) < 3 {
		return time.Time{}
	}

	// Try to parse timestamp (this is simplified)
	timeStr := strings.Join(fields[0:3], " ")
	t, _ := time.Parse("Jan 2 15:04:05", timeStr)
	return t
}

// checkLogFlooding detects excessive log entries
func (sm *SystemManager) checkLogFlooding() bool {
	cmd := exec.Command("logread")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	lines := strings.Split(string(output), "\n")
	hostapCount := 0
	cutoff := time.Now().Add(-1 * time.Hour)

	for _, line := range lines {
		if sm.parseLogTime(line).After(cutoff) {
			if strings.Contains(line, "hostapd") &&
				(strings.Contains(line, "STA-OPMODE-SMPS-MODE-CHANGED") ||
					strings.Contains(line, "CTRL-EVENT-") ||
					strings.Contains(line, "WPS-")) {
				hostapCount++
			}
		}
	}

	flooding := hostapCount > 100
	if flooding {
		sm.logger.Warn("log flooding detected", "hostap_entries", hostapCount)
	}

	return flooding
}

// checkTimeSync verifies NTP synchronization
func (sm *SystemManager) checkTimeSync() bool {
	cmd := exec.Command("pgrep", "ntpd")
	err := cmd.Run()
	if err != nil {
		sm.logger.Warn("NTP daemon not running")
		return false
	}

	return true
}

// checkInterfaceFlapping detects excessive interface state changes
func (sm *SystemManager) checkInterfaceFlapping() bool {
	cmd := exec.Command("logread")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	lines := strings.Split(string(output), "\n")
	interfaceEvents := 0
	cutoff := time.Now().Add(-10 * time.Minute)

	for _, line := range lines {
		if sm.parseLogTime(line).After(cutoff) {
			if strings.Contains(line, "interface") &&
				(strings.Contains(line, "up") || strings.Contains(line, "down")) {
				interfaceEvents++
			}
		}
	}

	flapping := interfaceEvents > 5
	if flapping {
		sm.logger.Warn("interface flapping detected", "events", interfaceEvents)
	}

	return flapping
}

// checkStarlinkScriptHealth verifies monitoring scripts are running
func (sm *SystemManager) checkStarlinkScriptHealth() bool {
	// Check for recent StarlinkMonitor log entries
	cmd := exec.Command("logread")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	lines := strings.Split(string(output), "\n")
	cutoff := time.Now().Add(-5 * time.Minute)

	for i := len(lines) - 1; i >= 0; i-- {
		line := lines[i]
		if strings.Contains(line, "StarlinkMonitor") && sm.parseLogTime(line).After(cutoff) {
			return true
		}
	}

	sm.logger.Warn("starlink monitoring script appears inactive")
	return false
}

// checkDatabaseIssues detects database corruption
func (sm *SystemManager) checkDatabaseIssues() []string {
	var issues []string

	databases := []string{
		"/tmp/dhcp.leases.sqlite",
		"/tmp/nlbw.db",
		"/tmp/hosts.db",
	}

	for _, db := range databases {
		if sm.isDatabaseCorrupted(db) {
			issues = append(issues, db)
			sm.logger.Warn("database corruption detected", "database", db)
		}
	}

	return issues
}

// isDatabaseCorrupted checks for database corruption indicators
func (sm *SystemManager) isDatabaseCorrupted(dbPath string) bool {
	// Check if file exists and has reasonable size
	info, err := os.Stat(dbPath)
	if err != nil {
		return false // File doesn't exist, not corrupted
	}

	// Very small database files are suspicious
	if info.Size() < 1024 {
		return true
	}

	// Check modification time (stale databases)
	if time.Since(info.ModTime()) > 7*24*time.Hour {
		return true
	}

	return false
}

// AnalyzeHealth analyzes health status and returns issue count
func (sm *SystemManager) AnalyzeHealth(health SystemHealth) int {
	issues := 0

	if health.OverlaySpaceUsed > 90 {
		sm.logger.Error("critical overlay space usage", "percentage", health.OverlaySpaceUsed)
		issues++
	} else if health.OverlaySpaceUsed > 80 {
		sm.logger.Warn("high overlay space usage", "percentage", health.OverlaySpaceUsed)
		issues++
	}

	if health.MemoryUsedPct > 90 {
		sm.logger.Warn("high memory usage", "percentage", health.MemoryUsedPct)
		issues++
	}

	if len(health.CriticalServices) > 0 {
		sm.logger.Error("critical services down", "services", health.CriticalServices)
		issues++
	}

	if len(health.HungServices) > 0 {
		sm.logger.Warn("hung services detected", "services", health.HungServices)
		issues++
	}

	if health.LogFloodDetected {
		sm.logger.Warn("log flooding detected")
		issues++
	}

	if !health.TimeSync {
		sm.logger.Warn("time synchronization issue")
		issues++
	}

	if health.InterfaceFlapping {
		sm.logger.Warn("network interface flapping")
		issues++
	}

	if !health.StarlinkScriptHealth {
		sm.logger.Warn("starlink monitoring inactive")
		issues++
	}

	if len(health.DatabaseIssues) > 0 {
		sm.logger.Warn("database issues detected", "databases", health.DatabaseIssues)
		issues++
	}

	return issues
}

// FixIssues attempts to automatically fix detected issues
func (sm *SystemManager) FixIssues(ctx context.Context, health SystemHealth) {
	if health.OverlaySpaceUsed > 80 {
		sm.cleanupOverlaySpace()
	}

	if len(health.CriticalServices) > 0 {
		sm.restartCriticalServices(health.CriticalServices)
	}

	if len(health.HungServices) > 0 {
		sm.restartHungServices(health.HungServices)
	}

	if health.LogFloodDetected {
		sm.mitigateLogFlooding()
	}

	if !health.TimeSync {
		sm.fixTimeSync()
	}

	if health.InterfaceFlapping {
		sm.restartNetworkService()
	}

	if !health.StarlinkScriptHealth {
		sm.restartCronService()
	}

	if len(health.DatabaseIssues) > 0 {
		sm.fixDatabaseIssues(health.DatabaseIssues)
	}
}

// cleanupOverlaySpace removes stale files to free space
func (sm *SystemManager) cleanupOverlaySpace() {
	sm.logger.Info("cleaning overlay space")

	// Remove old backup files
	if err := exec.Command("find", "/overlay", "-name", "*.old", "-mtime", "+7", "-delete").Run(); err != nil {
		log.Printf("Warning: failed to clean old backup files: %v", err)
	}
	if err := exec.Command("find", "/overlay", "-name", "*.bak", "-mtime", "+7", "-delete").Run(); err != nil {
		log.Printf("Warning: failed to clean bak backup files: %v", err)
	}
	if err := exec.Command("find", "/overlay", "-name", "*.tmp", "-mtime", "+7", "-delete").Run(); err != nil {
		log.Printf("Warning: failed to clean tmp backup files: %v", err)
	}

	// Clean old maintenance logs
	if err := exec.Command("find", "/var/log", "-name", "*maintenance*", "-mtime", "+14", "-delete").Run(); err != nil {
		log.Printf("Warning: failed to clean maintenance logs: %v", err)
	}
}

// restartCriticalServices restarts failed critical services
func (sm *SystemManager) restartCriticalServices(services []string) {
	for _, service := range services {
		if !isValidServiceName(service) {
			sm.logger.Warn("invalid service name for restart", "service", service)
			continue
		}
		sm.logger.Info("restarting critical service", "service", service)
		if err := exec.Command("/etc/init.d/"+service, "restart").Run(); err != nil {
			sm.logger.Warn("failed to restart critical service", "service", service, "error", err)
		}
	}
}

// restartHungServices restarts hung services
func (sm *SystemManager) restartHungServices(services []string) {
	for _, service := range services {
		if !isValidServiceName(service) {
			sm.logger.Warn("invalid service name for hung restart", "service", service)
			continue
		}
		sm.logger.Info("restarting hung service", "service", service)
		if err := exec.Command("killall", service).Run(); err != nil {
			sm.logger.Warn("failed to kill hung service", "service", service, "error", err)
		}
		time.Sleep(2 * time.Second)
		if err := exec.Command("/etc/init.d/"+service, "restart").Run(); err != nil {
			sm.logger.Warn("failed to restart service", "service", service, "error", err)
		}
	}
}

// mitigateLogFlooding reduces hostapd log verbosity
func (sm *SystemManager) mitigateLogFlooding() {
	sm.logger.Info("mitigating log flooding")
	// This would require hostapd configuration changes
	// For now, just log the action
}

// fixTimeSync restarts NTP service
func (sm *SystemManager) fixTimeSync() {
	sm.logger.Info("fixing time synchronization")
	if err := exec.Command("/etc/init.d/sysntpd", "restart").Run(); err != nil {
		sm.logger.Warn("failed to restart sysntpd", "error", err)
	}
}

// restartNetworkService restarts network to fix flapping
func (sm *SystemManager) restartNetworkService() {
	sm.logger.Info("restarting network service to fix flapping")
	if err := exec.Command("/etc/init.d/network", "restart").Run(); err != nil {
		sm.logger.Warn("failed to restart network service", "error", err)
	}
}

// restartCronService restarts cron daemon
func (sm *SystemManager) restartCronService() {
	sm.logger.Info("restarting cron service")
	if err := exec.Command("/etc/init.d/cron", "restart").Run(); err != nil {
		sm.logger.Warn("failed to restart cron service", "error", err)
	}
}

// fixDatabaseIssues recreates corrupted databases
func (sm *SystemManager) fixDatabaseIssues(databases []string) {
	for _, db := range databases {
		sm.logger.Info("fixing database issue", "database", db)

		// Backup corrupted database
		backupPath := db + ".corrupted." + time.Now().Format("20060102150405")
		if err := exec.Command("mv", db, backupPath).Run(); err != nil {
			log.Printf("Warning: failed to backup corrupted database %s: %v", db, err)
		} // The database will be recreated by the respective service
		// when it next starts or tries to access it
	}
}
