// Package decision implements scoring and decision logic for interface failover
package decision

import (
	"context"
	"time"
	
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
)

// Score represents interface health scoring
type Score struct {
	Instant    float64 `json:"instant"`     // 0-100, current score
	EWMA       float64 `json:"ewma"`        // Exponentially weighted moving average
	WindowAvg  float64 `json:"window_avg"`  // Window average over history_window_s
	Final      float64 `json:"final"`       // Blended final score (0.3*instant + 0.5*ewma + 0.2*window)
	LastUpdate time.Time `json:"last_update"`
}

// MemberState tracks the state of a member interface
type MemberState struct {
	Member      collector.Member `json:"member"`
	Score       Score            `json:"score"`
	Metrics     collector.Metrics `json:"metrics"`
	Eligible    bool             `json:"eligible"`
	CooldownUntil time.Time      `json:"cooldown_until,omitempty"`
	UpSince     *time.Time       `json:"up_since,omitempty"`
}

// SwitchEvent represents a failover/failback decision
type SwitchEvent struct {
	Timestamp   time.Time `json:"timestamp"`
	Type        string    `json:"type"`        // "failover", "failback", "predictive"
	From        string    `json:"from"`
	To          string    `json:"to"`
	Reason      string    `json:"reason"`
	ScoreDelta  float64   `json:"score_delta"`
	DecisionID  string    `json:"decision_id"`
}

// Config holds decision engine configuration
type Config struct {
	// Scoring weights (sum to 1.0)
	WeightLatency    float64 `json:"weight_latency"`
	WeightLoss       float64 `json:"weight_loss"`
	WeightJitter     float64 `json:"weight_jitter"`
	WeightClass      float64 `json:"weight_class"`
	
	// Thresholds
	SwitchMargin     float64       `json:"switch_margin"`      // Min score delta to switch
	MinUptimeS       time.Duration `json:"min_uptime_s"`       // Min uptime before eligible
	CooldownS        time.Duration `json:"cooldown_s"`         // Cooldown after switch
	HistoryWindowS   time.Duration `json:"history_window_s"`   // Window for rolling average
	
	// Fail/restore thresholds
	FailThresholdLoss     float64       `json:"fail_threshold_loss"`
	FailThresholdLatency  float64       `json:"fail_threshold_latency"`
	FailMinDurationS      time.Duration `json:"fail_min_duration_s"`
	RestoreThresholdLoss  float64       `json:"restore_threshold_loss"`
	RestoreThresholdLatency float64     `json:"restore_threshold_latency"`
	RestoreMinDurationS   time.Duration `json:"restore_min_duration_s"`
	
	// Predictive settings
	PredictiveEnabled bool `json:"predictive_enabled"`
}

// Engine implements the decision logic
type Engine struct {
	config Config
	members map[string]*MemberState
	current string // Current active member
	events  []SwitchEvent
}

// NewEngine creates a new decision engine
func NewEngine(config Config) *Engine {
	return &Engine{
		config:  config,
		members: make(map[string]*MemberState),
		events:  make([]SwitchEvent, 0),
	}
}

// UpdateMetrics updates member metrics and recalculates scores
func (e *Engine) UpdateMetrics(member collector.Member, metrics collector.Metrics) {
	state, exists := e.members[member.Name]
	if !exists {
		state = &MemberState{
			Member: member,
			Score:  Score{},
		}
		e.members[member.Name] = state
	}
	
	state.Metrics = metrics
	e.calculateScore(state)
	e.updateEligibility(state)
}

// calculateScore computes instant, EWMA, window average, and final scores
func (e *Engine) calculateScore(state *MemberState) {
	// TODO: Implement scoring algorithm from PROJECT_INSTRUCTION.md
	// - Normalize metrics (latency, loss, jitter, class-specific)
	// - Apply weights and penalties
	// - Calculate instant score (0-100)
	// - Update EWMA with α≈0.2
	// - Calculate window average over history
	// - Blend: final = 0.30*instant + 0.50*ewma + 0.20*window_avg
	
	state.Score.LastUpdate = time.Now()
}

// updateEligibility determines if a member is eligible for selection
func (e *Engine) updateEligibility(state *MemberState) {
	now := time.Now()
	
	// Check cooldown
	if now.Before(state.CooldownUntil) {
		state.Eligible = false
		return
	}
	
	// Check minimum uptime
	if state.UpSince != nil {
		uptime := now.Sub(*state.UpSince)
		if uptime < e.config.MinUptimeS {
			state.Eligible = false
			return
		}
	}
	
	// Check if member is enabled
	if !state.Member.Enabled {
		state.Eligible = false
		return
	}
	
	state.Eligible = true
}

// Evaluate performs decision logic and returns switch recommendation
func (e *Engine) Evaluate(ctx context.Context) (*SwitchEvent, error) {
	// TODO: Implement decision logic
	// 1. Rank eligible members by final score
	// 2. Check switch conditions (margin, duration windows)
	// 3. Apply predictive triggers if enabled
	// 4. Respect rate limiting and cooldowns
	// 5. Return switch event if change recommended
	
	return nil, nil
}

// GetMemberStates returns current state of all members
func (e *Engine) GetMemberStates() map[string]*MemberState {
	return e.members
}

// GetCurrent returns the currently active member
func (e *Engine) GetCurrent() string {
	return e.current
}

// SetCurrent updates the currently active member and applies cooldown
func (e *Engine) SetCurrent(memberName string) {
	e.current = memberName
	if state, exists := e.members[memberName]; exists {
		state.CooldownUntil = time.Now().Add(e.config.CooldownS)
	}
}
