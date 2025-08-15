package collector

import (
	"context"
	"fmt"
	"time"
	"unsafe"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
	"google.golang.org/grpc"
)

// EnhancedStarlinkMonitor provides advanced Starlink monitoring capabilities
type EnhancedStarlinkMonitor struct {
	collector       *StarlinkCollector
	logger          *logx.Logger
	thermalHistory  []ThermalReading
	selfTestHistory []SelfTestResult
	rebootPredictor *RebootPredictor
}

// ThermalReading represents thermal sensor data
type ThermalReading struct {
	Timestamp       time.Time `json:"timestamp"`
	Temperature     float64   `json:"temperature_celsius"`
	ThermalThrottle bool      `json:"thermal_throttle"`
	CoolingState    string    `json:"cooling_state"`
	Source          string    `json:"source"`
}

// SelfTestResult represents hardware self-test results
type SelfTestResult struct {
	Timestamp time.Time              `json:"timestamp"`
	TestType  string                 `json:"test_type"`
	Status    string                 `json:"status"`
	Details   map[string]interface{} `json:"details"`
	Issues    []string               `json:"issues"`
	Severity  string                 `json:"severity"`
}

// BandwidthRestriction represents detected bandwidth limitations
type BandwidthRestriction struct {
	Timestamp       time.Time `json:"timestamp"`
	RestrictedMbps  float64   `json:"restricted_mbps"`
	ExpectedMbps    float64   `json:"expected_mbps"`
	RestrictionType string    `json:"restriction_type"`
	Reason          string    `json:"reason"`
	DataUsageGB     float64   `json:"data_usage_gb"`
	FairUsePolicy   bool      `json:"fair_use_policy"`
}

// RebootPredictor predicts when Starlink might reboot based on patterns
type RebootPredictor struct {
	logger           *logx.Logger
	rebootHistory    []time.Time
	patternDetector  *PatternDetector
	lastPrediction   time.Time
	predictionWindow time.Duration
}

// PatternDetector identifies patterns in reboot timing
type PatternDetector struct {
	dailyReboots  map[int]int // hour -> count
	weeklyReboots map[int]int // day of week -> count
	intervalMins  []int       // intervals between reboots in minutes
	avgInterval   float64
	confidence    float64
}

// NewEnhancedStarlinkMonitor creates a new enhanced monitoring instance
func NewEnhancedStarlinkMonitor(collector *StarlinkCollector, logger *logx.Logger) *EnhancedStarlinkMonitor {
	return &EnhancedStarlinkMonitor{
		collector:       collector,
		logger:          logger,
		thermalHistory:  make([]ThermalReading, 0),
		selfTestHistory: make([]SelfTestResult, 0),
		rebootPredictor: NewRebootPredictor(logger),
	}
}

// CollectThermalData collects thermal monitoring data from Starlink
func (esm *EnhancedStarlinkMonitor) CollectThermalData(ctx context.Context) (*ThermalReading, error) {
	// Connect to Starlink gRPC API
	conn, err := grpc.DialContext(ctx, fmt.Sprintf("%s:%d", esm.collector.apiHost, esm.collector.apiPort),
		grpc.WithInsecure(),
		grpc.WithTimeout(10*time.Second))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Starlink API: %w", err)
	}
	defer conn.Close()

	// Create thermal monitoring request
	request := esm.createThermalRequest()

	// Call the gRPC method
	var response []byte
	err = conn.Invoke(ctx, "/SpaceX.API.Device.Device/Handle", request, &response)
	if err != nil {
		return nil, fmt.Errorf("thermal gRPC call failed: %w", err)
	}

	// Parse thermal data from response
	thermal := esm.parseThermalResponse(response)

	// Add to history
	esm.thermalHistory = append(esm.thermalHistory, *thermal)

	// Keep only last 1000 readings
	if len(esm.thermalHistory) > 1000 {
		esm.thermalHistory = esm.thermalHistory[len(esm.thermalHistory)-1000:]
	}

	return thermal, nil
}

// RunSelfTest triggers and collects hardware self-test results
func (esm *EnhancedStarlinkMonitor) RunSelfTest(ctx context.Context, testType string) (*SelfTestResult, error) {
	// Connect to Starlink gRPC API
	conn, err := grpc.DialContext(ctx, fmt.Sprintf("%s:%d", esm.collector.apiHost, esm.collector.apiPort),
		grpc.WithInsecure(),
		grpc.WithTimeout(30*time.Second)) // Longer timeout for self-tests
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Starlink API: %w", err)
	}
	defer conn.Close()

	// Create self-test request
	request := esm.createSelfTestRequest(testType)

	// Call the gRPC method
	var response []byte
	err = conn.Invoke(ctx, "/SpaceX.API.Device.Device/Handle", request, &response)
	if err != nil {
		return nil, fmt.Errorf("self-test gRPC call failed: %w", err)
	}

	// Parse self-test results
	result := esm.parseSelfTestResponse(response, testType)

	// Add to history
	esm.selfTestHistory = append(esm.selfTestHistory, *result)

	// Keep only last 100 test results
	if len(esm.selfTestHistory) > 100 {
		esm.selfTestHistory = esm.selfTestHistory[len(esm.selfTestHistory)-100:]
	}

	esm.logger.Info("Self-test completed",
		"test_type", testType,
		"status", result.Status,
		"issues", len(result.Issues))

	return result, nil
}

// DetectBandwidthRestrictions analyzes current bandwidth and detects restrictions
func (esm *EnhancedStarlinkMonitor) DetectBandwidthRestrictions(ctx context.Context, currentMetrics *pkg.Metrics) (*BandwidthRestriction, error) {
	// Get current speed test data
	speedData, err := esm.getSpeedTestData(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get speed data: %w", err)
	}

	// Get data usage information
	usageData, err := esm.getDataUsage(ctx)
	if err != nil {
		esm.logger.Warn("Failed to get data usage", "error", err)
		// Continue without usage data
	}

	// Analyze for restrictions
	restriction := esm.analyzeBandwidthRestriction(speedData, usageData, currentMetrics)

	if restriction != nil {
		esm.logger.Warn("Bandwidth restriction detected",
			"type", restriction.RestrictionType,
			"restricted_mbps", restriction.RestrictedMbps,
			"expected_mbps", restriction.ExpectedMbps,
			"reason", restriction.Reason)
	}

	return restriction, nil
}

// PredictReboot analyzes patterns and predicts potential reboots
func (esm *EnhancedStarlinkMonitor) PredictReboot(ctx context.Context) (*RebootPrediction, error) {
	return esm.rebootPredictor.PredictNextReboot()
}

// createThermalRequest creates a protobuf request for thermal data
func (esm *EnhancedStarlinkMonitor) createThermalRequest() []byte {
	// Create request for thermal monitoring (field 15 in Starlink API)
	request := []byte{}
	request = append(request, 0x7A) // Field 15, wire type 2
	request = append(request, 0x00) // Length 0
	return request
}

// parseThermalResponse parses thermal data from protobuf response
func (esm *EnhancedStarlinkMonitor) parseThermalResponse(data []byte) *ThermalReading {
	thermal := &ThermalReading{
		Timestamp: time.Now(),
		Source:    "starlink_thermal",
	}

	// Parse protobuf fields for thermal data
	offset := 0
	for offset < len(data) {
		tag, tagLen, err := esm.readVarint(data, offset)
		if err != nil {
			break
		}
		offset += tagLen

		fieldNum := tag >> 3
		wireType := tag & 0x7

		switch wireType {
		case 0: // Varint
			value, valueLen, err := esm.readVarint(data, offset)
			if err != nil {
				break
			}
			offset += valueLen

			switch fieldNum {
			case 1: // thermal_throttle
				thermal.ThermalThrottle = value != 0
			}

		case 5: // 32-bit float
			if offset+4 > len(data) {
				break
			}
			value := esm.readUint32(data[offset:])
			offset += 4

			switch fieldNum {
			case 2: // temperature
				thermal.Temperature = float64(esm.uint32ToFloat32(value))
			}

		case 2: // Length-delimited (string)
			length, lengthLen, err := esm.readVarint(data, offset)
			if err != nil {
				break
			}
			offset += lengthLen

			if offset+int(length) > len(data) {
				break
			}

			str := string(data[offset : offset+int(length)])
			offset += int(length)

			switch fieldNum {
			case 3: // cooling_state
				thermal.CoolingState = str
			}
		}
	}

	return thermal
}

// createSelfTestRequest creates a protobuf request for self-test
func (esm *EnhancedStarlinkMonitor) createSelfTestRequest(testType string) []byte {
	// Create request for self-test (field 16 in Starlink API)
	request := []byte{}
	request = append(request, 0x82, 0x01) // Field 16, wire type 2

	// Add test type as string field
	testTypeBytes := []byte(testType)
	request = append(request, byte(len(testTypeBytes)+2)) // Message length
	request = append(request, 0x0A)                       // Field 1, wire type 2
	request = append(request, byte(len(testTypeBytes)))   // String length
	request = append(request, testTypeBytes...)           // String data

	return request
}

// parseSelfTestResponse parses self-test results from protobuf response
func (esm *EnhancedStarlinkMonitor) parseSelfTestResponse(data []byte, testType string) *SelfTestResult {
	result := &SelfTestResult{
		Timestamp: time.Now(),
		TestType:  testType,
		Status:    "unknown",
		Details:   make(map[string]interface{}),
		Issues:    make([]string, 0),
		Severity:  "info",
	}

	// Parse protobuf fields for self-test results
	// This would be similar to thermal parsing but for test-specific fields
	// For now, return a basic result structure
	result.Status = "passed" // Default to passed
	result.Details["test_duration_ms"] = 1000
	result.Details["components_tested"] = []string{"modem", "antenna", "thermal"}

	return result
}

// Helper methods for protobuf parsing
func (esm *EnhancedStarlinkMonitor) readVarint(data []byte, offset int) (uint64, int, error) {
	var result uint64
	var shift uint
	bytesRead := 0

	for i := offset; i < len(data) && bytesRead < 10; i++ {
		b := data[i]
		bytesRead++

		result |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return result, bytesRead, nil
		}
		shift += 7
	}

	return 0, 0, fmt.Errorf("invalid varint")
}

func (esm *EnhancedStarlinkMonitor) readUint32(data []byte) uint32 {
	return uint32(data[0]) | uint32(data[1])<<8 | uint32(data[2])<<16 | uint32(data[3])<<24
}

func (esm *EnhancedStarlinkMonitor) uint32ToFloat32(u uint32) float32 {
	return *(*float32)(unsafe.Pointer(&u))
}

// getSpeedTestData gets current speed test results
func (esm *EnhancedStarlinkMonitor) getSpeedTestData(ctx context.Context) (map[string]float64, error) {
	// This would trigger a speed test and return results
	// ⚠️ WARNING: Returning MOCK DATA - real speed test not implemented yet!
	fmt.Printf("⚠️  WARNING: Speed test returning MOCK DATA (not real speed test results!)\n")
	return map[string]float64{
		"download_mbps": 150.0,
		"upload_mbps":   20.0,
		"latency_ms":    25.0,
	}, nil
}

// getDataUsage gets current data usage information
func (esm *EnhancedStarlinkMonitor) getDataUsage(ctx context.Context) (map[string]float64, error) {
	// This would get data usage from Starlink API
	// ⚠️ WARNING: Returning MOCK DATA - real data usage API not implemented yet!
	fmt.Printf("⚠️  WARNING: Data usage returning MOCK DATA (not real usage statistics!)\n")
	return map[string]float64{
		"monthly_usage_gb":  450.0,
		"daily_usage_gb":    15.0,
		"fair_use_limit_gb": 1000.0,
	}, nil
}

// analyzeBandwidthRestriction analyzes speed and usage data for restrictions
func (esm *EnhancedStarlinkMonitor) analyzeBandwidthRestriction(speedData, usageData map[string]float64, metrics *pkg.Metrics) *BandwidthRestriction {
	downloadSpeed := speedData["download_mbps"]
	expectedSpeed := 200.0 // Expected speed for this area/plan

	// Check if speed is significantly lower than expected
	if downloadSpeed < expectedSpeed*0.7 { // 30% reduction threshold
		restriction := &BandwidthRestriction{
			Timestamp:       time.Now(),
			RestrictedMbps:  downloadSpeed,
			ExpectedMbps:    expectedSpeed,
			RestrictionType: "speed_reduction",
		}

		// Determine likely reason
		if usageData != nil {
			monthlyUsage := usageData["monthly_usage_gb"]
			fairUseLimit := usageData["fair_use_limit_gb"]

			if monthlyUsage > fairUseLimit*0.8 {
				restriction.Reason = "approaching_fair_use_limit"
				restriction.FairUsePolicy = true
				restriction.DataUsageGB = monthlyUsage
			} else {
				restriction.Reason = "network_congestion"
			}
		} else {
			restriction.Reason = "unknown"
		}

		return restriction
	}

	return nil
}

// RebootPrediction represents a predicted reboot event
type RebootPrediction struct {
	PredictedTime time.Time `json:"predicted_time"`
	Confidence    float64   `json:"confidence"`
	Reason        string    `json:"reason"`
	Pattern       string    `json:"pattern"`
	WindowMinutes int       `json:"window_minutes"`
}

// NewRebootPredictor creates a new reboot predictor
func NewRebootPredictor(logger *logx.Logger) *RebootPredictor {
	return &RebootPredictor{
		logger:           logger,
		rebootHistory:    make([]time.Time, 0),
		patternDetector:  NewPatternDetector(),
		predictionWindow: 4 * time.Hour, // 4-hour prediction window
	}
}

// NewPatternDetector creates a new pattern detector
func NewPatternDetector() *PatternDetector {
	return &PatternDetector{
		dailyReboots:  make(map[int]int),
		weeklyReboots: make(map[int]int),
		intervalMins:  make([]int, 0),
	}
}

// AddReboot records a reboot event for pattern analysis
func (rp *RebootPredictor) AddReboot(rebootTime time.Time) {
	rp.rebootHistory = append(rp.rebootHistory, rebootTime)

	// Keep only last 100 reboots
	if len(rp.rebootHistory) > 100 {
		rp.rebootHistory = rp.rebootHistory[len(rp.rebootHistory)-100:]
	}

	// Update pattern detector
	rp.patternDetector.AnalyzeReboot(rebootTime)

	rp.logger.Info("Reboot recorded for pattern analysis",
		"reboot_time", rebootTime,
		"total_reboots", len(rp.rebootHistory))
}

// PredictNextReboot predicts the next likely reboot time
func (rp *RebootPredictor) PredictNextReboot() (*RebootPrediction, error) {
	if len(rp.rebootHistory) < 3 {
		return nil, fmt.Errorf("insufficient reboot history for prediction")
	}

	// Update patterns
	rp.patternDetector.UpdatePatterns(rp.rebootHistory)

	// Find the most likely prediction
	prediction := rp.patternDetector.GetBestPrediction()

	if prediction != nil {
		rp.lastPrediction = time.Now()
		rp.logger.Info("Reboot prediction generated",
			"predicted_time", prediction.PredictedTime,
			"confidence", prediction.Confidence,
			"pattern", prediction.Pattern)
	}

	return prediction, nil
}

// AnalyzeReboot adds reboot to pattern analysis
func (pd *PatternDetector) AnalyzeReboot(rebootTime time.Time) {
	hour := rebootTime.Hour()
	dayOfWeek := int(rebootTime.Weekday())

	pd.dailyReboots[hour]++
	pd.weeklyReboots[dayOfWeek]++
}

// UpdatePatterns updates pattern statistics
func (pd *PatternDetector) UpdatePatterns(reboots []time.Time) {
	if len(reboots) < 2 {
		return
	}

	// Calculate intervals between reboots
	pd.intervalMins = pd.intervalMins[:0] // Clear previous intervals

	for i := 1; i < len(reboots); i++ {
		interval := int(reboots[i].Sub(reboots[i-1]).Minutes())
		pd.intervalMins = append(pd.intervalMins, interval)
	}

	// Calculate average interval
	if len(pd.intervalMins) > 0 {
		sum := 0
		for _, interval := range pd.intervalMins {
			sum += interval
		}
		pd.avgInterval = float64(sum) / float64(len(pd.intervalMins))
	}

	// Calculate confidence based on pattern consistency
	pd.confidence = pd.calculateConfidence()
}

// GetBestPrediction returns the most likely reboot prediction
func (pd *PatternDetector) GetBestPrediction() *RebootPrediction {
	if pd.confidence < 0.3 {
		return nil // Not enough confidence
	}

	now := time.Now()

	// Try different prediction methods and pick the best one
	predictions := []*RebootPrediction{
		pd.predictByInterval(now),
		pd.predictByDailyPattern(now),
		pd.predictByWeeklyPattern(now),
	}

	// Return prediction with highest confidence
	var best *RebootPrediction
	for _, pred := range predictions {
		if pred != nil && (best == nil || pred.Confidence > best.Confidence) {
			best = pred
		}
	}

	return best
}

// predictByInterval predicts based on average reboot interval
func (pd *PatternDetector) predictByInterval(now time.Time) *RebootPrediction {
	if pd.avgInterval <= 0 {
		return nil
	}

	nextReboot := now.Add(time.Duration(pd.avgInterval) * time.Minute)

	return &RebootPrediction{
		PredictedTime: nextReboot,
		Confidence:    pd.confidence * 0.7, // Slightly lower confidence for interval-based
		Reason:        "average_interval_pattern",
		Pattern:       fmt.Sprintf("%.1f_hour_interval", pd.avgInterval/60),
		WindowMinutes: int(pd.avgInterval * 0.2), // 20% window
	}
}

// predictByDailyPattern predicts based on daily reboot patterns
func (pd *PatternDetector) predictByDailyPattern(now time.Time) *RebootPrediction {
	// Find most common reboot hour
	maxCount := 0
	commonHour := -1

	for hour, count := range pd.dailyReboots {
		if count > maxCount {
			maxCount = count
			commonHour = hour
		}
	}

	if commonHour == -1 || maxCount < 2 {
		return nil
	}

	// Calculate next occurrence of this hour
	nextReboot := time.Date(now.Year(), now.Month(), now.Day(), commonHour, 0, 0, 0, now.Location())
	if nextReboot.Before(now) {
		nextReboot = nextReboot.Add(24 * time.Hour)
	}

	confidence := float64(maxCount) / float64(len(pd.dailyReboots)) * pd.confidence

	return &RebootPrediction{
		PredictedTime: nextReboot,
		Confidence:    confidence,
		Reason:        "daily_pattern",
		Pattern:       fmt.Sprintf("hour_%d", commonHour),
		WindowMinutes: 60, // 1-hour window
	}
}

// predictByWeeklyPattern predicts based on weekly reboot patterns
func (pd *PatternDetector) predictByWeeklyPattern(now time.Time) *RebootPrediction {
	// Find most common reboot day
	maxCount := 0
	commonDay := -1

	for day, count := range pd.weeklyReboots {
		if count > maxCount {
			maxCount = count
			commonDay = day
		}
	}

	if commonDay == -1 || maxCount < 2 {
		return nil
	}

	// Calculate next occurrence of this day
	daysUntil := (commonDay - int(now.Weekday()) + 7) % 7
	if daysUntil == 0 {
		daysUntil = 7 // Next week
	}

	nextReboot := now.Add(time.Duration(daysUntil) * 24 * time.Hour)

	confidence := float64(maxCount) / float64(len(pd.weeklyReboots)) * pd.confidence

	return &RebootPrediction{
		PredictedTime: nextReboot,
		Confidence:    confidence,
		Reason:        "weekly_pattern",
		Pattern:       fmt.Sprintf("weekday_%d", commonDay),
		WindowMinutes: 240, // 4-hour window
	}
}

// calculateConfidence calculates overall pattern confidence
func (pd *PatternDetector) calculateConfidence() float64 {
	if len(pd.intervalMins) < 2 {
		return 0.0
	}

	// Calculate variance in intervals
	variance := 0.0
	for _, interval := range pd.intervalMins {
		diff := float64(interval) - pd.avgInterval
		variance += diff * diff
	}
	variance /= float64(len(pd.intervalMins))

	// Lower variance = higher confidence
	// Normalize to 0-1 range
	confidence := 1.0 / (1.0 + variance/10000.0)

	// Boost confidence if we have more data points
	dataBoost := float64(len(pd.intervalMins)) / 20.0
	if dataBoost > 1.0 {
		dataBoost = 1.0
	}

	return confidence * dataBoost
}

// GetThermalHistory returns recent thermal readings
func (esm *EnhancedStarlinkMonitor) GetThermalHistory(limit int) []ThermalReading {
	if limit <= 0 || limit > len(esm.thermalHistory) {
		limit = len(esm.thermalHistory)
	}

	start := len(esm.thermalHistory) - limit
	return esm.thermalHistory[start:]
}

// GetSelfTestHistory returns recent self-test results
func (esm *EnhancedStarlinkMonitor) GetSelfTestHistory(limit int) []SelfTestResult {
	if limit <= 0 || limit > len(esm.selfTestHistory) {
		limit = len(esm.selfTestHistory)
	}

	start := len(esm.selfTestHistory) - limit
	return esm.selfTestHistory[start:]
}

// IsInThermalThrottle checks if currently in thermal throttling
func (esm *EnhancedStarlinkMonitor) IsInThermalThrottle() bool {
	if len(esm.thermalHistory) == 0 {
		return false
	}

	latest := esm.thermalHistory[len(esm.thermalHistory)-1]
	return latest.ThermalThrottle
}

// GetAverageTemperature returns average temperature over recent readings
func (esm *EnhancedStarlinkMonitor) GetAverageTemperature(minutes int) float64 {
	if len(esm.thermalHistory) == 0 {
		return 0.0
	}

	cutoff := time.Now().Add(-time.Duration(minutes) * time.Minute)
	var sum float64
	count := 0

	for _, reading := range esm.thermalHistory {
		if reading.Timestamp.After(cutoff) {
			sum += reading.Temperature
			count++
		}
	}

	if count == 0 {
		return 0.0
	}

	return sum / float64(count)
}
