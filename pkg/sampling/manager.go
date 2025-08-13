// Package sampling provides adaptive sampling rates based on connection characteristics
package sampling

import (
	"context"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

// Manager handles adaptive sampling rate decisions
type Manager struct {
	config Config
	logger logx.Logger
	rates  map[string]*InterfaceRate
}

// Config holds sampling configuration
type Config struct {
	UnlimitedIntervalMs int     `uci:"unlimited_interval_ms" default:"1000"`
	MeteredIntervalMs   int     `uci:"metered_interval_ms" default:"60000"`
	DegradedIntervalMs  int     `uci:"degraded_interval_ms" default:"5000"`
	StableIntervalMs    int     `uci:"stable_interval_ms" default:"10000"`
	MaxProbeSize        int     `uci:"max_probe_size" default:"32"`
	BusinessHourStart   int     `uci:"business_hour_start" default:"8"`
	BusinessHourEnd     int     `uci:"business_hour_end" default:"18"`
	OffHoursMultiplier  float64 `uci:"off_hours_multiplier" default:"2.0"`
}

// InterfaceRate tracks sampling rate for a specific interface
type InterfaceRate struct {
	InterfaceName    string
	ConnectionType   ConnectionType
	CurrentInterval  time.Duration
	BaseInterval     time.Duration
	LastAdjustment   time.Time
	PerformanceState PerformanceState
	DataUsageKB      int64
	ProbeCount       int64
	IsBusinessHours  bool
}

// ConnectionType represents the type of connection
type ConnectionType int

const (
	ConnectionTypeUnknown ConnectionType = iota
	ConnectionTypeUnlimited
	ConnectionTypeMetered
	ConnectionTypeCapped
)

func (ct ConnectionType) String() string {
	switch ct {
	case ConnectionTypeUnlimited:
		return "unlimited"
	case ConnectionTypeMetered:
		return "metered"
	case ConnectionTypeCapped:
		return "capped"
	default:
		return "unknown"
	}
}

// PerformanceState represents the current performance level
type PerformanceState int

const (
	PerformanceStateUnknown PerformanceState = iota
	PerformanceStateStable
	PerformanceStateDegraded
	PerformanceStateUnstable
	PerformanceStateFailing
)

func (ps PerformanceState) String() string {
	switch ps {
	case PerformanceStateStable:
		return "stable"
	case PerformanceStateDegraded:
		return "degraded"
	case PerformanceStateUnstable:
		return "unstable"
	case PerformanceStateFailing:
		return "failing"
	default:
		return "unknown"
	}
}

// SamplingRequest represents a request for sampling rate
type SamplingRequest struct {
	InterfaceName  string
	ConnectionType ConnectionType
	IsMetered      bool
	CurrentLatency float64
	CurrentLoss    float64
	QualityScore   float64
	RecentFailures int
	UserActivity   bool
}

// SamplingResponse provides the recommended sampling parameters
type SamplingResponse struct {
	Interval    time.Duration
	ProbeSize   int
	ProbeCount  int
	Reason      string
	Adjustments []string
}

// NewManager creates a new adaptive sampling manager
func NewManager(config Config, logger logx.Logger) *Manager {
	return &Manager{
		config: config,
		logger: logger,
		rates:  make(map[string]*InterfaceRate),
	}
}

// GetSamplingRate determines the appropriate sampling rate for an interface
func (m *Manager) GetSamplingRate(ctx context.Context, req SamplingRequest) SamplingResponse {
	// Get or create interface rate tracker
	rate := m.getInterfaceRate(req.InterfaceName)

	// Update connection type if changed
	if rate.ConnectionType != req.ConnectionType {
		rate.ConnectionType = req.ConnectionType
		rate.BaseInterval = m.getBaseInterval(req.ConnectionType, req.IsMetered)
		m.logger.Info("connection type updated",
			"interface", req.InterfaceName,
			"type", req.ConnectionType.String(),
			"base_interval", rate.BaseInterval,
		)
	}

	// Determine current performance state
	newState := m.determinePerformanceState(req)
	if newState != rate.PerformanceState {
		m.logger.Debug("performance state changed",
			"interface", req.InterfaceName,
			"old_state", rate.PerformanceState.String(),
			"new_state", newState.String(),
		)
		rate.PerformanceState = newState
	}

	// Calculate adaptive interval
	interval := m.calculateAdaptiveInterval(rate, req)

	// Apply time-based adjustments
	interval = m.applyTimeBasedAdjustments(interval, rate)

	// Determine probe parameters
	probeSize, probeCount := m.getProbeParameters(req.ConnectionType, rate.PerformanceState)

	// Update tracking
	rate.CurrentInterval = interval
	rate.LastAdjustment = time.Now()
	rate.ProbeCount++

	response := SamplingResponse{
		Interval:   interval,
		ProbeSize:  probeSize,
		ProbeCount: probeCount,
		Reason:     m.buildReasonString(rate, req),
	}

	// Log adjustments if significant change
	if m.isSignificantChange(rate.BaseInterval, interval) {
		m.logger.Info("sampling rate adjusted",
			"interface", req.InterfaceName,
			"base_interval", rate.BaseInterval,
			"adjusted_interval", interval,
			"reason", response.Reason,
			"performance_state", rate.PerformanceState.String(),
		)
	}

	return response
}

// UpdateDataUsage updates data usage tracking for an interface
func (m *Manager) UpdateDataUsage(interfaceName string, bytesUsed int64) {
	rate := m.getInterfaceRate(interfaceName)
	rate.DataUsageKB += bytesUsed / 1024
}

// GetStatistics returns sampling statistics for all interfaces
func (m *Manager) GetStatistics() map[string]InterfaceRate {
	stats := make(map[string]InterfaceRate)
	for name, rate := range m.rates {
		stats[name] = *rate // Copy the struct
	}
	return stats
}

// getInterfaceRate gets or creates interface rate tracker
func (m *Manager) getInterfaceRate(interfaceName string) *InterfaceRate {
	if rate, exists := m.rates[interfaceName]; exists {
		return rate
	}

	rate := &InterfaceRate{
		InterfaceName:    interfaceName,
		ConnectionType:   ConnectionTypeUnknown,
		BaseInterval:     time.Duration(m.config.UnlimitedIntervalMs) * time.Millisecond,
		CurrentInterval:  time.Duration(m.config.UnlimitedIntervalMs) * time.Millisecond,
		PerformanceState: PerformanceStateUnknown,
		LastAdjustment:   time.Now(),
	}

	m.rates[interfaceName] = rate
	return rate
}

// getBaseInterval determines base interval for connection type
func (m *Manager) getBaseInterval(connType ConnectionType, isMetered bool) time.Duration {
	if isMetered || connType == ConnectionTypeMetered || connType == ConnectionTypeCapped {
		return time.Duration(m.config.MeteredIntervalMs) * time.Millisecond
	}
	return time.Duration(m.config.UnlimitedIntervalMs) * time.Millisecond
}

// determinePerformanceState analyzes current metrics to determine state
func (m *Manager) determinePerformanceState(req SamplingRequest) PerformanceState {
	// High quality and stable
	if req.QualityScore > 80 && req.CurrentLoss < 1 && req.CurrentLatency < 100 {
		return PerformanceStateStable
	}

	// Moderate quality but functioning
	if req.QualityScore > 60 && req.CurrentLoss < 3 && req.CurrentLatency < 300 {
		return PerformanceStateDegraded
	}

	// Poor quality or recent failures
	if req.QualityScore < 40 || req.RecentFailures > 2 {
		return PerformanceStateFailing
	}

	// Fluctuating performance
	if req.CurrentLoss > 1 || req.CurrentLatency > 200 {
		return PerformanceStateUnstable
	}

	return PerformanceStateUnknown
}

// calculateAdaptiveInterval calculates interval based on performance state
func (m *Manager) calculateAdaptiveInterval(rate *InterfaceRate, req SamplingRequest) time.Duration {
	baseInterval := rate.BaseInterval

	switch rate.PerformanceState {
	case PerformanceStateStable:
		// Stable connections can use longer intervals
		return time.Duration(float64(baseInterval) * 2.0)

	case PerformanceStateDegraded:
		// Slightly more frequent sampling for degraded connections
		return time.Duration(float64(baseInterval) * 0.8)

	case PerformanceStateUnstable:
		// More frequent sampling for unstable connections
		return time.Duration(float64(baseInterval) * 0.5)

	case PerformanceStateFailing:
		// High frequency sampling for failing connections
		if rate.ConnectionType == ConnectionTypeMetered {
			// Even metered connections need frequent checks when failing
			return time.Duration(m.config.DegradedIntervalMs) * time.Millisecond
		}
		return time.Duration(float64(baseInterval) * 0.3)

	default:
		return baseInterval
	}
}

// applyTimeBasedAdjustments applies business hours and off-hours adjustments
func (m *Manager) applyTimeBasedAdjustments(interval time.Duration, rate *InterfaceRate) time.Duration {
	now := time.Now()
	hour := now.Hour()

	isBusinessHours := hour >= m.config.BusinessHourStart && hour < m.config.BusinessHourEnd
	rate.IsBusinessHours = isBusinessHours

	// Apply off-hours multiplier
	if !isBusinessHours && rate.PerformanceState == PerformanceStateStable {
		return time.Duration(float64(interval) * m.config.OffHoursMultiplier)
	}

	return interval
}

// getProbeParameters determines probe size and count based on connection type
func (m *Manager) getProbeParameters(connType ConnectionType, perfState PerformanceState) (int, int) {
	probeSize := m.config.MaxProbeSize
	probeCount := 1

	// Reduce probe size for metered connections
	if connType == ConnectionTypeMetered || connType == ConnectionTypeCapped {
		probeSize = m.config.MaxProbeSize / 2
		if probeSize < 8 {
			probeSize = 8 // Minimum probe size
		}
	}

	// Increase probe count for unstable connections (but keep size small)
	if perfState == PerformanceStateUnstable || perfState == PerformanceStateFailing {
		probeCount = 3
		probeSize = probeSize / 2
		if probeSize < 8 {
			probeSize = 8
		}
	}

	return probeSize, probeCount
}

// buildReasonString builds a human-readable reason for the sampling decision
func (m *Manager) buildReasonString(rate *InterfaceRate, req SamplingRequest) string {
	reasons := []string{}

	reasons = append(reasons, "type:"+rate.ConnectionType.String())
	reasons = append(reasons, "state:"+rate.PerformanceState.String())

	if req.IsMetered {
		reasons = append(reasons, "metered")
	}

	if !rate.IsBusinessHours {
		reasons = append(reasons, "off-hours")
	}

	if req.UserActivity {
		reasons = append(reasons, "active")
	}

	return "adaptive:" + joinReasons(reasons)
}

// isSignificantChange determines if interval change is significant enough to log
func (m *Manager) isSignificantChange(baseInterval, newInterval time.Duration) bool {
	ratio := float64(newInterval) / float64(baseInterval)
	return ratio < 0.7 || ratio > 1.5 // 30% change threshold
}

// joinReasons joins reason strings with commas
func joinReasons(reasons []string) string {
	if len(reasons) == 0 {
		return "default"
	}
	result := reasons[0]
	for i := 1; i < len(reasons); i++ {
		result += "," + reasons[i]
	}
	return result
}
