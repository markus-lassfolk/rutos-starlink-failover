// Package collector implements Starlink-specific metric collection
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
)

// StarlinkCollector collects metrics from Starlink dish via JSON API and gRPC
type StarlinkCollector struct {
	dishIP     string
	dishPort   int
	httpClient *http.Client
	runner     *retry.Runner // command runner with retry logic
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

// NewStarlinkCollector creates a new Starlink metrics collector
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

	// Validate port range
	if dishPort < 1 || dishPort > 65535 {
		dishPort = 9200 // Fallback to safe default
	}

	// Configure retry for external commands
	retryConfig := retry.Config{
		MaxAttempts:   3,
		InitialDelay:  100 * time.Millisecond,
		MaxDelay:      2 * time.Second,
		BackoffFactor: 2.0,
	}

	return &StarlinkCollector{
		dishIP:   dishIP,
		dishPort: dishPort,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
		runner: retry.NewRunner(retryConfig),
	}
}

// Class returns the interface class this collector handles
func (s *StarlinkCollector) Class() string {
	return "starlink"
}

// SupportsInterface checks if this collector can handle the given interface
func (s *StarlinkCollector) SupportsInterface(interfaceName string) bool {
	// Check if interface routes through Starlink by testing dish connectivity
	return s.isStarlinkReachable()
}

// isStarlinkReachable tests if Starlink dish is accessible
func (s *StarlinkCollector) isStarlinkReachable() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("http://%s/support/debug", s.dishIP), nil)
	if err != nil {
		return false
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == 200
}

// Collect gathers enhanced metrics for the given member
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

	metrics.Extra["collection_method"] = "full"

	// Parse and set enhanced metrics
	if starlinkData != nil {
		// Basic connectivity metrics
		if starlinkData.PopPingMs != nil {
			latency := *starlinkData.PopPingMs
			metrics.LatencyMs = &latency
		}

		if starlinkData.PacketLossPct != nil {
			loss := *starlinkData.PacketLossPct
			metrics.LossPct = &loss
		}

		// Signal quality
		if starlinkData.SNR != nil {
			metrics.SNR = starlinkData.SNR
		}

		if starlinkData.ObstructionPct != nil {
			metrics.ObstructionPct = starlinkData.ObstructionPct
		}

		// Enhanced metrics in Extra field
		if metrics.Extra == nil {
			metrics.Extra = make(map[string]interface{})
		}

		// Hardware health
		if starlinkData.HardwareSelfTest != nil {
			metrics.Extra["hardware_self_test"] = *starlinkData.HardwareSelfTest
		}
		if starlinkData.ThermalThrottle != nil {
			metrics.Extra["thermal_throttle"] = *starlinkData.ThermalThrottle
		}
		if starlinkData.ThermalShutdown != nil {
			metrics.Extra["thermal_shutdown"] = *starlinkData.ThermalShutdown
		}
		if starlinkData.UptimeS != nil {
			metrics.Extra["uptime_seconds"] = *starlinkData.UptimeS
		}
		if starlinkData.BootCount != nil {
			metrics.Extra["boot_count"] = *starlinkData.BootCount
		}

		// Bandwidth restrictions
		if starlinkData.DlBandwidthRestricted != nil {
			metrics.Extra["dl_bandwidth_restricted"] = *starlinkData.DlBandwidthRestricted
		}
		if starlinkData.UlBandwidthRestricted != nil {
			metrics.Extra["ul_bandwidth_restricted"] = *starlinkData.UlBandwidthRestricted
		}

		// Signal quality indicators
		if starlinkData.IsSnrAboveNoise != nil {
			metrics.Extra["is_snr_above_noise"] = *starlinkData.IsSnrAboveNoise
		}
		if starlinkData.IsSnrPersistentLow != nil {
			metrics.Extra["is_snr_persistent_low"] = *starlinkData.IsSnrPersistentLow
		}

		// GPS data
		if starlinkData.Latitude != nil && starlinkData.Longitude != nil {
			metrics.Extra["latitude"] = *starlinkData.Latitude
			metrics.Extra["longitude"] = *starlinkData.Longitude
		}
		if starlinkData.Altitude != nil {
			metrics.Extra["altitude"] = *starlinkData.Altitude
		}
		if starlinkData.GPSValid != nil {
			metrics.Extra["gps_valid"] = *starlinkData.GPSValid
		}
		if starlinkData.GPSSatellites != nil {
			metrics.Extra["gps_satellites"] = *starlinkData.GPSSatellites
		}
		if starlinkData.GPSUncertainty != nil {
			metrics.Extra["gps_uncertainty_m"] = *starlinkData.GPSUncertainty
		}

		// Alerts
		if starlinkData.RoamingAlert != nil {
			metrics.Extra["roaming_alert"] = *starlinkData.RoamingAlert
		}
		if starlinkData.SoftwareUpdate != nil {
			metrics.Extra["software_update_pending"] = *starlinkData.SoftwareUpdate
		}
	}

	return metrics, nil
}

// EnhancedStarlinkData represents comprehensive Starlink dish telemetry
type EnhancedStarlinkData struct {
	// Basic connectivity
	PopPingMs      *float64 `json:"pop_ping_ms"`
	PacketLossPct  *float64 `json:"packet_loss_pct"`
	SNR            *float64 `json:"snr"`
	ObstructionPct *float64 `json:"obstruction_pct"`

	// Hardware diagnostics
	HardwareSelfTest *string `json:"hardware_self_test"`
	ThermalThrottle  *bool   `json:"thermal_throttle"`
	ThermalShutdown  *bool   `json:"thermal_shutdown"`
	UptimeS          *int64  `json:"uptime_s"`
	BootCount        *int    `json:"boot_count"`

	// Signal quality indicators
	IsSnrAboveNoise    *bool `json:"is_snr_above_noise_floor"`
	IsSnrPersistentLow *bool `json:"is_snr_persistently_low"`

	// Bandwidth and performance
	DlBandwidthRestricted *string `json:"dl_bandwidth_restricted_reason"`
	UlBandwidthRestricted *string `json:"ul_bandwidth_restricted_reason"`

	// GPS and location
	Latitude       *float64 `json:"latitude"`
	Longitude      *float64 `json:"longitude"`
	Altitude       *float64 `json:"altitude"`
	GPSValid       *bool    `json:"gps_valid"`
	GPSSatellites  *int     `json:"gps_satellites"`
	GPSUncertainty *float64 `json:"gps_uncertainty_m"`

	// Alerts and status
	RoamingAlert   *bool `json:"roaming_alert"`
	SoftwareUpdate *bool `json:"software_update_pending"`

	// Legacy fields for compatibility
	Outages *int    `json:"outages"`
	State   *string `json:"state"`
}

// getEnhancedStarlinkData fetches comprehensive telemetry using multiple APIs
func (s *StarlinkCollector) getEnhancedStarlinkData(ctx context.Context) (*EnhancedStarlinkData, error) {
	// Try gRPC API first for comprehensive data
	if grpcData, err := s.getGRPCData(ctx); err == nil {
		return grpcData, nil
	}

	// Fallback to JSON API
	return s.getJSONData(ctx)
}

// getGRPCData fetches data using grpcurl command with retry logic
func (s *StarlinkCollector) getGRPCData(ctx context.Context) (*EnhancedStarlinkData, error) {
	// Try get_diagnostics for comprehensive data with retry
	args := []string{
		"-plaintext", "-d",
		`{"get_diagnostics":{}}`,
		fmt.Sprintf("%s:%d", s.dishIP, s.dishPort),
		"SpaceX.API.Device.Device/Handle",
	}

	output, err := s.runner.Output(ctx, "grpcurl", args...)
	if err != nil {
		return nil, fmt.Errorf("grpcurl get_diagnostics failed: %w", err)
	}

	// Parse gRPC response
	var grpcResp map[string]interface{}
	if err := json.Unmarshal(output, &grpcResp); err != nil {
		return nil, fmt.Errorf("failed to parse gRPC response: %w", err)
	}

	return s.parseGRPCDiagnostics(grpcResp)
}

// parseGRPCDiagnostics extracts enhanced metrics from gRPC diagnostics response
func (s *StarlinkCollector) parseGRPCDiagnostics(resp map[string]interface{}) (*EnhancedStarlinkData, error) {
	data := &EnhancedStarlinkData{}

	// Navigate through nested JSON structure
	if diagnostics, ok := resp["dishGetDiagnostics"].(map[string]interface{}); ok {
		// Hardware diagnostics
		if alerts, ok := diagnostics["alerts"].(map[string]interface{}); ok {
			if val, exists := alerts["thermalThrottle"].(bool); exists {
				data.ThermalThrottle = &val
			}
			if val, exists := alerts["thermalShutdown"].(bool); exists {
				data.ThermalShutdown = &val
			}
			if val, exists := alerts["roaming"].(bool); exists {
				data.RoamingAlert = &val
			}
		}

		// Hardware self-test
		if val, exists := diagnostics["hardwareSelfTest"].(string); exists {
			data.HardwareSelfTest = &val
		}

		// Bandwidth restrictions
		if val, exists := diagnostics["dlBandwidthRestrictedReason"].(string); exists {
			data.DlBandwidthRestricted = &val
		}
		if val, exists := diagnostics["ulBandwidthRestrictedReason"].(string); exists {
			data.UlBandwidthRestricted = &val
		}

		// Location data
		if location, ok := diagnostics["location"].(map[string]interface{}); ok {
			if val, exists := location["latitude"].(float64); exists {
				data.Latitude = &val
			}
			if val, exists := location["longitude"].(float64); exists {
				data.Longitude = &val
			}
			if val, exists := location["altitude"].(float64); exists {
				data.Altitude = &val
			}
			if val, exists := location["uncertaintyMeters"].(float64); exists {
				data.GPSUncertainty = &val
			}
		}
	}

	// Get status data for connectivity metrics
	statusData, _ := s.getGRPCStatus(context.Background())
	if statusData != nil {
		data.PopPingMs = statusData.PopPingMs
		data.SNR = statusData.SNR
		data.ObstructionPct = statusData.ObstructionPct
		data.UptimeS = statusData.UptimeS
	}

	return data, nil
}

// getGRPCStatus gets basic status metrics with retry logic
func (s *StarlinkCollector) getGRPCStatus(ctx context.Context) (*EnhancedStarlinkData, error) {
	args := []string{
		"-plaintext", "-d",
		`{"get_status":{}}`,
		fmt.Sprintf("%s:%d", s.dishIP, s.dishPort),
		"SpaceX.API.Device.Device/Handle",
	}

	output, err := s.runner.Output(ctx, "grpcurl", args...)
	if err != nil {
		return nil, err
	}

	var grpcResp map[string]interface{}
	if err := json.Unmarshal(output, &grpcResp); err != nil {
		return nil, err
	}

	data := &EnhancedStarlinkData{}

	if status, ok := grpcResp["dishGetStatus"].(map[string]interface{}); ok {
		// Extract connectivity metrics
		if val, exists := status["popPingLatencyMs"].(float64); exists {
			data.PopPingMs = &val
		}
		if val, exists := status["snr"].(float64); exists {
			data.SNR = &val
		}
		if val, exists := status["obstructionStats"].(map[string]interface{}); exists {
			if obstruction, ok := val["fractionObstructed"].(float64); ok {
				obstructionPct := obstruction * 100
				data.ObstructionPct = &obstructionPct
			}
		}
		if val, exists := status["uptimeS"].(float64); exists {
			uptime := int64(val)
			data.UptimeS = &uptime
		}

		// Ready states for signal quality
		if readyStates, ok := status["readyStates"].(map[string]interface{}); ok {
			if val, exists := readyStates["snrAboveNoiseFloor"].(bool); exists {
				data.IsSnrAboveNoise = &val
			}
			if val, exists := readyStates["snrPersistentlyLow"].(bool); exists {
				// Invert the logic - we want "is persistently low"
				inverted := !val
				data.IsSnrPersistentLow = &inverted
			}
		}
	}

	return data, nil
}

// getJSONData fetches data using legacy JSON API
func (s *StarlinkCollector) getJSONData(ctx context.Context) (*EnhancedStarlinkData, error) {
	url := fmt.Sprintf("http://%s/support/debug", s.dishIP)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch data: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse JSON response (simplified for legacy API)
	var jsonResp map[string]interface{}
	if err := json.Unmarshal(body, &jsonResp); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	data := &EnhancedStarlinkData{}

	// Extract basic metrics from JSON API
	if val, exists := jsonResp["pop_ping_latency_ms"].(float64); exists {
		data.PopPingMs = &val
	}
	if val, exists := jsonResp["snr"].(float64); exists {
		data.SNR = &val
	}

	return data, nil
}

// extractMetrics extracts relevant metrics from raw Starlink JSON
func (s *StarlinkCollector) extractMetrics(raw map[string]interface{}, data *EnhancedStarlinkData) {
	// This is a simplified extraction - the actual Starlink API has a complex nested structure
	// In production, we'd need to navigate the proper JSON paths

	// Try to extract common metrics
	if val, ok := raw["obstruction_pct"]; ok {
		if f, ok := val.(float64); ok {
			data.ObstructionPct = &f
		}
	}

	if val, ok := raw["snr"]; ok {
		if f, ok := val.(float64); ok {
			data.SNR = &f
		}
	}

	if val, ok := raw["pop_ping_latency_ms"]; ok {
		if f, ok := val.(float64); ok {
			data.PopPingMs = &f
		}
	}

	if val, ok := raw["outage_count"]; ok {
		if i, ok := val.(float64); ok {
			outages := int(i)
			data.Outages = &outages
		}
	}

	if val, ok := raw["uptime"]; ok {
		if i, ok := val.(float64); ok {
			uptime := int64(i)
			data.UptimeS = &uptime
		}
	}

	if val, ok := raw["state"]; ok {
		if s, ok := val.(string); ok {
			data.State = &s
		}
	}
}

// getPingFallbackMetrics provides basic connectivity metrics when API fails
func (s *StarlinkCollector) getPingFallbackMetrics(ctx context.Context) Metrics {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: "starlink",
		Class:         "starlink",
	}

	// Simple ping test to dish IP to check basic connectivity
	output, err := s.runner.Output(ctx, "ping", "-c", "1", "-W", "2000", s.dishIP)
	if err == nil {
		// Parse ping output for latency (very basic parsing)
		if strings.Contains(string(output), "time=") {
			// Extract time= value (platform-dependent parsing)
			lines := strings.Split(string(output), "\n")
			for _, line := range lines {
				if strings.Contains(line, "time=") {
					// Basic regex-free parsing for time=XX.X format
					parts := strings.Split(line, "time=")
					if len(parts) > 1 {
						timeStr := strings.Split(parts[1], " ")[0]
						if latency, err := strconv.ParseFloat(timeStr, 64); err == nil {
							metrics.LatencyMs = &latency
							break
						}
					}
				}
			}
		}
	}

	return metrics
}
