// Package uci provides UCI configuration management for starfail
package uci

import (
	"fmt"
	"time"
)

// Config represents the complete starfail configuration
type Config struct {
	Main MainConfig `uci:"starfail.main"`
	Members []MemberConfig `uci:"starfail.member"`
}

// MainConfig represents the main starfail configuration section
type MainConfig struct {
	Enable              bool          `uci:"enable" default:"true"`
	UseMwan3           bool          `uci:"use_mwan3" default:"true"`
	PollIntervalMs     int           `uci:"poll_interval_ms" default:"1500"`
	HistoryWindowS     time.Duration `uci:"history_window_s" default:"600s"`
	RetentionHours     int           `uci:"retention_hours" default:"24"`
	MaxRamMB           int           `uci:"max_ram_mb" default:"16"`
	DataCapMode        string        `uci:"data_cap_mode" default:"balanced"`
	Predictive         bool          `uci:"predictive" default:"true"`
	SwitchMargin       float64       `uci:"switch_margin" default:"10"`
	MinUptimeS         time.Duration `uci:"min_uptime_s" default:"20s"`
	CooldownS          time.Duration `uci:"cooldown_s" default:"20s"`
	MetricsListener    bool          `uci:"metrics_listener" default:"false"`
	HealthListener     bool          `uci:"health_listener" default:"true"`
	LogLevel           string        `uci:"log_level" default:"info"`
	LogFile            string        `uci:"log_file" default:""`
	
	// Fail/restore thresholds
	FailThresholdLoss     float64       `uci:"fail_threshold_loss" default:"5"`
	FailThresholdLatency  time.Duration `uci:"fail_threshold_latency" default:"1200ms"`
	FailMinDurationS      time.Duration `uci:"fail_min_duration_s" default:"10s"`
	RestoreThresholdLoss  float64       `uci:"restore_threshold_loss" default:"1"`
	RestoreThresholdLatency time.Duration `uci:"restore_threshold_latency" default:"800ms"`
	RestoreMinDurationS   time.Duration `uci:"restore_min_duration_s" default:"30s"`
	
	// Optional notifications
	PushoverToken string `uci:"pushover_token" default:""`
	PushoverUser  string `uci:"pushover_user" default:""`
	
	// Optional telemetry
	MqttBroker string `uci:"mqtt_broker" default:""`
	MqttTopic  string `uci:"mqtt_topic" default:"starfail/status"`
}

// MemberConfig represents per-member configuration overrides
type MemberConfig struct {
	Name            string        `uci:".name"`
	Detect          string        `uci:"detect" default:"auto"`         // auto|disable|force
	Class           string        `uci:"class" default:""`
	Weight          int           `uci:"weight" default:"50"`
	MinUptimeS      time.Duration `uci:"min_uptime_s"`
	CooldownS       time.Duration `uci:"cooldown_s"`
	PreferRoaming   bool          `uci:"prefer_roaming" default:"false"`
	Metered         bool          `uci:"metered" default:"false"`
}

// Loader handles UCI configuration loading and validation
type Loader struct {
	configPath string
}

// NewLoader creates a new UCI configuration loader
func NewLoader(configPath string) *Loader {
	return &Loader{
		configPath: configPath,
	}
}

// Load reads and parses the UCI configuration
func (l *Loader) Load() (*Config, error) {
	// TODO: Implement UCI loading
	// 1. Parse UCI config file at l.configPath
	// 2. Apply defaults for missing values
	// 3. Validate ranges and constraints
	// 4. Log warnings for defaulted/invalid values
	// 5. Return parsed and validated config
	
	// For now, return default config
	config := &Config{
		Main: MainConfig{
			Enable:              true,
			UseMwan3:           true,
			PollIntervalMs:     1500,
			HistoryWindowS:     600 * time.Second,
			RetentionHours:     24,
			MaxRamMB:           16,
			DataCapMode:        "balanced",
			Predictive:         true,
			SwitchMargin:       10,
			MinUptimeS:         20 * time.Second,
			CooldownS:          20 * time.Second,
			MetricsListener:    false,
			HealthListener:     true,
			LogLevel:           "info",
			LogFile:            "",
			FailThresholdLoss:     5,
			FailThresholdLatency:  1200 * time.Millisecond,
			FailMinDurationS:      10 * time.Second,
			RestoreThresholdLoss:  1,
			RestoreThresholdLatency: 800 * time.Millisecond,
			RestoreMinDurationS:   30 * time.Second,
			PushoverToken:      "",
			PushoverUser:       "",
			MqttBroker:         "",
			MqttTopic:          "starfail/status",
		},
		Members: []MemberConfig{},
	}
	
	return config, nil
}

// Save writes the configuration back to UCI
func (l *Loader) Save(config *Config) error {
	// TODO: Implement UCI saving
	// 1. Convert config struct back to UCI format
	// 2. Write to UCI config file
	// 3. Commit changes
	return fmt.Errorf("UCI save not implemented yet")
}

// Validate checks configuration constraints and applies defaults
func (l *Loader) Validate(config *Config) error {
	// TODO: Implement validation
	// 1. Check numeric ranges
	// 2. Validate string enums
	// 3. Check time duration constraints
	// 4. Ensure weights and percentages are reasonable
	return nil
}
