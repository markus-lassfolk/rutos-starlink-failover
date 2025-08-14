package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/starfail/starfail/pkg"
)

// StarlinkCollector collects metrics from Starlink dish
type StarlinkCollector struct {
	*BaseCollector
	apiHost string
	timeout time.Duration
}

// StarlinkAPIResponse represents the enhanced response from Starlink API
type StarlinkAPIResponse struct {
	Status struct {
		// Obstruction data
		ObstructionStats struct {
			CurrentlyObstructed              bool      `json:"currentlyObstructed"`
			FractionObstructed               float64   `json:"fractionObstructed"`
			Last24hObstructedS               int       `json:"last24hObstructedS"`
			ValidS                           int       `json:"validS"`
			WedgeFractionObstructed          []float64 `json:"wedgeFractionObstructed"`
			WedgeAbsFractionObstructed       []float64 `json:"wedgeAbsFractionObstructed"`
			TimeObstructed                   float64   `json:"timeObstructed"`
			PatchesValid                     int       `json:"patchesValid"`
			AvgProlongedObstructionIntervalS float64   `json:"avgProlongedObstructionIntervalS"`
		} `json:"obstructionStats"`

		// Outage information
		Outage struct {
			LastOutageS    int `json:"lastOutageS"`
			OutageCount    int `json:"outageCount"`
			OutageDuration int `json:"outageDuration"`
		} `json:"outage"`

		// Network performance
		PopPingLatencyMs      float64 `json:"popPingLatencyMs"`
		DownlinkThroughputBps float64 `json:"downlinkThroughputBps"`
		UplinkThroughputBps   float64 `json:"uplinkThroughputBps"`
		PopPingDropRate       float64 `json:"popPingDropRate"`

		// SNR and signal quality
		SnrDb               float64 `json:"snrDb"`
		SecondsSinceLastSnr int     `json:"secondsSinceLastSnr"`

		// Hardware status
		HardwareSelfTest struct {
			Passed       bool     `json:"passed"`
			TestResults  []string `json:"testResults"`
			LastTestTime int64    `json:"lastTestTime"`
		} `json:"hardwareSelfTest"`

		// Thermal monitoring
		Thermal struct {
			Temperature     float64 `json:"temperature"`
			ThermalThrottle bool    `json:"thermalThrottle"`
			ThermalShutdown bool    `json:"thermalShutdown"`
		} `json:"thermal"`

		// Power and voltage
		Power struct {
			PowerDraw  float64 `json:"powerDraw"`
			Voltage    float64 `json:"voltage"`
			PowerState string  `json:"powerState"`
		} `json:"power"`

		// Bandwidth restrictions
		BandwidthRestrictions struct {
			Restricted      bool    `json:"restricted"`
			RestrictionType string  `json:"restrictionType"`
			MaxDownloadMbps float64 `json:"maxDownloadMbps"`
			MaxUploadMbps   float64 `json:"maxUploadMbps"`
		} `json:"bandwidthRestrictions"`

		// System status
		System struct {
			UptimeS         int      `json:"uptimeS"`
			AlertsActive    []string `json:"alertsActive"`
			ScheduledReboot bool     `json:"scheduledReboot"`
			RebootTimeS     int64    `json:"rebootTimeS"`
			SoftwareVersion string   `json:"softwareVersion"`
			HardwareVersion string   `json:"hardwareVersion"`
		} `json:"system"`

		// GPS information
		GPS struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
			Altitude  float64 `json:"altitude"`
			GPSValid  bool    `json:"gpsValid"`
			GPSLocked bool    `json:"gpsLocked"`
		} `json:"gps"`
	} `json:"status"`
}

// NewStarlinkCollector creates a new Starlink collector
func NewStarlinkCollector(config map[string]interface{}) (*StarlinkCollector, error) {
	timeout := 10 * time.Second
	if t, ok := config["timeout"].(time.Duration); ok {
		timeout = t
	}

	apiHost := "192.168.100.1"
	if h, ok := config["api_host"].(string); ok {
		apiHost = h
	}

	targets := []string{"8.8.8.8", "1.1.1.1"}
	if t, ok := config["targets"].([]string); ok {
		targets = t
	}

	return &StarlinkCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
		apiHost:       apiHost,
		timeout:       timeout,
	}, nil
}

// Collect collects metrics from Starlink
func (sc *StarlinkCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := sc.Validate(member); err != nil {
		return nil, err
	}

	// Start with common metrics
	metrics, err := sc.CollectCommonMetrics(ctx, member)
	if err != nil {
		return nil, err
	}

	// Collect Starlink-specific metrics
	starlinkMetrics, err := sc.collectStarlinkMetrics(ctx)
	if err != nil {
		// Log error but don't fail - continue with common metrics
		// TODO: Add logger parameter to collector
		fmt.Printf("Warning: Failed to collect Starlink metrics: %v\n", err)
	} else {
		// Merge Starlink metrics
		if starlinkMetrics.ObstructionPct != nil {
			metrics.ObstructionPct = starlinkMetrics.ObstructionPct
		}
		if starlinkMetrics.Outages != nil {
			metrics.Outages = starlinkMetrics.Outages
		}
	}

	return metrics, nil
}

// collectStarlinkMetrics collects comprehensive metrics from Starlink API
func (sc *StarlinkCollector) collectStarlinkMetrics(ctx context.Context) (*pkg.Metrics, error) {
	// Create HTTP client with timeout
	client := &http.Client{
		Timeout: sc.timeout,
	}

	// Make request to Starlink API
	url := fmt.Sprintf("http://%s/api/v1/status", sc.apiHost)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to request Starlink API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Starlink API returned status %d", resp.StatusCode)
	}

	// Parse response
	var apiResp StarlinkAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode Starlink API response: %w", err)
	}

	// Extract comprehensive metrics
	metrics := &pkg.Metrics{
		Timestamp: time.Now(),
	}

	// Basic obstruction data (enhanced with quality validation)
	obstructionPct := apiResp.Status.ObstructionStats.FractionObstructed * 100
	metrics.ObstructionPct = &obstructionPct

	// Enhanced outage tracking
	outages := apiResp.Status.Outage.OutageCount
	if apiResp.Status.Outage.LastOutageS > 0 && apiResp.Status.Outage.LastOutageS < 300 { // Recent outage (5 minutes)
		outages++
	}
	metrics.Outages = &outages

	// Network performance metrics
	if apiResp.Status.PopPingLatencyMs > 0 {
		latency := apiResp.Status.PopPingLatencyMs
		metrics.LatencyMS = latency
	}

	if apiResp.Status.PopPingDropRate >= 0 {
		lossPercent := apiResp.Status.PopPingDropRate * 100
		metrics.LossPercent = lossPercent
	}

	// SNR data for signal quality assessment (convert to int)
	if apiResp.Status.SnrDb > 0 {
		snr := int(apiResp.Status.SnrDb)
		metrics.SNR = &snr
	}

	// Enhanced Starlink diagnostics using proper struct fields
	uptime := int64(apiResp.Status.System.UptimeS)
	metrics.UptimeS = &uptime

	// Hardware self-test result
	if apiResp.Status.HardwareSelfTest.Passed {
		hardwareResult := "passed"
		metrics.HardwareSelfTest = &hardwareResult
	} else {
		hardwareResult := "failed"
		metrics.HardwareSelfTest = &hardwareResult
	}

	// Thermal monitoring
	metrics.ThermalThrottle = &apiResp.Status.Thermal.ThermalThrottle
	metrics.ThermalShutdown = &apiResp.Status.Thermal.ThermalShutdown

	// Bandwidth restrictions
	if apiResp.Status.BandwidthRestrictions.Restricted {
		metrics.DLBandwidthRestrictedReason = &apiResp.Status.BandwidthRestrictions.RestrictionType
		metrics.ULBandwidthRestrictedReason = &apiResp.Status.BandwidthRestrictions.RestrictionType
	}

	// Scheduled reboot detection
	if apiResp.Status.System.ScheduledReboot && apiResp.Status.System.RebootTimeS > 0 {
		rebootTime := time.Unix(apiResp.Status.System.RebootTimeS, 0).UTC().Format(time.RFC3339)
		metrics.RebootScheduledUTC = &rebootTime
	}

	// Enhanced obstruction data
	obstructionTime := apiResp.Status.ObstructionStats.TimeObstructed
	metrics.ObstructionTimePct = &obstructionTime

	validS := int64(apiResp.Status.ObstructionStats.ValidS)
	metrics.ObstructionValidS = &validS

	avgProlonged := apiResp.Status.ObstructionStats.AvgProlongedObstructionIntervalS
	metrics.ObstructionAvgProlonged = &avgProlonged

	patchesValid := apiResp.Status.ObstructionStats.PatchesValid
	metrics.ObstructionPatchesValid = &patchesValid

	// GPS data
	if apiResp.Status.GPS.GPSValid {
		metrics.GPSValid = &apiResp.Status.GPS.GPSValid
		metrics.GPSLatitude = &apiResp.Status.GPS.Latitude
		metrics.GPSLongitude = &apiResp.Status.GPS.Longitude
		metrics.GPSAltitude = &apiResp.Status.GPS.Altitude

		gpsSource := "starlink"
		metrics.GPSSource = &gpsSource
	}

	return metrics, nil
}

// Validate validates a member for the Starlink collector
func (sc *StarlinkCollector) Validate(member *pkg.Member) error {
	if err := sc.BaseCollector.Validate(member); err != nil {
		return err
	}

	// Additional Starlink-specific validation
	if member.Class != pkg.ClassStarlink {
		return fmt.Errorf("member class must be starlink, got %s", member.Class)
	}

	return nil
}

// TestStarlinkConnectivity tests if we can reach the Starlink API
func (sc *StarlinkCollector) TestStarlinkConnectivity(ctx context.Context) error {
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	url := fmt.Sprintf("http://%s/api/v1/status", sc.apiHost)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create test request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to reach Starlink API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Starlink API test failed with status %d", resp.StatusCode)
	}

	return nil
}

// GetStarlinkInfo returns comprehensive Starlink dish information
func (sc *StarlinkCollector) GetStarlinkInfo(ctx context.Context) (map[string]interface{}, error) {
	client := &http.Client{
		Timeout: sc.timeout,
	}

	url := fmt.Sprintf("http://%s/api/v1/status", sc.apiHost)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to request Starlink API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Starlink API returned status %d", resp.StatusCode)
	}

	var apiResp StarlinkAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode Starlink API response: %w", err)
	}

	info := map[string]interface{}{
		// Basic metrics
		"currently_obstructed":  apiResp.Status.ObstructionStats.CurrentlyObstructed,
		"fraction_obstructed":   apiResp.Status.ObstructionStats.FractionObstructed,
		"last_24h_obstructed_s": apiResp.Status.ObstructionStats.Last24hObstructedS,
		"pop_ping_latency_ms":   apiResp.Status.PopPingLatencyMs,
		"last_outage_s":         apiResp.Status.Outage.LastOutageS,
		"snr_db":                apiResp.Status.SnrDb,

		// Hardware health
		"hardware_test_passed":  apiResp.Status.HardwareSelfTest.Passed,
		"hardware_test_results": apiResp.Status.HardwareSelfTest.TestResults,
		"temperature":           apiResp.Status.Thermal.Temperature,
		"thermal_throttle":      apiResp.Status.Thermal.ThermalThrottle,
		"thermal_shutdown":      apiResp.Status.Thermal.ThermalShutdown,

		// System status
		"uptime_s":         apiResp.Status.System.UptimeS,
		"alerts_active":    apiResp.Status.System.AlertsActive,
		"scheduled_reboot": apiResp.Status.System.ScheduledReboot,
		"reboot_time_s":    apiResp.Status.System.RebootTimeS,
		"software_version": apiResp.Status.System.SoftwareVersion,
		"hardware_version": apiResp.Status.System.HardwareVersion,

		// Performance
		"downlink_throughput_bps": apiResp.Status.DownlinkThroughputBps,
		"uplink_throughput_bps":   apiResp.Status.UplinkThroughputBps,
		"bandwidth_restricted":    apiResp.Status.BandwidthRestrictions.Restricted,

		// GPS
		"gps_latitude":  apiResp.Status.GPS.Latitude,
		"gps_longitude": apiResp.Status.GPS.Longitude,
		"gps_valid":     apiResp.Status.GPS.GPSValid,
	}

	return info, nil
}

// CheckHardwareHealth performs comprehensive hardware health assessment
func (sc *StarlinkCollector) CheckHardwareHealth(ctx context.Context) (*StarlinkHealthStatus, error) {
	client := &http.Client{
		Timeout: sc.timeout,
	}

	url := fmt.Sprintf("http://%s/api/v1/status", sc.apiHost)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to request Starlink API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Starlink API returned status %d", resp.StatusCode)
	}

	var apiResp StarlinkAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode Starlink API response: %w", err)
	}

	health := &StarlinkHealthStatus{
		OverallHealth:    "healthy",
		HardwareTest:     apiResp.Status.HardwareSelfTest.Passed,
		ThermalStatus:    "normal",
		PowerStatus:      "normal",
		SignalQuality:    "good",
		PredictiveAlerts: []string{},
	}

	// Assess thermal status
	if apiResp.Status.Thermal.ThermalShutdown {
		health.OverallHealth = "critical"
		health.ThermalStatus = "shutdown"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "thermal_shutdown_imminent")
	} else if apiResp.Status.Thermal.ThermalThrottle {
		health.OverallHealth = "degraded"
		health.ThermalStatus = "throttling"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "thermal_throttling_active")
	} else if apiResp.Status.Thermal.Temperature > 70.0 { // High temperature threshold
		health.ThermalStatus = "warning"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "high_temperature_detected")
	}

	// Assess power status
	if apiResp.Status.Power.Voltage < 48.0 || apiResp.Status.Power.Voltage > 56.0 { // Voltage out of range
		health.PowerStatus = "warning"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "voltage_out_of_range")
	}

	// Assess signal quality
	if apiResp.Status.SnrDb < 5.0 { // Low SNR threshold
		health.SignalQuality = "poor"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "low_snr_detected")
	} else if apiResp.Status.SnrDb < 10.0 {
		health.SignalQuality = "fair"
	}

	// Check for scheduled reboot (predictive failover trigger)
	if apiResp.Status.System.ScheduledReboot {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "scheduled_reboot_pending")
		if apiResp.Status.System.RebootTimeS > 0 && apiResp.Status.System.RebootTimeS < time.Now().Unix()+300 {
			health.PredictiveAlerts = append(health.PredictiveAlerts, "reboot_imminent_5min")
		}
	}

	// Check for active alerts
	if len(apiResp.Status.System.AlertsActive) > 0 {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "system_alerts_active")
	}

	// Check obstruction acceleration (predictive obstruction failure)
	if apiResp.Status.ObstructionStats.FractionObstructed > 0.05 && // 5% obstruction
		apiResp.Status.ObstructionStats.AvgProlongedObstructionIntervalS > 30 { // Prolonged obstructions
		health.PredictiveAlerts = append(health.PredictiveAlerts, "obstruction_pattern_detected")
	}

	// Set overall health based on alerts
	if len(health.PredictiveAlerts) > 3 {
		health.OverallHealth = "critical"
	} else if len(health.PredictiveAlerts) > 1 {
		health.OverallHealth = "degraded"
	}

	return health, nil
}

// StarlinkHealthStatus represents comprehensive Starlink health assessment
type StarlinkHealthStatus struct {
	OverallHealth    string   `json:"overall_health"`
	HardwareTest     bool     `json:"hardware_test"`
	ThermalStatus    string   `json:"thermal_status"`
	PowerStatus      string   `json:"power_status"`
	SignalQuality    string   `json:"signal_quality"`
	PredictiveAlerts []string `json:"predictive_alerts"`
}

// DetectPredictiveFailure analyzes metrics to predict potential failures
func (sc *StarlinkCollector) DetectPredictiveFailure(ctx context.Context, recentMetrics []*pkg.Metrics) *PredictiveFailureAssessment {
	if len(recentMetrics) < 3 {
		return &PredictiveFailureAssessment{
			FailureRisk:   "unknown",
			Confidence:    0.0,
			TimeToFailure: 0,
			Triggers:      []string{"insufficient_data"},
		}
	}

	assessment := &PredictiveFailureAssessment{
		FailureRisk:   "low",
		Confidence:    0.5,
		TimeToFailure: 0,
		Triggers:      []string{},
	}

	// Analyze obstruction trends
	obstructionTrend := sc.analyzeObstructionTrend(recentMetrics)
	if obstructionTrend > 0.02 { // 2% increase per sample
		assessment.FailureRisk = "high"
		assessment.Confidence = 0.8
		assessment.TimeToFailure = 300 // 5 minutes
		assessment.Triggers = append(assessment.Triggers, "obstruction_acceleration")
	}

	// Analyze SNR degradation
	snrTrend := sc.analyzeSNRTrend(recentMetrics)
	if snrTrend < -1.0 { // SNR dropping by 1dB per sample
		assessment.FailureRisk = "medium"
		assessment.Confidence = 0.7
		assessment.TimeToFailure = 600 // 10 minutes
		assessment.Triggers = append(assessment.Triggers, "snr_degradation")
	}

	// Check for thermal issues
	if sc.hasThermalIssues(recentMetrics) {
		assessment.FailureRisk = "high"
		assessment.Confidence = 0.9
		assessment.TimeToFailure = 180 // 3 minutes
		assessment.Triggers = append(assessment.Triggers, "thermal_degradation")
	}

	return assessment
}

// PredictiveFailureAssessment represents failure prediction analysis
type PredictiveFailureAssessment struct {
	FailureRisk   string   `json:"failure_risk"`    // low, medium, high, critical
	Confidence    float64  `json:"confidence"`      // 0.0 to 1.0
	TimeToFailure int      `json:"time_to_failure"` // seconds
	Triggers      []string `json:"triggers"`        // reasons for prediction
}

// Helper methods for predictive analysis
func (sc *StarlinkCollector) analyzeObstructionTrend(metrics []*pkg.Metrics) float64 {
	if len(metrics) < 2 {
		return 0.0
	}

	var trend float64
	count := 0

	for i := 1; i < len(metrics); i++ {
		if metrics[i].ObstructionPct != nil && metrics[i-1].ObstructionPct != nil {
			trend += *metrics[i].ObstructionPct - *metrics[i-1].ObstructionPct
			count++
		}
	}

	if count == 0 {
		return 0.0
	}

	return trend / float64(count)
}

func (sc *StarlinkCollector) analyzeSNRTrend(metrics []*pkg.Metrics) float64 {
	if len(metrics) < 2 {
		return 0.0
	}

	var trend float64
	count := 0

	for i := 1; i < len(metrics); i++ {
		if metrics[i].SNR != nil && metrics[i-1].SNR != nil {
			trend += float64(*metrics[i].SNR - *metrics[i-1].SNR)
			count++
		}
	}

	if count == 0 {
		return 0.0
	}

	return trend / float64(count)
}

func (sc *StarlinkCollector) hasThermalIssues(metrics []*pkg.Metrics) bool {
	for _, metric := range metrics {
		if metric.ThermalThrottle != nil && *metric.ThermalThrottle {
			return true
		}
		if metric.ThermalShutdown != nil && *metric.ThermalShutdown {
			return true
		}
		// Note: Temperature is not directly available in current metrics struct
		// Could be added as a separate field if needed
	}
	return false
}
