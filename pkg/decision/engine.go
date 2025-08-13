package decision

import (
	"context"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/uci"
)

// Engine implements the decision logic for failover
type Engine struct {
	mu sync.RWMutex

	// Configuration
	config *uci.Config

	// Dependencies
	logger    *logx.Logger
	telemetry *telem.Store

	// State
	members     map[string]*pkg.Member
	memberState map[string]*MemberState
	current     *pkg.Member
	lastSwitch  time.Time

	// Scoring state
	scores map[string]*pkg.Score

	// Hysteresis state
	badWindows  map[string]time.Time
	goodWindows map[string]time.Time
	cooldowns   map[string]time.Time
	warmups     map[string]time.Time

	// Predictive state
	lastPredictive time.Time
	predictiveRate time.Duration
}

// MemberState tracks the state of a member
type MemberState struct {
	Member     *pkg.Member
	LastSeen   time.Time
	LastUpdate time.Time
	Status     string // eligible|cooldown|warmup|failed
	Uptime     time.Duration
}

// NewEngine creates a new decision engine
func NewEngine(config *uci.Config, logger *logx.Logger, telemetry *telem.Store) *Engine {
	return &Engine{
		config:         config,
		logger:         logger,
		telemetry:      telemetry,
		members:        make(map[string]*pkg.Member),
		memberState:    make(map[string]*MemberState),
		scores:         make(map[string]*pkg.Score),
		badWindows:     make(map[string]time.Time),
		goodWindows:    make(map[string]time.Time),
		cooldowns:      make(map[string]time.Time),
		warmups:        make(map[string]time.Time),
		predictiveRate: time.Duration(config.FailMinDurationS*5) * time.Second,
	}
}

// Tick performs one decision cycle
func (e *Engine) Tick(controller pkg.Controller) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Update member states
	e.updateMemberStates()

	// Collect metrics for all members
	if err := e.collectMetrics(); err != nil {
		e.logger.Error("Failed to collect metrics", "error", err)
		return err
	}

	// Update scores
	e.updateScores()

	// Make decision
	if err := e.makeDecision(controller); err != nil {
		e.logger.Error("Failed to make decision", "error", err)
		return err
	}

	return nil
}

// updateMemberStates updates the state of all members
func (e *Engine) updateMemberStates() {
	now := time.Now()

	for name, member := range e.members {
		state, exists := e.memberState[name]
		if !exists {
			state = &MemberState{
				Member:   member,
				LastSeen: now,
				Status:   pkg.StatusEligible,
			}
			e.memberState[name] = state
		}

		// Update uptime
		state.Uptime = now.Sub(state.LastSeen)

		// Check cooldown
		if cooldownUntil, exists := e.cooldowns[name]; exists && now.Before(cooldownUntil) {
			state.Status = pkg.StatusCooldown
			continue
		}

		// Check warmup
		if warmupUntil, exists := e.warmups[name]; exists && now.Before(warmupUntil) {
			state.Status = pkg.StatusWarmup
			continue
		}

		// Check minimum uptime
		if state.Uptime < time.Duration(e.config.MinUptimeS)*time.Second {
			state.Status = pkg.StatusWarmup
			continue
		}

		state.Status = pkg.StatusEligible
	}
}

// collectMetrics collects metrics for all members
func (e *Engine) collectMetrics() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for name, member := range e.members {
		// Skip members in cooldown or warmup
		if state := e.memberState[name]; state != nil {
			if state.Status == pkg.StatusCooldown || state.Status == pkg.StatusWarmup {
				continue
			}
		}

		// Collect metrics
		metrics, err := e.collectMemberMetrics(ctx, member)
		if err != nil {
			e.logger.Error("Failed to collect metrics for member", "member", name, "error", err)
			continue
		}

		// Store in telemetry
		if err := e.telemetry.AddSample(name, metrics, e.scores[name]); err != nil {
			e.logger.Error("Failed to store metrics", "member", name, "error", err)
		}

		// Update member state
		if state := e.memberState[name]; state != nil {
			state.LastUpdate = time.Now()
		}
	}

	return nil
}

// collectMemberMetrics collects metrics for a specific member
func (e *Engine) collectMemberMetrics(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	// TODO: Use the collector factory to get the appropriate collector
	// For now, return a mock metrics object
	metrics := &pkg.Metrics{
		Timestamp:   time.Now(),
		LatencyMS:   50.0, // Mock values
		LossPercent: 0.1,
		JitterMS:    5.0,
	}

	return metrics, nil
}

// updateScores updates the scores for all members
func (e *Engine) updateScores() {
	now := time.Now()

	for name, member := range e.members {
		// Get recent metrics
		samples, err := e.telemetry.GetSamples(name, now.Add(-time.Duration(e.config.HistoryWindowS)*time.Second))
		if err != nil {
			e.logger.Error("Failed to get samples for scoring", "member", name, "error", err)
			continue
		}

		if len(samples) == 0 {
			continue
		}

		// Calculate scores
		score := e.calculateScore(member, samples)
		e.scores[name] = score
	}
}

// calculateScore calculates the score for a member based on recent samples
func (e *Engine) calculateScore(member *pkg.Member, samples []*telem.Sample) *pkg.Score {
	if len(samples) == 0 {
		return &pkg.Score{
			Instant:   0,
			EWMA:      0,
			Final:     0,
			UpdatedAt: time.Now(),
		}
	}

	// Calculate instant score from latest sample
	latest := samples[len(samples)-1]
	instant := e.calculateInstantScore(member, latest.Metrics)

	// Calculate EWMA
	ewma := e.calculateEWMA(member.Name, instant)

	// Calculate window average
	windowAvg := e.calculateWindowAverage(samples)

	// Calculate final score
	final := 0.30*instant + 0.50*ewma + 0.20*windowAvg

	return &pkg.Score{
		Instant:   instant,
		EWMA:      ewma,
		Final:     final,
		UpdatedAt: time.Now(),
	}
}

// calculateInstantScore calculates the instant score for a member
func (e *Engine) calculateInstantScore(member *pkg.Member, metrics map[string]interface{}) float64 {
	score := 100.0 // Base score

	// Get member config
	memberConfig := e.config.Members[member.Name]

	// Apply class-specific scoring
	switch member.Class {
	case pkg.ClassStarlink:
		score = e.scoreStarlink(metrics, memberConfig)
	case pkg.ClassCellular:
		score = e.scoreCellular(metrics, memberConfig)
	case pkg.ClassWiFi:
		score = e.scoreWiFi(metrics, memberConfig)
	case pkg.ClassLAN:
		score = e.scoreLAN(metrics, memberConfig)
	default:
		score = e.scoreGeneric(metrics, memberConfig)
	}

	// Apply weight
	if memberConfig != nil {
		score = score * float64(memberConfig.Weight) / 100.0
	}

	// Clamp to 0-100
	return math.Max(0, math.Min(100, score))
}

// scoreStarlink calculates score for Starlink members
func (e *Engine) scoreStarlink(metrics map[string]interface{}, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	if lat, ok := metrics["lat_ms"].(float64); ok {
		latPenalty := e.normalize(lat, 50, 1500) * 20
		score -= latPenalty
	}

	// Loss penalty
	if loss, ok := metrics["loss_pct"].(float64); ok {
		lossPenalty := e.normalize(loss, 0, 10) * 30
		score -= lossPenalty
	}

	// Jitter penalty
	if jitter, ok := metrics["jitter_ms"].(float64); ok {
		jitterPenalty := e.normalize(jitter, 5, 200) * 15
		score -= jitterPenalty
	}

	// Obstruction penalty
	if obst, ok := metrics["obstruction_pct"].(float64); ok {
		obstPenalty := e.normalize(obst, 0, 10) * 25
		score -= obstPenalty
	}

	// Outage penalty
	if outages, ok := metrics["outages"].(int); ok && outages > 0 {
		score -= 20 // Significant penalty for outages
	}

	return score
}

// scoreCellular calculates score for cellular members
func (e *Engine) scoreCellular(metrics map[string]interface{}, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	if lat, ok := metrics["lat_ms"].(float64); ok {
		latPenalty := e.normalize(lat, 50, 1500) * 20
		score -= latPenalty
	}

	// Loss penalty
	if loss, ok := metrics["loss_pct"].(float64); ok {
		lossPenalty := e.normalize(loss, 0, 10) * 30
		score -= lossPenalty
	}

	// Signal quality bonus/penalty
	if rsrp, ok := metrics["rsrp"].(int); ok {
		// RSRP ranges from -140 to -44 dBm
		rsrpScore := float64(rsrp+140) / 96.0 * 100
		if rsrpScore > 100 {
			rsrpScore = 100
		} else if rsrpScore < 0 {
			rsrpScore = 0
		}
		score = score*0.7 + rsrpScore*0.3
	}

	// Roaming penalty
	if roaming, ok := metrics["roaming"].(bool); ok && roaming {
		if config == nil || !config.PreferRoaming {
			score -= 15 // Penalty for roaming
		}
	}

	return score
}

// scoreWiFi calculates score for WiFi members
func (e *Engine) scoreWiFi(metrics map[string]interface{}, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	if lat, ok := metrics["lat_ms"].(float64); ok {
		latPenalty := e.normalize(lat, 50, 1500) * 20
		score -= latPenalty
	}

	// Loss penalty
	if loss, ok := metrics["loss_pct"].(float64); ok {
		lossPenalty := e.normalize(loss, 0, 10) * 30
		score -= lossPenalty
	}

	// Signal strength bonus/penalty
	if signal, ok := metrics["signal"].(int); ok {
		// WiFi signal typically ranges from -100 to -30 dBm
		signalScore := float64(signal+100) / 70.0 * 100
		if signalScore > 100 {
			signalScore = 100
		} else if signalScore < 0 {
			signalScore = 0
		}
		score = score*0.7 + signalScore*0.3
	}

	return score
}

// scoreLAN calculates score for LAN members
func (e *Engine) scoreLAN(metrics map[string]interface{}, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty (LAN should be very fast)
	if lat, ok := metrics["lat_ms"].(float64); ok {
		latPenalty := e.normalize(lat, 1, 100) * 25
		score -= latPenalty
	}

	// Loss penalty (LAN should have no loss)
	if loss, ok := metrics["loss_pct"].(float64); ok {
		lossPenalty := loss * 50 // High penalty for any loss on LAN
		score -= lossPenalty
	}

	return score
}

// scoreGeneric calculates score for generic members
func (e *Engine) scoreGeneric(metrics map[string]interface{}, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	if lat, ok := metrics["lat_ms"].(float64); ok {
		latPenalty := e.normalize(lat, 50, 1500) * 20
		score -= latPenalty
	}

	// Loss penalty
	if loss, ok := metrics["loss_pct"].(float64); ok {
		lossPenalty := e.normalize(loss, 0, 10) * 30
		score -= lossPenalty
	}

	return score
}

// normalize normalizes a value between 0 and 1 based on good and bad thresholds
func (e *Engine) normalize(value, good, bad float64) float64 {
	if value <= good {
		return 0
	}
	if value >= bad {
		return 1
	}
	return (value - good) / (bad - good)
}

// calculateEWMA calculates the exponential weighted moving average
func (e *Engine) calculateEWMA(memberName string, instant float64) float64 {
	// TODO: Implement proper EWMA calculation with historical data
	// For now, use a simple approach
	alpha := 0.2 // EWMA factor

	if score, exists := e.scores[memberName]; exists {
		return alpha*instant + (1-alpha)*score.EWMA
	}

	return instant
}

// calculateWindowAverage calculates the average over the history window
func (e *Engine) calculateWindowAverage(samples []*telem.Sample) float64 {
	if len(samples) == 0 {
		return 0
	}

	total := 0.0
	count := 0

	for _, sample := range samples {
		if sample.Score != nil {
			total += sample.Score.Instant
			count++
		}
	}

	if count == 0 {
		return 0
	}

	return total / float64(count)
}

// makeDecision makes the failover decision
func (e *Engine) makeDecision(controller pkg.Controller) error {
	// Get eligible members ranked by score
	eligible := e.getEligibleMembers()
	if len(eligible) == 0 {
		return fmt.Errorf("no eligible members")
	}

	// Sort by final score (descending)
	sort.Slice(eligible, func(i, j int) bool {
		scoreI := e.scores[eligible[i].Name]
		scoreJ := e.scores[eligible[j].Name]
		if scoreI == nil || scoreJ == nil {
			return false
		}
		return scoreI.Final > scoreJ.Final
	})

	top := eligible[0]

	// Check if we need to switch
	if e.shouldSwitch(top) {
		return e.performSwitch(controller, top)
	}

	return nil
}

// getEligibleMembers returns all eligible members
func (e *Engine) getEligibleMembers() []*pkg.Member {
	var eligible []*pkg.Member

	for name, member := range e.members {
		if state := e.memberState[name]; state != nil && state.Status == pkg.StatusEligible {
			eligible = append(eligible, member)
		}
	}

	return eligible
}

// shouldSwitch determines if we should switch to the given member
func (e *Engine) shouldSwitch(target *pkg.Member) bool {
	if e.current == nil {
		return true // No current member, switch to target
	}

	if e.current.Name == target.Name {
		return false // Already using this member
	}

	// Check switch margin
	currentScore := e.scores[e.current.Name]
	targetScore := e.scores[target.Name]

	if currentScore == nil || targetScore == nil {
		return false
	}

	scoreDelta := targetScore.Final - currentScore.Final
	if scoreDelta < float64(e.config.SwitchMargin) {
		return false // Not enough improvement
	}

	// Check cooldown
	if time.Since(e.lastSwitch) < time.Duration(e.config.CooldownS)*time.Second {
		return false // In cooldown period
	}

	// Check predictive conditions
	if e.config.Predictive && e.shouldPredictiveSwitch(target) {
		return true
	}

	// Check duration windows
	return e.checkDurationWindows(target)
}

// shouldPredictiveSwitch checks if we should switch due to predictive conditions
func (e *Engine) shouldPredictiveSwitch(target *pkg.Member) bool {
	now := time.Now()

	// Rate limit predictive decisions
	if now.Sub(e.lastPredictive) < e.predictiveRate {
		return false
	}

	// TODO: Implement predictive logic based on trends
	// For now, just check if current member is degrading rapidly

	return false
}

// checkDurationWindows checks if duration windows are satisfied
func (e *Engine) checkDurationWindows(target *pkg.Member) bool {
	now := time.Now()

	// Check if target has been good long enough
	if goodStart, exists := e.goodWindows[target.Name]; exists {
		if now.Sub(goodStart) >= time.Duration(e.config.RestoreMinDurationS)*time.Second {
			return true
		}
	}

	// Check if current member has been bad long enough
	if e.current != nil {
		if badStart, exists := e.badWindows[e.current.Name]; exists {
			if now.Sub(badStart) >= time.Duration(e.config.FailMinDurationS)*time.Second {
				return true
			}
		}
	}

	return false
}

// performSwitch performs the actual switch
func (e *Engine) performSwitch(controller pkg.Controller, target *pkg.Member) error {
	from := e.current
	e.current = target
	e.lastSwitch = time.Now()

	// Perform the switch
	if err := controller.Switch(from, target); err != nil {
		e.logger.Error("Failed to perform switch", "from", from, "to", target, "error", err)
		return err
	}

	// Log the switch
	e.logger.LogSwitch(
		func() string { if from != nil { return from.Name } else { return "none" } }(),
		target.Name,
		"score",
		func() float64 { if score := e.scores[target.Name]; score != nil { return score.Final } else { return 0 } }(),
		map[string]interface{}{
			"switch_margin": e.config.SwitchMargin,
		},
	)

	// Add event to telemetry
	event := &pkg.Event{
		ID:        fmt.Sprintf("switch_%d", time.Now().Unix()),
		Type:      pkg.EventFailover,
		Timestamp: time.Now(),
		From:      func() string { if from != nil { return from.Name } else { return "none" } }(),
		To:        target.Name,
		Reason:    "score",
		Data: map[string]interface{}{
			"switch_margin": e.config.SwitchMargin,
		},
	}

	e.telemetry.AddEvent(event)

	return nil
}

// AddMember adds a member to the decision engine
func (e *Engine) AddMember(member *pkg.Member) {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.members[member.Name] = member
	e.logger.LogDiscovery(member.Name, member.Class, member.Iface, map[string]interface{}{
		"weight": member.Weight,
		"policy": member.Policy,
	})
}

// RemoveMember removes a member from the decision engine
func (e *Engine) RemoveMember(name string) {
	e.mu.Lock()
	defer e.mu.Unlock()

	delete(e.members, name)
	delete(e.memberState, name)
	delete(e.scores, name)
	delete(e.badWindows, name)
	delete(e.goodWindows, name)
	delete(e.cooldowns, name)
	delete(e.warmups, name)

	e.logger.LogEvent(pkg.EventMemberLost, name, map[string]interface{}{
		"reason": "removed",
	})
}

// GetMembers returns all members
func (e *Engine) GetMembers() []*pkg.Member {
	e.mu.RLock()
	defer e.mu.RUnlock()

	members := make([]*pkg.Member, 0, len(e.members))
	for _, member := range e.members {
		members = append(members, member)
	}

	return members
}

// GetCurrentMember returns the current active member
func (e *Engine) GetCurrentMember() *pkg.Member {
	e.mu.RLock()
	defer e.mu.RUnlock()

	return e.current
}

// GetScores returns all member scores
func (e *Engine) GetScores() map[string]*pkg.Score {
	e.mu.RLock()
	defer e.mu.RUnlock()

	scores := make(map[string]*pkg.Score)
	for k, v := range e.scores {
		scores[k] = v
	}

	return scores
}
