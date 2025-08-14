package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
)

// CellularCollector collects metrics from cellular interfaces
type CellularCollector struct {
	*BaseCollector
	ubusPath string
	timeout  time.Duration
}

// CellularInfo represents cellular connection information
type CellularInfo struct {
	RSRP        *int    `json:"rsrp,omitempty"`
	RSRQ        *int    `json:"rsrq,omitempty"`
	SINR        *int    `json:"sinr,omitempty"`
	NetworkType *string `json:"network_type,omitempty"`
	Roaming     *bool   `json:"roaming,omitempty"`
	Operator    *string `json:"operator,omitempty"`
	Band        *string `json:"band,omitempty"`
	CellID      *string `json:"cell_id,omitempty"`
}

// NewCellularCollector creates a new cellular collector
func NewCellularCollector(config map[string]interface{}) (*CellularCollector, error) {
	timeout := 8 * time.Second // Cellular can be slower
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

	return &CellularCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
		ubusPath:      ubusPath,
		timeout:       timeout,
	}, nil
}

// Collect collects metrics from cellular interface
func (cc *CellularCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := cc.Validate(member); err != nil {
		return nil, err
	}

	// Start with common metrics
	metrics, err := cc.CollectCommonMetrics(ctx, member)
	if err != nil {
		return nil, err
	}

	// Collect cellular-specific metrics
	cellularInfo, err := cc.collectCellularInfo(ctx, member)
	if err != nil {
		// Log error but don't fail - continue with common metrics
		fmt.Printf("Warning: Failed to collect cellular metrics for %s: %v\n", member.Name, err)
	} else {
		// Merge cellular metrics
		metrics.RSRP = cellularInfo.RSRP
		metrics.RSRQ = cellularInfo.RSRQ
		metrics.SINR = cellularInfo.SINR
		metrics.NetworkType = cellularInfo.NetworkType
		metrics.Roaming = cellularInfo.Roaming
		metrics.Operator = cellularInfo.Operator
		metrics.Band = cellularInfo.Band
		metrics.CellID = cellularInfo.CellID
	}

	return metrics, nil
}

// collectCellularInfo collects cellular-specific information via ubus
func (cc *CellularCollector) collectCellularInfo(ctx context.Context, member *pkg.Member) (*CellularInfo, error) {
	info := &CellularInfo{}

	// Try different ubus providers based on RutOS/OpenWrt variants
	providers := []string{"mobiled", "gsm", "modem"}

	for _, provider := range providers {
		if cellularData, err := cc.queryUbusProvider(ctx, provider, member.Iface); err == nil {
			// Parse the response and extract metrics
			if err := cc.parseCellularData(cellularData, info); err == nil {
				return info, nil
			}
		}
	}

	// Fallback: try to get basic info from sysfs or proc
	if err := cc.collectFallbackInfo(ctx, member, info); err != nil {
		return nil, fmt.Errorf("failed to collect cellular info: %w", err)
	}

	return info, nil
}

// queryUbusProvider queries a specific ubus provider
func (cc *CellularCollector) queryUbusProvider(ctx context.Context, provider, iface string) (map[string]interface{}, error) {
	// Create context with timeout
	ctx, cancel := context.WithTimeout(ctx, cc.timeout)
	defer cancel()

	// Try to call ubus
	cmd := exec.CommandContext(ctx, cc.ubusPath, "call", provider, "status")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ubus call failed: %w", err)
	}

	// Parse JSON response
	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("failed to parse ubus response: %w", err)
	}

	return result, nil
}

// parseCellularData parses cellular data from ubus response
func (cc *CellularCollector) parseCellularData(data map[string]interface{}, info *CellularInfo) error {
	// Try to extract RSRP
	if rsrp, ok := data["rsrp"].(float64); ok {
		rsrpInt := int(rsrp)
		info.RSRP = &rsrpInt
	}

	// Try to extract RSRQ
	if rsrq, ok := data["rsrq"].(float64); ok {
		rsrqInt := int(rsrq)
		info.RSRQ = &rsrqInt
	}

	// Try to extract SINR
	if sinr, ok := data["sinr"].(float64); ok {
		sinrInt := int(sinr)
		info.SINR = &sinrInt
	}

	// Try to extract network type
	if networkType, ok := data["network_type"].(string); ok {
		info.NetworkType = &networkType
	}

	// Try to extract roaming status
	if roaming, ok := data["roaming"].(bool); ok {
		info.Roaming = &roaming
	}

	// Try to extract operator
	if operator, ok := data["operator"].(string); ok {
		info.Operator = &operator
	}

	// Try to extract band
	if band, ok := data["band"].(string); ok {
		info.Band = &band
	}

	// Try to extract cell ID
	if cellID, ok := data["cell_id"].(string); ok {
		info.CellID = &cellID
	}

	return nil
}

// collectFallbackInfo collects basic cellular info from sysfs/proc
func (cc *CellularCollector) collectFallbackInfo(ctx context.Context, member *pkg.Member, info *CellularInfo) error {
	// Try to read from /sys/class/net/<iface>/carrier
	carrierPath := fmt.Sprintf("/sys/class/net/%s/carrier", member.Iface)
	if carrierData, err := cc.readFile(carrierPath); err == nil {
		if strings.TrimSpace(carrierData) == "1" {
			// Interface is up, try to get basic signal info
			cc.collectBasicSignalInfo(member, info)
		}
	}

	return nil
}

// collectBasicSignalInfo collects basic signal information
func (cc *CellularCollector) collectBasicSignalInfo(member *pkg.Member, info *CellularInfo) {
	// Try to read signal strength from various possible locations
	signalPaths := []string{
		fmt.Sprintf("/sys/class/net/%s/signal", member.Iface),
		fmt.Sprintf("/proc/net/wireless"),
	}

	for _, path := range signalPaths {
		if data, err := cc.readFile(path); err == nil {
			if signal := cc.parseSignalFromFile(data, member.Iface); signal != nil {
				// Convert signal to RSRP (rough approximation)
				rsrp := cc.convertSignalToRSRP(*signal)
				info.RSRP = &rsrp
				break
			}
		}
	}
}

// readFile reads a file and returns its contents
func (cc *CellularCollector) readFile(path string) (string, error) {
	// This is a simplified implementation
	// In a real implementation, you'd use os.ReadFile
	return "", fmt.Errorf("file reading not implemented")
}

// parseSignalFromFile parses signal strength from file contents
func (cc *CellularCollector) parseSignalFromFile(data, iface string) *int {
	// First, try to parse the data as a simple integer value
	if val, err := strconv.Atoi(strings.TrimSpace(data)); err == nil {
		return &val
	}

	// Otherwise attempt to parse /proc/net/wireless format
	lines := strings.Split(data, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		// Fix: Use exact interface name matching instead of prefix matching
		// This prevents matching "wwan0" when looking for "wwan"
		if !strings.HasPrefix(line, iface+":") {
			continue
		}

		fields := strings.Fields(line)
		// Expected format: iface: status link level noise ...
		if len(fields) < 4 {
			return nil
		}

		// The level is typically the 4th field
		levelStr := strings.TrimSuffix(fields[3], ".")
		level, err := strconv.ParseFloat(levelStr, 64)
		if err != nil {
			return nil
		}
		lvl := int(level)
		return &lvl
	}

	return nil
}

// convertSignalToRSRP converts signal strength to RSRP
func (cc *CellularCollector) convertSignalToRSRP(signal int) int {
	// Rough conversion from signal strength to RSRP
	// This is a simplified approximation
	if signal > 0 {
		return -50 - signal // Convert to negative RSRP values
	}
	return -120 // Default poor signal
}

// Validate validates a member for the cellular collector
func (cc *CellularCollector) Validate(member *pkg.Member) error {
	if err := cc.BaseCollector.Validate(member); err != nil {
		return err
	}

	// Additional cellular-specific validation
	if member.Class != pkg.ClassCellular {
		return fmt.Errorf("member class must be cellular, got %s", member.Class)
	}

	return nil
}

// TestCellularConnectivity tests if we can get cellular information
func (cc *CellularCollector) TestCellularConnectivity(ctx context.Context, member *pkg.Member) error {
	// Try to get basic cellular info
	info, err := cc.collectCellularInfo(ctx, member)
	if err != nil {
		return fmt.Errorf("failed to collect cellular info: %w", err)
	}

	// Check if we got any meaningful data
	if info.RSRP == nil && info.RSRQ == nil && info.SINR == nil {
		return fmt.Errorf("no cellular metrics available")
	}

	return nil
}

// GetCellularInfo returns detailed cellular information
func (cc *CellularCollector) GetCellularInfo(ctx context.Context, member *pkg.Member) (map[string]interface{}, error) {
	info, err := cc.collectCellularInfo(ctx, member)
	if err != nil {
		return nil, err
	}

	result := make(map[string]interface{})

	if info.RSRP != nil {
		result["rsrp"] = *info.RSRP
	}
	if info.RSRQ != nil {
		result["rsrq"] = *info.RSRQ
	}
	if info.SINR != nil {
		result["sinr"] = *info.SINR
	}
	if info.NetworkType != nil {
		result["network_type"] = *info.NetworkType
	}
	if info.Roaming != nil {
		result["roaming"] = *info.Roaming
	}
	if info.Operator != nil {
		result["operator"] = *info.Operator
	}
	if info.Band != nil {
		result["band"] = *info.Band
	}
	if info.CellID != nil {
		result["cell_id"] = *info.CellID
	}

	return result, nil
}

// GetSignalQuality returns a signal quality score based on cellular metrics
func (cc *CellularCollector) GetSignalQuality(rsrp, rsrq, sinr *int) float64 {
	// Calculate signal quality score (0-100)
	score := 50.0 // Base score

	if rsrp != nil {
		// RSRP ranges from -140 to -44 dBm
		// Convert to 0-100 scale
		rsrpScore := float64(*rsrp+140) / 96.0 * 100
		if rsrpScore > 100 {
			rsrpScore = 100
		} else if rsrpScore < 0 {
			rsrpScore = 0
		}
		score = score*0.4 + rsrpScore*0.6
	}

	if rsrq != nil {
		// RSRQ ranges from -20 to -3 dB
		// Convert to 0-100 scale
		rsrqScore := float64(*rsrq+20) / 17.0 * 100
		if rsrqScore > 100 {
			rsrqScore = 100
		} else if rsrqScore < 0 {
			rsrqScore = 0
		}
		score = score*0.7 + rsrqScore*0.3
	}

	if sinr != nil {
		// SINR ranges from -20 to 30 dB
		// Convert to 0-100 scale
		sinrScore := float64(*sinr+20) / 50.0 * 100
		if sinrScore > 100 {
			sinrScore = 100
		} else if sinrScore < 0 {
			sinrScore = 0
		}
		score = score*0.8 + sinrScore*0.2
	}

	return score
}
