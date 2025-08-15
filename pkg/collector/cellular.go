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

// CellularCollector collects metrics from cellular interfaces
type CellularCollector struct {
	*BaseCollector
	ubusPath string
	timeout  time.Duration
}

// CellularInfo represents comprehensive cellular connection information
type CellularInfo struct {
	// Signal metrics
	RSRP *int `json:"rsrp,omitempty"`
	RSRQ *int `json:"rsrq,omitempty"`
	SINR *int `json:"sinr,omitempty"`
	RSSI *int `json:"rssi,omitempty"`

	// Network information
	NetworkType *string `json:"network_type,omitempty"`
	Roaming     *bool   `json:"roaming,omitempty"`
	Operator    *string `json:"operator,omitempty"`
	Band        *string `json:"band,omitempty"`
	CellID      *string `json:"cell_id,omitempty"`

	// Multi-SIM support
	SimSlot   *int    `json:"sim_slot,omitempty"`
	SimCount  *int    `json:"sim_count,omitempty"`
	ActiveSim *int    `json:"active_sim,omitempty"`
	SimStatus *string `json:"sim_status,omitempty"`

	// Connection details
	ModemType *string  `json:"modem_type,omitempty"` // qmi, mbim, ncm, ppp
	IPAddress *string  `json:"ip_address,omitempty"`
	Gateway   *string  `json:"gateway,omitempty"`
	DNS       []string `json:"dns,omitempty"`

	// Quality metrics
	SignalQuality   *float64 `json:"signal_quality,omitempty"`   // 0-100 score
	ConnectionState *string  `json:"connection_state,omitempty"` // connected, connecting, disconnected

	// Roaming details
	HomeOperator *string `json:"home_operator,omitempty"`
	RoamingType  *string `json:"roaming_type,omitempty"` // national, international

	// Advanced metrics
	TAC    *string `json:"tac,omitempty"`    // Tracking Area Code
	EARFCN *int    `json:"earfcn,omitempty"` // E-UTRA Absolute Radio Frequency Channel Number
	PCI    *int    `json:"pci,omitempty"`    // Physical Cell ID

	// Data usage (if available)
	TxBytes *uint64 `json:"tx_bytes,omitempty"`
	RxBytes *uint64 `json:"rx_bytes,omitempty"`

	// Temperature and power
	Temperature *float64 `json:"temperature,omitempty"`
	PowerLevel  *int     `json:"power_level,omitempty"`
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

// collectCellularInfo collects comprehensive cellular information via multiple methods
func (cc *CellularCollector) collectCellularInfo(ctx context.Context, member *pkg.Member) (*CellularInfo, error) {
	info := &CellularInfo{}

	// Try different ubus providers based on RutOS/OpenWrt variants
	providers := []string{
		"mobiled",           // RutOS primary
		"gsm",               // Alternative RutOS
		"modem",             // OpenWrt
		"network.interface", // Network interface status
		"qmi",               // QMI modem
		"mbim",              // MBIM modem
	}

	var lastError error
	for _, provider := range providers {
		if cellularData, err := cc.queryUbusProvider(ctx, provider, member.Iface); err == nil {
			// Parse the response and extract metrics
			if err := cc.parseCellularData(cellularData, info, provider); err == nil {
				// Successfully parsed data, now enhance with additional info
				cc.enhanceCellularInfo(ctx, member, info)
				return info, nil
			}
			lastError = err
		} else {
			lastError = err
		}
	}

	// Try modem-specific methods
	if err := cc.collectModemSpecificInfo(ctx, member, info); err == nil {
		cc.enhanceCellularInfo(ctx, member, info)
		return info, nil
	}

	// Fallback: try to get basic info from sysfs or proc
	if err := cc.collectFallbackInfo(ctx, member, info); err != nil {
		return nil, fmt.Errorf("failed to collect cellular info from all sources, last error: %w", lastError)
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

// parseCellularData parses cellular data from ubus response with provider-specific handling
func (cc *CellularCollector) parseCellularData(data map[string]interface{}, info *CellularInfo, provider string) error {
	// Set modem type based on provider
	info.ModemType = &provider

	// Parse based on provider type
	switch provider {
	case "mobiled":
		return cc.parseMobiledData(data, info)
	case "gsm":
		return cc.parseGSMData(data, info)
	case "qmi":
		return cc.parseQMIData(data, info)
	case "mbim":
		return cc.parseMBIMData(data, info)
	default:
		return cc.parseGenericData(data, info)
	}
}

// parseMobiledData parses RutOS mobiled provider data
func (cc *CellularCollector) parseMobiledData(data map[string]interface{}, info *CellularInfo) error {
	// Signal metrics
	if rsrp, ok := cc.extractNumber(data, []string{"rsrp", "signal_rsrp", "rsrp_dbm"}); ok {
		info.RSRP = &rsrp
	}

	if rsrq, ok := cc.extractNumber(data, []string{"rsrq", "signal_rsrq", "rsrq_db"}); ok {
		info.RSRQ = &rsrq
	}

	if sinr, ok := cc.extractNumber(data, []string{"sinr", "signal_sinr", "sinr_db"}); ok {
		info.SINR = &sinr
	}

	if rssi, ok := cc.extractNumber(data, []string{"rssi", "signal_rssi"}); ok {
		info.RSSI = &rssi
	}

	// Network information
	if networkType, ok := cc.extractString(data, []string{"network_type", "rat", "access_technology"}); ok {
		info.NetworkType = &networkType
	}

	if operator, ok := cc.extractString(data, []string{"operator", "operator_name", "plmn"}); ok {
		info.Operator = &operator
	}

	if band, ok := cc.extractString(data, []string{"band", "frequency_band"}); ok {
		info.Band = &band
	}

	if cellID, ok := cc.extractString(data, []string{"cell_id", "cid", "cellid"}); ok {
		info.CellID = &cellID
	}

	// Multi-SIM support
	if simSlot, ok := cc.extractNumber(data, []string{"sim_slot", "active_sim"}); ok {
		info.ActiveSim = &simSlot
	}

	if simCount, ok := cc.extractNumber(data, []string{"sim_count", "available_sims"}); ok {
		info.SimCount = &simCount
	}

	if simStatus, ok := cc.extractString(data, []string{"sim_status", "sim_state"}); ok {
		info.SimStatus = &simStatus
	}

	// Roaming detection
	if roaming, ok := cc.extractBool(data, []string{"roaming", "is_roaming"}); ok {
		info.Roaming = &roaming
	}

	if homeOperator, ok := cc.extractString(data, []string{"home_operator", "home_plmn"}); ok {
		info.HomeOperator = &homeOperator
	}

	// Connection state
	if connectionState, ok := cc.extractString(data, []string{"connection_state", "state", "status"}); ok {
		info.ConnectionState = &connectionState
	}

	// Advanced metrics
	if tac, ok := cc.extractString(data, []string{"tac", "tracking_area_code"}); ok {
		info.TAC = &tac
	}

	if earfcn, ok := cc.extractNumber(data, []string{"earfcn", "frequency"}); ok {
		info.EARFCN = &earfcn
	}

	if pci, ok := cc.extractNumber(data, []string{"pci", "physical_cell_id"}); ok {
		info.PCI = &pci
	}

	return nil
}

// parseGSMData parses GSM provider data
func (cc *CellularCollector) parseGSMData(data map[string]interface{}, info *CellularInfo) error {
	// Similar parsing logic for GSM provider
	return cc.parseGenericData(data, info)
}

// parseQMIData parses QMI modem data
func (cc *CellularCollector) parseQMIData(data map[string]interface{}, info *CellularInfo) error {
	// QMI-specific parsing logic
	return cc.parseGenericData(data, info)
}

// parseMBIMData parses MBIM modem data
func (cc *CellularCollector) parseMBIMData(data map[string]interface{}, info *CellularInfo) error {
	// MBIM-specific parsing logic
	return cc.parseGenericData(data, info)
}

// parseGenericData parses generic cellular data
func (cc *CellularCollector) parseGenericData(data map[string]interface{}, info *CellularInfo) error {
	// Basic signal metrics
	if rsrp, ok := cc.extractNumber(data, []string{"rsrp"}); ok {
		info.RSRP = &rsrp
	}

	if rsrq, ok := cc.extractNumber(data, []string{"rsrq"}); ok {
		info.RSRQ = &rsrq
	}

	if sinr, ok := cc.extractNumber(data, []string{"sinr"}); ok {
		info.SINR = &sinr
	}

	// Basic network info
	if networkType, ok := cc.extractString(data, []string{"network_type"}); ok {
		info.NetworkType = &networkType
	}

	if roaming, ok := cc.extractBool(data, []string{"roaming"}); ok {
		info.Roaming = &roaming
	}

	if operator, ok := cc.extractString(data, []string{"operator"}); ok {
		info.Operator = &operator
	}

	if band, ok := cc.extractString(data, []string{"band"}); ok {
		info.Band = &band
	}

	if cellID, ok := cc.extractString(data, []string{"cell_id"}); ok {
		info.CellID = &cellID
	}

	return nil
}

// Helper methods for data extraction
func (cc *CellularCollector) extractNumber(data map[string]interface{}, keys []string) (int, bool) {
	for _, key := range keys {
		if val, ok := data[key]; ok {
			switch v := val.(type) {
			case float64:
				return int(v), true
			case int:
				return v, true
			case string:
				if intVal, err := strconv.Atoi(v); err == nil {
					return intVal, true
				}
			}
		}
	}
	return 0, false
}

func (cc *CellularCollector) extractString(data map[string]interface{}, keys []string) (string, bool) {
	for _, key := range keys {
		if val, ok := data[key].(string); ok && val != "" {
			return val, true
		}
	}
	return "", false
}

func (cc *CellularCollector) extractBool(data map[string]interface{}, keys []string) (bool, bool) {
	for _, key := range keys {
		if val, ok := data[key].(bool); ok {
			return val, true
		}
		if val, ok := data[key].(string); ok {
			if val == "true" || val == "1" || val == "yes" {
				return true, true
			} else if val == "false" || val == "0" || val == "no" {
				return false, true
			}
		}
	}
	return false, false
}

// collectModemSpecificInfo tries modem-specific collection methods
func (cc *CellularCollector) collectModemSpecificInfo(ctx context.Context, member *pkg.Member, info *CellularInfo) error {
	// Try AT commands if available
	if err := cc.tryATCommands(ctx, member, info); err == nil {
		return nil
	}

	// Try QMI commands
	if err := cc.tryQMICommands(ctx, member, info); err == nil {
		return nil
	}

	// Try MBIM commands
	if err := cc.tryMBIMCommands(ctx, member, info); err == nil {
		return nil
	}

	return fmt.Errorf("no modem-specific methods succeeded")
}

// tryATCommands attempts to collect info using AT commands
func (cc *CellularCollector) tryATCommands(ctx context.Context, member *pkg.Member, info *CellularInfo) error {
	// This would typically require access to the modem device
	// For now, return an error to indicate this method is not available
	return fmt.Errorf("AT commands not implemented")
}

// tryQMICommands attempts to collect info using QMI commands
func (cc *CellularCollector) tryQMICommands(ctx context.Context, member *pkg.Member, info *CellularInfo) error {
	// Try qmicli command if available
	cmd := exec.CommandContext(ctx, "qmicli", "--device-open-proxy", "--client-nas", "--get-signal-strength")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("qmicli failed: %w", err)
	}

	// Parse QMI output
	return cc.parseQMIOutput(string(output), info)
}

// tryMBIMCommands attempts to collect info using MBIM commands
func (cc *CellularCollector) tryMBIMCommands(ctx context.Context, member *pkg.Member, info *CellularInfo) error {
	// Try mbimcli command if available
	cmd := exec.CommandContext(ctx, "mbimcli", "--device-open-proxy", "--query-signal-state")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("mbimcli failed: %w", err)
	}

	// Parse MBIM output
	return cc.parseMBIMOutput(string(output), info)
}

// parseQMIOutput parses QMI command output
func (cc *CellularCollector) parseQMIOutput(output string, info *CellularInfo) error {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)

		if strings.Contains(line, "RSRP:") {
			if rsrp := cc.extractNumberFromLine(line, "RSRP:"); rsrp != nil {
				info.RSRP = rsrp
			}
		}
		if strings.Contains(line, "RSRQ:") {
			if rsrq := cc.extractNumberFromLine(line, "RSRQ:"); rsrq != nil {
				info.RSRQ = rsrq
			}
		}
		if strings.Contains(line, "SINR:") {
			if sinr := cc.extractNumberFromLine(line, "SINR:"); sinr != nil {
				info.SINR = sinr
			}
		}
	}

	modemType := "qmi"
	info.ModemType = &modemType

	return nil
}

// parseMBIMOutput parses MBIM command output
func (cc *CellularCollector) parseMBIMOutput(output string, info *CellularInfo) error {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)

		if strings.Contains(line, "RSRP:") {
			if rsrp := cc.extractNumberFromLine(line, "RSRP:"); rsrp != nil {
				info.RSRP = rsrp
			}
		}
		if strings.Contains(line, "RSRQ:") {
			if rsrq := cc.extractNumberFromLine(line, "RSRQ:"); rsrq != nil {
				info.RSRQ = rsrq
			}
		}
		if strings.Contains(line, "SNR:") {
			if snr := cc.extractNumberFromLine(line, "SNR:"); snr != nil {
				info.SINR = snr
			}
		}
	}

	modemType := "mbim"
	info.ModemType = &modemType

	return nil
}

// extractNumberFromLine extracts a number from a line after a prefix
func (cc *CellularCollector) extractNumberFromLine(line, prefix string) *int {
	if idx := strings.Index(line, prefix); idx != -1 {
		remaining := strings.TrimSpace(line[idx+len(prefix):])
		fields := strings.Fields(remaining)
		if len(fields) > 0 {
			if val, err := strconv.Atoi(fields[0]); err == nil {
				return &val
			}
		}
	}
	return nil
}

// enhanceCellularInfo adds additional information to cellular info
func (cc *CellularCollector) enhanceCellularInfo(ctx context.Context, member *pkg.Member, info *CellularInfo) {
	// Calculate signal quality score
	if quality := cc.GetSignalQuality(info.RSRP, info.RSRQ, info.SINR); quality > 0 {
		info.SignalQuality = &quality
	}

	// Detect roaming type if roaming is detected
	if info.Roaming != nil && *info.Roaming {
		roamingType := cc.detectRoamingType(info.Operator, info.HomeOperator)
		if roamingType != "" {
			info.RoamingType = &roamingType
		}
	}

	// Get network interface information
	cc.getNetworkInterfaceInfo(member.Iface, info)

	// Get data usage if available
	cc.getDataUsage(member.Iface, info)
}

// detectRoamingType determines if roaming is national or international
func (cc *CellularCollector) detectRoamingType(currentOperator, homeOperator *string) string {
	if currentOperator == nil || homeOperator == nil {
		return "unknown"
	}

	// Simple heuristic: if operators are different, assume international
	// In a real implementation, this would use MCC/MNC codes
	if *currentOperator != *homeOperator {
		return "international"
	}
	return "national"
}

// getNetworkInterfaceInfo gets IP and network information from interface
func (cc *CellularCollector) getNetworkInterfaceInfo(iface string, info *CellularInfo) {
	// Try to get IP address
	cmd := exec.Command("ip", "addr", "show", iface)
	output, err := cmd.Output()
	if err != nil {
		return
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "inet ") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				ip := strings.Split(fields[1], "/")[0]
				info.IPAddress = &ip
				break
			}
		}
	}

	// Try to get gateway
	cmd = exec.Command("ip", "route", "show", "dev", iface)
	output, err = cmd.Output()
	if err != nil {
		return
	}

	lines = strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "default") {
			fields := strings.Fields(line)
			for i, field := range fields {
				if field == "via" && i+1 < len(fields) {
					info.Gateway = &fields[i+1]
					break
				}
			}
			break
		}
	}
}

// getDataUsage gets TX/RX byte counts for the interface
func (cc *CellularCollector) getDataUsage(iface string, info *CellularInfo) {
	// Read from /sys/class/net/<iface>/statistics/
	if data, err := cc.readFile(fmt.Sprintf("/sys/class/net/%s/statistics/tx_bytes", iface)); err == nil {
		if val, err := strconv.ParseUint(strings.TrimSpace(data), 10, 64); err == nil {
			info.TxBytes = &val
		}
	}

	if data, err := cc.readFile(fmt.Sprintf("/sys/class/net/%s/statistics/rx_bytes", iface)); err == nil {
		if val, err := strconv.ParseUint(strings.TrimSpace(data), 10, 64); err == nil {
			info.RxBytes = &val
		}
	}
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
	} else {
		fmt.Printf("Warning: failed to read %s: %v\n", carrierPath, err)
	}

	return nil
}

// collectBasicSignalInfo collects basic signal information
func (cc *CellularCollector) collectBasicSignalInfo(member *pkg.Member, info *CellularInfo) {
	// Try to read signal strength from various possible locations
	signalPaths := []string{
		fmt.Sprintf("/sys/class/net/%s/signal", member.Iface),
		"/proc/net/wireless",
	}

	for _, path := range signalPaths {
		data, err := cc.readFile(path)
		if err != nil {
			fmt.Printf("Warning: failed to read %s: %v\n", path, err)
			continue
		}

		if signal := cc.parseSignalFromFile(data, member.Iface); signal != nil {
			// Convert signal to RSRP (rough approximation)
			rsrp := cc.convertSignalToRSRP(*signal)
			info.RSRP = &rsrp
			break
		} else {
			fmt.Printf("Debug: unable to parse signal from %s for %s\n", path, member.Iface)
		}
	}
}

// readFile reads a file and returns its contents
func (cc *CellularCollector) readFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	return string(data), nil
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
		if !strings.HasPrefix(line, iface) {
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
