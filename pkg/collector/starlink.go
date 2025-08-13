package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
)

// StarlinkCollector collects metrics from Starlink dish
type StarlinkCollector struct {
	*BaseCollector
	apiHost string
	timeout time.Duration
}

// StarlinkAPIResponse represents the response from Starlink API
type StarlinkAPIResponse struct {
	Status struct {
		ObstructionStats struct {
			CurrentlyObstructed bool    `json:"currentlyObstructed"`
			FractionObstructed  float64 `json:"fractionObstructed"`
			Last24hObstructedS  int     `json:"last24hObstructedS"`
			WedgeFractionObstructed []float64 `json:"wedgeFractionObstructed"`
		} `json:"obstructionStats"`
		Outage struct {
			LastOutageS int `json:"lastOutageS"`
		} `json:"outage"`
		PopPingLatencyMs float64 `json:"popPingLatencyMs"`
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

// collectStarlinkMetrics collects metrics from Starlink API
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

	// Extract metrics
	metrics := &pkg.Metrics{
		Timestamp: time.Now(),
	}

	// Obstruction percentage
	obstructionPct := apiResp.Status.ObstructionStats.FractionObstructed * 100
	metrics.ObstructionPct = &obstructionPct

	// Outages (simplified - could be enhanced to track more outage data)
	outages := 0
	if apiResp.Status.Outage.LastOutageS > 0 {
		outages = 1 // Indicate recent outage
	}
	metrics.Outages = &outages

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

// GetStarlinkInfo returns basic Starlink dish information
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
		"currently_obstructed": apiResp.Status.ObstructionStats.CurrentlyObstructed,
		"fraction_obstructed":  apiResp.Status.ObstructionStats.FractionObstructed,
		"last_24h_obstructed_s": apiResp.Status.ObstructionStats.Last24hObstructedS,
		"pop_ping_latency_ms":   apiResp.Status.PopPingLatencyMs,
		"last_outage_s":         apiResp.Status.Outage.LastOutageS,
	}

	return info, nil
}
