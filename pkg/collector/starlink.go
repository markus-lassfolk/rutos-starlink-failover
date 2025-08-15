// Package collector implements Starlink-specific metric collection using native gRPC
package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/retry"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/starlink"
)

// StarlinkCollector collects metrics from Starlink dish via native gRPC and JSON API fallback
type StarlinkCollector struct {
	dishIP      string
	dishPort    int
	httpClient  *http.Client
	grpcClient  *starlink.Client
	runner      *retry.Runner // command runner with retry logic for fallback
}

// isValidIP validates IP address format and prevents command injection
func isValidIP(ip string) bool {
	// Only allow valid IPv4 addresses
	if net.ParseIP(ip) == nil {
		return false
	}
	// Additional check to ensure only IP format (no special characters)
	matched, _ := regexp.MatchString(`^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$`, ip)
	return matched
}

// NewStarlinkCollector creates a new Starlink metrics collector with native gRPC
func NewStarlinkCollector(dishIP string, dishPort int) *StarlinkCollector {
	if dishIP == "" {
		dishIP = "192.168.100.1" // Default Starlink dish IP
	}

	if dishPort == 0 {
		dishPort = 9200 // Default Starlink gRPC port
	}

	// Validate IP to prevent command injection
	if !isValidIP(dishIP) {
		dishIP = "192.168.100.1" // Fallback to safe default
	}

	// Create HTTP client for JSON API fallback
	httpClient := &http.Client{
		Timeout: 10 * time.Second,
	}

	// Create native gRPC client
	grpcClient := starlink.NewClient(dishIP, dishPort)

	// Create retry runner for fallback commands
	retryConfig := retry.Config{
		MaxAttempts:   3,
		InitialDelay:  500 * time.Millisecond,
		MaxDelay:      2 * time.Second,
		BackoffFactor: 2.0,
	}
	retryRunner := retry.NewRunner(retryConfig)

	return &StarlinkCollector{
		dishIP:     dishIP,
		dishPort:   dishPort,
		httpClient: httpClient,
		grpcClient: grpcClient,
		runner:     retryRunner,
	}
}

// EnhancedStarlinkData represents comprehensive Starlink metrics with native gRPC
type EnhancedStarlinkData struct {
	// Connectivity metrics
	PopPingMs      *float64 `json:"pop_ping_ms,omitempty"`
	SNR            *float64 `json:"snr,omitempty"`
	ObstructionPct *float64 `json:"obstruction_pct,omitempty"`
	UptimeS        *uint64  `json:"uptime_s,omitempty"`
	State          *string  `json:"state,omitempty"`

	// Hardware diagnostics
	ThermalThrottle   *bool   `json:"thermal_throttle,omitempty"`
	ThermalShutdown   *bool   `json:"thermal_shutdown,omitempty"`
	RoamingAlert      *bool   `json:"roaming_alert,omitempty"`
	HardwareSelfTest  *string `json:"hardware_self_test,omitempty"`

	// Bandwidth restrictions
	DlBandwidthRestricted *string `json:"dl_bandwidth_restricted,omitempty"`
	UlBandwidthRestricted *string `json:"ul_bandwidth_restricted,omitempty"`

	// GPS/Location data
	Latitude       *float64 `json:"latitude,omitempty"`
	Longitude      *float64 `json:"longitude,omitempty"`
	Altitude       *float64 `json:"altitude,omitempty"`
	GPSUncertainty *float64 `json:"gps_uncertainty,omitempty"`

	// Enhanced API data
	HistoricalData    map[string]interface{} `json:"historical_data,omitempty"`
	DeviceInfo        map[string]interface{} `json:"device_info,omitempty"`
	EnhancedLocation  map[string]interface{} `json:"enhanced_location,omitempty"`
}

// isStarlinkReachable checks if Starlink dish is accessible via native gRPC
func (s *StarlinkCollector) isStarlinkReachable(ctx context.Context) bool {
	// Try a quick status check
	_, err := s.grpcClient.GetStatus(ctx)
	return err == nil
}

// Class returns the interface class this collector handles
func (s *StarlinkCollector) Class() string {
	return "starlink"
}

// SupportsInterface checks if this collector can handle the given interface
func (s *StarlinkCollector) SupportsInterface(interfaceName string) bool {
	// Starlink collector supports interfaces that contain "starlink" or "sat"
	name := strings.ToLower(interfaceName)
	return strings.Contains(name, "starlink") || strings.Contains(name, "sat") || strings.Contains(name, "wwan")
}

// Collect gathers enhanced metrics for the given member using native gRPC
func (s *StarlinkCollector) Collect(ctx context.Context, member Member) (Metrics, error) {
	startTime := time.Now()
	metrics := Metrics{
		Timestamp:     startTime,
		InterfaceName: member.InterfaceName,
		Class:         "starlink",
	}

	// Collect enhanced Starlink diagnostics with graceful degradation
	starlinkData, err := s.getEnhancedStarlinkData(ctx)

	// Set API response time and accessibility status
	apiResponseTime := time.Since(startTime).Seconds() * 1000
	metrics.Extra = map[string]interface{}{
		"api_response_time_ms": apiResponseTime,
		"api_accessible":       starlinkData != nil,
		"collection_method":    "native_grpc",
	}

	if err != nil {
		// Log error but continue with partial metrics rather than failing completely
		metrics.Extra["collection_error"] = err.Error()
		metrics.Extra["collection_method"] = "degraded"

		// Try to provide basic connectivity check via ping fallback
		if s.dishIP != "" {
			pingMetrics := s.getPingFallbackMetrics(ctx)
			if pingMetrics.LatencyMs != nil {
				metrics.LatencyMs = pingMetrics.LatencyMs
				metrics.Extra["fallback_ping_used"] = true
			}
		}

		// Return partial metrics instead of complete failure
		return metrics, nil
	}

	// Parse and set enhanced metrics
	if starlinkData != nil {
		// Basic connectivity metrics
		if starlinkData.PopPingMs != nil {
			latency := *starlinkData.PopPingMs
			metrics.LatencyMs = &latency
		}

		if starlinkData.SNR != nil {
			snr := *starlinkData.SNR
			metrics.SNR = &snr
		}

		if starlinkData.ObstructionPct != nil {
			obstruction := *starlinkData.ObstructionPct * 100 // Convert to percentage
			metrics.ObstructionPct = &obstruction
		}

		// Enhanced metrics in Extra
		if starlinkData.UptimeS != nil {
			metrics.Extra["uptime_s"] = *starlinkData.UptimeS
		}
		if starlinkData.State != nil {
			metrics.Extra["state"] = *starlinkData.State
		}

		// Hardware diagnostics
		if starlinkData.ThermalThrottle != nil {
			metrics.Extra["thermal_throttle"] = *starlinkData.ThermalThrottle
		}
		if starlinkData.ThermalShutdown != nil {
			metrics.Extra["thermal_shutdown"] = *starlinkData.ThermalShutdown
		}
		if starlinkData.RoamingAlert != nil {
			metrics.Extra["roaming_alert"] = *starlinkData.RoamingAlert
		}
		if starlinkData.HardwareSelfTest != nil {
			metrics.Extra["hardware_self_test"] = *starlinkData.HardwareSelfTest
		}

		// Bandwidth restrictions
		if starlinkData.DlBandwidthRestricted != nil {
			metrics.Extra["dl_bandwidth_restricted"] = *starlinkData.DlBandwidthRestricted
		}
		if starlinkData.UlBandwidthRestricted != nil {
			metrics.Extra["ul_bandwidth_restricted"] = *starlinkData.UlBandwidthRestricted
		}

		// GPS/Location data
		if starlinkData.Latitude != nil {
			metrics.Extra["latitude"] = *starlinkData.Latitude
		}
		if starlinkData.Longitude != nil {
			metrics.Extra["longitude"] = *starlinkData.Longitude
		}
		if starlinkData.Altitude != nil {
			metrics.Extra["altitude"] = *starlinkData.Altitude
		}
		if starlinkData.GPSUncertainty != nil {
			metrics.Extra["gps_uncertainty"] = *starlinkData.GPSUncertainty
		}

		// Enhanced API data
		if starlinkData.HistoricalData != nil {
			for key, value := range starlinkData.HistoricalData {
				metrics.Extra["history_"+key] = value
			}
		}
		if starlinkData.DeviceInfo != nil {
			for key, value := range starlinkData.DeviceInfo {
				metrics.Extra["device_"+key] = value
			}
		}
		if starlinkData.EnhancedLocation != nil {
			for key, value := range starlinkData.EnhancedLocation {
				metrics.Extra["location_"+key] = value
			}
		}
	}

	return metrics, nil
}

// getEnhancedStarlinkData fetches comprehensive data using native gRPC with JSON fallback
func (s *StarlinkCollector) getEnhancedStarlinkData(ctx context.Context) (*EnhancedStarlinkData, error) {
	// Try native gRPC first
	if data, err := s.getNativeGRPCData(ctx); err == nil {
		return data, nil
	}

	// Fallback to JSON API
	return s.getJSONData(ctx)
}

// getNativeGRPCData fetches data using native gRPC client with expanded API coverage
func (s *StarlinkCollector) getNativeGRPCData(ctx context.Context) (*EnhancedStarlinkData, error) {
	data := &EnhancedStarlinkData{}

	// Get basic status
	status, err := s.grpcClient.GetStatus(ctx)
	if err == nil && status.DishGetStatus != nil {
		if status.DishGetStatus.PopPingLatencyMs != nil {
			data.PopPingMs = status.DishGetStatus.PopPingLatencyMs
		}
		if status.DishGetStatus.SNR != nil {
			data.SNR = status.DishGetStatus.SNR
		}
		if status.DishGetStatus.ObstructionStats != nil && status.DishGetStatus.ObstructionStats.FractionObstructed != nil {
			data.ObstructionPct = status.DishGetStatus.ObstructionStats.FractionObstructed
		}
		if status.DishGetStatus.UptimeS != nil {
			data.UptimeS = status.DishGetStatus.UptimeS
		}
		if status.DishGetStatus.State != nil {
			data.State = status.DishGetStatus.State
		}
	}

	// Get detailed diagnostics
	diagnostics, err := s.grpcClient.GetDiagnostics(ctx)
	if err == nil && diagnostics.DishGetDiagnostics != nil {
		diag := diagnostics.DishGetDiagnostics

		// Hardware alerts
		if diag.Alerts != nil {
			if diag.Alerts.ThermalThrottle != nil {
				data.ThermalThrottle = diag.Alerts.ThermalThrottle
			}
			if diag.Alerts.ThermalShutdown != nil {
				data.ThermalShutdown = diag.Alerts.ThermalShutdown
			}
			if diag.Alerts.Roaming != nil {
				data.RoamingAlert = diag.Alerts.Roaming
			}
		}

		// Hardware self-test
		if diag.HardwareSelfTest != nil {
			data.HardwareSelfTest = diag.HardwareSelfTest
		}

		// Bandwidth restrictions
		if diag.DlBandwidthRestricted != nil {
			data.DlBandwidthRestricted = diag.DlBandwidthRestricted
		}
		if diag.UlBandwidthRestricted != nil {
			data.UlBandwidthRestricted = diag.UlBandwidthRestricted
		}

		// GPS/Location data
		if diag.Location != nil {
			if diag.Location.Latitude != nil {
				data.Latitude = diag.Location.Latitude
			}
			if diag.Location.Longitude != nil {
				data.Longitude = diag.Location.Longitude
			}
			if diag.Location.Altitude != nil {
				data.Altitude = diag.Location.Altitude
			}
			if diag.Location.UncertaintyMeters != nil {
				data.GPSUncertainty = diag.Location.UncertaintyMeters
			}
		}
	}

	// Get historical performance data for trend analysis
	if history, err := s.grpcClient.GetHistory(ctx); err == nil && history != nil {
		data.HistoricalData = s.processHistoricalData(history)
	}

	// Get device information for enhanced context
	if deviceInfo, err := s.grpcClient.GetDeviceInfo(ctx); err == nil && deviceInfo != nil {
		data.DeviceInfo = s.processDeviceInfo(deviceInfo)
	}

	// Get enhanced location data using dedicated endpoint
	if locationData, err := s.grpcClient.GetLocation(ctx); err == nil && locationData != nil {
		data.EnhancedLocation = s.processLocationData(locationData)
	}

	return data, nil
}

// getJSONData fetches data using fallback JSON API
func (s *StarlinkCollector) getJSONData(ctx context.Context) (*EnhancedStarlinkData, error) {
	url := fmt.Sprintf("http://%s/support/debug", s.dishIP)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP error: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse JSON response
	var jsonData map[string]interface{}
	if err := json.Unmarshal(body, &jsonData); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	return s.parseJSONResponse(jsonData), nil
}

// parseJSONResponse extracts metrics from JSON API response
func (s *StarlinkCollector) parseJSONResponse(data map[string]interface{}) *EnhancedStarlinkData {
	result := &EnhancedStarlinkData{}

	// Basic connectivity - JSON API has limited data
	if val, ok := data["pop_ping_latency_ms"].(float64); ok {
		result.PopPingMs = &val
	}
	if val, ok := data["snr"].(float64); ok {
		result.SNR = &val
	}
	if val, ok := data["obstruction_percent"].(float64); ok {
		pct := val / 100.0 // Convert percentage to fraction
		result.ObstructionPct = &pct
	}

	return result
}

// getPingFallbackMetrics provides basic connectivity check via ping
func (s *StarlinkCollector) getPingFallbackMetrics(ctx context.Context) Metrics {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: "starlink_ping_fallback",
		Class:         "starlink",
	}

	// Simple ping check
	if output, err := s.runner.Output(ctx, "ping", "-c", "1", "-W", "2", s.dishIP); err == nil {
		// Parse ping output for latency
		outputStr := string(output)
		if strings.Contains(outputStr, "time=") {
			// Extract latency from ping output
			parts := strings.Split(outputStr, "time=")
			if len(parts) > 1 {
				timeStr := strings.Split(parts[1], " ")[0]
				timeStr = strings.TrimSuffix(timeStr, "ms")
				if latency, err := strconv.ParseFloat(timeStr, 64); err == nil {
					metrics.LatencyMs = &latency
				}
			}
		}
	}

	return metrics
}

// processHistoricalData extracts useful metrics from historical performance data
func (s *StarlinkCollector) processHistoricalData(history *starlink.DishHistory) map[string]interface{} {
	result := make(map[string]interface{})

	if history == nil {
		return result
	}

	// Calculate averages and trends from historical arrays
	if len(history.PopPingLatencyMs) > 0 {
		result["avg_ping_latency_ms"] = calculateAverage(history.PopPingLatencyMs)
		result["ping_trend"] = calculateTrend(history.PopPingLatencyMs)
		result["ping_samples"] = len(history.PopPingLatencyMs)
	}

	if len(history.PopPingDropRate) > 0 {
		result["avg_drop_rate"] = calculateAverage(history.PopPingDropRate)
		result["drop_rate_trend"] = calculateTrend(history.PopPingDropRate)
	}

	if len(history.SNR) > 0 {
		result["avg_snr"] = calculateAverage(history.SNR)
		result["snr_trend"] = calculateTrend(history.SNR)
	}

	if len(history.DownlinkThroughputBps) > 0 {
		result["avg_dl_throughput_bps"] = calculateAverage(history.DownlinkThroughputBps)
		result["dl_throughput_trend"] = calculateTrend(history.DownlinkThroughputBps)
	}

	if len(history.UplinkThroughputBps) > 0 {
		result["avg_ul_throughput_bps"] = calculateAverage(history.UplinkThroughputBps)
		result["ul_throughput_trend"] = calculateTrend(history.UplinkThroughputBps)
	}

	// Obstruction and scheduling stats
	if len(history.Obstructed) > 0 {
		obstructedCount := 0
		for _, obstructed := range history.Obstructed {
			if obstructed {
				obstructedCount++
			}
		}
		result["obstruction_rate"] = float64(obstructedCount) / float64(len(history.Obstructed))
	}

	if len(history.Scheduled) > 0 {
		scheduledCount := 0
		for _, scheduled := range history.Scheduled {
			if scheduled {
				scheduledCount++
			}
		}
		result["schedule_rate"] = float64(scheduledCount) / float64(len(history.Scheduled))
	}

	if history.Current != nil {
		result["current_sample"] = *history.Current
	}

	return result
}

// processDeviceInfo extracts device information for context
func (s *StarlinkCollector) processDeviceInfo(deviceInfo *starlink.DeviceInfo) map[string]interface{} {
	result := make(map[string]interface{})

	if deviceInfo == nil {
		return result
	}

	if deviceInfo.ID != nil {
		result["id"] = *deviceInfo.ID
	}
	if deviceInfo.HardwareVersion != nil {
		result["hardware_version"] = *deviceInfo.HardwareVersion
	}
	if deviceInfo.SoftwareVersion != nil {
		result["software_version"] = *deviceInfo.SoftwareVersion
	}
	if deviceInfo.CountryCode != nil {
		result["country_code"] = *deviceInfo.CountryCode
	}
	if deviceInfo.UtcOffsetS != nil {
		result["utc_offset_s"] = *deviceInfo.UtcOffsetS
	}
	if deviceInfo.SoftwarePartNumber != nil {
		result["software_part_number"] = *deviceInfo.SoftwarePartNumber
	}
	if deviceInfo.GenerationNumber != nil {
		result["generation_number"] = *deviceInfo.GenerationNumber
	}
	if deviceInfo.DishCohoused != nil {
		result["dish_cohoused"] = *deviceInfo.DishCohoused
	}
	if deviceInfo.UtcnsOffsetNs != nil {
		result["utcns_offset_ns"] = *deviceInfo.UtcnsOffsetNs
	}

	return result
}

// processLocationData extracts enhanced location information
func (s *StarlinkCollector) processLocationData(locationData *starlink.LocationData) map[string]interface{} {
	result := make(map[string]interface{})

	if locationData == nil {
		return result
	}

	if locationData.Source != nil {
		result["source"] = *locationData.Source
	}

	if locationData.LLA != nil {
		lla := make(map[string]interface{})
		if locationData.LLA.Lat != nil {
			lla["lat"] = *locationData.LLA.Lat
		}
		if locationData.LLA.Lon != nil {
			lla["lon"] = *locationData.LLA.Lon
		}
		if locationData.LLA.Alt != nil {
			lla["alt"] = *locationData.LLA.Alt
		}
		if len(lla) > 0 {
			result["lla"] = lla
		}
	}

	if locationData.ECEF != nil {
		ecef := make(map[string]interface{})
		if locationData.ECEF.X != nil {
			ecef["x"] = *locationData.ECEF.X
		}
		if locationData.ECEF.Y != nil {
			ecef["y"] = *locationData.ECEF.Y
		}
		if locationData.ECEF.Z != nil {
			ecef["z"] = *locationData.ECEF.Z
		}
		if len(ecef) > 0 {
			result["ecef"] = ecef
		}
	}

	return result
}

// calculateAverage computes the mean of a float64 slice
func calculateAverage(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}

// calculateTrend returns simple trend indicator: positive, negative, or stable
func calculateTrend(values []float64) string {
	if len(values) < 2 {
		return "stable"
	}

	// Compare first half vs second half
	mid := len(values) / 2
	firstHalf := calculateAverage(values[:mid])
	secondHalf := calculateAverage(values[mid:])

	diff := secondHalf - firstHalf
	threshold := firstHalf * 0.1 // 10% threshold

	if diff > threshold {
		return "improving"
	} else if diff < -threshold {
		return "degrading"
	}
	return "stable"
}
