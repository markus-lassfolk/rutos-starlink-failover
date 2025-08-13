package sysmgmt

import (
	"time"
)

// Config represents the system management configuration
type Config struct {
	// General settings
	Enabled                    bool          `json:"enabled"`
	CheckInterval             time.Duration `json:"check_interval"`
	MaxExecutionTime          time.Duration `json:"max_execution_time"`
	AutoFixEnabled            bool          `json:"auto_fix_enabled"`
	ServiceRestartEnabled     bool          `json:"service_restart_enabled"`
	
	// Overlay space management
	OverlaySpaceThreshold     int           `json:"overlay_space_threshold"`      // Percentage
	OverlayCriticalThreshold  int           `json:"overlay_critical_threshold"`   // Percentage
	CleanupRetentionDays      int           `json:"cleanup_retention_days"`
	
	// Service watchdog
	ServiceWatchdogEnabled    bool          `json:"service_watchdog_enabled"`
	ServiceTimeout           time.Duration `json:"service_timeout"`
	ServicesToMonitor        []string      `json:"services_to_monitor"`
	
	// Log flood detection
	LogFloodEnabled          bool          `json:"log_flood_enabled"`
	LogFloodThreshold        int           `json:"log_flood_threshold"`        // Entries per hour
	LogFloodPatterns         []string      `json:"log_flood_patterns"`
	
	// Time drift correction
	TimeDriftEnabled         bool          `json:"time_drift_enabled"`
	TimeDriftThreshold       time.Duration `json:"time_drift_threshold"`
	NTPTimeout              time.Duration `json:"ntp_timeout"`
	
	// Network interface stabilization
	InterfaceFlappingEnabled bool          `json:"interface_flapping_enabled"`
	FlappingThreshold        int           `json:"flapping_threshold"`        // Events per hour
	FlappingInterfaces       []string      `json:"flapping_interfaces"`
	
	// Starlink script health
	StarlinkScriptEnabled    bool          `json:"starlink_script_enabled"`
	StarlinkLogTimeout       time.Duration `json:"starlink_log_timeout"`
	
	// Database management
	DatabaseEnabled          bool          `json:"database_enabled"`
	DatabaseErrorThreshold   int           `json:"database_error_threshold"`
	DatabaseMinSizeKB        int           `json:"database_min_size_kb"`
	DatabaseMaxAgeDays       int           `json:"database_max_age_days"`
	
	// Notifications
	NotificationsEnabled     bool          `json:"notifications_enabled"`
	NotifyOnFixes           bool          `json:"notify_on_fixes"`
	NotifyOnFailures        bool          `json:"notify_on_failures"`
	NotifyOnCritical        bool          `json:"notify_on_critical"`
	NotificationCooldown    time.Duration `json:"notification_cooldown"`
	MaxNotificationsPerRun  int           `json:"max_notifications_per_run"`
	
	// Pushover settings
	PushoverEnabled          bool          `json:"pushover_enabled"`
	PushoverToken           string        `json:"pushover_token"`
	PushoverUser            string        `json:"pushover_user"`
	PushoverPriorityFixed   int           `json:"pushover_priority_fixed"`
	PushoverPriorityFailed  int           `json:"pushover_priority_failed"`
	PushoverPriorityCritical int          `json:"pushover_priority_critical"`
}

// DefaultConfig returns a default configuration
func DefaultConfig() *Config {
	return &Config{
		Enabled:                    true,
		CheckInterval:             5 * time.Minute,
		MaxExecutionTime:          30 * time.Second,
		AutoFixEnabled:            true,
		ServiceRestartEnabled:     true,
		
		OverlaySpaceThreshold:     80,
		OverlayCriticalThreshold:  90,
		CleanupRetentionDays:      7,
		
		ServiceWatchdogEnabled:    true,
		ServiceTimeout:           5 * time.Minute,
		ServicesToMonitor:        []string{"nlbwmon", "mdcollectd", "connchecker", "hostapd", "network"},
		
		LogFloodEnabled:          true,
		LogFloodThreshold:        100,
		LogFloodPatterns:         []string{"STA-OPMODE-SMPS-MODE-CHANGED", "CTRL-EVENT-", "WPS-"},
		
		TimeDriftEnabled:         true,
		TimeDriftThreshold:       30 * time.Second,
		NTPTimeout:              10 * time.Second,
		
		InterfaceFlappingEnabled: true,
		FlappingThreshold:        5,
		FlappingInterfaces:       []string{"wan", "wwan", "mob"},
		
		StarlinkScriptEnabled:    true,
		StarlinkLogTimeout:       10 * time.Minute,
		
		DatabaseEnabled:          true,
		DatabaseErrorThreshold:   5,
		DatabaseMinSizeKB:        1,
		DatabaseMaxAgeDays:       7,
		
		NotificationsEnabled:     true,
		NotifyOnFixes:           true,
		NotifyOnFailures:        true,
		NotifyOnCritical:        true,
		NotificationCooldown:    30 * time.Minute,
		MaxNotificationsPerRun:  10,
		
		PushoverEnabled:          false,
		PushoverToken:           "",
		PushoverUser:            "",
		PushoverPriorityFixed:   0,
		PushoverPriorityFailed:  1,
		PushoverPriorityCritical: 2,
	}
}

// LoadConfig loads configuration from UCI
func LoadConfig(configPath string) (*Config, error) {
	// TODO: Implement UCI configuration loading
	// For now, return default config
	return DefaultConfig(), nil
}
