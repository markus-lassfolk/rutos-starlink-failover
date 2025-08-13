// Package decision implements scoring and decision logic for interface failover
package decision

import (
	"math"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/audit"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/gps"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/obstruction"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
)

// Score represents interface health scoring
type Score struct {
	Instant    float64   `json:"instant"`    // 0-100, current score
	EWMA       float64   `json:"ewma"`       // Exponentially weighted moving average
	WindowAvg  float64   `json:"window_avg"` // Window average over history_window_s
	Final      float64   `json:"final"`      // Blended final score (0.3*instant + 0.5*ewma + 0.2*window)
	LastUpdate time.Time `json:"last_update"`
}

// MemberState tracks the state of a member interface
type MemberState struct {
	Member        collector.Member  `json:"member"`
	Score         Score             `json:"score"`
	Metrics       collector.Metrics `json:"metrics"`
	Eligible      bool              `json:"eligible"`
	CooldownUntil time.Time         `json:"cooldown_until,omitempty"`
	UpSince       *time.Time        `json:"up_since,omitempty"`
}

// SwitchEvent represents a failover/failback decision
type SwitchEvent struct {
	Timestamp  time.Time `json:"timestamp"`
	Type       string    `json:"type"` // "failover", "failback", "predictive"
	From       string    `json:"from"`
	To         string    `json:"to"`
	Reason     string    `json:"reason"`
	ScoreDelta float64   `json:"score_delta"`
	DecisionID string    `json:"decision_id"`
}

// Config holds decision engine configuration
type Config struct {
	// Scoring weights (sum to 1.0)
	WeightLatency float64 `json:"weight_latency"`
	WeightLoss    float64 `json:"weight_loss"`
	WeightJitter  float64 `json:"weight_jitter"`
	WeightClass   float64 `json:"weight_class"`

	// Thresholds
	SwitchMargin   float64       `json:"switch_margin"`    // Min score delta to switch
	MinUptimeS     time.Duration `json:"min_uptime_s"`     // Min uptime before eligible
	CooldownS      time.Duration `json:"cooldown_s"`       // Cooldown after switch
	HistoryWindowS time.Duration `json:"history_window_s"` // Rolling average window

	// Class preferences (higher = more preferred)
	ClassWeights map[string]float64 `json:"class_weights"`

	// Predictive settings
	EnablePredictive bool    `json:"enable_predictive"`
	PredictThreshold float64 `json:"predict_threshold"`
}

// Engine implements the enhanced decision logic for interface failover
type Engine struct {
	config         Config
	members        map[string]*MemberState
	currentPrimary string
	lastSwitch     time.Time
	eventHistory   []SwitchEvent

	// Enhanced components
	logger             logx.Logger
	store              *telem.Store
	auditLogger        *audit.AuditLogger
	gpsManager         *gps.GPSManager
	obstructionManager *obstruction.ObstructionManager
}

// NewEngine creates a new enhanced decision engine
func NewEngine(config Config, logger logx.Logger, store *telem.Store, auditLogger *audit.AuditLogger, gpsManager *gps.GPSManager, obstructionManager *obstruction.ObstructionManager) *Engine {
	// Set default weights if not provided
	if config.WeightLatency == 0 && config.WeightLoss == 0 &&
		config.WeightJitter == 0 && config.WeightClass == 0 {
		config.WeightLatency = 0.4
		config.WeightLoss = 0.4
		config.WeightJitter = 0.1
		config.WeightClass = 0.1
	}

	// Set default class weights
	if config.ClassWeights == nil {
		config.ClassWeights = map[string]float64{
			"starlink": 1.0,
			"cellular": 0.8,
			"wifi":     0.6,
			"lan":      0.7,
			"other":    0.5,
		}
	}

	return &Engine{
		config:             config,
		members:            make(map[string]*MemberState),
		eventHistory:       make([]SwitchEvent, 0),
		logger:             logger,
		store:              store,
		auditLogger:        auditLogger,
		gpsManager:         gpsManager,
		obstructionManager: obstructionManager,
	}
}

// UpdateMember updates the state and metrics for a member
func (e *Engine) UpdateMember(member collector.Member, metrics collector.Metrics) {
	state := e.members[member.Name]
	if state == nil {
		state = &MemberState{
			Member: member,
			Score: Score{
				LastUpdate: time.Now(),
			},
		}
		e.members[member.Name] = state
	}

	// Update metrics
	state.Metrics = metrics

	// Calculate new scores
	e.calculateScores(state)

	// Update eligibility
	e.updateEligibility(state)
}

// GetCurrentPrimary returns the current primary interface
func (e *Engine) GetCurrentPrimary() string {
	return e.currentPrimary
}

// GetMemberStates returns a copy of all member states
func (e *Engine) GetMemberStates() map[string]MemberState {
	states := make(map[string]MemberState)
	for name, state := range e.members {
		states[name] = *state
	}
	return states
}

// EvaluateSwitch determines if a failover/failback should occur
func (e *Engine) EvaluateSwitch() *SwitchEvent {
	// Find the best eligible member
	bestMember := e.findBestMember()
	if bestMember == "" {
		return nil // No eligible members
	}

	// Check if we need to switch
	if bestMember == e.currentPrimary {
		return nil // Already using the best member
	}

	// Check cooldown
	if time.Since(e.lastSwitch) < e.config.CooldownS {
		return nil // Still in cooldown
	}

	// Calculate score delta
	currentScore := 0.0
	if e.currentPrimary != "" {
		if current := e.members[e.currentPrimary]; current != nil {
			currentScore = current.Score.Final
		}
	}

	bestScore := e.members[bestMember].Score.Final
	scoreDelta := bestScore - currentScore

	// Check if score improvement justifies switch
	if scoreDelta < e.config.SwitchMargin {
		return nil // Not enough improvement
	}

	// Determine switch type
	switchType := "failover"
	if e.currentPrimary != "" && currentScore > 50 {
		switchType = "failback" // Current interface is still decent
	}

	// Predictive check
	if e.config.EnablePredictive && e.shouldPreemptiveSwitch(bestMember) {
		switchType = "predictive"
	}

	// Create switch event
	event := SwitchEvent{
		Timestamp:  time.Now(),
		Type:       switchType,
		From:       e.currentPrimary,
		To:         bestMember,
		ScoreDelta: scoreDelta,
		Reason:     e.generateSwitchReason(bestMember),
	}

	// Execute switch
	e.executeSwitch(event)

	return &event
}

// calculateScores computes instant, EWMA, window average, and final scores
func (e *Engine) calculateScores(state *MemberState) {
	now := time.Now()
	metrics := state.Metrics

	// Calculate instant score (0-100)
	instant := e.calculateInstantScore(metrics, state.Member)

	// Update EWMA (exponentially weighted moving average)
	alpha := 0.1 // Smoothing factor
	if state.Score.LastUpdate.IsZero() {
		state.Score.EWMA = instant
	} else {
		state.Score.EWMA = alpha*instant + (1-alpha)*state.Score.EWMA
	}

	// TODO: Implement window average using historical data
	state.Score.WindowAvg = state.Score.EWMA // Placeholder

	// Calculate final blended score
	state.Score.Instant = instant
	state.Score.Final = 0.3*instant + 0.5*state.Score.EWMA + 0.2*state.Score.WindowAvg
	state.Score.LastUpdate = now
}

// calculateInstantScore computes the current score for metrics
func (e *Engine) calculateInstantScore(metrics collector.Metrics, member collector.Member) float64 {
	score := 100.0 // Start with perfect score

	// Latency penalty
	if metrics.LatencyMs != nil {
		latency := *metrics.LatencyMs
		latencyScore := e.scoreLatency(latency)
		score -= (100 - latencyScore) * e.config.WeightLatency
	}

	// Packet loss penalty
	if metrics.PacketLossPct != nil {
		loss := *metrics.PacketLossPct
		lossScore := e.scoreLoss(loss)
		score -= (100 - lossScore) * e.config.WeightLoss
	}

	// Jitter penalty
	if metrics.JitterMs != nil {
		jitter := *metrics.JitterMs
		jitterScore := e.scoreJitter(jitter)
		score -= (100 - jitterScore) * e.config.WeightJitter
	}

	// Class preference adjustment
	classWeight := e.config.ClassWeights[member.Class]
	if classWeight == 0 {
		classWeight = 0.5 // Default for unknown classes
	}
	score = score*classWeight + (100-score)*e.config.WeightClass

	// Ensure score stays in bounds
	if score < 0 {
		score = 0
	}
	if score > 100 {
		score = 100
	}

	return score
}

// scoreLatency converts latency to 0-100 score (lower latency = higher score)
func (e *Engine) scoreLatency(latencyMs float64) float64 {
	// Excellent: <50ms = 100, Good: <200ms = 80, Fair: <500ms = 60, Poor: >500ms = 0-60
	if latencyMs <= 50 {
		return 100
	} else if latencyMs <= 200 {
		return 100 - (latencyMs-50)*20/150 // 100 to 80
	} else if latencyMs <= 500 {
		return 80 - (latencyMs-200)*20/300 // 80 to 60
	} else {
		return math.Max(0, 60-(latencyMs-500)*60/1000) // 60 to 0
	}
}

// scoreLoss converts packet loss to 0-100 score (lower loss = higher score)
func (e *Engine) scoreLoss(lossPct float64) float64 {
	// 0% loss = 100, 1% = 90, 5% = 50, 10%+ = 0
	if lossPct <= 0 {
		return 100
	} else if lossPct <= 1 {
		return 100 - lossPct*10 // 100 to 90
	} else if lossPct <= 5 {
		return 90 - (lossPct-1)*40/4 // 90 to 50
	} else if lossPct <= 10 {
		return 50 - (lossPct-5)*50/5 // 50 to 0
	} else {
		return 0
	}
}

// scoreJitter converts jitter to 0-100 score (lower jitter = higher score)
func (e *Engine) scoreJitter(jitterMs float64) float64 {
	// <5ms = 100, <20ms = 80, <50ms = 60, >50ms = 0-60
	if jitterMs <= 5 {
		return 100
	} else if jitterMs <= 20 {
		return 100 - (jitterMs-5)*20/15 // 100 to 80
	} else if jitterMs <= 50 {
		return 80 - (jitterMs-20)*20/30 // 80 to 60
	} else {
		return math.Max(0, 60-(jitterMs-50)*60/100) // 60 to 0
	}
}

// updateEligibility determines if a member is eligible for failover
func (e *Engine) updateEligibility(state *MemberState) {
	now := time.Now()

	// Check if member is enabled
	if !state.Member.Enabled {
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

	// Check cooldown
	if now.Before(state.CooldownUntil) {
		state.Eligible = false
		return
	}

	// Check basic connectivity (score > 0)
	if state.Score.Final <= 0 {
		state.Eligible = false
		return
	}

	state.Eligible = true
}

// findBestMember returns the name of the best eligible member
func (e *Engine) findBestMember() string {
	var bestMember string
	bestScore := -1.0

	for name, state := range e.members {
		if state.Eligible && state.Score.Final > bestScore {
			bestScore = state.Score.Final
			bestMember = name
		}
	}

	return bestMember
}

// shouldPreemptiveSwitch determines if predictive switching should occur
func (e *Engine) shouldPreemptiveSwitch(candidate string) bool {
	if !e.config.EnablePredictive {
		return false
	}

	// Check if current primary is degrading
	if e.currentPrimary == "" {
		return true // No current primary
	}

	current := e.members[e.currentPrimary]
	if current == nil {
		return true // Current primary not found
	}

	// Check if current score is trending downward
	scoreDecline := current.Score.EWMA - current.Score.Instant
	if scoreDecline > e.config.PredictThreshold {
		return true
	}

	return false
}

// generateSwitchReason creates a human-readable reason for the switch
func (e *Engine) generateSwitchReason(newPrimary string) string {
	newState := e.members[newPrimary]
	if newState == nil {
		return "unknown"
	}

	if e.currentPrimary == "" {
		return "initial_selection"
	}

	currentState := e.members[e.currentPrimary]
	if currentState == nil {
		return "current_unavailable"
	}

	// Analyze what's driving the switch
	metrics := newState.Metrics
	currentMetrics := currentState.Metrics

	reasons := []string{}

	// Check latency improvement
	if metrics.LatencyMs != nil && currentMetrics.LatencyMs != nil {
		if *currentMetrics.LatencyMs > *metrics.LatencyMs+50 {
			reasons = append(reasons, "latency_improvement")
		}
	}

	// Check packet loss improvement
	if metrics.PacketLossPct != nil && currentMetrics.PacketLossPct != nil {
		if *currentMetrics.PacketLossPct > *metrics.PacketLossPct+1 {
			reasons = append(reasons, "loss_reduction")
		}
	}

	// Check class preference
	newClassWeight := e.config.ClassWeights[newState.Member.Class]
	currentClassWeight := e.config.ClassWeights[currentState.Member.Class]
	if newClassWeight > currentClassWeight {
		reasons = append(reasons, "preferred_class")
	}

	if len(reasons) > 0 {
		return reasons[0] // Return the first/most important reason
	}

	return "score_improvement"
}

// executeSwitch performs the actual switch and updates state
func (e *Engine) executeSwitch(event SwitchEvent) {
	// Update state
	previousPrimary := e.currentPrimary
	e.currentPrimary = event.To
	e.lastSwitch = event.Timestamp

	// Set cooldown for previous primary
	if previousPrimary != "" && e.members[previousPrimary] != nil {
		e.members[previousPrimary].CooldownUntil = event.Timestamp.Add(e.config.CooldownS)
	}

	// Record event
	e.eventHistory = append(e.eventHistory, event)

	// Trim event history to reasonable size
	if len(e.eventHistory) > 100 {
		e.eventHistory = e.eventHistory[len(e.eventHistory)-100:]
	}
}

// GetEventHistory returns recent switch events
func (e *Engine) GetEventHistory() []SwitchEvent {
	// Return a copy to prevent modification
	events := make([]SwitchEvent, len(e.eventHistory))
	copy(events, e.eventHistory)
	return events
}
