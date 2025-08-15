// Package notification provides intelligent notification management with context-aware alerting
package notification

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

// Manager handles smart notification management
type Manager struct {
	config   Config
	channels []Channel
	limiter  *RateLimiter
	logger   logx.Logger
	mutex    sync.RWMutex
}

// Config holds notification configuration
type Config struct {
	Enabled                bool `uci:"enabled" default:"true"`
	EmergencyCooldownS     int  `uci:"emergency_cooldown_s" default:"0"`
	CriticalCooldownS      int  `uci:"critical_cooldown_s" default:"300"`
	WarningCooldownS       int  `uci:"warning_cooldown_s" default:"3600"`
	InfoCooldownS          int  `uci:"info_cooldown_s" default:"21600"`
	MaxRetries             int  `uci:"max_retries" default:"3"`
	RetryBackoffS          int  `uci:"retry_backoff_s" default:"60"`
	AcknowledgmentRequired bool `uci:"acknowledgment_required" default:"false"`
}

// Priority represents notification priority levels
type Priority int

const (
	PriorityInfo Priority = iota
	PriorityWarning
	PriorityCritical
	PriorityEmergency
)

func (p Priority) String() string {
	switch p {
	case PriorityInfo:
		return "info"
	case PriorityWarning:
		return "warning"
	case PriorityCritical:
		return "critical"
	case PriorityEmergency:
		return "emergency"
	default:
		return "unknown"
	}
}

// NotificationType represents different types of notifications
type NotificationType string

const (
	TypeFix      NotificationType = "fix"
	TypeFailure  NotificationType = "failure"
	TypeCritical NotificationType = "critical"
	TypeStatus   NotificationType = "status"
)

// Notification represents a notification message with context
type Notification struct {
	ID           string           `json:"id"`
	Priority     Priority         `json:"priority"`
	Type         NotificationType `json:"type"`
	Title        string           `json:"title"`
	Message      string           `json:"message"`
	Context      Context          `json:"context"`
	Timestamp    time.Time        `json:"timestamp"`
	Retry        RetryPolicy      `json:"retry"`
	Acknowledged bool             `json:"acknowledged"`
	Channels     []string         `json:"channels"` // Which channels to use
}

// Context provides rich contextual information
type Context struct {
	CurrentStatus   string                 `json:"current_status"`
	AttemptedFixes  []string               `json:"attempted_fixes,omitempty"`
	NextSteps       []string               `json:"next_steps,omitempty"`
	InterfaceStates map[string]interface{} `json:"interface_states,omitempty"`
	SystemMetrics   map[string]interface{} `json:"system_metrics,omitempty"`
	LocationInfo    map[string]interface{} `json:"location_info,omitempty"`
	SeverityFactors []string               `json:"severity_factors,omitempty"`
}

// RetryPolicy defines how notifications should be retried
type RetryPolicy struct {
	MaxRetries    int           `json:"max_retries"`
	BackoffDelay  time.Duration `json:"backoff_delay"`
	EscalateAfter int           `json:"escalate_after"`
	EscalateTo    Priority      `json:"escalate_to"`
}

// Channel interface for different notification channels
type Channel interface {
	Name() string
	Send(ctx context.Context, notification Notification) error
	SupportsRetry() bool
	SupportsAcknowledgment() bool
}

// RateLimiter manages notification rate limiting
type RateLimiter struct {
	lastSent  map[string]time.Time
	cooldowns map[Priority]time.Duration
	mutex     sync.RWMutex
}

// NewManager creates a new notification manager
func NewManager(config Config, logger logx.Logger) *Manager {
	cooldowns := map[Priority]time.Duration{
		PriorityEmergency: time.Duration(config.EmergencyCooldownS) * time.Second,
		PriorityCritical:  time.Duration(config.CriticalCooldownS) * time.Second,
		PriorityWarning:   time.Duration(config.WarningCooldownS) * time.Second,
		PriorityInfo:      time.Duration(config.InfoCooldownS) * time.Second,
	}

	return &Manager{
		config: config,
		limiter: &RateLimiter{
			lastSent:  make(map[string]time.Time),
			cooldowns: cooldowns,
		},
		logger: logger,
	}
}

// AddChannel adds a notification channel
func (m *Manager) AddChannel(channel Channel) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.channels = append(m.channels, channel)
}

// Send sends a notification with intelligent routing and rate limiting
func (m *Manager) Send(ctx context.Context, notification Notification) error {
	if !m.config.Enabled {
		return nil
	}

	// Check rate limiting
	if !m.limiter.Allow(notification.Priority, notification.Type) {
		m.logger.Debug("notification rate limited",
			"priority", notification.Priority,
			"type", notification.Type,
			"title", notification.Title,
		)
		return nil
	}

	// Set retry policy if not specified
	if notification.Retry.MaxRetries == 0 {
		notification.Retry = m.getDefaultRetryPolicy(notification.Priority)
	}

	// Send to appropriate channels
	return m.sendToChannels(ctx, notification)
}

// SendNotification is an alias for Send to implement decision.NotificationManager interface
func (m *Manager) SendNotification(ctx context.Context, notification Notification) error {
	return m.Send(ctx, notification)
}

// SendFix sends a notification that a problem was automatically resolved
func (m *Manager) SendFix(ctx context.Context, title, message string, context Context) error {
	notification := Notification{
		ID:        generateID(),
		Priority:  PriorityInfo,
		Type:      TypeFix,
		Title:     "✅ " + title,
		Message:   message,
		Context:   context,
		Timestamp: time.Now(),
		Channels:  []string{"all"},
	}
	return m.Send(ctx, notification)
}

// SendFailure sends a notification that requires human intervention
func (m *Manager) SendFailure(ctx context.Context, title, message string, context Context) error {
	notification := Notification{
		ID:        generateID(),
		Priority:  PriorityWarning,
		Type:      TypeFailure,
		Title:     "⚠️ " + title,
		Message:   message,
		Context:   context,
		Timestamp: time.Now(),
		Channels:  []string{"all"},
	}
	return m.Send(ctx, notification)
}

// SendCritical sends a critical notification with emergency priority
func (m *Manager) SendCritical(ctx context.Context, title, message string, context Context) error {
	notification := Notification{
		ID:        generateID(),
		Priority:  PriorityEmergency,
		Type:      TypeCritical,
		Title:     "🚨 " + title,
		Message:   message,
		Context:   context,
		Timestamp: time.Now(),
		Channels:  []string{"all"},
	}
	return m.Send(ctx, notification)
}

// SendStatus sends a regular status update
func (m *Manager) SendStatus(ctx context.Context, title, message string, context Context) error {
	notification := Notification{
		ID:        generateID(),
		Priority:  PriorityInfo,
		Type:      TypeStatus,
		Title:     "ℹ️ " + title,
		Message:   message,
		Context:   context,
		Timestamp: time.Now(),
		Channels:  []string{"status"},
	}
	return m.Send(ctx, notification)
}

// Acknowledge marks a notification as acknowledged
func (m *Manager) Acknowledge(notificationID string) error {
	// Implementation for acknowledgment tracking
	m.logger.Info("notification acknowledged", "id", notificationID)
	return nil
}

// Allow checks if a notification should be sent based on rate limiting
func (rl *RateLimiter) Allow(priority Priority, notType NotificationType) bool {
	rl.mutex.Lock()
	defer rl.mutex.Unlock()

	key := fmt.Sprintf("%s_%s", priority.String(), string(notType))
	cooldown := rl.cooldowns[priority]

	if lastSent, exists := rl.lastSent[key]; exists {
		if time.Since(lastSent) < cooldown {
			return false
		}
	}

	rl.lastSent[key] = time.Now()
	return true
}

// sendToChannels sends notification to appropriate channels
func (m *Manager) sendToChannels(ctx context.Context, notification Notification) error {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	var errors []string
	sent := false

	for _, channel := range m.channels {
		// Check if this channel should receive this notification
		if !m.shouldSendToChannel(channel, notification) {
			continue
		}

		if err := m.sendWithRetry(ctx, channel, notification); err != nil {
			errors = append(errors, fmt.Sprintf("%s: %v", channel.Name(), err))
		} else {
			sent = true
		}
	}

	if !sent && len(errors) > 0 {
		return fmt.Errorf("failed to send notification: %s", strings.Join(errors, "; "))
	}

	return nil
}

// shouldSendToChannel determines if a channel should receive a notification
func (m *Manager) shouldSendToChannel(channel Channel, notification Notification) bool {
	// Check if channel is in the notification's channel list
	for _, ch := range notification.Channels {
		if ch == "all" || ch == channel.Name() {
			return true
		}
		if ch == "status" && notification.Type == TypeStatus {
			return true
		}
	}
	return false
}

// sendWithRetry sends notification with retry logic
func (m *Manager) sendWithRetry(ctx context.Context, channel Channel, notification Notification) error {
	var lastErr error

	for attempt := 0; attempt <= notification.Retry.MaxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(notification.Retry.BackoffDelay * time.Duration(attempt)):
			}
		}

		if err := channel.Send(ctx, notification); err != nil {
			lastErr = err
			m.logger.Warn("notification send failed",
				"channel", channel.Name(),
				"attempt", attempt+1,
				"error", err,
			)
			continue
		}

		m.logger.Info("notification sent successfully",
			"channel", channel.Name(),
			"priority", notification.Priority,
			"type", notification.Type,
		)
		return nil
	}

	return fmt.Errorf("failed after %d attempts: %w", notification.Retry.MaxRetries+1, lastErr)
}

// getDefaultRetryPolicy returns default retry policy for priority level
func (m *Manager) getDefaultRetryPolicy(priority Priority) RetryPolicy {
	switch priority {
	case PriorityEmergency:
		return RetryPolicy{
			MaxRetries:    5,
			BackoffDelay:  30 * time.Second,
			EscalateAfter: 3,
			EscalateTo:    PriorityEmergency,
		}
	case PriorityCritical:
		return RetryPolicy{
			MaxRetries:    3,
			BackoffDelay:  60 * time.Second,
			EscalateAfter: 2,
			EscalateTo:    PriorityEmergency,
		}
	default:
		return RetryPolicy{
			MaxRetries:    m.config.MaxRetries,
			BackoffDelay:  time.Duration(m.config.RetryBackoffS) * time.Second,
			EscalateAfter: 0,
		}
	}
}

// generateID generates a unique notification ID
func generateID() string {
	return fmt.Sprintf("notif_%d", time.Now().UnixNano())
}

// PushoverChannel implements Pushover notifications
type PushoverChannel struct {
	token string
	user  string
	name  string
}

// NewPushoverChannel creates a new Pushover notification channel
func NewPushoverChannel(token, user string) *PushoverChannel {
	return &PushoverChannel{
		token: token,
		user:  user,
		name:  "pushover",
	}
}

func (p *PushoverChannel) Name() string {
	return p.name
}

func (p *PushoverChannel) SupportsRetry() bool {
	return true
}

func (p *PushoverChannel) SupportsAcknowledgment() bool {
	return true
}

func (p *PushoverChannel) Send(ctx context.Context, notification Notification) error {
	if p.token == "" || p.user == "" {
		return fmt.Errorf("pushover token and user required")
	}

	// Prepare Pushover payload
	payload := map[string]interface{}{
		"token":   p.token,
		"user":    p.user,
		"title":   notification.Title,
		"message": notification.Message,
	}

	// Set priority mapping
	switch notification.Priority {
	case PriorityEmergency:
		payload["priority"] = 2
		payload["retry"] = 30
		payload["expire"] = 3600
	case PriorityCritical:
		payload["priority"] = 1
	case PriorityWarning:
		payload["priority"] = 0
	case PriorityInfo:
		payload["priority"] = -1
	}

	// Add context as supplementary URL if available
	if len(notification.Context.NextSteps) > 0 {
		payload["url_title"] = "Troubleshooting Steps"
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal pushover payload: %w", err)
	}

	// Send to Pushover API
	req, err := http.NewRequestWithContext(ctx, "POST",
		"https://api.pushover.net/1/messages.json",
		strings.NewReader(string(jsonData)))
	if err != nil {
		return fmt.Errorf("failed to create pushover request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send pushover notification: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("pushover API returned status %d", resp.StatusCode)
	}

	return nil
}
