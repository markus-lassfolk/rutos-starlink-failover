package notifications

import (
	"time"

	"github.com/starfail/starfail/pkg/uci"
)

// ConfigFromUCI converts UCI configuration to notification configuration
func ConfigFromUCI(uciConfig *uci.Config) *NotificationConfig {
	config := DefaultNotificationConfig()
	
	if uciConfig == nil {
		return config
	}
	
	// Basic Pushover settings
	config.PushoverEnabled = uciConfig.PushoverEnabled && 
		uciConfig.PushoverToken != "" && 
		uciConfig.PushoverUser != ""
	config.PushoverToken = uciConfig.PushoverToken
	config.PushoverUser = uciConfig.PushoverUser
	config.PushoverDevice = uciConfig.PushoverDevice
	
	// Advanced Pushover features
	config.PriorityThreshold = uciConfig.PriorityThreshold
	config.AcknowledgmentTracking = uciConfig.AcknowledgmentTracking
	config.LocationEnabled = uciConfig.LocationEnabled
	config.RichContextEnabled = uciConfig.RichContextEnabled
	
	// Notification type controls
	config.NotifyOnFailover = uciConfig.NotifyOnFailover
	config.NotifyOnFailback = uciConfig.NotifyOnFailback
	config.NotifyOnMemberDown = uciConfig.NotifyOnMemberDown
	config.NotifyOnMemberUp = uciConfig.NotifyOnMemberUp
	config.NotifyOnPredictive = uciConfig.NotifyOnPredictive
	config.NotifyOnCritical = uciConfig.NotifyOnCritical
	config.NotifyOnRecovery = uciConfig.NotifyOnRecovery
	
	// Timing and rate limiting
	if uciConfig.NotificationCooldownS > 0 {
		config.CooldownPeriod = time.Duration(uciConfig.NotificationCooldownS) * time.Second
	}
	if uciConfig.MaxNotificationsHour > 0 {
		config.MaxNotificationsHour = uciConfig.MaxNotificationsHour
	}
	
	// Priority settings
	config.PriorityFailover = uciConfig.PriorityFailover
	config.PriorityFailback = uciConfig.PriorityFailback
	config.PriorityMemberDown = uciConfig.PriorityMemberDown
	config.PriorityMemberUp = uciConfig.PriorityMemberUp
	config.PriorityPredictive = uciConfig.PriorityPredictive
	config.PriorityCritical = uciConfig.PriorityCritical
	config.PriorityRecovery = uciConfig.PriorityRecovery
	
	return config
}

// ValidateConfig validates notification configuration
func ValidateConfig(config *NotificationConfig) error {
	if config == nil {
		return nil
	}
	
	// Validate Pushover credentials if enabled
	if config.PushoverEnabled {
		if config.PushoverToken == "" {
			config.PushoverEnabled = false
		}
		if config.PushoverUser == "" {
			config.PushoverEnabled = false
		}
	}
	
	// Validate priorities are in valid range (-2 to 2)
	priorities := []*int{
		&config.PriorityFailover,
		&config.PriorityFailback,
		&config.PriorityMemberDown,
		&config.PriorityMemberUp,
		&config.PriorityPredictive,
		&config.PriorityCritical,
		&config.PriorityRecovery,
		&config.PriorityStatusUpdate,
	}
	
	for _, priority := range priorities {
		if *priority < -2 {
			*priority = -2
		}
		if *priority > 2 {
			*priority = 2
		}
	}
	
	// Validate timing settings
	if config.CooldownPeriod < 0 {
		config.CooldownPeriod = 5 * time.Minute
	}
	if config.EmergencyCooldown < 0 {
		config.EmergencyCooldown = 1 * time.Minute
	}
	if config.MaxNotificationsHour < 1 {
		config.MaxNotificationsHour = 20
	}
	if config.RetryAttempts < 0 {
		config.RetryAttempts = 3
	}
	if config.RetryDelay < time.Second {
		config.RetryDelay = 30 * time.Second
	}
	if config.HTTPTimeout < time.Second {
		config.HTTPTimeout = 10 * time.Second
	}
	
	return nil
}
