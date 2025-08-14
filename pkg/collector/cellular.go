// Package collector implements cellular-specific metric collection via ubus
package collector

import (
	"context"
	"encoding/json"
	"fmt"
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

// Collect gathers metrics for the given cellular member
func (c *CellularCollector) Collect(ctx context.Context, member Member) (Metrics, error) {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: member.InterfaceName,
		Class:         "cellular",
	}

	// Try to get cellular metrics via ubus
	cellularData, err := c.getCellularData(ctx)
	if err != nil {
		// Fallback to basic ping metrics if cellular-specific data unavailable
		return c.fallbackPingMetrics(ctx, member)
	}

	// Set cellular-specific metrics
	if cellularData != nil {
		metrics.RSSI = cellularData.RSSI
		metrics.RSRP = cellularData.RSRP
		metrics.RSRQ = cellularData.RSRQ
		metrics.SINR = cellularData.SINR
		metrics.NetworkType = cellularData.NetworkType
		metrics.Roaming = cellularData.Roaming

		// Convert signal strength to quality score for latency approximation
		if cellularData.RSSI != nil {
			// Rough approximation: better signal = lower latency
			rssi := *cellularData.RSSI
			estimatedLatency := c.estimateLatencyFromRSSI(rssi)
			metrics.LatencyMs = &estimatedLatency
		}
	}

	return metrics, nil
}

// CellularData represents parsed cellular modem telemetry
type CellularData struct {
	RSSI        *float64 `json:"rssi"`         // Signal strength
	RSRP        *float64 `json:"rsrp"`         // Reference Signal Received Power
	RSRQ        *float64 `json:"rsrq"`         // Reference Signal Received Quality
	SINR        *float64 `json:"sinr"`         // Signal-to-Interference-plus-Noise Ratio
	NetworkType *string  `json:"network_type"` // 2G/3G/4G/5G
	Roaming     *bool    `json:"roaming"`      // Roaming status
	Provider    *string  `json:"provider"`     // Network operator
	IMEI        *string  `json:"imei"`         // Device IMEI
	State       *string  `json:"state"`        // Connection state
}

// getCellularData fetches telemetry from ubus mobiled or GSM providers
func (c *CellularCollector) getCellularData(ctx context.Context) (*CellularData, error) {
	// Try provider-specific interface if specified
	if c.provider != "" {
		if data, err := c.getProviderData(ctx, c.provider); err == nil {
			return data, nil
		}
	}

	// Try mobiled interface (newer RutOS)
	if data, err := c.getMobiledData(ctx); err == nil {
		return data, nil
	}

	// Try specific GSM modem interface (common pattern: gsm.modem0)
	if data, err := c.getGSMModemData(ctx, "gsm.modem0"); err == nil {
		return data, nil
	}

	// Try generic GSM ubus interface
	if data, err := c.getGSMData(ctx); err == nil {
		return data, nil
	}

	return nil, fmt.Errorf("no cellular data sources available")
}

// getMobiledData gets data from RutOS mobiled ubus service
func (c *CellularCollector) getMobiledData(ctx context.Context) (*CellularData, error) {
	// Get mobile interface info
	output, err := c.runner.Output(ctx, "ubus", "call", "mobiled", "get_interfaces")
	if err != nil {
		return nil, fmt.Errorf("failed to call mobiled: %w", err)
	}

	var interfaces map[string]interface{}
	if err := json.Unmarshal(output, &interfaces); err != nil {
		return nil, fmt.Errorf("failed to parse mobiled interfaces: %w", err)
	}

	// Find the first available interface
	var interfaceID string
	if ifaces, ok := interfaces["interfaces"].(map[string]interface{}); ok {
		for id := range ifaces {
			interfaceID = id
			break
		}
	}

	if interfaceID == "" {
		return nil, fmt.Errorf("no mobile interfaces found")
	}

	// Get detailed info for the interface
	output, err = c.runner.Output(ctx, "ubus", "call", "mobiled", "get_interface_info",
		fmt.Sprintf(`{"interface":"%s"}`, interfaceID))
	if err != nil {
		return nil, fmt.Errorf("failed to get interface info: %w", err)
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse interface info: %w", err)
	}

	// Extract cellular metrics
	data := &CellularData{}
	c.parseMobiledInfo(info, data)

	return data, nil
}

// getProviderData gets data from a specific provider interface
func (c *CellularCollector) getProviderData(ctx context.Context, provider string) (*CellularData, error) {
	output, err := c.runner.Output(ctx, "ubus", "call", provider, "info")
	if err != nil {
		return nil, fmt.Errorf("failed to call provider %s: %w", provider, err)
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse provider info: %w", err)
	}

	data := &CellularData{}
	c.parseGSMModemInfo(info, data)
	return data, nil
}

// getGSMModemData gets data from specific GSM modem interface (e.g., gsm.modem0)
func (c *CellularCollector) getGSMModemData(ctx context.Context, modemInterface string) (*CellularData, error) {
	output, err := c.runner.Output(ctx, "ubus", "call", modemInterface, "info")
	if err != nil {
		return nil, fmt.Errorf("failed to call %s: %w", modemInterface, err)
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse modem info: %w", err)
	}

	data := &CellularData{}
	c.parseGSMModemInfo(info, data)
	return data, nil
}

// getGSMData gets data from generic GSM ubus interface
func (c *CellularCollector) getGSMData(ctx context.Context) (*CellularData, error) {
	output, err := c.runner.Output(ctx, "ubus", "call", "gsm", "info")
	if err != nil {
		return nil, fmt.Errorf("failed to call gsm: %w", err)
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse gsm info: %w", err)
	}

	data := &CellularData{}
	c.parseGSMInfo(info, data)

	return data, nil
}

// parseMobiledInfo extracts metrics from mobiled ubus response
func (c *CellularCollector) parseMobiledInfo(info map[string]interface{}, data *CellularData) {
	// Extract signal strength metrics
	if val, ok := info["rssi"]; ok {
		if f, err := c.parseFloat(val); err == nil {
			data.RSSI = &f
		}
	}

	if val, ok := info["rsrp"]; ok {
		if f, err := c.parseFloat(val); err == nil {
			data.RSRP = &f
		}
	}

	if val, ok := info["rsrq"]; ok {
		if f, err := c.parseFloat(val); err == nil {
			data.RSRQ = &f
		}
	}

	if val, ok := info["sinr"]; ok {
		if f, err := c.parseFloat(val); err == nil {
			data.SINR = &f
		}
	}

	// Network type and roaming
	if val, ok := info["network_type"]; ok {
		if s, ok := val.(string); ok {
			data.NetworkType = &s
		}
	}

	if val, ok := info["roaming"]; ok {
		if b, ok := val.(bool); ok {
			data.Roaming = &b
		}
	}

	if val, ok := info["provider"]; ok {
		if s, ok := val.(string); ok {
			data.Provider = &s
		}
	}

	if val, ok := info["state"]; ok {
		if s, ok := val.(string); ok {
			data.State = &s
		}
	}
}

// parseGSMInfo extracts metrics from generic GSM ubus response
func (c *CellularCollector) parseGSMInfo(info map[string]interface{}, data *CellularData) {
	// Similar parsing for generic GSM interface
	if val, ok := info["signal"]; ok {
		if f, err := c.parseFloat(val); err == nil {
			data.RSSI = &f
		}
	}

	if val, ok := info["access_technology"]; ok {
		if s, ok := val.(string); ok {
			data.NetworkType = &s
		}
	}
}

// parseGSMModemInfo extracts metrics from detailed GSM modem response (e.g., gsm.modem0)
func (c *CellularCollector) parseGSMModemInfo(info map[string]interface{}, data *CellularData) {
	// Extract signal strength from cache
	if cache, ok := info["cache"].(map[string]interface{}); ok {
		if val, ok := cache["rsrp_value"]; ok {
			if f, err := c.parseFloat(val); err == nil {
				data.RSRP = &f
			}
		}

		if val, ok := cache["rsrq_value"]; ok {
			if f, err := c.parseFloat(val); err == nil {
				data.RSRQ = &f
			}
		}

		if val, ok := cache["sinr_value"]; ok {
			if f, err := c.parseFloat(val); err == nil {
				data.SINR = &f
			}
		}

		if val, ok := cache["rssi_value"]; ok {
			if f, err := c.parseFloat(val); err == nil {
				data.RSSI = &f
			}
		}

		if val, ok := cache["net_mode_str"]; ok {
			if s, ok := val.(string); ok {
				data.NetworkType = &s
			}
		}

		if val, ok := cache["provider_name"]; ok {
			if s, ok := val.(string); ok {
				data.Provider = &s
			}
		}

		// Note: Band and Temperature fields not available in CellularData struct
		// Consider adding them to the struct if needed for monitoring

		// Parse network mode
		if val, ok := cache["net_mode_str"]; ok {
			if s, ok := val.(string); ok {
				data.NetworkType = &s
			}
		}
	}

	// Note: Model field not available in CellularData struct
	// Consider adding it if device identification is needed
}

// parseFloat safely converts interface{} to float64
func (c *CellularCollector) parseFloat(val interface{}) (float64, error) {
	switch v := val.(type) {
	case float64:
		return v, nil
	case int:
		return float64(v), nil
	case string:
		return strconv.ParseFloat(v, 64)
	default:
		return 0, fmt.Errorf("cannot convert %T to float64", val)
	}
}

// estimateLatencyFromRSSI provides rough latency estimate based on signal strength
func (c *CellularCollector) estimateLatencyFromRSSI(rssi float64) float64 {
	// Very rough approximation:
	// Excellent signal (-40 to -60 dBm): ~50-100ms
	// Good signal (-60 to -80 dBm): ~100-200ms
	// Fair signal (-80 to -100 dBm): ~200-400ms
	// Poor signal (-100+ dBm): ~400+ ms

	if rssi >= -60 {
		return 75 // Excellent
	} else if rssi >= -80 {
		return 150 // Good
	} else if rssi >= -100 {
		return 300 // Fair
	} else {
		return 500 // Poor
	}
}

// fallbackPingMetrics provides basic ping-based metrics if cellular-specific data unavailable
func (c *CellularCollector) fallbackPingMetrics(ctx context.Context, member Member) (Metrics, error) {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: member.InterfaceName,
		Class:         "cellular",
	}

	// Basic ping test using the interface
	// TODO: Implement ping via specific interface
	// For now, return empty metrics

	return metrics, nil
}
