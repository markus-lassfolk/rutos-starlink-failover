// Package collector implements WiFi-specific metric collection via ubus iwinfo
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

// WiFiCollector collects metrics from WiFi interfaces via ubus iwinfo
type WiFiCollector struct {
	pingCollector *PingCollector // Fallback for connectivity metrics
	runner        *retry.Runner  // For external command reliability
}

// NewWiFiCollector creates a new WiFi metrics collector
func NewWiFiCollector(pingHosts []string) *WiFiCollector {
	// Conservative retry config for WiFi ubus/iwconfig operations
	retryConfig := retry.Config{
		MaxAttempts:   3,
		InitialDelay:  500 * time.Millisecond,
		MaxDelay:      2 * time.Second,
		BackoffFactor: 1.5,
	}

	return &WiFiCollector{
		pingCollector: NewPingCollector(pingHosts),
		runner:        retry.NewRunner(retryConfig),
	}
}

// Class returns the interface class this collector handles
func (w *WiFiCollector) Class() string {
	return "wifi"
}

// SupportsInterface checks if this collector can handle the given interface
func (w *WiFiCollector) SupportsInterface(interfaceName string) bool {
	// Common WiFi interface patterns
	patterns := []string{"wlan", "ath", "ra", "wl", "wifi", "radio"}

	ifLower := strings.ToLower(interfaceName)
	for _, pattern := range patterns {
		if strings.Contains(ifLower, pattern) {
			return true
		}
	}

	return false
}

// Collect gathers metrics for the given WiFi member
func (w *WiFiCollector) Collect(ctx context.Context, member Member) (Metrics, error) {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: member.InterfaceName,
		Class:         "wifi",
	}

	// Get WiFi-specific metrics via iwinfo
	wifiData, err := w.getWiFiData(ctx, member.InterfaceName)
	if err != nil {
		// Log error but continue with ping metrics
		// TODO: Use logger when available
	}

	// Get connectivity metrics via ping
	pingMetrics, err := w.pingCollector.Collect(ctx, member)
	if err == nil {
		metrics.LatencyMs = pingMetrics.LatencyMs
		metrics.PacketLossPct = pingMetrics.PacketLossPct
		metrics.JitterMs = pingMetrics.JitterMs
	}

	// Add WiFi-specific metrics if available
	if wifiData != nil {
		metrics.Signal = wifiData.Signal
		metrics.Noise = wifiData.Noise
		metrics.Bitrate = wifiData.Bitrate
	}

	return metrics, nil
}

// WiFiData represents parsed WiFi interface telemetry
type WiFiData struct {
	Signal     *float64 `json:"signal"`     // Signal strength in dBm
	Noise      *float64 `json:"noise"`      // Noise level in dBm
	Bitrate    *float64 `json:"bitrate"`    // Current bitrate in Mbps
	Quality    *float64 `json:"quality"`    // Link quality percentage
	SSID       *string  `json:"ssid"`       // Connected SSID
	BSSID      *string  `json:"bssid"`      // AP MAC address
	Channel    *int     `json:"channel"`    // WiFi channel
	Frequency  *int     `json:"frequency"`  // Frequency in MHz
	Mode       *string  `json:"mode"`       // STA/AP/Monitor mode
	Encryption *string  `json:"encryption"` // Security type
}

// getWiFiData fetches WiFi telemetry via ubus iwinfo
func (w *WiFiCollector) getWiFiData(ctx context.Context, interfaceName string) (*WiFiData, error) {
	// Try ubus iwinfo first
	if data, err := w.getIWInfoData(ctx, interfaceName); err == nil {
		return data, nil
	}

	// Fallback to iwconfig parsing
	if data, err := w.getIWConfigData(ctx, interfaceName); err == nil {
		return data, nil
	}

	return nil, fmt.Errorf("no WiFi data sources available for %s", interfaceName)
}

// getIWInfoData gets WiFi data from ubus iwinfo service
func (w *WiFiCollector) getIWInfoData(ctx context.Context, interfaceName string) (*WiFiData, error) {
	output, err := w.runner.Output(ctx, "ubus", "call", "iwinfo", "info",
		fmt.Sprintf(`{"device":"%s"}`, interfaceName))
	if err != nil {
		return nil, fmt.Errorf("failed to call iwinfo: %w", err)
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse iwinfo data: %w", err)
	}

	data := &WiFiData{}
	w.parseIWInfoData(info, data)

	return data, nil
}

// getIWConfigData gets WiFi data from iwconfig command as fallback
func (w *WiFiCollector) getIWConfigData(ctx context.Context, interfaceName string) (*WiFiData, error) {
	output, err := w.runner.Output(ctx, "iwconfig", interfaceName)
	if err != nil {
		return nil, fmt.Errorf("failed to run iwconfig: %w", err)
	}

	data := &WiFiData{}
	w.parseIWConfigData(string(output), data)

	return data, nil
}

// parseIWInfoData extracts metrics from iwinfo ubus response
func (w *WiFiCollector) parseIWInfoData(info map[string]interface{}, data *WiFiData) {
	// Signal strength
	if val, ok := info["signal"]; ok {
		if f, err := w.parseFloat(val); err == nil {
			data.Signal = &f
		}
	}

	// Noise level
	if val, ok := info["noise"]; ok {
		if f, err := w.parseFloat(val); err == nil {
			data.Noise = &f
		}
	}

	// Bitrate
	if val, ok := info["bitrate"]; ok {
		if f, err := w.parseFloat(val); err == nil {
			// Convert from kbps to Mbps
			bitrateMbps := f / 1000.0
			data.Bitrate = &bitrateMbps
		}
	}

	// Quality
	if val, ok := info["quality"]; ok {
		if f, err := w.parseFloat(val); err == nil {
			data.Quality = &f
		}
	}

	// SSID
	if val, ok := info["ssid"]; ok {
		if s, ok := val.(string); ok {
			data.SSID = &s
		}
	}

	// BSSID
	if val, ok := info["bssid"]; ok {
		if s, ok := val.(string); ok {
			data.BSSID = &s
		}
	}

	// Channel
	if val, ok := info["channel"]; ok {
		if i, err := w.parseInt(val); err == nil {
			data.Channel = &i
		}
	}

	// Frequency
	if val, ok := info["frequency"]; ok {
		if i, err := w.parseInt(val); err == nil {
			data.Frequency = &i
		}
	}

	// Mode
	if val, ok := info["mode"]; ok {
		if s, ok := val.(string); ok {
			data.Mode = &s
		}
	}

	// Encryption
	if val, ok := info["encryption"]; ok {
		if enc, ok := val.(map[string]interface{}); ok {
			if enabled, ok := enc["enabled"].(bool); ok && enabled {
				if description, ok := enc["description"].(string); ok {
					data.Encryption = &description
				}
			} else {
				none := "none"
				data.Encryption = &none
			}
		}
	}
}

// parseIWConfigData extracts metrics from iwconfig command output
func (w *WiFiCollector) parseIWConfigData(output string, data *WiFiData) {
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)

		// Parse signal and noise: "Link Quality=70/70  Signal level=-30 dBm  Noise level=-85 dBm"
		if strings.Contains(line, "Signal level") {
			w.parseSignalLine(line, data)
		}

		// Parse bitrate: "Bit Rate=54 Mb/s   Tx-Power=20 dBm"
		if strings.Contains(line, "Bit Rate") {
			w.parseBitrateLine(line, data)
		}

		// Parse ESSID: "ESSID:"MyNetwork""
		if strings.Contains(line, "ESSID:") {
			w.parseESSIDLine(line, data)
		}

		// Parse Access Point: "Access Point: 00:11:22:33:44:55"
		if strings.Contains(line, "Access Point:") {
			w.parseAccessPointLine(line, data)
		}
	}
}

// parseSignalLine extracts signal and noise from iwconfig signal line
func (w *WiFiCollector) parseSignalLine(line string, data *WiFiData) {
	// Example: "Link Quality=70/70  Signal level=-30 dBm  Noise level=-85 dBm"

	if strings.Contains(line, "Signal level=") {
		parts := strings.Split(line, "Signal level=")
		if len(parts) > 1 {
			signalPart := strings.Fields(parts[1])[0]
			signalPart = strings.TrimSuffix(signalPart, " dBm")
			if signal, err := strconv.ParseFloat(signalPart, 64); err == nil {
				data.Signal = &signal
			}
		}
	}

	if strings.Contains(line, "Noise level=") {
		parts := strings.Split(line, "Noise level=")
		if len(parts) > 1 {
			noisePart := strings.Fields(parts[1])[0]
			noisePart = strings.TrimSuffix(noisePart, " dBm")
			if noise, err := strconv.ParseFloat(noisePart, 64); err == nil {
				data.Noise = &noise
			}
		}
	}
}

// parseBitrateLine extracts bitrate from iwconfig bitrate line
func (w *WiFiCollector) parseBitrateLine(line string, data *WiFiData) {
	// Example: "Bit Rate=54 Mb/s   Tx-Power=20 dBm"

	if strings.Contains(line, "Bit Rate=") {
		parts := strings.Split(line, "Bit Rate=")
		if len(parts) > 1 {
			bitratePart := strings.Fields(parts[1])[0]
			bitratePart = strings.TrimSuffix(bitratePart, " Mb/s")
			if bitrate, err := strconv.ParseFloat(bitratePart, 64); err == nil {
				data.Bitrate = &bitrate
			}
		}
	}
}

// parseESSIDLine extracts SSID from iwconfig ESSID line
func (w *WiFiCollector) parseESSIDLine(line string, data *WiFiData) {
	// Example: ESSID:"MyNetwork"

	if strings.Contains(line, "ESSID:") {
		parts := strings.Split(line, "ESSID:")
		if len(parts) > 1 {
			ssid := strings.TrimSpace(parts[1])
			ssid = strings.Trim(ssid, `"`)
			if ssid != "" && ssid != "off/any" {
				data.SSID = &ssid
			}
		}
	}
}

// parseAccessPointLine extracts BSSID from iwconfig Access Point line
func (w *WiFiCollector) parseAccessPointLine(line string, data *WiFiData) {
	// Example: "Access Point: 00:11:22:33:44:55"

	if strings.Contains(line, "Access Point:") {
		parts := strings.Split(line, "Access Point:")
		if len(parts) > 1 {
			bssid := strings.TrimSpace(parts[1])
			if bssid != "" && bssid != "Not-Associated" {
				data.BSSID = &bssid
			}
		}
	}
}

// parseFloat safely converts interface{} to float64
func (w *WiFiCollector) parseFloat(val interface{}) (float64, error) {
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

// parseInt safely converts interface{} to int
func (w *WiFiCollector) parseInt(val interface{}) (int, error) {
	switch v := val.(type) {
	case int:
		return v, nil
	case float64:
		return int(v), nil
	case string:
		return strconv.Atoi(v)
	default:
		return 0, fmt.Errorf("cannot convert %T to int", val)
	}
}
