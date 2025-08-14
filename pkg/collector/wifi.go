package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
)

// WiFiCollector collects metrics from WiFi interfaces
type WiFiCollector struct {
	*BaseCollector
	ubusPath string
	timeout  time.Duration
}

// WiFiInfo represents WiFi connection information
type WiFiInfo struct {
	SignalStrength *int    `json:"signal,omitempty"`
	NoiseLevel     *int    `json:"noise,omitempty"`
	SNR            *int    `json:"snr,omitempty"`
	Bitrate        *int    `json:"bitrate,omitempty"`
	SSID           *string `json:"ssid,omitempty"`
	Channel        *int    `json:"channel,omitempty"`
	Mode           *string `json:"mode,omitempty"`
}

// NewWiFiCollector creates a new WiFi collector
func NewWiFiCollector(config map[string]interface{}) (*WiFiCollector, error) {
	timeout := 5 * time.Second
	if t, ok := config["timeout"].(time.Duration); ok {
		timeout = t
	}

	ubusPath := "ubus"
	if p, ok := config["ubus_path"].(string); ok {
		ubusPath = p
	}

	targets := []string{"8.8.8.8", "1.1.1.1"}
	if t, ok := config["targets"].([]string); ok {
		targets = t
	}

	return &WiFiCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
		ubusPath:      ubusPath,
		timeout:       timeout,
	}, nil
}

// Collect collects metrics from WiFi interface
func (wc *WiFiCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := wc.Validate(member); err != nil {
		return nil, err
	}

	// Start with common metrics
	metrics, err := wc.CollectCommonMetrics(ctx, member)
	if err != nil {
		return nil, err
	}

	// Collect WiFi-specific metrics
	wifiInfo, err := wc.collectWiFiInfo(ctx, member)
	if err != nil {
		// Log error but don't fail - continue with common metrics
		fmt.Printf("Warning: Failed to collect WiFi metrics for %s: %v\n", member.Name, err)
	} else {
		// Merge WiFi metrics
		metrics.SignalStrength = wifiInfo.SignalStrength
		metrics.NoiseLevel = wifiInfo.NoiseLevel
		metrics.SNR = wifiInfo.SNR
		metrics.Bitrate = wifiInfo.Bitrate
	}

	return metrics, nil
}

// collectWiFiInfo collects WiFi-specific information via ubus iwinfo
func (wc *WiFiCollector) collectWiFiInfo(ctx context.Context, member *pkg.Member) (*WiFiInfo, error) {
	info := &WiFiInfo{}

	// Try to get WiFi info via ubus iwinfo
	if wifiData, err := wc.queryIwinfo(ctx, member.Iface); err == nil {
		if err := wc.parseWiFiData(wifiData, info); err == nil {
			return info, nil
		}
	}

	// Fallback: try to get basic info from /proc/net/wireless
	if err := wc.collectFallbackInfo(ctx, member, info); err != nil {
		return nil, fmt.Errorf("failed to collect WiFi info: %w", err)
	}

	return info, nil
}

// queryIwinfo queries WiFi information via ubus iwinfo
func (wc *WiFiCollector) queryIwinfo(ctx context.Context, iface string) (map[string]interface{}, error) {
	// Create context with timeout
	ctx, cancel := context.WithTimeout(ctx, wc.timeout)
	defer cancel()

	// Try to call ubus iwinfo
	cmd := exec.CommandContext(ctx, wc.ubusPath, "call", "iwinfo", "info", fmt.Sprintf(`{"device":"%s"}`, iface))
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ubus iwinfo call failed: %w", err)
	}

	// Parse JSON response
	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse iwinfo response: %w", err)
	}

	return result, nil
}

// parseWiFiData parses WiFi data from ubus response
func (wc *WiFiCollector) parseWiFiData(data map[string]interface{}, info *WiFiInfo) error {
	// Try to extract signal strength
	if signal, ok := data["signal"].(float64); ok {
		signalInt := int(signal)
		info.SignalStrength = &signalInt
	}

	// Try to extract noise level
	if noise, ok := data["noise"].(float64); ok {
		noiseInt := int(noise)
		info.NoiseLevel = &noiseInt
	}

	// Try to extract bitrate
	if bitrate, ok := data["bitrate"].(float64); ok {
		bitrateInt := int(bitrate)
		info.Bitrate = &bitrateInt
	}

	// Try to extract SSID
	if ssid, ok := data["ssid"].(string); ok {
		info.SSID = &ssid
	}

	// Try to extract channel
	if channel, ok := data["channel"].(float64); ok {
		channelInt := int(channel)
		info.Channel = &channelInt
	}

	// Try to extract mode
	if mode, ok := data["mode"].(string); ok {
		info.Mode = &mode
	}

	// Calculate SNR if we have both signal and noise
	if info.SignalStrength != nil && info.NoiseLevel != nil {
		snr := *info.SignalStrength - *info.NoiseLevel
		info.SNR = &snr
	}

	return nil
}

// collectFallbackInfo collects basic WiFi info from /proc/net/wireless
func (wc *WiFiCollector) collectFallbackInfo(ctx context.Context, member *pkg.Member, info *WiFiInfo) error {
	// Try to read from /proc/net/wireless
	if wirelessData, err := wc.readWirelessFile(); err == nil {
		if wifiData := wc.parseWirelessFile(wirelessData, member.Iface); wifiData != nil {
			info.SignalStrength = wifiData.SignalStrength
			info.NoiseLevel = wifiData.NoiseLevel
			info.SNR = wifiData.SNR
			info.Bitrate = wifiData.Bitrate
		} else {
			fmt.Printf("Debug: no wireless stats found for %s\n", member.Iface)
		}
	} else {
		fmt.Printf("Warning: failed to read /proc/net/wireless: %v\n", err)
	}

	return nil
}

// readWirelessFile reads /proc/net/wireless
func (wc *WiFiCollector) readWirelessFile() (string, error) {
	data, err := os.ReadFile("/proc/net/wireless")
	if err != nil {
		return "", fmt.Errorf("read /proc/net/wireless: %w", err)
	}
	return string(data), nil
}

// parseWirelessFile parses /proc/net/wireless format
func (wc *WiFiCollector) parseWirelessFile(data, iface string) *WiFiInfo {
	lines := strings.Split(data, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, iface) {
			continue
		}

		fields := strings.Fields(line)
		// Expected: iface: status link level noise ...
		if len(fields) < 5 {
			return nil
		}

		levelStr := strings.TrimSuffix(fields[3], ".")
		noiseStr := strings.TrimSuffix(fields[4], ".")

		levelF, err1 := strconv.ParseFloat(levelStr, 64)
		noiseF, err2 := strconv.ParseFloat(noiseStr, 64)
		if err1 != nil || err2 != nil {
			return nil
		}

		level := int(levelF)
		noise := int(noiseF)
		snr := level - noise

		return &WiFiInfo{
			SignalStrength: &level,
			NoiseLevel:     &noise,
			SNR:            &snr,
		}
	}

	return nil
}

// Validate validates a member for the WiFi collector
func (wc *WiFiCollector) Validate(member *pkg.Member) error {
	if err := wc.BaseCollector.Validate(member); err != nil {
		return err
	}

	// Additional WiFi-specific validation
	if member.Class != pkg.ClassWiFi {
		return fmt.Errorf("member class must be wifi, got %s", member.Class)
	}

	return nil
}

// TestWiFiConnectivity tests if we can get WiFi information
func (wc *WiFiCollector) TestWiFiConnectivity(ctx context.Context, member *pkg.Member) error {
	// Try to get basic WiFi info
	info, err := wc.collectWiFiInfo(ctx, member)
	if err != nil {
		return fmt.Errorf("failed to collect WiFi info: %w", err)
	}

	// Check if we got any meaningful data
	if info.SignalStrength == nil && info.SNR == nil {
		return fmt.Errorf("no WiFi metrics available")
	}

	return nil
}

// GetWiFiInfo returns detailed WiFi information
func (wc *WiFiCollector) GetWiFiInfo(ctx context.Context, member *pkg.Member) (map[string]interface{}, error) {
	info, err := wc.collectWiFiInfo(ctx, member)
	if err != nil {
		return nil, err
	}

	result := make(map[string]interface{})

	if info.SignalStrength != nil {
		result["signal"] = *info.SignalStrength
	}
	if info.NoiseLevel != nil {
		result["noise"] = *info.NoiseLevel
	}
	if info.SNR != nil {
		result["snr"] = *info.SNR
	}
	if info.Bitrate != nil {
		result["bitrate"] = *info.Bitrate
	}
	if info.SSID != nil {
		result["ssid"] = *info.SSID
	}
	if info.Channel != nil {
		result["channel"] = *info.Channel
	}
	if info.Mode != nil {
		result["mode"] = *info.Mode
	}

	return result, nil
}

// GetSignalQuality returns a signal quality score based on WiFi metrics
func (wc *WiFiCollector) GetSignalQuality(signal, noise, snr *int) float64 {
	// Calculate signal quality score (0-100)
	score := 50.0 // Base score

	if signal != nil {
		// WiFi signal strength typically ranges from -100 to -30 dBm
		// Convert to 0-100 scale
		signalScore := float64(*signal+100) / 70.0 * 100
		if signalScore > 100 {
			signalScore = 100
		} else if signalScore < 0 {
			signalScore = 0
		}
		score = score*0.3 + signalScore*0.7
	}

	if snr != nil {
		// SNR typically ranges from 0 to 40 dB
		// Convert to 0-100 scale
		snrScore := float64(*snr) / 40.0 * 100
		if snrScore > 100 {
			snrScore = 100
		} else if snrScore < 0 {
			snrScore = 0
		}
		score = score*0.6 + snrScore*0.4
	}

	return score
}

// GetBitrateQuality returns a bitrate quality score
func (wc *WiFiCollector) GetBitrateQuality(bitrate *int) float64 {
	if bitrate == nil {
		return 50.0 // Default score
	}

	// Bitrate quality based on typical WiFi speeds
	// Assuming 802.11n/g speeds
	bitrateMbps := float64(*bitrate) / 1000000 // Convert to Mbps

	if bitrateMbps >= 100 {
		return 100.0 // Excellent
	} else if bitrateMbps >= 50 {
		return 80.0 // Good
	} else if bitrateMbps >= 25 {
		return 60.0 // Fair
	} else if bitrateMbps >= 10 {
		return 40.0 // Poor
	} else {
		return 20.0 // Very poor
	}
}

// IsWiFiInterface checks if an interface is a WiFi interface
func (wc *WiFiCollector) IsWiFiInterface(iface string) bool {
	// Check if interface name matches WiFi patterns
	wifiPatterns := []string{"wlan", "wifi", "ath", "radio"}

	ifaceLower := strings.ToLower(iface)
	for _, pattern := range wifiPatterns {
		if strings.Contains(ifaceLower, pattern) {
			return true
		}
	}

	return false
}

// GetWiFiChannels returns available WiFi channels for the interface
func (wc *WiFiCollector) GetWiFiChannels(ctx context.Context, iface string) ([]int, error) {
	// Try to get channel information via ubus
	if wifiData, err := wc.queryIwinfo(ctx, iface); err == nil {
		if channels, ok := wifiData["channels"].([]interface{}); ok {
			result := make([]int, 0, len(channels))
			for _, ch := range channels {
				if channel, ok := ch.(float64); ok {
					result = append(result, int(channel))
				}
			}
			return result, nil
		}
	}

	return nil, fmt.Errorf("failed to get WiFi channels")
}

// GetWiFiModes returns available WiFi modes for the interface
func (wc *WiFiCollector) GetWiFiModes(ctx context.Context, iface string) ([]string, error) {
	// Try to get mode information via ubus
	if wifiData, err := wc.queryIwinfo(ctx, iface); err == nil {
		if modes, ok := wifiData["modes"].([]interface{}); ok {
			result := make([]string, 0, len(modes))
			for _, m := range modes {
				if mode, ok := m.(string); ok {
					result = append(result, mode)
				}
			}
			return result, nil
		}
	}

	return nil, fmt.Errorf("failed to get WiFi modes")
}
