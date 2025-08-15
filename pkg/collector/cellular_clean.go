// Package collector implements cellular-specific metric collection via ubus
package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/retry"
)

// CellularCollector collects metrics from cellular interfaces via ubus mobiled
type CellularCollector struct {
	provider string        // ubus provider to use (auto-detect if empty)
	runner   *retry.Runner // command runner with retry logic
}

// NewCellularCollector creates a new cellular metrics collector
func NewCellularCollector(provider string) *CellularCollector {
	// Conservative retry config for ubus operations
	config := retry.Config{
		MaxAttempts:   3,
		InitialDelay:  50 * time.Millisecond,
		MaxDelay:      500 * time.Millisecond,
		BackoffFactor: 2.0,
	}

	return &CellularCollector{
		provider: provider,
		runner:   retry.NewRunner(config),
	}
}

// Class returns the interface class this collector handles
func (c *CellularCollector) Class() string {
	return "cellular"
}

// SupportsInterface checks if this collector can handle the given interface
func (c *CellularCollector) SupportsInterface(interfaceName string) bool {
	// Common cellular interface patterns on RutOS
	patterns := []string{"wwan", "eth1", "usb", "mobile", "cellular", "lte", "gsm"}

	ifLower := strings.ToLower(interfaceName)
	for _, pattern := range patterns {
		if strings.Contains(ifLower, pattern) {
			return true
		}
	}
	return false
}

// Collect gathers cellular-specific metrics from ubus mobiled interface
func (c *CellularCollector) Collect(ctx context.Context, interfaceName string) (*Metrics, error) {
	metrics := &Metrics{
		InterfaceName: interfaceName,
		Class:         "cellular",
		Timestamp:     time.Now(),
	}

	// Try cellular-specific metrics first via ubus mobiled
	if err := c.collectCellularMetrics(ctx, interfaceName, metrics); err != nil {
		// Fallback to interface-bound ping if cellular metrics unavailable
		if fallbackMetrics, fallbackErr := c.fallbackPingMetrics(ctx, interfaceName); fallbackErr == nil {
			metrics.Latency = fallbackMetrics.Latency
			metrics.PacketLoss = fallbackMetrics.PacketLoss
			metrics.Available = true
		} else {
			// Mark as unavailable if both cellular and ping fail
			metrics.Available = false
			return metrics, fmt.Errorf("cellular metrics and ping fallback both failed: %w, fallback: %w", err, fallbackErr)
		}
	}

	return metrics, nil
}

// collectCellularMetrics gathers cellular-specific data via ubus mobiled
func (c *CellularCollector) collectCellularMetrics(ctx context.Context, interfaceName string, metrics *Metrics) error {
	provider := c.provider
	if provider == "" {
		// Auto-detect provider if not specified
		detectedProvider, err := c.detectProvider(ctx)
		if err != nil {
			return fmt.Errorf("failed to detect cellular provider: %w", err)
		}
		provider = detectedProvider
	}

	// Get connection info
	connInfo, err := c.getConnectionInfo(ctx, provider)
	if err != nil {
		return fmt.Errorf("failed to get connection info: %w", err)
	}

	// Get signal info for signal strength metrics
	signalInfo, err := c.getSignalInfo(ctx, provider)
	if err != nil {
		return fmt.Errorf("failed to get signal info: %w", err)
	}

	// Parse and populate metrics
	c.parseConnectionInfo(connInfo, metrics)
	c.parseSignalInfo(signalInfo, metrics)

	metrics.Available = true
	return nil
}

// detectProvider discovers available cellular providers via ubus
func (c *CellularCollector) detectProvider(ctx context.Context) (string, error) {
	// Common provider patterns on RutOS
	providers := []string{"gsm", "lte", "cellular", "mobile"}

	for _, provider := range providers {
		// Test if provider responds to ubus call
		_, err := c.runner.Output(ctx, "ubus", "call", provider, "get_status")
		if err == nil {
			return provider, nil
		}
	}

	return "", fmt.Errorf("no cellular provider found via ubus")
}

// getConnectionInfo retrieves connection status from cellular provider
func (c *CellularCollector) getConnectionInfo(ctx context.Context, provider string) (map[string]interface{}, error) {
	output, err := c.runner.Output(ctx, "ubus", "call", provider, "get_status")
	if err != nil {
		return nil, fmt.Errorf("ubus call to %s get_status failed: %w", provider, err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse connection info JSON: %w", err)
	}

	return result, nil
}

// getSignalInfo retrieves signal strength from cellular provider
func (c *CellularCollector) getSignalInfo(ctx context.Context, provider string) (map[string]interface{}, error) {
	output, err := c.runner.Output(ctx, "ubus", "call", provider, "get_signal")
	if err != nil {
		return nil, fmt.Errorf("ubus call to %s get_signal failed: %w", provider, err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse signal info JSON: %w", err)
	}

	return result, nil
}

// parseConnectionInfo extracts connection metrics from ubus response
func (c *CellularCollector) parseConnectionInfo(info map[string]interface{}, metrics *Metrics) {
	// Extract connection state
	if state, ok := info["state"].(string); ok {
		metrics.Connected = (state == "connected" || state == "active")
	}

	// Extract network type if available
	if netType, ok := info["network_type"].(string); ok {
		metrics.NetworkType = &netType
	}

	// Extract operator info if available
	if operator, ok := info["operator"].(string); ok && operator != "" {
		metrics.NetworkName = &operator
	}
}

// parseSignalInfo extracts signal strength metrics from ubus response
func (c *CellularCollector) parseSignalInfo(info map[string]interface{}, metrics *Metrics) {
	// Extract RSRP (Reference Signal Received Power)
	if rsrp, ok := info["rsrp"].(float64); ok {
		metrics.RSRP = &rsrp
	} else if rsrpStr, ok := info["rsrp"].(string); ok {
		if rsrp, err := strconv.ParseFloat(rsrpStr, 64); err == nil {
			metrics.RSRP = &rsrp
		}
	}

	// Extract RSRQ (Reference Signal Received Quality)
	if rsrq, ok := info["rsrq"].(float64); ok {
		metrics.RSRQ = &rsrq
	} else if rsrqStr, ok := info["rsrq"].(string); ok {
		if rsrq, err := strconv.ParseFloat(rsrqStr, 64); err == nil {
			metrics.RSRQ = &rsrq
		}
	}

	// Extract RSSI (Received Signal Strength Indicator)
	if rssi, ok := info["rssi"].(float64); ok {
		metrics.RSSI = &rssi
	} else if rssiStr, ok := info["rssi"].(string); ok {
		if rssi, err := strconv.ParseFloat(rssiStr, 64); err == nil {
			metrics.RSSI = &rssi
		}
	}

	// Extract SINR (Signal to Interference plus Noise Ratio)
	if sinr, ok := info["sinr"].(float64); ok {
		metrics.SINR = &sinr
	} else if sinrStr, ok := info["sinr"].(string); ok {
		if sinr, err := strconv.ParseFloat(sinrStr, 64); err == nil {
			metrics.SINR = &sinr
		}
	}
}

// fallbackPingMetrics performs interface-bound ping when cellular-specific metrics fail
func (c *CellularCollector) fallbackPingMetrics(ctx context.Context, interfaceName string) (*Metrics, error) {
	metrics := &Metrics{
		InterfaceName: interfaceName,
		Class:         "cellular",
		Timestamp:     time.Now(),
	}

	// Test multiple hosts for redundancy
	hosts := []string{"8.8.8.8", "1.1.1.1", "8.8.4.4"}
	var latencies []float64
	var totalLoss float64
	var successfulPings int

	for _, host := range hosts {
		result, err := c.pingViaInterface(ctx, host, interfaceName)
		if err != nil {
			continue // Try next host
		}

		if result.AvgLatency > 0 {
			latencies = append(latencies, result.AvgLatency)
		}
		totalLoss += result.PacketLoss
		successfulPings++
	}

	if successfulPings == 0 {
		return nil, fmt.Errorf("all ping tests failed for interface %s", interfaceName)
	}

	// Calculate aggregate metrics
	if len(latencies) > 0 {
		avgLatency := c.calculateMean(latencies)
		metrics.Latency = &avgLatency

		// Calculate jitter from latency variation
		jitter := c.calculateJitter(latencies)
		metrics.Jitter = &jitter
	}

	// Average packet loss across hosts
	avgLoss := totalLoss / float64(successfulPings)
	metrics.PacketLoss = &avgLoss

	// Mark as connected if we got any successful pings
	metrics.Connected = true
	metrics.Available = true

	return metrics, nil
}

// PingResult represents ping test results
type PingResult struct {
	AvgLatency float64
	PacketLoss float64
}

// pingViaInterface performs interface-bound ping test
func (c *CellularCollector) pingViaInterface(ctx context.Context, host, interfaceName string) (*PingResult, error) {
	// Use interface-specific ping command
	// On Linux: ping -I interface_name -c 3 -W 5 host
	args := []string{"-I", interfaceName, "-c", "3", "-W", "5", host}

	output, err := c.runner.Output(ctx, "ping", args...)
	if err != nil {
		return nil, fmt.Errorf("ping failed for %s via %s: %w", host, interfaceName, err)
	}

	latency, loss, err := c.parsePingOutput(string(output))
	if err != nil {
		return nil, err
	}

	return &PingResult{
		AvgLatency: latency,
		PacketLoss: loss,
	}, nil
}

// parsePingOutput extracts latency and packet loss from ping command output
func (c *CellularCollector) parsePingOutput(output string) (float64, float64, error) {
	lines := strings.Split(output, "\n")

	var avgLatency, packetLoss float64

	// Look for packet loss line: "3 packets transmitted, 3 received, 0% packet loss"
	for _, line := range lines {
		if strings.Contains(line, "packet loss") {
			fields := strings.Fields(line)
			for i, field := range fields {
				if strings.HasSuffix(field, "%") && i > 0 {
					lossStr := strings.TrimSuffix(field, "%")
					if loss, err := strconv.ParseFloat(lossStr, 64); err == nil {
						packetLoss = loss
					}
					break
				}
			}
		}

		// Look for average latency line: "round-trip min/avg/max = 10.123/15.456/20.789 ms"
		if strings.Contains(line, "round-trip") || strings.Contains(line, "min/avg/max") {
			// Extract the avg value from the format: min/avg/max = X/Y/Z ms
			parts := strings.Split(line, "=")
			if len(parts) >= 2 {
				values := strings.Fields(parts[1])
				if len(values) > 0 {
					// Get the first value set (X/Y/Z)
					valueSet := values[0]
					latencies := strings.Split(valueSet, "/")
					if len(latencies) >= 2 {
						// Take the average (middle value)
						if avg, err := strconv.ParseFloat(latencies[1], 64); err == nil {
							avgLatency = avg
						}
					}
				}
			}
		}
	}

	return avgLatency, packetLoss, nil
}

// calculateMean computes the arithmetic mean of a slice of float64
func (c *CellularCollector) calculateMean(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}

	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}

// calculateJitter computes the jitter (standard deviation) of latency values
func (c *CellularCollector) calculateJitter(latencies []float64) float64 {
	if len(latencies) < 2 {
		return 0
	}

	mean := c.calculateMean(latencies)
	sumSquares := 0.0
	for _, latency := range latencies {
		diff := latency - mean
		sumSquares += diff * diff
	}

	variance := sumSquares / float64(len(latencies))
	return math.Sqrt(variance)
}
