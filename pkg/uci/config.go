package uci

import (
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
	Enable            bool   `json:"enable"`
	UseMWAN3          bool   `json:"use_mwan3"`
	PollIntervalMS    int    `json:"poll_interval_ms"`
	HistoryWindowS    int    `json:"history_window_s"`
	RetentionHours    int    `json:"retention_hours"`
	MaxRAMMB          int    `json:"max_ram_mb"`
	DataCapMode       string `json:"data_cap_mode"`
	Predictive        bool   `json:"predictive"`
	SwitchMargin      int    `json:"switch_margin"`
	MinUptimeS        int    `json:"min_uptime_s"`
	CooldownS         int    `json:"cooldown_s"`
	MetricsListener   bool   `json:"metrics_listener"`
	HealthListener    bool   `json:"health_listener"`
	LogLevel          string `json:"log_level"`
	LogFile           string `json:"log_file"`

	// Thresholds
	FailThresholdLoss     int `json:"fail_threshold_loss"`
	FailThresholdLatency  int `json:"fail_threshold_latency"`
	FailMinDurationS      int `json:"fail_min_duration_s"`
	RestoreThresholdLoss  int `json:"restore_threshold_loss"`
	RestoreThresholdLatency int `json:"restore_threshold_latency"`
	RestoreMinDurationS   int `json:"restore_min_duration_s"`

	// Notifications
	PushoverToken string `json:"pushover_token"`
	PushoverUser  string `json:"pushover_user"`

	// Telemetry publish
	MQTTBroker string `json:"mqtt_broker"`
	MQTTTopic  string `json:"mqtt_topic"`

	// Member configurations
	Members map[string]*MemberConfig `json:"members"`

	// Internal state
	lastModified time.Time
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
	DefaultPollIntervalMS     = 1500
	DefaultHistoryWindowS     = 600
	DefaultRetentionHours     = 24
	DefaultMaxRAMMB           = 16
	DefaultDataCapMode        = "balanced"
	DefaultSwitchMargin       = 10
	DefaultMinUptimeS         = 20
	DefaultCooldownS          = 20
	DefaultLogLevel           = "info"
	DefaultFailThresholdLoss  = 5
	DefaultFailThresholdLatency = 1200
	DefaultFailMinDurationS   = 10
	DefaultRestoreThresholdLoss = 1
	DefaultRestoreThresholdLatency = 800
	DefaultRestoreMinDurationS = 30
)

// LoadConfig loads and validates the starfail configuration from UCI
func LoadConfig(path string) (*Config, error) {
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
	c.LogLevel = DefaultLogLevel
	c.LogFile = ""
	c.FailThresholdLoss = DefaultFailThresholdLoss
	c.FailThresholdLatency = DefaultFailThresholdLatency
	c.FailMinDurationS = DefaultFailMinDurationS
	c.RestoreThresholdLoss = DefaultRestoreThresholdLoss
	c.RestoreThresholdLatency = DefaultRestoreThresholdLatency
	c.RestoreMinDurationS = DefaultRestoreMinDurationS
	c.PushoverToken = ""
	c.PushoverUser = ""
	c.MQTTBroker = ""
	c.MQTTTopic = "starfail/status"
}

// parseUCI parses the UCI configuration file
func (c *Config) parseUCI(path string) error {
	// TODO: Implement actual UCI parsing
	// For now, we'll use a simple approach that reads the file and parses it
	// In a real implementation, this would use the UCI library or parse the file format

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
	case "mqtt_broker":
		c.MQTTBroker = value
	case "mqtt_topic":
		c.MQTTTopic = value
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
