package uci

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
)

// Config represents the starfail configuration
type Config struct {
	// Main configuration
	Enable              bool   `json:"enable"`
	UseMWAN3            bool   `json:"use_mwan3"`
	PollIntervalMS      int    `json:"poll_interval_ms"`
	DecisionIntervalMS  int    `json:"decision_interval_ms"`
	DiscoveryIntervalMS int    `json:"discovery_interval_ms"`
	CleanupIntervalMS   int    `json:"cleanup_interval_ms"`
	HistoryWindowS      int    `json:"history_window_s"`
	RetentionHours      int    `json:"retention_hours"`
	MaxRAMMB            int    `json:"max_ram_mb"`
	DataCapMode         string `json:"data_cap_mode"`
	Predictive          bool   `json:"predictive"`
	SwitchMargin        int    `json:"switch_margin"`
	MinUptimeS          int    `json:"min_uptime_s"`
	CooldownS           int    `json:"cooldown_s"`
	MetricsListener     bool   `json:"metrics_listener"`
	HealthListener      bool   `json:"health_listener"`
	MetricsPort         int    `json:"metrics_port"`
	HealthPort          int    `json:"health_port"`
	LogLevel            string `json:"log_level"`
	LogFile             string `json:"log_file"`

	// Performance and Security
	PerformanceProfiling bool `json:"performance_profiling"`
	SecurityAuditing     bool `json:"security_auditing"`
	ProfilingEnabled     bool `json:"profiling_enabled"`
	AuditingEnabled      bool `json:"auditing_enabled"`

	// Machine Learning
	MLEnabled    bool   `json:"ml_enabled"`
	MLModelPath  string `json:"ml_model_path"`
	MLTraining   bool   `json:"ml_training"`
	MLPrediction bool   `json:"ml_prediction"`

	// Starlink API Configuration
	StarlinkAPIHost   string `json:"starlink_api_host"`
	StarlinkAPIPort   int    `json:"starlink_api_port"`
	StarlinkTimeout   int    `json:"starlink_timeout_s"`
	StarlinkGRPCFirst bool   `json:"starlink_grpc_first"`
	StarlinkHTTPFirst bool   `json:"starlink_http_first"`

	// Security Configuration
	AllowedIPs        []string `json:"allowed_ips"`
	BlockedIPs        []string `json:"blocked_ips"`
	AllowedPorts      []int    `json:"allowed_ports"`
	BlockedPorts      []int    `json:"blocked_ports"`
	MaxFailedAttempts int      `json:"max_failed_attempts"`
	BlockDuration     int      `json:"block_duration"`

	// Thresholds
	FailThresholdLoss       int `json:"fail_threshold_loss"`
	FailThresholdLatency    int `json:"fail_threshold_latency"`
	FailMinDurationS        int `json:"fail_min_duration_s"`
	RestoreThresholdLoss    int `json:"restore_threshold_loss"`
	RestoreThresholdLatency int `json:"restore_threshold_latency"`
	RestoreMinDurationS     int `json:"restore_min_duration_s"`

	// Notifications
	PushoverToken          string `json:"pushover_token"`
	PushoverUser           string `json:"pushover_user"`
	PushoverEnabled        bool   `json:"pushover_enabled"`
	PushoverDevice         string `json:"pushover_device"`
	PriorityThreshold      string `json:"priority_threshold"`
	AcknowledgmentTracking bool   `json:"acknowledgment_tracking"`
	LocationEnabled        bool   `json:"location_enabled"`
	RichContextEnabled     bool   `json:"rich_context_enabled"`
	NotifyOnFailover       bool   `json:"notify_on_failover"`
	NotifyOnFailback       bool   `json:"notify_on_failback"`
	NotifyOnMemberDown     bool   `json:"notify_on_member_down"`
	NotifyOnMemberUp       bool   `json:"notify_on_member_up"`
	NotifyOnPredictive     bool   `json:"notify_on_predictive"`
	NotifyOnCritical       bool   `json:"notify_on_critical"`
	NotifyOnRecovery       bool   `json:"notify_on_recovery"`
	NotificationCooldownS  int    `json:"notification_cooldown_s"`
	MaxNotificationsHour   int    `json:"max_notifications_hour"`
	PriorityFailover       int    `json:"priority_failover"`
	PriorityFailback       int    `json:"priority_failback"`
	PriorityMemberDown     int    `json:"priority_member_down"`
	PriorityMemberUp       int    `json:"priority_member_up"`
	PriorityPredictive     int    `json:"priority_predictive"`
	PriorityCritical       int    `json:"priority_critical"`
	PriorityRecovery       int    `json:"priority_recovery"`

	// Telemetry publish
	MQTTBroker string `json:"mqtt_broker"`
	MQTTTopic  string `json:"mqtt_topic"`

	// MQTT Configuration
	MQTT MQTTConfig `json:"mqtt"`

	// Member configurations
	Members map[string]*MemberConfig `json:"members"`

	// Internal state
	lastModified time.Time
}

// MQTTConfig represents MQTT configuration
type MQTTConfig struct {
	Broker      string `json:"broker"`
	Port        int    `json:"port"`
	ClientID    string `json:"client_id"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	TopicPrefix string `json:"topic_prefix"`
	QoS         int    `json:"qos"`
	Retain      bool   `json:"retain"`
	Enabled     bool   `json:"enabled"`
}

// MemberConfig represents configuration for a specific member
type MemberConfig struct {
	Detect        string `json:"detect"`
	Class         string `json:"class"`
	Weight        int    `json:"weight"`
	MinUptimeS    int    `json:"min_uptime_s"`
	CooldownS     int    `json:"cooldown_s"`
	PreferRoaming bool   `json:"prefer_roaming"`
	Metered       bool   `json:"metered"`
}

// Default configuration values
const (
	DefaultPollIntervalMS          = 1500
	DefaultHistoryWindowS          = 600
	DefaultRetentionHours          = 24
	DefaultMaxRAMMB                = 16
	DefaultDataCapMode             = "balanced"
	DefaultSwitchMargin            = 10
	DefaultMinUptimeS              = 5
	DefaultCooldownS               = 20
	DefaultLogLevel                = "info"
	DefaultFailThresholdLoss       = 5
	DefaultFailThresholdLatency    = 1200
	DefaultFailMinDurationS        = 10
	DefaultRestoreThresholdLoss    = 1
	DefaultRestoreThresholdLatency = 800
	DefaultRestoreMinDurationS     = 30
)

// LoadConfig loads and validates the starfail configuration from UCI
func LoadConfig(path string) (*Config, error) {
	// Try to load from UCI first
	uci := NewUCI(nil) // We'll create a proper logger later
	config, err := uci.LoadConfig(context.Background())
	if err != nil {
		// Fallback to file-based loading for development/testing
		return loadConfigFromFile(path)
	}

	// Validate configuration
	if err := config.validate(); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	return config, nil
}

// loadConfigFromFile loads configuration from a file (fallback method)
func loadConfigFromFile(path string) (*Config, error) {
	cfg := &Config{
		Members: make(map[string]*MemberConfig),
	}

	// Set defaults
	cfg.setDefaults()

	// Check if config file exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		// Return default config if file doesn't exist
		return cfg, nil
	}

	// Parse UCI configuration
	if err := cfg.parseUCI(path); err != nil {
		return nil, fmt.Errorf("failed to parse UCI config: %w", err)
	}

	// Validate configuration
	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	return cfg, nil
}

// setDefaults sets default values for the configuration
func (c *Config) setDefaults() {
	c.Enable = true
	c.UseMWAN3 = true
	c.PollIntervalMS = DefaultPollIntervalMS
	c.DecisionIntervalMS = 5000
	c.DiscoveryIntervalMS = 30000
	c.CleanupIntervalMS = 60000
	c.HistoryWindowS = DefaultHistoryWindowS
	c.RetentionHours = DefaultRetentionHours
	c.MaxRAMMB = DefaultMaxRAMMB
	c.DataCapMode = DefaultDataCapMode
	c.Predictive = true
	c.SwitchMargin = DefaultSwitchMargin
	c.MinUptimeS = DefaultMinUptimeS
	c.CooldownS = DefaultCooldownS
	c.MetricsListener = false
	c.HealthListener = true
	c.MetricsPort = 9090
	c.HealthPort = 8080
	c.LogLevel = DefaultLogLevel
	c.LogFile = ""

	// Performance and Security defaults
	c.PerformanceProfiling = false
	c.SecurityAuditing = false
	c.ProfilingEnabled = false
	c.AuditingEnabled = false

	// Machine Learning defaults
	c.MLEnabled = false
	c.MLModelPath = "/tmp/starfail/models"
	c.MLTraining = false
	c.MLPrediction = false

	// Starlink API defaults
	c.StarlinkAPIHost = "192.168.100.1"
	c.StarlinkAPIPort = 9200
	c.StarlinkTimeout = 10
	c.StarlinkGRPCFirst = true
	c.StarlinkHTTPFirst = false

	// Security defaults
	c.AllowedIPs = []string{}
	c.BlockedIPs = []string{}
	c.AllowedPorts = []int{8080, 9090}
	c.BlockedPorts = []int{22, 23, 25}
	c.MaxFailedAttempts = 5
	c.BlockDuration = 24

	c.FailThresholdLoss = DefaultFailThresholdLoss
	c.FailThresholdLatency = DefaultFailThresholdLatency
	c.FailMinDurationS = DefaultFailMinDurationS
	c.RestoreThresholdLoss = DefaultRestoreThresholdLoss
	c.RestoreThresholdLatency = DefaultRestoreThresholdLatency
	c.RestoreMinDurationS = DefaultRestoreMinDurationS

	// Notification defaults
	c.PushoverToken = ""
	c.PushoverUser = ""
	c.PushoverEnabled = false
	c.PushoverDevice = ""
	c.PriorityThreshold = "warning"
	c.AcknowledgmentTracking = true
	c.LocationEnabled = true
	c.RichContextEnabled = true
	c.NotifyOnFailover = true
	c.NotifyOnFailback = true
	c.NotifyOnMemberDown = true
	c.NotifyOnMemberUp = false
	c.NotifyOnPredictive = true
	c.NotifyOnCritical = true
	c.NotifyOnRecovery = true
	c.NotificationCooldownS = 300 // 5 minutes
	c.MaxNotificationsHour = 20
	c.PriorityFailover = 1   // High
	c.PriorityFailback = 0   // Normal
	c.PriorityMemberDown = 1 // High
	c.PriorityMemberUp = -1  // Low
	c.PriorityPredictive = 0 // Normal
	c.PriorityCritical = 2   // Emergency
	c.PriorityRecovery = 0   // Normal

	c.MQTTBroker = ""
	c.MQTTTopic = "starfail/status"

	// Set MQTT defaults
	c.MQTT = MQTTConfig{
		Broker:      "localhost",
		Port:        1883,
		ClientID:    "starfaild",
		TopicPrefix: "starfail",
		QoS:         1,
		Retain:      false,
		Enabled:     false,
	}
}

// parseUCI parses the UCI configuration file
func (c *Config) parseUCI(path string) error {
	// Parse UCI configuration file using simple text parsing
	// This implements a basic UCI parser that handles the starfail configuration format

	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	lines := strings.Split(string(data), "\n")
	var currentSection string
	var currentOption string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "config ") {
			parts := strings.Fields(line)
			if len(parts) >= 3 {
				currentSection = parts[2]
				if parts[1] == "starfail" && currentSection == "main" {
					// Main configuration section
				} else if parts[1] == "member" {
					// Member configuration section
					if c.Members[currentSection] == nil {
						c.Members[currentSection] = &MemberConfig{
							Detect:     pkg.DetectAuto,
							Weight:     50,
							MinUptimeS: c.MinUptimeS,
							CooldownS:  c.CooldownS,
						}
					}
				}
			}
		} else if strings.HasPrefix(line, "option ") {
			parts := strings.Fields(line)
			if len(parts) >= 3 {
				currentOption = parts[1]
				value := strings.Trim(parts[2], "'\"")

				if currentSection == "main" {
					c.parseMainOption(currentOption, value)
				} else if c.Members[currentSection] != nil {
					c.parseMemberOption(currentSection, currentOption, value)
				}
			}
		}
	}

	return nil
}

// parseMainOption parses a main configuration option
func (c *Config) parseMainOption(option, value string) {
	switch option {
	case "enable":
		c.Enable = value == "1"
	case "use_mwan3":
		c.UseMWAN3 = value == "1"
	case "poll_interval_ms":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.PollIntervalMS = v
		}
	case "history_window_s":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.HistoryWindowS = v
		}
	case "retention_hours":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.RetentionHours = v
		}
	case "max_ram_mb":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.MaxRAMMB = v
		}
	case "data_cap_mode":
		if isValidDataCapMode(value) {
			c.DataCapMode = value
		}
	case "predictive":
		c.Predictive = value == "1"
	case "switch_margin":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.SwitchMargin = v
		}
	case "min_uptime_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.MinUptimeS = v
		}
	case "cooldown_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.CooldownS = v
		}
	case "metrics_listener":
		c.MetricsListener = value == "1"
	case "health_listener":
		c.HealthListener = value == "1"
	case "log_level":
		if isValidLogLevel(value) {
			c.LogLevel = value
		}
	case "log_file":
		c.LogFile = value

	// Performance and Security options
	case "performance_profiling":
		c.PerformanceProfiling = value == "1"
	case "security_auditing":
		c.SecurityAuditing = value == "1"
	case "profiling_enabled":
		c.ProfilingEnabled = value == "1"
	case "auditing_enabled":
		c.AuditingEnabled = value == "1"

	// Machine Learning options
	case "ml_enabled":
		c.MLEnabled = value == "1"
	case "ml_model_path":
		c.MLModelPath = value
	case "ml_training":
		c.MLTraining = value == "1"
	case "ml_prediction":
		c.MLPrediction = value == "1"

	// Security options
	case "max_failed_attempts":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.MaxFailedAttempts = v
		}
	case "block_duration":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.BlockDuration = v
		}

	case "fail_threshold_loss":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.FailThresholdLoss = v
		}
	case "fail_threshold_latency":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.FailThresholdLatency = v
		}
	case "fail_min_duration_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.FailMinDurationS = v
		}
	case "restore_threshold_loss":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.RestoreThresholdLoss = v
		}
	case "restore_threshold_latency":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.RestoreThresholdLatency = v
		}
	case "restore_min_duration_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			c.RestoreMinDurationS = v
		}
	case "pushover_token":
		c.PushoverToken = value
	case "pushover_user":
		c.PushoverUser = value
	case "pushover_enabled":
		c.PushoverEnabled = value == "1"
	case "pushover_device":
		c.PushoverDevice = value
	case "priority_threshold":
		// Validate priority threshold
		threshold := strings.ToLower(value)
		if threshold == "info" || threshold == "warning" || threshold == "critical" || threshold == "emergency" {
			c.PriorityThreshold = threshold
		}
	case "acknowledgment_tracking":
		c.AcknowledgmentTracking = value == "1"
	case "location_enabled":
		c.LocationEnabled = value == "1"
	case "rich_context_enabled":
		c.RichContextEnabled = value == "1"
	case "notify_on_failover":
		c.NotifyOnFailover = value == "1"
	case "notify_on_failback":
		c.NotifyOnFailback = value == "1"
	case "notify_on_member_down":
		c.NotifyOnMemberDown = value == "1"
	case "notify_on_member_up":
		c.NotifyOnMemberUp = value == "1"
	case "notify_on_predictive":
		c.NotifyOnPredictive = value == "1"
	case "notify_on_critical":
		c.NotifyOnCritical = value == "1"
	case "notify_on_recovery":
		c.NotifyOnRecovery = value == "1"
	case "notification_cooldown_s":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.NotificationCooldownS = v
		}
	case "max_notifications_hour":
		if v, err := strconv.Atoi(value); err == nil && v > 0 {
			c.MaxNotificationsHour = v
		}
	case "priority_failover":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityFailover = v
		}
	case "priority_failback":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityFailback = v
		}
	case "priority_member_down":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityMemberDown = v
		}
	case "priority_member_up":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityMemberUp = v
		}
	case "priority_predictive":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityPredictive = v
		}
	case "priority_critical":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityCritical = v
		}
	case "priority_recovery":
		if v, err := strconv.Atoi(value); err == nil && v >= -2 && v <= 2 {
			c.PriorityRecovery = v
		}
	case "mqtt_broker":
		c.MQTTBroker = value
	case "mqtt_topic":
		c.MQTTTopic = value

	// Starlink API configuration options
	case "starlink_api_host":
		if value != "" {
			c.StarlinkAPIHost = value
		}
	case "starlink_api_port":
		if v, err := strconv.Atoi(value); err == nil && v > 0 && v <= 65535 {
			c.StarlinkAPIPort = v
		}
	case "starlink_timeout_s":
		if v, err := strconv.Atoi(value); err == nil && v > 0 && v <= 300 {
			c.StarlinkTimeout = v
		}
	case "starlink_grpc_first":
		c.StarlinkGRPCFirst = value == "1"
	case "starlink_http_first":
		c.StarlinkHTTPFirst = value == "1"
	}
}

// parseMemberOption parses a member configuration option
func (c *Config) parseMemberOption(memberName, option, value string) {
	member := c.Members[memberName]
	if member == nil {
		return
	}

	switch option {
	case "detect":
		if isValidDetectMode(value) {
			member.Detect = value
		}
	case "class":
		if isValidMemberClass(value) {
			member.Class = value
		}
	case "weight":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			member.Weight = v
		}
	case "min_uptime_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			member.MinUptimeS = v
		}
	case "cooldown_s":
		if v, err := strconv.Atoi(value); err == nil && v >= 0 {
			member.CooldownS = v
		}
	case "prefer_roaming":
		member.PreferRoaming = value == "1"
	case "metered":
		member.Metered = value == "1"
	}
}

// validate validates the configuration
func (c *Config) validate() error {
	if c.PollIntervalMS < 100 || c.PollIntervalMS > 10000 {
		return fmt.Errorf("poll_interval_ms must be between 100 and 10000")
	}

	if c.HistoryWindowS < 60 || c.HistoryWindowS > 3600 {
		return fmt.Errorf("history_window_s must be between 60 and 3600")
	}

	if c.RetentionHours < 1 || c.RetentionHours > 168 {
		return fmt.Errorf("retention_hours must be between 1 and 168")
	}

	if c.MaxRAMMB < 1 || c.MaxRAMMB > 128 {
		return fmt.Errorf("max_ram_mb must be between 1 and 128")
	}

	if c.SwitchMargin < 0 || c.SwitchMargin > 100 {
		return fmt.Errorf("switch_margin must be between 0 and 100")
	}

	return nil
}

// Helper functions for validation
func isValidDataCapMode(mode string) bool {
	validModes := []string{"balanced", "conservative", "aggressive"}
	for _, valid := range validModes {
		if mode == valid {
			return true
		}
	}
	return false
}

func isValidLogLevel(level string) bool {
	validLevels := []string{"debug", "info", "warn", "error"}
	for _, valid := range validLevels {
		if level == valid {
			return true
		}
	}
	return false
}

func isValidDetectMode(mode string) bool {
	validModes := []string{pkg.DetectAuto, pkg.DetectDisable, pkg.DetectForce}
	for _, valid := range validModes {
		if mode == valid {
			return true
		}
	}
	return false
}

func isValidMemberClass(class string) bool {
	validClasses := []string{pkg.ClassStarlink, pkg.ClassCellular, pkg.ClassWiFi, pkg.ClassLAN, pkg.ClassOther}
	for _, valid := range validClasses {
		if class == valid {
			return true
		}
	}
	return false
}
