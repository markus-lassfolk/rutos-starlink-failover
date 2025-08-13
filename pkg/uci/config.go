// Package uci provides UCI configuration management for starfail
package uci

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// Config represents the complete starfail configuration
type Config struct {
	Main          MainConfig         `uci:"starfail.main"`
	Scoring       ScoringConfig      `uci:"starfail.scoring"`
	SysMgmt       SysMgmtConfig      `uci:"starfail.sysmgmt"`
	Recovery      RecoveryConfig     `uci:"starfail.recovery"`
	Notifications NotificationConfig `uci:"starfail.notifications"`
	Sampling      SamplingConfig     `uci:"starfail.sampling"`
	Members       []MemberConfig     `uci:"starfail.member"`
}

// ScoringConfig represents scoring algorithm configuration
type ScoringConfig struct {
	WeightLatency     float64 `uci:"weight_latency" default:"25"`
	WeightLoss        float64 `uci:"weight_loss" default:"30"`
	WeightJitter      float64 `uci:"weight_jitter" default:"15"`
	WeightObstruction float64 `uci:"weight_obstruction" default:"20"`

	LatencyOkMs       float64 `uci:"latency_ok_ms" default:"50"`
	LatencyBadMs      float64 `uci:"latency_bad_ms" default:"1500"`
	LossOkPct         float64 `uci:"loss_ok_pct" default:"0"`
	LossBadPct        float64 `uci:"loss_bad_pct" default:"10"`
	JitterOkMs        float64 `uci:"jitter_ok_ms" default:"5"`
	JitterBadMs       float64 `uci:"jitter_bad_ms" default:"200"`
	ObstructionOkPct  float64 `uci:"obstruction_ok_pct" default:"0"`
	ObstructionBadPct float64 `uci:"obstruction_bad_pct" default:"10"`
}

// SysMgmtConfig represents system management configuration
type SysMgmtConfig struct {
	Enable                 bool `uci:"enable" default:"true"`
	OverlayCleanupDays     int  `uci:"overlay_cleanup_days" default:"7"`
	LogCleanupDays         int  `uci:"log_cleanup_days" default:"3"`
	ServiceCheckInterval   int  `uci:"service_check_interval" default:"300"`
	TimeDriftThreshold     int  `uci:"time_drift_threshold" default:"30"`
	InterfaceFlapThreshold int  `uci:"interface_flap_threshold" default:"5"`
}

// MainConfig represents the main starfail configuration section
type MainConfig struct {
	Enable              bool          `uci:"enable" default:"true"`
	UseMwan3            bool          `uci:"use_mwan3" default:"true"`
	DryRun              bool          `uci:"dry_run" default:"false"`
	EnableUbus          bool          `uci:"enable_ubus" default:"true"`
	PollIntervalMs      int           `uci:"poll_interval_ms" default:"1500"`
	HistoryWindowS      time.Duration `uci:"history_window_s" default:"600s"`
	RetentionHours      int           `uci:"retention_hours" default:"24"`
	MaxRAMMB            int           `uci:"max_ram_mb" default:"16"`
	MaxSamplesPerMember int           `uci:"max_samples_per_member" default:"1000"`
	MaxEvents           int           `uci:"max_events" default:"500"`
	DataCapMode         string        `uci:"data_cap_mode" default:"balanced"`
	Predictive          bool          `uci:"predictive" default:"true"`
	SwitchMargin        float64       `uci:"switch_margin" default:"10"`
	MinUptimeS          time.Duration `uci:"min_uptime_s" default:"20s"`
	CooldownS           int           `uci:"cooldown_s" default:"30"`
	EWMAAlpha           float64       `uci:"ewma_alpha" default:"0.2"`
	MetricsListener     bool          `uci:"metrics_listener" default:"false"`
	HealthListener      bool          `uci:"health_listener" default:"true"`
	LogLevel            string        `uci:"log_level" default:"info"`
	LogFile             string        `uci:"log_file" default:""`

	// Fail/restore thresholds
	FailThresholdLoss       float64       `uci:"fail_threshold_loss" default:"5"`
	FailThresholdLatency    time.Duration `uci:"fail_threshold_latency" default:"1200ms"`
	FailMinDurationS        time.Duration `uci:"fail_min_duration_s" default:"10s"`
	RestoreThresholdLoss    float64       `uci:"restore_threshold_loss" default:"1"`
	RestoreThresholdLatency time.Duration `uci:"restore_threshold_latency" default:"800ms"`
	RestoreMinDurationS     time.Duration `uci:"restore_min_duration_s" default:"30s"`

	// Optional notifications
	PushoverToken string `uci:"pushover_token" default:""`
	PushoverUser  string `uci:"pushover_user" default:""`

	// Optional telemetry
	MqttBroker string `uci:"mqtt_broker" default:""`
	MqttTopic  string `uci:"mqtt_topic" default:"starfail/status"`
}

// MemberConfig represents per-member configuration overrides
type MemberConfig struct {
	Name          string        `uci:".name"`
	Detect        string        `uci:"detect" default:"auto"` // auto|disable|force
	Class         string        `uci:"class" default:""`
	Weight        int           `uci:"weight" default:"50"`
	MinUptimeS    time.Duration `uci:"min_uptime_s"`
	CooldownS     time.Duration `uci:"cooldown_s"`
	PreferRoaming bool          `uci:"prefer_roaming" default:"false"`
	Metered       bool          `uci:"metered" default:"false"`
}

// RecoveryConfig represents backup and recovery configuration
type RecoveryConfig struct {
	Enable             bool   `uci:"enable" default:"true"`
	BackupDir          string `uci:"backup_dir" default:"/etc/starfail/backup"`
	MaxVersions        int    `uci:"max_versions" default:"10"`
	AutoBackupOnChange bool   `uci:"auto_backup_on_change" default:"true"`
	BackupInterval     int    `uci:"backup_interval_hours" default:"24"`
	CompressBackups    bool   `uci:"compress_backups" default:"true"`
}

// NotificationConfig represents notification system configuration
type NotificationConfig struct {
	Enable            bool   `uci:"enable" default:"true"`
	RateLimitMinutes  int    `uci:"rate_limit_minutes" default:"5"`
	PriorityThreshold string `uci:"priority_threshold" default:"medium"`

	// Pushover
	PushoverEnabled bool   `uci:"pushover_enabled" default:"false"`
	PushoverToken   string `uci:"pushover_token" default:""`
	PushoverUser    string `uci:"pushover_user" default:""`

	// MQTT
	MqttEnabled bool   `uci:"mqtt_enabled" default:"false"`
	MqttBroker  string `uci:"mqtt_broker" default:""`
	MqttTopic   string `uci:"mqtt_topic" default:"starfail/alerts"`

	// Webhook
	WebhookEnabled bool   `uci:"webhook_enabled" default:"false"`
	WebhookURL     string `uci:"webhook_url" default:""`

	// Email
	EmailEnabled    bool   `uci:"email_enabled" default:"false"`
	EmailSMTPServer string `uci:"email_smtp_server" default:""`
	EmailFrom       string `uci:"email_from" default:""`
	EmailTo         string `uci:"email_to" default:""`
}

// SamplingConfig represents adaptive sampling configuration
type SamplingConfig struct {
	Enable               bool    `uci:"enable" default:"true"`
	BaseIntervalMs       int     `uci:"base_interval_ms" default:"1000"`
	FastIntervalMs       int     `uci:"fast_interval_ms" default:"500"`
	SlowIntervalMs       int     `uci:"slow_interval_ms" default:"5000"`
	PerformanceThreshold float64 `uci:"performance_threshold" default:"70.0"`
	DataCapAware         bool    `uci:"data_cap_aware" default:"true"`
	AdaptationFactor     float64 `uci:"adaptation_factor" default:"0.1"`
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
	// Start with default config
	config := l.getDefaultConfig()

	// Try to load UCI values
	err := l.loadFromUCI(config)
	if err != nil {
		// Log warning but continue with defaults
		// TODO: Use logger when available
		fmt.Printf("Warning: Failed to load UCI config: %v, using defaults\n", err)
	}

	// Validate the configuration
	err = l.Validate(config)
	if err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return config, nil
}

// getDefaultConfig returns configuration with default values
func (l *Loader) getDefaultConfig() *Config {
	return &Config{
		Main: MainConfig{
			Enable:                  true,
			UseMwan3:                true,
			DryRun:                  false,
			EnableUbus:              true,
			PollIntervalMs:          1500,
			HistoryWindowS:          600 * time.Second,
			RetentionHours:          24,
			MaxRAMMB:                16,
			MaxSamplesPerMember:     1000,
			MaxEvents:               500,
			DataCapMode:             "balanced",
			Predictive:              true,
			SwitchMargin:            10,
			MinUptimeS:              20 * time.Second,
			CooldownS:               30,
			EWMAAlpha:               0.2,
			MetricsListener:         false,
			HealthListener:          true,
			LogLevel:                "info",
			LogFile:                 "",
			FailThresholdLoss:       5,
			FailThresholdLatency:    1200 * time.Millisecond,
			FailMinDurationS:        10 * time.Second,
			RestoreThresholdLoss:    1,
			RestoreThresholdLatency: 800 * time.Millisecond,
			RestoreMinDurationS:     30 * time.Second,
			PushoverToken:           "",
			PushoverUser:            "",
			MqttBroker:              "",
			MqttTopic:               "starfail/status",
		},
		Scoring: ScoringConfig{
			WeightLatency:     25,
			WeightLoss:        30,
			WeightJitter:      15,
			WeightObstruction: 20,
			LatencyOkMs:       50,
			LatencyBadMs:      1500,
			LossOkPct:         0,
			LossBadPct:        10,
			JitterOkMs:        5,
			JitterBadMs:       200,
			ObstructionOkPct:  0,
			ObstructionBadPct: 10,
		},
		SysMgmt: SysMgmtConfig{
			Enable:                 true,
			OverlayCleanupDays:     7,
			LogCleanupDays:         3,
			ServiceCheckInterval:   300,
			TimeDriftThreshold:     30,
			InterfaceFlapThreshold: 5,
		},
		Recovery: RecoveryConfig{
			Enable:             true,
			BackupDir:          "/etc/starfail/backup",
			MaxVersions:        10,
			AutoBackupOnChange: true,
			BackupInterval:     24,
			CompressBackups:    true,
		},
		Notifications: NotificationConfig{
			Enable:            true,
			RateLimitMinutes:  5,
			PriorityThreshold: "medium",
			PushoverEnabled:   false,
			PushoverToken:     "",
			PushoverUser:      "",
			MqttEnabled:       false,
			MqttBroker:        "",
			MqttTopic:         "starfail/alerts",
			WebhookEnabled:    false,
			WebhookURL:        "",
			EmailEnabled:      false,
			EmailSMTPServer:   "",
			EmailFrom:         "",
			EmailTo:           "",
		},
		Sampling: SamplingConfig{
			Enable:               true,
			BaseIntervalMs:       1000,
			FastIntervalMs:       500,
			SlowIntervalMs:       5000,
			PerformanceThreshold: 70.0,
			DataCapAware:         true,
			AdaptationFactor:     0.1,
		},
		Members: []MemberConfig{},
	}
}

// loadFromUCI loads values from UCI using uci command
func (l *Loader) loadFromUCI(config *Config) error {
	// Load main section
	err := l.loadMainFromUCI(config)
	if err != nil {
		return fmt.Errorf("failed to load main config: %w", err)
	}

	// Load member sections
	err = l.loadMembersFromUCI(config)
	if err != nil {
		return fmt.Errorf("failed to load member configs: %w", err)
	}

	return nil
}

// loadMainFromUCI loads main section from UCI
func (l *Loader) loadMainFromUCI(config *Config) error {
	cmd := exec.Command("uci", "show", "starfail.main")
	output, err := cmd.Output()
	if err != nil {
		// Section doesn't exist, use defaults
		return nil
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Parse: starfail.main.option='value'
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := parts[0]
		value := strings.Trim(parts[1], "'\"")

		// Extract option name
		keyParts := strings.Split(key, ".")
		if len(keyParts) < 3 || keyParts[1] != "main" {
			continue
		}
		option := keyParts[2]

		// Set config values
		l.setMainOption(config, option, value)
	}

	return nil
}

// loadMembersFromUCI loads member sections from UCI
func (l *Loader) loadMembersFromUCI(config *Config) error {
	cmd := exec.Command("uci", "show", "starfail")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	memberMap := make(map[string]*MemberConfig)
	lines := strings.Split(string(output), "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || !strings.Contains(line, ".@member[") {
			continue
		}

		// Parse member line
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := parts[0]
		value := strings.Trim(parts[1], "'\"")

		// Extract member index and option from starfail.@member[0].option
		keyParts := strings.Split(key, ".")
		if len(keyParts) < 3 {
			continue
		}

		memberPart := keyParts[1]
		option := keyParts[2]

		// Extract index from @member[0]
		if !strings.HasPrefix(memberPart, "@member[") || !strings.HasSuffix(memberPart, "]") {
			continue
		}
		indexStr := memberPart[8 : len(memberPart)-1]

		// Get or create member
		member := memberMap[indexStr]
		if member == nil {
			member = &MemberConfig{
				Weight:        50,
				Detect:        "auto",
				PreferRoaming: false,
				Metered:       false,
			}
			memberMap[indexStr] = member
		}

		// Set option value
		l.setMemberOption(member, option, value)
	}

	// Convert map to slice
	config.Members = make([]MemberConfig, 0, len(memberMap))
	for _, member := range memberMap {
		config.Members = append(config.Members, *member)
	}

	return nil
}

// setMainOption sets a main config option from UCI value
func (l *Loader) setMainOption(config *Config, option, value string) {
	switch option {
	case "enable":
		config.Main.Enable = l.parseBool(value)
	case "use_mwan3":
		config.Main.UseMwan3 = l.parseBool(value)
	case "poll_interval_ms":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.PollIntervalMs = v
		}
	case "history_window_s":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.HistoryWindowS = time.Duration(v) * time.Second
		}
	case "retention_hours":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.RetentionHours = v
		}
	case "max_ram_mb":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.MaxRAMMB = v
		}
	case "data_cap_mode":
		config.Main.DataCapMode = value
	case "predictive":
		config.Main.Predictive = l.parseBool(value)
	case "switch_margin":
		if v, err := strconv.ParseFloat(value, 64); err == nil {
			config.Main.SwitchMargin = v
		}
	case "min_uptime_s":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.MinUptimeS = time.Duration(v) * time.Second
		}
	case "cooldown_s":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.CooldownS = int(v)
		}
	case "metrics_listener":
		config.Main.MetricsListener = l.parseBool(value)
	case "health_listener":
		config.Main.HealthListener = l.parseBool(value)
	case "log_level":
		config.Main.LogLevel = value
	case "log_file":
		config.Main.LogFile = value
	case "fail_threshold_loss":
		if v, err := strconv.ParseFloat(value, 64); err == nil {
			config.Main.FailThresholdLoss = v
		}
	case "fail_threshold_latency":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.FailThresholdLatency = time.Duration(v) * time.Millisecond
		}
	case "fail_min_duration_s":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.FailMinDurationS = time.Duration(v) * time.Second
		}
	case "restore_threshold_loss":
		if v, err := strconv.ParseFloat(value, 64); err == nil {
			config.Main.RestoreThresholdLoss = v
		}
	case "restore_threshold_latency":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.RestoreThresholdLatency = time.Duration(v) * time.Millisecond
		}
	case "restore_min_duration_s":
		if v, err := strconv.Atoi(value); err == nil {
			config.Main.RestoreMinDurationS = time.Duration(v) * time.Second
		}
	case "pushover_token":
		config.Main.PushoverToken = value
	case "pushover_user":
		config.Main.PushoverUser = value
	case "mqtt_broker":
		config.Main.MqttBroker = value
	case "mqtt_topic":
		config.Main.MqttTopic = value
	}
}

// setMemberOption sets a member config option from UCI value
func (l *Loader) setMemberOption(member *MemberConfig, option, value string) {
	switch option {
	case "detect":
		member.Detect = value
	case "class":
		member.Class = value
	case "weight":
		if v, err := strconv.Atoi(value); err == nil {
			member.Weight = v
		}
	case "min_uptime_s":
		if v, err := strconv.Atoi(value); err == nil {
			member.MinUptimeS = time.Duration(v) * time.Second
		}
	case "cooldown_s":
		if v, err := strconv.Atoi(value); err == nil {
			member.CooldownS = time.Duration(v) * time.Second
		}
	case "prefer_roaming":
		member.PreferRoaming = l.parseBool(value)
	case "metered":
		member.Metered = l.parseBool(value)
	}
}

// parseBool parses a string as boolean (1/0, true/false, yes/no)
func (l *Loader) parseBool(value string) bool {
	value = strings.ToLower(value)
	return value == "1" || value == "true" || value == "yes" || value == "on"
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
	// Validate main config
	if err := l.validateMain(&config.Main); err != nil {
		return fmt.Errorf("main config validation failed: %w", err)
	}

	// Validate member configs
	for i, member := range config.Members {
		if err := l.validateMember(&member); err != nil {
			return fmt.Errorf("member[%d] config validation failed: %w", i, err)
		}
		config.Members[i] = member // Update in case of modifications
	}

	return nil
}

// validateMain validates main configuration
func (l *Loader) validateMain(main *MainConfig) error {
	// Validate numeric ranges
	if main.PollIntervalMs < 500 || main.PollIntervalMs > 30000 {
		return fmt.Errorf("poll_interval_ms must be between 500-30000ms, got %d", main.PollIntervalMs)
	}

	if main.HistoryWindowS < 60*time.Second || main.HistoryWindowS > 3600*time.Second {
		return fmt.Errorf("history_window_s must be between 60-3600s, got %v", main.HistoryWindowS)
	}

	if main.RetentionHours < 1 || main.RetentionHours > 168 {
		return fmt.Errorf("retention_hours must be between 1-168 hours, got %d", main.RetentionHours)
	}

	if main.MaxRAMMB < 4 || main.MaxRAMMB > 128 {
		return fmt.Errorf("max_ram_mb must be between 4-128MB, got %d", main.MaxRAMMB)
	}

	if main.SwitchMargin < 1 || main.SwitchMargin > 50 {
		return fmt.Errorf("switch_margin must be between 1-50, got %f", main.SwitchMargin)
	}

	if main.MinUptimeS < 1*time.Second || main.MinUptimeS > 300*time.Second {
		return fmt.Errorf("min_uptime_s must be between 1-300s, got %v", main.MinUptimeS)
	}

	if main.CooldownS < 1 || main.CooldownS > 300 {
		return fmt.Errorf("cooldown_s must be between 1-300s, got %v", main.CooldownS)
	}

	// Validate string enums
	validDataCapModes := []string{"conservative", "balanced", "aggressive"}
	if !l.contains(validDataCapModes, main.DataCapMode) {
		return fmt.Errorf("data_cap_mode must be one of %v, got '%s'", validDataCapModes, main.DataCapMode)
	}

	validLogLevels := []string{"debug", "info", "warn", "error"}
	if !l.contains(validLogLevels, main.LogLevel) {
		return fmt.Errorf("log_level must be one of %v, got '%s'", validLogLevels, main.LogLevel)
	}

	// Validate thresholds
	if main.FailThresholdLoss < 0 || main.FailThresholdLoss > 100 {
		return fmt.Errorf("fail_threshold_loss must be between 0-100%%, got %f", main.FailThresholdLoss)
	}

	if main.RestoreThresholdLoss < 0 || main.RestoreThresholdLoss > 100 {
		return fmt.Errorf("restore_threshold_loss must be between 0-100%%, got %f", main.RestoreThresholdLoss)
	}

	if main.FailThresholdLatency < 50*time.Millisecond || main.FailThresholdLatency > 10*time.Second {
		return fmt.Errorf("fail_threshold_latency must be between 50ms-10s, got %v", main.FailThresholdLatency)
	}

	if main.RestoreThresholdLatency < 10*time.Millisecond || main.RestoreThresholdLatency > 5*time.Second {
		return fmt.Errorf("restore_threshold_latency must be between 10ms-5s, got %v", main.RestoreThresholdLatency)
	}

	return nil
}

// validateMember validates member configuration
func (l *Loader) validateMember(member *MemberConfig) error {
	// Generate name if not set
	if member.Name == "" {
		if member.Class != "" {
			member.Name = fmt.Sprintf("member_%s", member.Class)
		} else {
			member.Name = "member_unknown"
		}
	}

	// Validate detect mode
	validDetectModes := []string{"auto", "disable", "force"}
	if !l.contains(validDetectModes, member.Detect) {
		return fmt.Errorf("detect must be one of %v, got '%s'", validDetectModes, member.Detect)
	}

	// Validate class if set
	if member.Class != "" {
		validClasses := []string{"starlink", "cellular", "wifi", "lan", "other"}
		if !l.contains(validClasses, member.Class) {
			return fmt.Errorf("class must be one of %v, got '%s'", validClasses, member.Class)
		}
	}

	// Validate weight
	if member.Weight < 1 || member.Weight > 100 {
		return fmt.Errorf("weight must be between 1-100, got %d", member.Weight)
	}

	// Validate durations if set
	if member.MinUptimeS != 0 && (member.MinUptimeS < 1*time.Second || member.MinUptimeS > 300*time.Second) {
		return fmt.Errorf("min_uptime_s must be between 1-300s, got %v", member.MinUptimeS)
	}

	if member.CooldownS != 0 && (member.CooldownS < 1*time.Second || member.CooldownS > 300*time.Second) {
		return fmt.Errorf("cooldown_s must be between 1-300s, got %v", member.CooldownS)
	}

	return nil
}

// contains checks if a slice contains a string
func (l *Loader) contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}
