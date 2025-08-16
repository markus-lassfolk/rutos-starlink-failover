package decision

import (
	"context"
	"fmt"
	"math"
	"os"
	"sort"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/collector"
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

	// Advanced predictive algorithms
	predictiveModels map[string]*PredictiveModel
	trendAnalysis    map[string]*TrendAnalysis
	patternDetector  *PatternDetector
	mlPredictor      *MLPredictor
	predictiveEngine *PredictiveEngine
}

// PredictiveModel represents a predictive model for a member
type PredictiveModel struct {
	MemberName   string
	LastUpdate   time.Time
	HealthTrend  float64 // -1.0 to 1.0 (declining to improving)
	FailureRisk  float64 // 0.0 to 1.0 (low to high risk)
	RecoveryTime time.Duration
	Confidence   float64 // 0.0 to 1.0
	DataPoints   []DataPoint
	ModelType    string // "linear", "exponential", "ml"
}

// DataPoint represents a historical data point
type DataPoint struct {
	Timestamp time.Time
	Latency   float64
	Loss      float64
	Score     float64
	Status    string
}

// TrendAnalysis tracks trends for a member
type TrendAnalysis struct {
	MemberName     string
	LatencyTrend   float64 // ms per minute
	LossTrend      float64 // % per minute
	ScoreTrend     float64 // points per minute
	Volatility     float64 // standard deviation
	LastCalculated time.Time
	Window         time.Duration
}

// PatternDetector detects patterns in member behavior
type PatternDetector struct {
	patterns map[string]*Pattern
	mu       sync.RWMutex
}

// Pattern represents a detected pattern
type Pattern struct {
	ID          string
	MemberName  string
	Type        string // "cyclic", "deteriorating", "improving", "stable"
	Confidence  float64
	StartTime   time.Time
	EndTime     time.Time
	Description string
}

// Note: MLPredictor and MLModel are defined in predictive.go to avoid duplication

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
	// Create predictive engine configuration
	predictiveConfig := &PredictiveConfig{
		Enabled:             config.Predictive,
		LookbackWindow:      time.Duration(config.HistoryWindowS) * time.Second,
		PredictionHorizon:   time.Duration(config.FailMinDurationS*2) * time.Second,
		ConfidenceThreshold: 0.7,
		AnomalyThreshold:    0.8,
		TrendSensitivity:    0.1,
		PatternMinSamples:   10,
		MLEnabled:           true,
		MLModelPath:         "/tmp/starfail/ml_models.json",
	}
	
	// Ensure ML model directory exists
	if predictiveConfig.MLEnabled {
		if err := os.MkdirAll("/tmp/starfail", 0755); err != nil {
			logger.Warn("Failed to create ML model directory, disabling ML features", "error", err)
			predictiveConfig.MLEnabled = false
		}
	}

	return &Engine{
		config:           config,
		logger:           logger,
		telemetry:        telemetry,
		members:          make(map[string]*pkg.Member),
		memberState:      make(map[string]*MemberState),
		scores:           make(map[string]*pkg.Score),
		badWindows:       make(map[string]time.Time),
		goodWindows:      make(map[string]time.Time),
		cooldowns:        make(map[string]time.Time),
		warmups:          make(map[string]time.Time),
		predictiveRate:   time.Duration(config.FailMinDurationS*5) * time.Second,
		predictiveModels: make(map[string]*PredictiveModel),
		trendAnalysis:    make(map[string]*TrendAnalysis),
		patternDetector:  NewPatternDetector(),
		mlPredictor:      NewMLPredictor("", logger), // Use empty model path for now
		predictiveEngine: NewPredictiveEngine(predictiveConfig, logger),
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

// collectorFactory returns the appropriate collector for a member based on its class
func (e *Engine) collectorFactory(member *pkg.Member) (pkg.Collector, error) {
	cfg := map[string]interface{}{}

	switch member.Class {
	case pkg.ClassStarlink:
		return collector.NewStarlinkCollector(cfg)
	case pkg.ClassCellular:
		return collector.NewCellularCollector(cfg)
	case pkg.ClassWiFi:
		return collector.NewWiFiCollector(cfg)
	case pkg.ClassLAN:
		return collector.NewLANCollector(cfg)
	case pkg.ClassOther:
		return collector.NewGenericCollector(cfg)
	default:
		return collector.NewGenericCollector(cfg)
	}
}

// collectMemberMetrics collects metrics for a specific member
func (e *Engine) collectMemberMetrics(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	coll, err := e.collectorFactory(member)
	if err != nil {
		return nil, fmt.Errorf("failed to create collector for %s: %w", member.Name, err)
	}

	metrics, err := coll.Collect(ctx, member)
	if err != nil {
		return nil, fmt.Errorf("failed to collect metrics for %s: %w", member.Name, err)
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

		// Update predictive engine with new data
		if e.predictiveEngine != nil && len(samples) > 0 {
			latest := samples[len(samples)-1]
			e.predictiveEngine.UpdateMemberData(name, latest.Metrics, score)
		}

		// Update trend analysis
		e.updateTrendAnalysis(name, samples)
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
func (e *Engine) calculateInstantScore(member *pkg.Member, metrics *pkg.Metrics) float64 {
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
func (e *Engine) scoreStarlink(metrics *pkg.Metrics, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	latPenalty := e.normalize(metrics.LatencyMS, 50, 1500) * 20
	score -= latPenalty

	// Loss penalty
	lossPenalty := e.normalize(metrics.LossPercent, 0, 10) * 30
	score -= lossPenalty

	// Jitter penalty
	jitterPenalty := e.normalize(metrics.JitterMS, 5, 200) * 15
	score -= jitterPenalty

	// Obstruction penalty
	if metrics.ObstructionPct != nil {
		obstPenalty := e.normalize(*metrics.ObstructionPct, 0, 10) * 25
		score -= obstPenalty
	}

	// Outage penalty
	if metrics.Outages != nil && *metrics.Outages > 0 {
		score -= 20 // Significant penalty for outages
	}

	return score
}

// scoreCellular calculates score for cellular members
func (e *Engine) scoreCellular(metrics *pkg.Metrics, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	latPenalty := e.normalize(metrics.LatencyMS, 50, 1500) * 20
	score -= latPenalty

	// Loss penalty
	lossPenalty := e.normalize(metrics.LossPercent, 0, 10) * 30
	score -= lossPenalty

	// Signal quality bonus/penalty
	if metrics.RSRP != nil {
		// RSRP ranges from -140 to -44 dBm
		rsrpScore := float64(*metrics.RSRP+140) / 96.0 * 100
		if rsrpScore > 100 {
			rsrpScore = 100
		} else if rsrpScore < 0 {
			rsrpScore = 0
		}
		score = score*0.7 + rsrpScore*0.3
	}

	// Roaming penalty
	if metrics.Roaming != nil && *metrics.Roaming {
		if config == nil || !config.PreferRoaming {
			score -= 15 // Penalty for roaming
		}
	}

	return score
}

// scoreWiFi calculates score for WiFi members
func (e *Engine) scoreWiFi(metrics *pkg.Metrics, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	latPenalty := e.normalize(metrics.LatencyMS, 50, 1500) * 20
	score -= latPenalty

	// Loss penalty
	lossPenalty := e.normalize(metrics.LossPercent, 0, 10) * 30
	score -= lossPenalty

	// Signal strength bonus/penalty
	if metrics.SignalStrength != nil {
		// WiFi signal typically ranges from -100 to -30 dBm
		signalScore := float64(*metrics.SignalStrength+100) / 70.0 * 100
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
func (e *Engine) scoreLAN(metrics *pkg.Metrics, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty (LAN should be very fast)
	latPenalty := e.normalize(metrics.LatencyMS, 1, 100) * 25
	score -= latPenalty

	// Loss penalty (LAN should have no loss)
	lossPenalty := metrics.LossPercent * 50 // High penalty for any loss on LAN
	score -= lossPenalty

	return score
}

// scoreGeneric calculates score for generic members
func (e *Engine) scoreGeneric(metrics *pkg.Metrics, config *uci.MemberConfig) float64 {
	score := 100.0

	// Latency penalty
	latPenalty := e.normalize(metrics.LatencyMS, 50, 1500) * 20
	score -= latPenalty

	// Loss penalty
	lossPenalty := e.normalize(metrics.LossPercent, 0, 10) * 30
	score -= lossPenalty

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
	// Implement EWMA calculation with configurable alpha and historical data support
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

	if e.current == nil || e.predictiveEngine == nil {
		return false
	}

	// Get failure prediction for current member
	prediction, err := e.predictiveEngine.PredictFailure(e.current.Name)
	if err != nil {
		e.logger.Debug("Failed to get failure prediction", "member", e.current.Name, "error", err)
		return false
	}

	// Check if prediction indicates high failure risk
	if prediction.Risk > 0.7 && prediction.Confidence > 0.6 {
		e.logger.Info("Predictive failover triggered",
			"current", e.current.Name,
			"target", target.Name,
			"risk", prediction.Risk,
			"confidence", prediction.Confidence,
			"method", prediction.Method,
		)

		e.lastPredictive = now
		return true
	}

	// Check for specific predictive triggers based on member class
	if e.checkClassSpecificPredictiveTriggers(target) {
		e.logger.Info("Class-specific predictive failover triggered",
			"current", e.current.Name,
			"target", target.Name,
		)

		e.lastPredictive = now
		return true
	}

	// Check trend-based predictive triggers
	if e.checkTrendBasedPredictiveTriggers(target) {
		e.logger.Info("Trend-based predictive failover triggered",
			"current", e.current.Name,
			"target", target.Name,
		)

		e.lastPredictive = now
		return true
	}

	return false
}

// checkClassSpecificPredictiveTriggers checks for class-specific predictive conditions
func (e *Engine) checkClassSpecificPredictiveTriggers(target *pkg.Member) bool {
	if e.current == nil {
		return false
	}

	// Get recent samples for current member
	now := time.Now()
	samples, err := e.telemetry.GetSamples(e.current.Name, now.Add(-5*time.Minute))
	if err != nil || len(samples) < 3 {
		return false
	}

	// Starlink-specific triggers
	if e.current.Class == pkg.ClassStarlink {
		return e.checkStarlinkPredictiveTriggers(samples)
	}

	// Cellular-specific triggers
	if e.current.Class == pkg.ClassCellular {
		return e.checkCellularPredictiveTriggers(samples)
	}

	// WiFi-specific triggers
	if e.current.Class == pkg.ClassWiFi {
		return e.checkWiFiPredictiveTriggers(samples)
	}

	return false
}

// checkStarlinkPredictiveTriggers checks Starlink-specific predictive conditions
func (e *Engine) checkStarlinkPredictiveTriggers(samples []*telem.Sample) bool {
	if len(samples) < 3 {
		return false
	}

	latest := samples[len(samples)-1]
	metrics := latest.Metrics

	// Check for rapid obstruction increase
	if metrics.ObstructionPct != nil && *metrics.ObstructionPct > 5.0 {
		// Check if obstruction is accelerating
		if len(samples) >= 3 {
			prev1 := samples[len(samples)-2]
			prev2 := samples[len(samples)-3]

			if prev1.Metrics.ObstructionPct != nil && prev2.Metrics.ObstructionPct != nil {
				current := *metrics.ObstructionPct
				prev1Val := *prev1.Metrics.ObstructionPct
				prev2Val := *prev2.Metrics.ObstructionPct

				// Check for acceleration in obstruction
				if current > prev1Val && prev1Val > prev2Val {
					acceleration := (current - prev1Val) - (prev1Val - prev2Val)
					if acceleration > 2.0 { // 2% acceleration threshold
						e.logger.Info("Starlink obstruction acceleration detected",
							"current", current,
							"prev1", prev1Val,
							"prev2", prev2Val,
							"acceleration", acceleration,
						)
						return true
					}
				}
			}
		}
	}

	// Check for thermal issues
	if metrics.ThermalThrottle != nil && *metrics.ThermalThrottle {
		e.logger.Info("Starlink thermal throttling detected")
		return true
	}

	// Check for pending software update reboot
	if metrics.SwupdateRebootReady != nil && *metrics.SwupdateRebootReady {
		e.logger.Info("Starlink software update reboot pending")
		return true
	}

	// Check for persistently low SNR
	if metrics.IsSNRPersistentlyLow != nil && *metrics.IsSNRPersistentlyLow {
		e.logger.Info("Starlink persistently low SNR detected")
		return true
	}

	return false
}

// checkCellularPredictiveTriggers checks cellular-specific predictive conditions
func (e *Engine) checkCellularPredictiveTriggers(samples []*telem.Sample) bool {
	if len(samples) < 3 {
		return false
	}

	latest := samples[len(samples)-1]
	metrics := latest.Metrics

	// Check for signal degradation
	if metrics.RSRP != nil && *metrics.RSRP < -110 {
		e.logger.Info("Cellular signal severely degraded", "rsrp", *metrics.RSRP)
		return true
	}

	// Check for roaming activation
	if metrics.Roaming != nil && *metrics.Roaming {
		e.logger.Info("Cellular roaming detected")
		return true
	}

	// Check for rapid RSRP degradation
	if len(samples) >= 3 && metrics.RSRP != nil {
		prev1 := samples[len(samples)-2]
		prev2 := samples[len(samples)-3]

		if prev1.Metrics.RSRP != nil && prev2.Metrics.RSRP != nil {
			current := float64(*metrics.RSRP)
			prev1Val := float64(*prev1.Metrics.RSRP)
			prev2Val := float64(*prev2.Metrics.RSRP)

			// Check for rapid degradation (RSRP getting more negative)
			if current < prev1Val-5 && prev1Val < prev2Val-5 {
				e.logger.Info("Cellular rapid signal degradation detected",
					"current", current,
					"prev1", prev1Val,
					"prev2", prev2Val,
				)
				return true
			}
		}
	}

	return false
}

// checkWiFiPredictiveTriggers checks WiFi-specific predictive conditions
func (e *Engine) checkWiFiPredictiveTriggers(samples []*telem.Sample) bool {
	if len(samples) < 3 {
		return false
	}

	latest := samples[len(samples)-1]
	metrics := latest.Metrics

	// Check for very poor signal strength
	if metrics.SignalStrength != nil && *metrics.SignalStrength < -80 {
		e.logger.Info("WiFi signal severely degraded", "signal", *metrics.SignalStrength)
		return true
	}

	// Check for very low SNR
	if metrics.SNR != nil && *metrics.SNR < 10 {
		e.logger.Info("WiFi SNR critically low", "snr", *metrics.SNR)
		return true
	}

	return false
}

// checkTrendBasedPredictiveTriggers checks for trend-based predictive conditions
func (e *Engine) checkTrendBasedPredictiveTriggers(target *pkg.Member) bool {
	if e.current == nil {
		return false
	}

	// Get trend analysis for current member
	trend, exists := e.trendAnalysis[e.current.Name]
	if !exists {
		return false
	}

	now := time.Now()
	// Only use recent trend data
	if now.Sub(trend.LastCalculated) > 2*time.Minute {
		return false
	}

	// Check for rapid latency increase
	if trend.LatencyTrend > 50.0 { // 50ms per minute increase
		e.logger.Info("Rapid latency increase detected",
			"member", e.current.Name,
			"trend", trend.LatencyTrend,
		)
		return true
	}

	// Check for rapid loss increase
	if trend.LossTrend > 2.0 { // 2% per minute increase
		e.logger.Info("Rapid loss increase detected",
			"member", e.current.Name,
			"trend", trend.LossTrend,
		)
		return true
	}

	// Check for rapid score degradation
	if trend.ScoreTrend < -10.0 { // 10 points per minute decrease
		e.logger.Info("Rapid score degradation detected",
			"member", e.current.Name,
			"trend", trend.ScoreTrend,
		)
		return true
	}

	return false
}

// updateTrendAnalysis updates trend analysis for a member
func (e *Engine) updateTrendAnalysis(memberName string, samples []*telem.Sample) {
	if len(samples) < 5 {
		return // Need at least 5 samples for trend analysis
	}

	now := time.Now()

	// Get or create trend analysis
	trend, exists := e.trendAnalysis[memberName]
	if !exists {
		trend = &TrendAnalysis{
			MemberName:     memberName,
			LastCalculated: now,
			Window:         time.Duration(e.config.HistoryWindowS) * time.Second,
		}
		e.trendAnalysis[memberName] = trend
	}

	// Only update if enough time has passed
	if now.Sub(trend.LastCalculated) < 30*time.Second {
		return
	}

	// Calculate trends using linear regression on recent samples
	recentSamples := samples
	if len(samples) > 20 {
		recentSamples = samples[len(samples)-20:] // Use last 20 samples
	}

	// Calculate latency trend
	trend.LatencyTrend = e.calculateTrendForMetric(recentSamples, func(s *telem.Sample) float64 {
		return s.Metrics.LatencyMS
	})

	// Calculate loss trend
	trend.LossTrend = e.calculateTrendForMetric(recentSamples, func(s *telem.Sample) float64 {
		return s.Metrics.LossPercent
	})

	// Calculate score trend (if we have score data)
	if len(recentSamples) > 0 {
		// Get scores for recent samples
		scoreValues := make([]float64, 0, len(recentSamples))
		timestamps := make([]time.Time, 0, len(recentSamples))

		for _, sample := range recentSamples {
			// Calculate instant score for each sample
			member := e.members[memberName]
			if member != nil {
				instantScore := e.calculateInstantScore(member, sample.Metrics)
				scoreValues = append(scoreValues, instantScore)
				timestamps = append(timestamps, sample.Timestamp)
			}
		}

		if len(scoreValues) >= 3 {
			trend.ScoreTrend = e.calculateTrendFromValues(timestamps, scoreValues)
		}
	}

	// Calculate volatility (standard deviation of recent scores)
	if len(recentSamples) >= 3 {
		latencyValues := make([]float64, len(recentSamples))
		for i, sample := range recentSamples {
			latencyValues[i] = sample.Metrics.LatencyMS
		}
		trend.Volatility = e.calculateStandardDeviation(latencyValues)
	}

	trend.LastCalculated = now
}

// calculateTrendForMetric calculates trend for a specific metric
func (e *Engine) calculateTrendForMetric(samples []*telem.Sample, extractor func(*telem.Sample) float64) float64 {
	if len(samples) < 3 {
		return 0.0
	}

	timestamps := make([]time.Time, len(samples))
	values := make([]float64, len(samples))

	for i, sample := range samples {
		timestamps[i] = sample.Timestamp
		values[i] = extractor(sample)
	}

	return e.calculateTrendFromValues(timestamps, values)
}

// calculateTrendFromValues calculates trend from timestamp/value pairs
func (e *Engine) calculateTrendFromValues(timestamps []time.Time, values []float64) float64 {
	if len(timestamps) != len(values) || len(values) < 2 {
		return 0.0
	}

	n := float64(len(values))

	// Convert timestamps to seconds since first timestamp
	baseTime := timestamps[0]
	x := make([]float64, len(timestamps))
	for i, ts := range timestamps {
		x[i] = ts.Sub(baseTime).Seconds()
	}

	// Calculate linear regression
	sumX := 0.0
	sumY := 0.0
	sumXY := 0.0
	sumX2 := 0.0

	for i := 0; i < len(x); i++ {
		sumX += x[i]
		sumY += values[i]
		sumXY += x[i] * values[i]
		sumX2 += x[i] * x[i]
	}

	// Calculate slope (trend per second)
	denominator := n*sumX2 - sumX*sumX
	if denominator == 0 {
		return 0.0
	}

	slope := (n*sumXY - sumX*sumY) / denominator

	// Convert to per-minute trend
	return slope * 60.0
}

// calculateStandardDeviation calculates standard deviation of values
func (e *Engine) calculateStandardDeviation(values []float64) float64 {
	if len(values) < 2 {
		return 0.0
	}

	// Calculate mean
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	mean := sum / float64(len(values))

	// Calculate variance
	variance := 0.0
	for _, v := range values {
		diff := v - mean
		variance += diff * diff
	}
	variance /= float64(len(values))

	return math.Sqrt(variance)
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
		func() string {
			if from != nil {
				return from.Name
			} else {
				return "none"
			}
		}(),
		target.Name,
		"score",
		func() float64 {
			if score := e.scores[target.Name]; score != nil {
				return score.Final
			} else {
				return 0
			}
		}(),
		map[string]interface{}{
			"switch_margin": e.config.SwitchMargin,
		},
	)

	// Add event to telemetry
	event := &pkg.Event{
		ID:        fmt.Sprintf("switch_%d", time.Now().Unix()),
		Type:      pkg.EventFailover,
		Timestamp: time.Now(),
		From: func() string {
			if from != nil {
				return from.Name
			} else {
				return "none"
			}
		}(),
		To:     target.Name,
		Reason: "score",
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

// GetMemberState returns the state of a specific member
func (e *Engine) GetMemberState(memberName string) (*MemberState, error) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	state, exists := e.memberState[memberName]
	if !exists {
		return nil, fmt.Errorf("member state not found: %s", memberName)
	}

	return state, nil
}

// Advanced Predictive Methods

// NewPatternDetector creates a new pattern detector
func NewPatternDetector() *PatternDetector {
	return &PatternDetector{
		patterns: make(map[string]*Pattern),
	}
}

// Note: NewMLPredictor is defined in predictive.go to avoid duplication

// updatePredictiveModels updates predictive models for all members
func (e *Engine) updatePredictiveModels() {
	now := time.Now()

	for name := range e.members {
		// Get historical data
		samples, err := e.telemetry.GetSamples(name, now.Add(-time.Hour))
		if err != nil {
			continue
		}

		if len(samples) < 10 {
			continue // Need minimum data points
		}

		// Update or create predictive model
		model := e.getOrCreatePredictiveModel(name)
		e.updateModel(model, samples)

		// Trend analysis is updated in updateTrendAnalysis method called earlier
	}
}

// getOrCreatePredictiveModel gets or creates a predictive model for a member
func (e *Engine) getOrCreatePredictiveModel(memberName string) *PredictiveModel {
	if model, exists := e.predictiveModels[memberName]; exists {
		return model
	}

	model := &PredictiveModel{
		MemberName: memberName,
		ModelType:  "linear",
		DataPoints: make([]DataPoint, 0),
	}
	e.predictiveModels[memberName] = model
	return model
}

// getOrCreateTrendAnalysis gets or creates trend analysis for a member
func (e *Engine) getOrCreateTrendAnalysis(memberName string) *TrendAnalysis {
	if trend, exists := e.trendAnalysis[memberName]; exists {
		return trend
	}

	trend := &TrendAnalysis{
		MemberName: memberName,
		Window:     time.Hour,
	}
	e.trendAnalysis[memberName] = trend
	return trend
}

// updateModel updates a predictive model with new data
func (e *Engine) updateModel(model *PredictiveModel, samples []*telem.Sample) {
	// Convert samples to data points
	var dataPoints []DataPoint
	for _, sample := range samples {
		// Extract metrics from struct
		latency := sample.Metrics.LatencyMS
		loss := sample.Metrics.LossPercent

		dataPoint := DataPoint{
			Timestamp: sample.Timestamp,
			Latency:   latency,
			Loss:      loss,
			Score:     sample.Score.Final,
			Status:    "healthy", // Default status
		}
		dataPoints = append(dataPoints, dataPoint)
	}

	// Update model data
	model.DataPoints = dataPoints
	model.LastUpdate = time.Now()

	// Calculate health trend
	model.HealthTrend = e.calculateHealthTrend(dataPoints)

	// Calculate failure risk
	model.FailureRisk = e.calculateFailureRisk(dataPoints)

	// Calculate recovery time
	model.RecoveryTime = e.calculateRecoveryTime(dataPoints)

	// Calculate confidence
	model.Confidence = e.calculateConfidence(dataPoints)
}

// detectPatterns detects patterns in member behavior
func (e *Engine) detectPatterns() {
	for name := range e.members {
		samples, err := e.telemetry.GetSamples(name, time.Now().Add(-time.Hour))
		if err != nil {
			continue
		}

		patterns := e.patternDetector.detectPatterns(name, samples)
		for _, pattern := range patterns {
			e.logger.Info("Detected pattern", "member", name, "pattern", pattern.Type, "confidence", pattern.Confidence)
		}
	}
}

// getEligibleMembersWithPredictions returns eligible members with predictive adjustments
func (e *Engine) getEligibleMembersWithPredictions() []*pkg.Member {
	eligible := e.getEligibleMembers()

	// Apply predictive adjustments
	for _, member := range eligible {
		if model := e.predictiveModels[member.Name]; model != nil {
			// Adjust score based on predictive model
			if score := e.scores[member.Name]; score != nil {
				adjustment := e.calculatePredictiveAdjustment(model)
				score.Final += adjustment
			}
		}
	}

	return eligible
}

// rankMembersWithPredictions ranks members with predictive considerations
func (e *Engine) rankMembersWithPredictions(members []*pkg.Member) []*pkg.Member {
	// Sort by adjusted score
	sort.Slice(members, func(i, j int) bool {
		scoreI := e.scores[members[i].Name]
		scoreJ := e.scores[members[j].Name]
		if scoreI == nil || scoreJ == nil {
			return false
		}
		return scoreI.Final > scoreJ.Final
	})

	return members
}

// shouldSwitchWithPredictions checks if we should switch with predictive considerations
func (e *Engine) shouldSwitchWithPredictions(target *pkg.Member) bool {
	// Basic switch logic
	if !e.shouldSwitch(target) {
		return false
	}

	// Check predictive triggers
	if e.config.Predictive {
		// Check if current member is predicted to fail soon
		if e.current != nil {
			if model := e.predictiveModels[e.current.Name]; model != nil {
				if model.FailureRisk > 0.7 && model.Confidence > 0.6 {
					e.logger.Info("Predictive switch triggered", "member", e.current.Name, "risk", model.FailureRisk)
					return true
				}
			}
		}

		// Check if target member is predicted to improve
		if model := e.predictiveModels[target.Name]; model != nil {
			if model.HealthTrend > 0.3 && model.Confidence > 0.6 {
				e.logger.Info("Predictive switch to improving member", "member", target.Name, "trend", model.HealthTrend)
				return true
			}
		}
	}

	return true
}

// isPredictiveSwitch checks if this is a predictive switch
func (e *Engine) isPredictiveSwitch(target *pkg.Member) bool {
	if !e.config.Predictive {
		return false
	}

	// Check if current member has high failure risk
	if e.current != nil {
		if model := e.predictiveModels[e.current.Name]; model != nil {
			if model.FailureRisk > 0.7 && model.Confidence > 0.6 {
				return true
			}
		}
	}

	// Check if target member has improving trend
	if model := e.predictiveModels[target.Name]; model != nil {
		if model.HealthTrend > 0.3 && model.Confidence > 0.6 {
			return true
		}
	}

	return false
}

// Helper methods for predictive calculations

func (e *Engine) calculateHealthTrend(dataPoints []DataPoint) float64 {
	if len(dataPoints) < 2 {
		return 0.0
	}

	// Simple linear trend calculation
	first := dataPoints[0]
	last := dataPoints[len(dataPoints)-1]

	timeDiff := last.Timestamp.Sub(first.Timestamp).Minutes()
	if timeDiff == 0 {
		return 0.0
	}

	scoreDiff := last.Score - first.Score
	return scoreDiff / timeDiff
}

func (e *Engine) calculateFailureRisk(dataPoints []DataPoint) float64 {
	if len(dataPoints) < 5 {
		return 0.0
	}

	// Calculate risk based on recent performance degradation
	recent := dataPoints[len(dataPoints)-5:]
	avgScore := 0.0
	for _, dp := range recent {
		avgScore += dp.Score
	}
	avgScore /= float64(len(recent))

	// Risk increases as score decreases
	if avgScore > 80 {
		return 0.0
	} else if avgScore > 60 {
		return 0.3
	} else if avgScore > 40 {
		return 0.6
	} else {
		return 0.9
	}
}

func (e *Engine) calculateRecoveryTime(dataPoints []DataPoint) time.Duration {
	// Simple heuristic based on recent performance
	if len(dataPoints) < 3 {
		return 5 * time.Minute
	}

	recent := dataPoints[len(dataPoints)-3:]
	avgScore := 0.0
	for _, dp := range recent {
		avgScore += dp.Score
	}
	avgScore /= float64(len(recent))

	if avgScore > 80 {
		return 1 * time.Minute
	} else if avgScore > 60 {
		return 3 * time.Minute
	} else {
		return 10 * time.Minute
	}
}

func (e *Engine) calculateConfidence(dataPoints []DataPoint) float64 {
	if len(dataPoints) < 10 {
		return 0.0
	}

	// Confidence increases with more data points
	baseConfidence := math.Min(float64(len(dataPoints))/100.0, 1.0)

	// Adjust based on data consistency
	variance := e.calculateVariance(dataPoints)
	consistencyBonus := math.Max(0, 1.0-variance/100.0)

	return math.Min(baseConfidence+consistencyBonus, 1.0)
}

func (e *Engine) calculateLatencyTrend(samples []*telem.Sample) float64 {
	if len(samples) < 2 {
		return 0.0
	}

	first := samples[0]
	last := samples[len(samples)-1]

	timeDiff := last.Timestamp.Sub(first.Timestamp).Minutes()
	if timeDiff == 0 {
		return 0.0
	}

	lastLatency := last.Metrics.LatencyMS
	firstLatency := first.Metrics.LatencyMS
	latencyDiff := lastLatency - firstLatency
	return latencyDiff / timeDiff
}

func (e *Engine) calculateLossTrend(samples []*telem.Sample) float64 {
	if len(samples) < 2 {
		return 0.0
	}

	first := samples[0]
	last := samples[len(samples)-1]

	timeDiff := last.Timestamp.Sub(first.Timestamp).Minutes()
	if timeDiff == 0 {
		return 0.0
	}

	lastLoss := last.Metrics.LossPercent
	firstLoss := first.Metrics.LossPercent
	lossDiff := lastLoss - firstLoss
	return lossDiff / timeDiff
}

func (e *Engine) calculateScoreTrend(samples []*telem.Sample) float64 {
	if len(samples) < 2 {
		return 0.0
	}

	first := samples[0]
	last := samples[len(samples)-1]

	timeDiff := last.Timestamp.Sub(first.Timestamp).Minutes()
	if timeDiff == 0 {
		return 0.0
	}

	scoreDiff := last.Score.Final - first.Score.Final
	return scoreDiff / timeDiff
}

func (e *Engine) calculateVolatility(samples []*telem.Sample) float64 {
	if len(samples) < 2 {
		return 0.0
	}

	// Calculate standard deviation of scores
	scores := make([]float64, len(samples))
	for i, sample := range samples {
		scores[i] = sample.Score.Final
	}

	return e.calculateStandardDeviation(scores)
}

func (e *Engine) calculatePredictiveAdjustment(model *PredictiveModel) float64 {
	// Adjust score based on predictive model
	adjustment := 0.0

	// Health trend adjustment
	adjustment += model.HealthTrend * 10.0

	// Failure risk adjustment (negative)
	adjustment -= model.FailureRisk * 20.0

	// Confidence weighting
	adjustment *= model.Confidence

	return adjustment
}

func (e *Engine) calculateVariance(dataPoints []DataPoint) float64 {
	if len(dataPoints) < 2 {
		return 0.0
	}

	scores := make([]float64, len(dataPoints))
	for i, dp := range dataPoints {
		scores[i] = dp.Score
	}

	mean := 0.0
	for _, score := range scores {
		mean += score
	}
	mean /= float64(len(scores))

	variance := 0.0
	for _, score := range scores {
		variance += math.Pow(score-mean, 2)
	}
	variance /= float64(len(scores))

	return variance
}

// PatternDetector methods

func (pd *PatternDetector) detectPatterns(memberName string, samples []*telem.Sample) []*Pattern {
	var patterns []*Pattern

	// Detect cyclic patterns
	if pattern := pd.detectCyclicPattern(memberName, samples); pattern != nil {
		patterns = append(patterns, pattern)
	}

	// Detect deteriorating patterns
	if pattern := pd.detectDeterioratingPattern(memberName, samples); pattern != nil {
		patterns = append(patterns, pattern)
	}

	// Detect improving patterns
	if pattern := pd.detectImprovingPattern(memberName, samples); pattern != nil {
		patterns = append(patterns, pattern)
	}

	return patterns
}

func (pd *PatternDetector) detectCyclicPattern(memberName string, samples []*telem.Sample) *Pattern {
	// Simple cyclic pattern detection
	if len(samples) < 20 {
		return nil
	}

	// Check for periodic score variations
	scores := make([]float64, len(samples))
	for i, sample := range samples {
		scores[i] = sample.Score.Final
	}

	// Simple autocorrelation check
	autocorr := pd.calculateAutocorrelation(scores)
	if autocorr > 0.5 {
		return &Pattern{
			ID:          fmt.Sprintf("cyclic_%s_%d", memberName, time.Now().Unix()),
			MemberName:  memberName,
			Type:        "cyclic",
			Confidence:  autocorr,
			StartTime:   samples[0].Timestamp,
			EndTime:     samples[len(samples)-1].Timestamp,
			Description: "Detected cyclic performance pattern",
		}
	}

	return nil
}

func (pd *PatternDetector) detectDeterioratingPattern(memberName string, samples []*telem.Sample) *Pattern {
	if len(samples) < 10 {
		return nil
	}

	// Check for consistent score decline
	recent := samples[len(samples)-10:]
	trend := 0.0

	for i := 1; i < len(recent); i++ {
		if recent[i].Score.Final < recent[i-1].Score.Final {
			trend += 1.0
		}
	}

	declineRatio := trend / float64(len(recent)-1)
	if declineRatio > 0.7 {
		return &Pattern{
			ID:          fmt.Sprintf("deteriorating_%s_%d", memberName, time.Now().Unix()),
			MemberName:  memberName,
			Type:        "deteriorating",
			Confidence:  declineRatio,
			StartTime:   recent[0].Timestamp,
			EndTime:     recent[len(recent)-1].Timestamp,
			Description: "Detected deteriorating performance pattern",
		}
	}

	return nil
}

func (pd *PatternDetector) detectImprovingPattern(memberName string, samples []*telem.Sample) *Pattern {
	if len(samples) < 10 {
		return nil
	}

	// Check for consistent score improvement
	recent := samples[len(samples)-10:]
	trend := 0.0

	for i := 1; i < len(recent); i++ {
		if recent[i].Score.Final > recent[i-1].Score.Final {
			trend += 1.0
		}
	}

	improveRatio := trend / float64(len(recent)-1)
	if improveRatio > 0.7 {
		return &Pattern{
			ID:          fmt.Sprintf("improving_%s_%d", memberName, time.Now().Unix()),
			MemberName:  memberName,
			Type:        "improving",
			Confidence:  improveRatio,
			StartTime:   recent[0].Timestamp,
			EndTime:     recent[len(recent)-1].Timestamp,
			Description: "Detected improving performance pattern",
		}
	}

	return nil
}

func (pd *PatternDetector) calculateAutocorrelation(values []float64) float64 {
	if len(values) < 10 {
		return 0.0
	}

	// Simple autocorrelation calculation
	lag := len(values) / 4
	if lag < 2 {
		return 0.0
	}

	numerator := 0.0
	denominator := 0.0

	mean := 0.0
	for _, value := range values {
		mean += value
	}
	mean /= float64(len(values))

	for i := lag; i < len(values); i++ {
		numerator += (values[i] - mean) * (values[i-lag] - mean)
		denominator += math.Pow(values[i]-mean, 2)
	}

	if denominator == 0 {
		return 0.0
	}

	return numerator / denominator
}
