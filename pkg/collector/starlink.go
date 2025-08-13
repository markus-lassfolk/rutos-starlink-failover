// Package collector implements Starlink-specific metric collection
package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// StarlinkCollector collects metrics from Starlink dish via JSON API
type StarlinkCollector struct {
	dishIP     string
	httpClient *http.Client
}

// NewStarlinkCollector creates a new Starlink metrics collector
func NewStarlinkCollector(dishIP string) *StarlinkCollector {
	if dishIP == "" {
		dishIP = "192.168.100.1" // Default Starlink dish IP
	}
	
	return &StarlinkCollector{
		dishIP: dishIP,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// Class returns the interface class this collector handles
func (s *StarlinkCollector) Class() string {
	return "starlink"
}

// SupportsInterface checks if this collector can handle the given interface
func (s *StarlinkCollector) SupportsInterface(interfaceName string) bool {
	// TODO: Check if interface routes through Starlink
	// For now, basic heuristic based on interface name
	return interfaceName == "eth2" || interfaceName == "starlink0" || interfaceName == "wwan0"
}

// Collect gathers metrics for the given member
func (s *StarlinkCollector) Collect(ctx context.Context, member Member) (Metrics, error) {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: member.InterfaceName,
		Class:         "starlink",
	}
	
	// Collect Starlink-specific metrics
	starlinkData, err := s.getStarlinkData(ctx)
	if err != nil {
		return metrics, fmt.Errorf("failed to get Starlink data: %w", err)
	}
	
	// Parse and set metrics
	if starlinkData != nil {
		metrics.ObstructionPct = starlinkData.ObstructionPct
		metrics.SNR = starlinkData.SNR
		metrics.Outages = starlinkData.Outages
		metrics.PopPingMs = starlinkData.PopPingMs
		
		// Convert Starlink latency to common latency field
		if starlinkData.PopPingMs != nil {
			latency := *starlinkData.PopPingMs
			metrics.LatencyMs = &latency
		}
	}
	
	return metrics, nil
}

// StarlinkData represents parsed Starlink dish telemetry
type StarlinkData struct {
	ObstructionPct *float64 `json:"obstruction_pct"`
	SNR           *float64 `json:"snr"`
	Outages       *int     `json:"outages"`
	PopPingMs     *float64 `json:"pop_ping_ms"`
	UptimeS       *int     `json:"uptime_s"`
	State         *string  `json:"state"`
}

// getStarlinkData fetches telemetry from Starlink dish
func (s *StarlinkCollector) getStarlinkData(ctx context.Context) (*StarlinkData, error) {
	// Use the newer JSON API endpoint
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
	
	// Parse the JSON response
	var rawData map[string]interface{}
	if err := json.Unmarshal(body, &rawData); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}
	
	// Extract relevant metrics from the complex JSON structure
	data := &StarlinkData{}
	s.extractMetrics(rawData, data)
	
	return data, nil
}

// extractMetrics extracts relevant metrics from raw Starlink JSON
func (s *StarlinkCollector) extractMetrics(raw map[string]interface{}, data *StarlinkData) {
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
			uptime := int(i)
			data.UptimeS = &uptime
		}
	}
	
	if val, ok := raw["state"]; ok {
		if s, ok := val.(string); ok {
			data.State = &s
		}
	}
}
