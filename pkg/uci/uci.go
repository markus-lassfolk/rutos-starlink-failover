package uci

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg/logx"
)

// UCI represents a UCI configuration manager
type UCI struct {
	logger *logx.Logger
}

// NewUCI creates a new UCI manager
func NewUCI(logger *logx.Logger) *UCI {
	return &UCI{
		logger: logger,
	}
}

// Get retrieves a UCI option value
func (u *UCI) Get(ctx context.Context, config, section, option string) (string, error) {
	cmd := exec.CommandContext(ctx, "uci", "get", fmt.Sprintf("%s.%s.%s", config, section, option))
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get UCI option %s.%s.%s: %w", config, section, option, err)
	}
	
	return strings.TrimSpace(string(output)), nil
}

// Set sets a UCI option value
func (u *UCI) Set(ctx context.Context, config, section, option, value string) error {
	cmd := exec.CommandContext(ctx, "uci", "set", fmt.Sprintf("%s.%s.%s=%s", config, section, option, value))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to set UCI option %s.%s.%s: %w", config, section, option, err)
	}
	return nil
}

// Delete deletes a UCI option
func (u *UCI) Delete(ctx context.Context, config, section, option string) error {
	cmd := exec.CommandContext(ctx, "uci", "delete", fmt.Sprintf("%s.%s.%s", config, section, option))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to delete UCI option %s.%s.%s: %w", config, section, option, err)
	}
	return nil
}

// AddSection adds a new section to a UCI config
func (u *UCI) AddSection(ctx context.Context, config, sectionType, sectionName string) error {
	cmd := exec.CommandContext(ctx, "uci", "add", config, sectionType)
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to add UCI section %s.%s: %w", config, sectionType, err)
	}
	
	// If sectionName is provided, rename the section
	if sectionName != "" {
		sectionID := strings.TrimSpace(string(output))
		cmd = exec.CommandContext(ctx, "uci", "rename", fmt.Sprintf("%s.%s=%s", config, sectionID, sectionName))
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to rename UCI section %s.%s to %s: %w", config, sectionID, sectionName, err)
		}
	}
	
	return nil
}

// DeleteSection deletes a UCI section
func (u *UCI) DeleteSection(ctx context.Context, config, section string) error {
	cmd := exec.CommandContext(ctx, "uci", "delete", fmt.Sprintf("%s.%s", config, section))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to delete UCI section %s.%s: %w", config, section, err)
	}
	return nil
}

// Show shows the UCI configuration in JSON format
func (u *UCI) Show(ctx context.Context, config string) (map[string]interface{}, error) {
	cmd := exec.CommandContext(ctx, "uci", "show", config, "-j")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to show UCI config %s: %w", config, err)
	}
	
	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse UCI JSON output: %w", err)
	}
	
	return result, nil
}

// ShowSection shows a specific section in JSON format
func (u *UCI) ShowSection(ctx context.Context, config, section string) (map[string]interface{}, error) {
	cmd := exec.CommandContext(ctx, "uci", "show", fmt.Sprintf("%s.%s", config, section), "-j")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to show UCI section %s.%s: %w", config, section, err)
	}
	
	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse UCI JSON output: %w", err)
	}
	
	return result, nil
}

// Commit commits pending UCI changes
func (u *UCI) Commit(ctx context.Context, config string) error {
	cmd := exec.CommandContext(ctx, "uci", "commit", config)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to commit UCI config %s: %w", config, err)
	}
	return nil
}

// Revert reverts pending UCI changes
func (u *UCI) Revert(ctx context.Context, config string) error {
	cmd := exec.CommandContext(ctx, "uci", "revert", config)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to revert UCI config %s: %w", config, err)
	}
	return nil
}

// Changes shows pending UCI changes
func (u *UCI) Changes(ctx context.Context, config string) ([]string, error) {
	cmd := exec.CommandContext(ctx, "uci", "changes", config)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get UCI changes for %s: %w", config, err)
	}
	
	var changes []string
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			changes = append(changes, line)
		}
	}
	
	return changes, nil
}

// LoadConfig loads the complete starfail configuration from UCI
func (u *UCI) LoadConfig(ctx context.Context) (*Config, error) {
	config := &Config{}
	config.setDefaults()
	
	// Load main configuration
	if err := u.loadMainConfig(ctx, config); err != nil {
		return nil, fmt.Errorf("failed to load main config: %w", err)
	}
	
	// Load member configurations
	if err := u.loadMemberConfigs(ctx, config); err != nil {
		return nil, fmt.Errorf("failed to load member configs: %w", err)
	}
	
	config.lastModified = time.Now()
	return config, nil
}

// SaveConfig saves the configuration to UCI
func (u *UCI) SaveConfig(ctx context.Context, config *Config) error {
	// Save main configuration
	if err := u.saveMainConfig(ctx, config); err != nil {
		return fmt.Errorf("failed to save main config: %w", err)
	}
	
	// Save member configurations
	if err := u.saveMemberConfigs(ctx, config); err != nil {
		return fmt.Errorf("failed to save member configs: %w", err)
	}
	
	// Commit changes
	if err := u.Commit(ctx, "starfail"); err != nil {
		return fmt.Errorf("failed to commit config: %w", err)
	}
	
	config.lastModified = time.Now()
	return nil
}

// loadMainConfig loads the main configuration section
func (u *UCI) loadMainConfig(ctx context.Context, config *Config) error {
	// Try to get main section data
	mainData, err := u.ShowSection(ctx, "starfail", "main")
	if err != nil {
		u.logger.Warn("No main section found, using defaults")
		return nil
	}
	
	// Parse main section options
	for key, value := range mainData {
		if err := u.parseMainOption(config, key, value); err != nil {
			u.logger.Warn("Failed to parse option", "key", key, "value", value, "error", err)
		}
	}
	
	return nil
}

// saveMainConfig saves the main configuration section
func (u *UCI) saveMainConfig(ctx context.Context, config *Config) error {
	// Ensure main section exists
	if err := u.ensureSection(ctx, "starfail", "starfail", "main"); err != nil {
		return err
	}
	
	// Save main options
	options := map[string]string{
		"enable":                 strconv.FormatBool(config.Enable),
		"use_mwan3":              strconv.FormatBool(config.UseMWAN3),
		"poll_interval_ms":       strconv.Itoa(config.PollIntervalMS),
		"decision_interval_ms":   strconv.Itoa(config.DecisionIntervalMS),
		"discovery_interval_ms":  strconv.Itoa(config.DiscoveryIntervalMS),
		"cleanup_interval_ms":    strconv.Itoa(config.CleanupIntervalMS),
		"history_window_s":       strconv.Itoa(config.HistoryWindowS),
		"retention_hours":        strconv.Itoa(config.RetentionHours),
		"max_ram_mb":             strconv.Itoa(config.MaxRAMMB),
		"data_cap_mode":          config.DataCapMode,
		"predictive":             strconv.FormatBool(config.Predictive),
		"switch_margin":          strconv.Itoa(config.SwitchMargin),
		"min_uptime_s":           strconv.Itoa(config.MinUptimeS),
		"cooldown_s":             strconv.Itoa(config.CooldownS),
		"metrics_listener":       strconv.FormatBool(config.MetricsListener),
		"health_listener":        strconv.FormatBool(config.HealthListener),
		"metrics_port":           strconv.Itoa(config.MetricsPort),
		"health_port":            strconv.Itoa(config.HealthPort),
		"log_level":              config.LogLevel,
		"log_file":               config.LogFile,
		"fail_threshold_loss":    strconv.Itoa(config.FailThresholdLoss),
		"fail_threshold_latency": strconv.Itoa(config.FailThresholdLatency),
		"fail_min_duration_s":    strconv.Itoa(config.FailMinDurationS),
		"restore_threshold_loss": strconv.Itoa(config.RestoreThresholdLoss),
		"restore_threshold_latency": strconv.Itoa(config.RestoreThresholdLatency),
		"restore_min_duration_s": strconv.Itoa(config.RestoreMinDurationS),
		"pushover_token":         config.PushoverToken,
		"pushover_user":          config.PushoverUser,
		"mqtt_broker":            config.MQTTBroker,
		"mqtt_topic":             config.MQTTTopic,
		"mqtt_enabled":           strconv.FormatBool(config.MQTT.Enabled),
		"mqtt_port":              strconv.Itoa(config.MQTT.Port),
		"mqtt_client_id":         config.MQTT.ClientID,
		"mqtt_username":          config.MQTT.Username,
		"mqtt_password":          config.MQTT.Password,
		"mqtt_topic_prefix":      config.MQTT.TopicPrefix,
		"mqtt_qos":               strconv.Itoa(config.MQTT.QoS),
		"mqtt_retain":            strconv.FormatBool(config.MQTT.Retain),
	}
	
	for option, value := range options {
		if err := u.Set(ctx, "starfail", "main", option, value); err != nil {
			return fmt.Errorf("failed to set %s: %w", option, err)
		}
	}
	
	return nil
}

// loadMemberConfigs loads member configurations
func (u *UCI) loadMemberConfigs(ctx context.Context, config *Config) error {
	// Get all sections
	allData, err := u.Show(ctx, "starfail")
	if err != nil {
		return err
	}
	
	config.Members = make(map[string]*MemberConfig)
	
	for sectionName, sectionData := range allData {
		if strings.HasPrefix(sectionName, "starfail.member_") {
			memberName := strings.TrimPrefix(sectionName, "starfail.member_")
			memberConfig := &MemberConfig{}
			
			if sectionMap, ok := sectionData.(map[string]interface{}); ok {
				for key, value := range sectionMap {
					if err := u.parseMemberOption(memberConfig, key, value); err != nil {
						u.logger.Warn("Failed to parse member option", "member", memberName, "key", key, "value", value, "error", err)
					}
				}
			}
			
			config.Members[memberName] = memberConfig
		}
	}
	
	return nil
}

// saveMemberConfigs saves member configurations
func (u *UCI) saveMemberConfigs(ctx context.Context, config *Config) error {
	// Remove existing member sections
	allData, err := u.Show(ctx, "starfail")
	if err == nil {
		for sectionName := range allData {
			if strings.HasPrefix(sectionName, "starfail.member_") {
				memberName := strings.TrimPrefix(sectionName, "starfail.member_")
				if err := u.DeleteSection(ctx, "starfail", memberName); err != nil {
					u.logger.Warn("Failed to delete member section", "member", memberName, "error", err)
				}
			}
		}
	}
	
	// Add new member sections
	for memberName, memberConfig := range config.Members {
		sectionName := fmt.Sprintf("member_%s", memberName)
		if err := u.ensureSection(ctx, "starfail", "starfail", sectionName); err != nil {
			return fmt.Errorf("failed to create member section %s: %w", memberName, err)
		}
		
		options := map[string]string{
			"detect":         memberConfig.Detect,
			"class":          memberConfig.Class,
			"weight":         strconv.Itoa(memberConfig.Weight),
			"min_uptime_s":   strconv.Itoa(memberConfig.MinUptimeS),
			"cooldown_s":     strconv.Itoa(memberConfig.CooldownS),
			"prefer_roaming": strconv.FormatBool(memberConfig.PreferRoaming),
			"metered":        strconv.FormatBool(memberConfig.Metered),
		}
		
		for option, value := range options {
			if err := u.Set(ctx, "starfail", sectionName, option, value); err != nil {
				return fmt.Errorf("failed to set member option %s.%s: %w", memberName, option, err)
			}
		}
	}
	
	return nil
}

// ensureSection ensures a section exists
func (u *UCI) ensureSection(ctx context.Context, config, sectionType, sectionName string) error {
	// Check if section exists
	_, err := u.ShowSection(ctx, config, sectionName)
	if err == nil {
		return nil // Section already exists
	}
	
	// Create section
	return u.AddSection(ctx, config, sectionType, sectionName)
}

// parseMainOption parses a main configuration option
func (u *UCI) parseMainOption(config *Config, key string, value interface{}) error {
	switch key {
	case "enable":
		if v, ok := value.(bool); ok {
			config.Enable = v
		}
	case "use_mwan3":
		if v, ok := value.(bool); ok {
			config.UseMWAN3 = v
		}
	case "poll_interval_ms":
		if v, ok := value.(float64); ok {
			config.PollIntervalMS = int(v)
		}
	case "decision_interval_ms":
		if v, ok := value.(float64); ok {
			config.DecisionIntervalMS = int(v)
		}
	case "discovery_interval_ms":
		if v, ok := value.(float64); ok {
			config.DiscoveryIntervalMS = int(v)
		}
	case "cleanup_interval_ms":
		if v, ok := value.(float64); ok {
			config.CleanupIntervalMS = int(v)
		}
	case "history_window_s":
		if v, ok := value.(float64); ok {
			config.HistoryWindowS = int(v)
		}
	case "retention_hours":
		if v, ok := value.(float64); ok {
			config.RetentionHours = int(v)
		}
	case "max_ram_mb":
		if v, ok := value.(float64); ok {
			config.MaxRAMMB = int(v)
		}
	case "data_cap_mode":
		if v, ok := value.(string); ok {
			config.DataCapMode = v
		}
	case "predictive":
		if v, ok := value.(bool); ok {
			config.Predictive = v
		}
	case "switch_margin":
		if v, ok := value.(float64); ok {
			config.SwitchMargin = int(v)
		}
	case "min_uptime_s":
		if v, ok := value.(float64); ok {
			config.MinUptimeS = int(v)
		}
	case "cooldown_s":
		if v, ok := value.(float64); ok {
			config.CooldownS = int(v)
		}
	case "metrics_listener":
		if v, ok := value.(bool); ok {
			config.MetricsListener = v
		}
	case "health_listener":
		if v, ok := value.(bool); ok {
			config.HealthListener = v
		}
	case "metrics_port":
		if v, ok := value.(float64); ok {
			config.MetricsPort = int(v)
		}
	case "health_port":
		if v, ok := value.(float64); ok {
			config.HealthPort = int(v)
		}
	case "log_level":
		if v, ok := value.(string); ok {
			config.LogLevel = v
		}
	case "log_file":
		if v, ok := value.(string); ok {
			config.LogFile = v
		}
	case "fail_threshold_loss":
		if v, ok := value.(float64); ok {
			config.FailThresholdLoss = int(v)
		}
	case "fail_threshold_latency":
		if v, ok := value.(float64); ok {
			config.FailThresholdLatency = int(v)
		}
	case "fail_min_duration_s":
		if v, ok := value.(float64); ok {
			config.FailMinDurationS = int(v)
		}
	case "restore_threshold_loss":
		if v, ok := value.(float64); ok {
			config.RestoreThresholdLoss = int(v)
		}
	case "restore_threshold_latency":
		if v, ok := value.(float64); ok {
			config.RestoreThresholdLatency = int(v)
		}
	case "restore_min_duration_s":
		if v, ok := value.(float64); ok {
			config.RestoreMinDurationS = int(v)
		}
	case "pushover_token":
		if v, ok := value.(string); ok {
			config.PushoverToken = v
		}
	case "pushover_user":
		if v, ok := value.(string); ok {
			config.PushoverUser = v
		}
	case "mqtt_broker":
		if v, ok := value.(string); ok {
			config.MQTTBroker = v
		}
	case "mqtt_topic":
		if v, ok := value.(string); ok {
			config.MQTTTopic = v
		}
	case "mqtt_enabled":
		if v, ok := value.(bool); ok {
			config.MQTT.Enabled = v
		}
	case "mqtt_port":
		if v, ok := value.(float64); ok {
			config.MQTT.Port = int(v)
		}
	case "mqtt_client_id":
		if v, ok := value.(string); ok {
			config.MQTT.ClientID = v
		}
	case "mqtt_username":
		if v, ok := value.(string); ok {
			config.MQTT.Username = v
		}
	case "mqtt_password":
		if v, ok := value.(string); ok {
			config.MQTT.Password = v
		}
	case "mqtt_topic_prefix":
		if v, ok := value.(string); ok {
			config.MQTT.TopicPrefix = v
		}
	case "mqtt_qos":
		if v, ok := value.(float64); ok {
			config.MQTT.QoS = int(v)
		}
	case "mqtt_retain":
		if v, ok := value.(bool); ok {
			config.MQTT.Retain = v
		}
	}
	
	return nil
}

// parseMemberOption parses a member configuration option
func (u *UCI) parseMemberOption(config *MemberConfig, key string, value interface{}) error {
	switch key {
	case "detect":
		if v, ok := value.(string); ok {
			config.Detect = v
		}
	case "class":
		if v, ok := value.(string); ok {
			config.Class = v
		}
	case "weight":
		if v, ok := value.(float64); ok {
			config.Weight = int(v)
		}
	case "min_uptime_s":
		if v, ok := value.(float64); ok {
			config.MinUptimeS = int(v)
		}
	case "cooldown_s":
		if v, ok := value.(float64); ok {
			config.CooldownS = int(v)
		}
	case "prefer_roaming":
		if v, ok := value.(bool); ok {
			config.PreferRoaming = v
		}
	case "metered":
		if v, ok := value.(bool); ok {
			config.Metered = v
		}
	}
	
	return nil
}
