// Package decision implements scoring and decision logic for interface failover
package decision

import (
	"context"
	"crypto/rand"
	"fmt"
	"math"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/audit"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/gps"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/notification"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/obstruction"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
)

// NotificationManager defines the interface for sending notifications
type NotificationManager interface {
	SendNotification(ctx context.Context, notif notification.Notification) error
}

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
	SwitchMargin        float64       `json:"switch_margin"`          // Min score delta to switch
	MinUptimeS          time.Duration `json:"min_uptime_s"`           // Min uptime before eligible
	CooldownS           time.Duration `json:"cooldown_s"`             // Cooldown after switch
	HistoryWindowS      time.Duration `json:"history_window_s"`       // Rolling average window
	FailMinDurationS    time.Duration `json:"fail_min_duration_s"`    // Sustained dominance before failover
	RestoreMinDurationS time.Duration `json:"restore_min_duration_s"` // Sustained dominance before failback

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
	notificationMgr    NotificationManager // Interface for notifications

	// dominanceSince tracks when a candidate started leading current by margin
	dominanceSince map[string]time.Time
}

// NewEngine creates a new enhanced decision engine
func NewEngine(config Config, logger logx.Logger, store *telem.Store, auditLogger *audit.AuditLogger, gpsManager *gps.GPSManager, obstructionManager *obstruction.ObstructionManager, notificationMgr NotificationManager) *Engine {
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
		notificationMgr:    notificationMgr,
		dominanceSince:     make(map[string]time.Time),
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
	evaluationStart := time.Now()
	
	// Find the best eligible member
	bestMember := e.findBestMember()
	if bestMember == "" {
		e.logEvaluation("no_eligible_members", "", "", 0, evaluationStart)
		return nil // No eligible members
	}

	// Check if we need to switch
	if bestMember == e.currentPrimary {
		e.logEvaluation("maintain_current", e.currentPrimary, bestMember, 0, evaluationStart)
		return nil // Already using the best member
	}

	// Check cooldown
	cooldownRemaining := e.config.CooldownS - time.Since(e.lastSwitch)
	if cooldownRemaining > 0 {
		e.logEvaluation("cooldown_active", e.currentPrimary, bestMember, float64(cooldownRemaining.Seconds()), evaluationStart)
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
		e.logEvaluation("insufficient_margin", e.currentPrimary, bestMember, scoreDelta, evaluationStart)
		return nil // Not enough improvement
	}

	// Update dominance tracking for the best vs current
	e.updateDominance(bestMember, scoreDelta)

	// Determine required duration based on current quality (approximate "bad" vs "good")
	required := e.config.FailMinDurationS
	if currentScore > 50 && e.config.RestoreMinDurationS > 0 {
		required = e.config.RestoreMinDurationS
	}
	if required > 0 {
		since, ok := e.dominanceSince[bestMember]
		if !ok || time.Since(since) < required {
			remainingDuration := required
			if ok {
				remainingDuration = required - time.Since(since)
			}
			e.logEvaluation("insufficient_duration", e.currentPrimary, bestMember, float64(remainingDuration.Seconds()), evaluationStart)
			return nil // Not dominant long enough
		}
	}

	// Determine switch type
	switchType := "failover"
	if e.currentPrimary != "" && currentScore > 50 {
		switchType = "failback" // Current interface is still decent
	}

	// Predictive check
	isPredictive := false
	if e.config.EnablePredictive && e.shouldPreemptiveSwitch(bestMember) {
		switchType = "predictive"
		isPredictive = true
	}

	// Create switch event
	event := SwitchEvent{
		Timestamp:  time.Now(),
		Type:       switchType,
		From:       e.currentPrimary,
		To:         bestMember,
		ScoreDelta: scoreDelta,
		Reason:     e.generateSwitchReason(bestMember),
		DecisionID: e.generateDecisionID(),
	}

	// Log comprehensive audit event before executing
	e.logDecisionEvent(&event, isPredictive, evaluationStart)

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

	// Window average over recent history using telemetry store (average of instant scores)
	state.Score.WindowAvg = e.calculateWindowAverage(state.Member.Name, instant)

	// Calculate final blended score
	state.Score.Instant = instant
	state.Score.Final = 0.3*instant + 0.5*state.Score.EWMA + 0.2*state.Score.WindowAvg
	state.Score.LastUpdate = now

	// Record sample to telemetry store (after computing final)
	if e.store != nil {
		e.store.AddSample(telem.Sample{
			Timestamp:    now,
			Member:       state.Member.Name,
			Metrics:      metrics,
			InstantScore: instant,
			EWMAScore:    state.Score.EWMA,
			FinalScore:   state.Score.Final,
		})
	}
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

// calculateWindowAverage computes the average of instant scores from telemetry within HistoryWindowS.
// Includes the current instant value provided (to avoid dependence on store write timing).
func (e *Engine) calculateWindowAverage(member string, currentInstant float64) float64 {
	// Default to EWMA when no window configured
	if e.config.HistoryWindowS <= 0 {
		return currentInstant
	}
	var values []float64
	// Pull recent samples and aggregate instant scores
	if e.store != nil {
		samples := e.store.GetRecentSamples(member, e.config.HistoryWindowS)
		for _, s := range samples {
			if s.InstantScore > 0 { // include zeros as valid, but keep logic simple
				values = append(values, s.InstantScore)
			}
		}
	}
	// Always include current instant in the window computation
	values = append(values, currentInstant)
	if len(values) == 0 {
		return currentInstant
	}
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}

// updateDominance updates the timestamp since when best has led current by at least SwitchMargin
func (e *Engine) updateDominance(best string, scoreDelta float64) {
	if e.currentPrimary == "" {
		// Initial selection shouldn't require dominance
		e.dominanceSince[best] = time.Now()
		return
	}
	if scoreDelta >= e.config.SwitchMargin {
		if _, ok := e.dominanceSince[best]; !ok {
			e.dominanceSince[best] = time.Now()
		}
		// Reset others
		for name := range e.dominanceSince {
			if name != best {
				delete(e.dominanceSince, name)
			}
		}
	} else {
		// Not leading by margin; reset
		delete(e.dominanceSince, best)
	}
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

	// Enhanced predictive analysis with multiple signals
	shouldSwitch := false
	
	// 1. Score decline trend
	scoreDecline := current.Score.EWMA - current.Score.Instant
	if scoreDecline > e.config.PredictThreshold {
		shouldSwitch = true
		e.logger.Debug("predictive: score declining", 
			"member", e.currentPrimary,
			"decline", scoreDecline,
			"threshold", e.config.PredictThreshold)
	}

	// 2. Latency trend analysis (if we have telemetry data)
	if e.store != nil && current.Metrics.LatencyMs != nil {
		recentSamples := e.store.GetRecentSamples(e.currentPrimary, 30*time.Second)
		if len(recentSamples) >= 3 {
			latencyTrend := e.calculateLatencyTrend(recentSamples)
			if latencyTrend > 20.0 { // >20ms/minute increase
				shouldSwitch = true
				e.logger.Debug("predictive: latency trending up",
					"member", e.currentPrimary,
					"trend_ms_per_min", latencyTrend)
			}
		}
	}

	// 3. Loss rate spike detection
	if current.Metrics.PacketLossPct != nil && *current.Metrics.PacketLossPct > 2.0 {
		// Sudden loss spike - consider predictive failover
		if e.store != nil {
			recentSamples := e.store.GetRecentSamples(e.currentPrimary, 15*time.Second)
			if len(recentSamples) >= 2 {
				avgLoss := e.calculateAverageLoss(recentSamples)
				if *current.Metrics.PacketLossPct > avgLoss*2 { // 2x recent average
					shouldSwitch = true
					e.logger.Debug("predictive: loss spike detected",
						"member", e.currentPrimary,
						"current_loss", *current.Metrics.PacketLossPct,
						"recent_avg", avgLoss)
				}
			}
		}
	}

	// 4. Starlink-specific predictive signals
	if current.Member.Class == "starlink" {
		// Obstruction percentage trending up
		if current.Metrics.ObstructionPct != nil && *current.Metrics.ObstructionPct > 0.01 {
			// Check if obstruction is rising
			if e.store != nil {
				recentSamples := e.store.GetRecentSamples(e.currentPrimary, 60*time.Second)
				if len(recentSamples) >= 3 {
					obstructionTrend := e.calculateObstructionTrend(recentSamples)
					if obstructionTrend > 0.005 { // >0.5% increase per minute
						shouldSwitch = true
						e.logger.Debug("predictive: obstruction rising",
							"member", e.currentPrimary,
							"current_obstruction", *current.Metrics.ObstructionPct,
							"trend_per_min", obstructionTrend)
					}
				}
			}
		}

		// SNR degradation
		if current.Metrics.SNR != nil && *current.Metrics.SNR < 8.0 {
			shouldSwitch = true
			e.logger.Debug("predictive: low SNR detected",
				"member", e.currentPrimary,
				"snr", *current.Metrics.SNR)
		}
	}

	// 5. Cellular-specific predictive signals
	if current.Member.Class == "cellular" {
		// Signal strength degradation
		if current.Metrics.RSRP != nil && *current.Metrics.RSRP < -110 {
			shouldSwitch = true
			e.logger.Debug("predictive: weak cellular signal",
				"member", e.currentPrimary,
				"rsrp", *current.Metrics.RSRP)
		}
		
		// Signal quality issues
		if current.Metrics.RSRQ != nil && *current.Metrics.RSRQ < -15 {
			shouldSwitch = true
			e.logger.Debug("predictive: poor cellular quality",
				"member", e.currentPrimary,
				"rsrq", *current.Metrics.RSRQ)
		}
	}

	return shouldSwitch
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

	// Send notification for the switch
	e.sendSwitchNotification(event)
}

// GetEventHistory returns recent switch events
func (e *Engine) GetEventHistory() []SwitchEvent {
	// Return a copy to prevent modification
	events := make([]SwitchEvent, len(e.eventHistory))
	copy(events, e.eventHistory)
	return events
}

// generateDecisionID creates a unique decision ID
func (e *Engine) generateDecisionID() string {
	timestamp := time.Now().Format("20060102150405")
	buf := make([]byte, 4)
	rand.Read(buf)
	return fmt.Sprintf("d_%s_%x", timestamp, buf)
}

// logEvaluation logs an evaluation decision with context
func (e *Engine) logEvaluation(reason, from, to string, value float64, startTime time.Time) {
	if e.auditLogger == nil {
		return
	}

	processingTime := time.Since(startTime)
	
	event := &audit.DecisionEvent{
		Timestamp:     time.Now(),
		EventType:     "evaluation",
		Component:     "decision_engine",
		TriggerReason: reason,
		DecisionType:  "maintain",
		FromInterface: from,
		ToInterface:   to,
		ProcessingTime: processingTime,
		InterfaceMetrics: e.buildInterfaceMetrics(),
		QualityFactors:   e.buildQualityFactors(),
		Thresholds: audit.DecisionThresholds{
			SwitchMargin:            e.config.SwitchMargin,
			FailThresholdLoss:       5.0,  // TODO: Make configurable
			FailThresholdLatency:    150.0, // TODO: Make configurable
			RestoreThresholdLoss:    1.0,   // TODO: Make configurable
			RestoreThresholdLatency: 50.0,  // TODO: Make configurable
		},
		Windows: audit.DecisionWindows{
			BadDurationS:  int(e.config.FailMinDurationS.Seconds()),
			GoodDurationS: int(e.config.RestoreMinDurationS.Seconds()),
			CooldownS:     int(e.config.CooldownS.Seconds()),
			MinUptimeS:    int(e.config.MinUptimeS.Seconds()),
		},
	}

	// Add specific context based on reason
	switch reason {
	case "cooldown_active":
		event.Extra = map[string]interface{}{
			"cooldown_remaining_s": value,
		}
	case "insufficient_margin":
		event.Extra = map[string]interface{}{
			"score_delta": value,
			"required_margin": e.config.SwitchMargin,
		}
	case "insufficient_duration":
		event.Extra = map[string]interface{}{
			"remaining_duration_s": value,
		}
	}

	e.auditLogger.LogDecision(context.TODO(), event)
}

// logDecisionEvent logs a comprehensive decision event
func (e *Engine) logDecisionEvent(event *SwitchEvent, isPredictive bool, startTime time.Time) {
	if e.auditLogger == nil {
		return
	}

	processingTime := time.Since(startTime)
	
	auditEvent := &audit.DecisionEvent{
		Timestamp:        event.Timestamp,
		EventType:        "action",
		Component:        "decision_engine",
		TriggerReason:    event.Reason,
		DecisionType:     event.Type,
		FromInterface:    event.From,
		ToInterface:      event.To,
		ProcessingTime:   processingTime,
		InterfaceMetrics: e.buildInterfaceMetrics(),
		QualityFactors:   e.buildQualityFactors(),
		Thresholds: audit.DecisionThresholds{
			SwitchMargin:            e.config.SwitchMargin,
			FailThresholdLoss:       5.0,  // TODO: Make configurable
			FailThresholdLatency:    150.0, // TODO: Make configurable
			RestoreThresholdLoss:    1.0,   // TODO: Make configurable
			RestoreThresholdLatency: 50.0,  // TODO: Make configurable
		},
		Windows: audit.DecisionWindows{
			BadDurationS:  int(e.config.FailMinDurationS.Seconds()),
			GoodDurationS: int(e.config.RestoreMinDurationS.Seconds()),
			CooldownS:     int(e.config.CooldownS.Seconds()),
			MinUptimeS:    int(e.config.MinUptimeS.Seconds()),
		},
		Extra: map[string]interface{}{
			"score_delta":    event.ScoreDelta,
			"is_predictive":  isPredictive,
			"decision_id":    event.DecisionID,
		},
	}

	e.auditLogger.LogDecision(context.TODO(), auditEvent)
}

// buildInterfaceMetrics creates a map of current interface metrics
func (e *Engine) buildInterfaceMetrics() map[string]interface{} {
	metrics := make(map[string]interface{})
	
	for name, state := range e.members {
		metrics[name] = map[string]interface{}{
			"latency_ms":     state.Metrics.LatencyMs,
			"packet_loss_pct": state.Metrics.PacketLossPct,
			"jitter_ms":      state.Metrics.JitterMs,
			"instant_score":  state.Score.Instant,
			"ewma_score":     state.Score.EWMA,
			"window_avg":     state.Score.WindowAvg,
			"final_score":    state.Score.Final,
			"eligible":       state.Eligible,
			"class":          state.Member.Class,
		}
	}
	
	return metrics
}

// buildQualityFactors creates a map of quality factor breakdowns
func (e *Engine) buildQualityFactors() map[string]audit.ScoreBreakdown {
	factors := make(map[string]audit.ScoreBreakdown)
	
	for name, state := range e.members {
		components := make(map[string]float64)
		
		// Calculate individual component scores
		if state.Metrics.LatencyMs != nil {
			components["latency"] = e.scoreLatency(*state.Metrics.LatencyMs)
		}
		if state.Metrics.PacketLossPct != nil {
			components["loss"] = e.scoreLoss(*state.Metrics.PacketLossPct)
		}
		if state.Metrics.JitterMs != nil {
			components["jitter"] = e.scoreJitter(*state.Metrics.JitterMs)
		}
		
		// Add class weight
		classWeight := e.config.ClassWeights[state.Member.Class]
		if classWeight == 0 {
			classWeight = 0.5
		}
		
		factors[name] = audit.ScoreBreakdown{
			FinalScore:   state.Score.Final,
			InstantScore: state.Score.Instant,
			EWMAScore:    state.Score.EWMA,
			WindowScore:  state.Score.WindowAvg,
			Components:   components,
			WeightFactors: map[string]float64{
				"latency": e.config.WeightLatency,
				"loss":    e.config.WeightLoss,
				"jitter":  e.config.WeightJitter,
				"class":   classWeight,
			},
		}
	}
	
	return factors
}

// calculateLatencyTrend computes the rate of latency change (ms per minute)
func (e *Engine) calculateLatencyTrend(samples []telem.Sample) float64 {
	if len(samples) < 2 {
		return 0
	}

	// Extract latency values with timestamps
	var points []struct {
		time    float64 // minutes since first sample
		latency float64
	}

	firstTime := samples[0].Timestamp
	for _, sample := range samples {
		if sample.Metrics.LatencyMs != nil {
			minutes := sample.Timestamp.Sub(firstTime).Minutes()
			points = append(points, struct {
				time    float64
				latency float64
			}{minutes, *sample.Metrics.LatencyMs})
		}
	}

	if len(points) < 2 {
		return 0
	}

	// Simple linear regression to find slope (trend)
	n := float64(len(points))
	sumX, sumY, sumXY, sumX2 := 0.0, 0.0, 0.0, 0.0

	for _, p := range points {
		sumX += p.time
		sumY += p.latency
		sumXY += p.time * p.latency
		sumX2 += p.time * p.time
	}

	// Slope = (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)
	denominator := n*sumX2 - sumX*sumX
	if denominator == 0 {
		return 0
	}

	slope := (n*sumXY - sumX*sumY) / denominator
	return slope // ms per minute
}

// calculateAverageLoss computes average packet loss from recent samples
func (e *Engine) calculateAverageLoss(samples []telem.Sample) float64 {
	if len(samples) == 0 {
		return 0
	}

	sum := 0.0
	count := 0
	for _, sample := range samples {
		if sample.Metrics.PacketLossPct != nil {
			sum += *sample.Metrics.PacketLossPct
			count++
		}
	}

	if count == 0 {
		return 0
	}

	return sum / float64(count)
}

// calculateObstructionTrend computes the rate of obstruction change (percentage points per minute)
func (e *Engine) calculateObstructionTrend(samples []telem.Sample) float64 {
	if len(samples) < 2 {
		return 0
	}

	// Extract obstruction values with timestamps
	var points []struct {
		time        float64 // minutes since first sample
		obstruction float64
	}

	firstTime := samples[0].Timestamp
	for _, sample := range samples {
		if sample.Metrics.ObstructionPct != nil {
			minutes := sample.Timestamp.Sub(firstTime).Minutes()
			points = append(points, struct {
				time        float64
				obstruction float64
			}{minutes, *sample.Metrics.ObstructionPct})
		}
	}

	if len(points) < 2 {
		return 0
	}

	// Simple linear regression to find slope (trend)
	n := float64(len(points))
	sumX, sumY, sumXY, sumX2 := 0.0, 0.0, 0.0, 0.0

	for _, p := range points {
		sumX += p.time
		sumY += p.obstruction
		sumXY += p.time * p.obstruction
		sumX2 += p.time * p.time
	}

	// Slope = (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)
	denominator := n*sumX2 - sumX*sumX
	if denominator == 0 {
		return 0
	}

	slope := (n*sumXY - sumX*sumY) / denominator
	return slope // percentage points per minute
}

// sendSwitchNotification sends a notification about a failover event
func (e *Engine) sendSwitchNotification(event SwitchEvent) {
	if e.notificationMgr == nil {
		return
	}

	// Determine notification priority and type based on event
	var priority notification.Priority
	var notifType notification.NotificationType
	var title, message string

	switch event.Type {
	case "predictive":
		priority = notification.PriorityWarning
		notifType = notification.TypeStatus
		title = "🔮 Predictive Failover"
		message = fmt.Sprintf("Preemptively switched from %s to %s due to %s (score improved by %.1f)", 
			event.From, event.To, event.Reason, event.ScoreDelta)
	case "failover":
		priority = notification.PriorityCritical
		notifType = notification.TypeFailure
		title = "⚠️ Failover Activated"
		message = fmt.Sprintf("Failed over from %s to %s due to %s (score improved by %.1f)", 
			event.From, event.To, event.Reason, event.ScoreDelta)
	case "failback":
		priority = notification.PriorityInfo
		notifType = notification.TypeFix
		title = "✅ Failback Complete"
		message = fmt.Sprintf("Restored primary connection from %s to %s, %s (score improved by %.1f)", 
			event.From, event.To, event.Reason, event.ScoreDelta)
	default:
		priority = notification.PriorityInfo
		notifType = notification.TypeStatus
		title = "🔄 Interface Switch"
		message = fmt.Sprintf("Switched from %s to %s due to %s", event.From, event.To, event.Reason)
	}

	// Build rich context
	notifContext := notification.Context{
		CurrentStatus: fmt.Sprintf("Primary: %s", e.currentPrimary),
		InterfaceStates: make(map[string]interface{}),
	}

	// Add interface states to context
	for name, state := range e.members {
		notifContext.InterfaceStates[name] = map[string]interface{}{
			"score":    state.Score.Final,
			"eligible": state.Eligible,
			"class":    state.Member.Class,
		}
		
		// Add specific metrics
		if state.Metrics.LatencyMs != nil {
			notifContext.InterfaceStates[name].(map[string]interface{})["latency_ms"] = *state.Metrics.LatencyMs
		}
		if state.Metrics.PacketLossPct != nil {
			notifContext.InterfaceStates[name].(map[string]interface{})["loss_pct"] = *state.Metrics.PacketLossPct
		}
	}

	// Add next steps based on event type
	switch event.Type {
	case "predictive":
		notifContext.NextSteps = []string{
			"Monitor original interface for recovery",
			"Check for environmental factors affecting connectivity",
		}
	case "failover":
		notifContext.NextSteps = []string{
			"Investigate cause of primary interface failure",
			"Monitor backup interface performance",
			"Check for service restoration on failed interface",
		}
	case "failback":
		notifContext.NextSteps = []string{
			"Verify stable performance on restored interface",
			"Update monitoring thresholds if needed",
		}
	}

	notif := notification.Notification{
		ID:        fmt.Sprintf("switch_%s", event.DecisionID),
		Priority:  priority,
		Type:      notifType,
		Title:     title,
		Message:   message,
		Context:   notifContext,
		Timestamp: event.Timestamp,
		Channels:  []string{"default"}, // Use default channels
	}

	// Send the notification (non-blocking)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		
		if err := e.notificationMgr.SendNotification(ctx, notif); err != nil {
			e.logger.Warn("failed to send switch notification", 
				"error", err, 
				"event_type", event.Type,
				"decision_id", event.DecisionID)
		}
	}()
}
