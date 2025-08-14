package discovery

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
)

// Discoverer handles member discovery and classification
type Discoverer struct {
	logger *logx.Logger
}

// NewDiscoverer creates a new discoverer instance
func NewDiscoverer(logger *logx.Logger) *Discoverer {
	return &Discoverer{
		logger: logger,
	}
}

// DiscoverMembers scans the system for network interfaces and classifies them
func (d *Discoverer) DiscoverMembers() ([]pkg.Member, error) {
	d.logger.Info("Starting member discovery")

	// Get all network interfaces
	interfaces, err := d.getNetworkInterfaces()
	if err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}

	var members []pkg.Member

	for _, iface := range interfaces {
		member, err := d.classifyInterface(iface)
		if err != nil {
			d.logger.Warn("Failed to classify interface", map[string]interface{}{
				"interface": iface,
				"error":     err.Error(),
			})
			continue
		}

		if member != nil {
			members = append(members, *member)
			d.logger.Info("Discovered member", map[string]interface{}{
				"name":      member.Name,
				"class":     member.Class,
				"interface": member.Iface,
			})
		}
	}

	d.logger.Info("Member discovery completed", map[string]interface{}{
		"total_members": len(members),
		"members":       getMemberNames(members),
	})

	return members, nil
}

// getNetworkInterfaces returns a list of network interface names
func (d *Discoverer) getNetworkInterfaces() ([]string, error) {
	var interfaces []string

	// Read /sys/class/net directory
	netDir := "/sys/class/net"
	entries, err := os.ReadDir(netDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read %s: %w", netDir, err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			// Skip loopback and virtual interfaces
			name := entry.Name()
			if name == "lo" || strings.HasPrefix(name, "veth") ||
				strings.HasPrefix(name, "docker") || strings.HasPrefix(name, "br-") {
				continue
			}
			interfaces = append(interfaces, name)
		}
	}

	return interfaces, nil
}

// classifyInterface determines the class and properties of a network interface
func (d *Discoverer) classifyInterface(iface string) (*pkg.Member, error) {
	// Check if interface is up and has an IP address
	if !d.isInterfaceActive(iface) {
		return nil, fmt.Errorf("interface %s is not active", iface)
	}

	// Try to classify by interface name patterns
	class := d.classifyByName(iface)
	if class != "" {
		return d.createMember(iface, class)
	}

	// Try to classify by driver/module
	class = d.classifyByDriver(iface)
	if class != "" {
		return d.createMember(iface, class)
	}

	// Try to classify by device properties
	class = d.classifyByProperties(iface)
	if class != "" {
		return d.createMember(iface, class)
	}

	// Default to generic class
	return d.createMember(iface, pkg.MemberClassGeneric)
}

// isInterfaceActive checks if an interface is up and has an IP address
func (d *Discoverer) isInterfaceActive(iface string) bool {
	// Check if interface is up
	operstatePath := fmt.Sprintf("/sys/class/net/%s/operstate", iface)
	operstate, err := os.ReadFile(operstatePath)
	if err != nil {
		return false
	}

	if strings.TrimSpace(string(operstate)) != "up" {
		return false
	}

	// Check if interface has an IP address
	// This is a simplified check - in practice, you'd want to use netlink or ip command
	addrPath := fmt.Sprintf("/sys/class/net/%s/address", iface)
	_, err = os.ReadFile(addrPath)
	return err == nil
}

// classifyByName classifies interfaces based on their name patterns
func (d *Discoverer) classifyByName(iface string) string {
	// Starlink patterns
	if strings.Contains(iface, "starlink") || strings.Contains(iface, "dish") {
		return pkg.MemberClassStarlink
	}

	// Cellular patterns
	if strings.HasPrefix(iface, "wwan") || strings.HasPrefix(iface, "usb") ||
		strings.Contains(iface, "modem") || strings.Contains(iface, "cellular") {
		return pkg.MemberClassCellular
	}

	// WiFi patterns
	if strings.HasPrefix(iface, "wlan") || strings.HasPrefix(iface, "wifi") ||
		strings.Contains(iface, "wireless") {
		return pkg.MemberClassWiFi
	}

	// Ethernet patterns
	if strings.HasPrefix(iface, "eth") || strings.HasPrefix(iface, "en") ||
		strings.HasPrefix(iface, "lan") || strings.HasPrefix(iface, "wan") {
		return pkg.MemberClassLAN
	}

	return ""
}

// classifyByDriver classifies interfaces based on their driver
func (d *Discoverer) classifyByDriver(iface string) string {
	driverPath := fmt.Sprintf("/sys/class/net/%s/device/driver", iface)

	// Read the driver symlink target
	driverLink, err := os.Readlink(driverPath)
	if err != nil {
		return ""
	}

	driver := filepath.Base(driverLink)

	// Starlink drivers
	if strings.Contains(driver, "starlink") || strings.Contains(driver, "dish") {
		return pkg.MemberClassStarlink
	}

	// Cellular drivers
	if strings.Contains(driver, "qmi") || strings.Contains(driver, "cdc") ||
		strings.Contains(driver, "usb_serial") || strings.Contains(driver, "option") {
		return pkg.MemberClassCellular
	}

	// WiFi drivers
	if strings.Contains(driver, "ath") || strings.Contains(driver, "mac80211") ||
		strings.Contains(driver, "wl") || strings.Contains(driver, "brcm") {
		return pkg.MemberClassWiFi
	}

	return ""
}

// classifyByProperties classifies interfaces based on their properties
func (d *Discoverer) classifyByProperties(iface string) string {
	// Check for Starlink-specific properties
	if d.hasStarlinkProperties(iface) {
		return pkg.MemberClassStarlink
	}

	// Check for cellular-specific properties
	if d.hasCellularProperties(iface) {
		return pkg.MemberClassCellular
	}

	// Check for WiFi-specific properties
	if d.hasWiFiProperties(iface) {
		return pkg.MemberClassWiFi
	}

	return ""
}

// hasStarlinkProperties checks for Starlink-specific device properties
func (d *Discoverer) hasStarlinkProperties(iface string) bool {
	// Check for Starlink API endpoint
	// This is a simplified check - in practice, you'd want to actually test connectivity
	devicePath := fmt.Sprintf("/sys/class/net/%s/device", iface)

	// Look for Starlink-specific files or properties
	vendorPath := filepath.Join(devicePath, "vendor")
	if vendor, err := os.ReadFile(vendorPath); err == nil {
		if strings.Contains(strings.ToLower(string(vendor)), "starlink") {
			return true
		}
	}

	// Check if interface can reach Starlink API
	// This would require actual network testing
	return false
}

// hasCellularProperties checks for cellular-specific device properties
func (d *Discoverer) hasCellularProperties(iface string) bool {
	devicePath := fmt.Sprintf("/sys/class/net/%s/device", iface)

	// Check for cellular modem properties
	modemPath := filepath.Join(devicePath, "modem")
	if _, err := os.Stat(modemPath); err == nil {
		return true
	}

	// Check for QMI or CDC interfaces
	qmiPath := filepath.Join(devicePath, "qmi")
	if _, err := os.Stat(qmiPath); err == nil {
		return true
	}

	return false
}

// hasWiFiProperties checks for WiFi-specific device properties
func (d *Discoverer) hasWiFiProperties(iface string) bool {
	// Check for wireless directory
	wirelessPath := fmt.Sprintf("/proc/net/wireless")
	if _, err := os.Stat(wirelessPath); err == nil {
		// Read wireless info to see if this interface is listed
		content, err := os.ReadFile(wirelessPath)
		if err == nil && strings.Contains(string(content), iface) {
			return true
		}
	}

	// Check for iw command output
	// This would require executing the iw command
	return false
}

// createMember creates a Member struct with appropriate defaults
func (d *Discoverer) createMember(iface, class string) (*pkg.Member, error) {
	member := &pkg.Member{
		Name:      iface,
		Iface:     iface,
		Class:     class,
		Eligible:  true,
		CreatedAt: time.Now(),
		LastSeen:  time.Now(),
	}

	// Set class-specific defaults based on the actual pkg.Member structure
	switch class {
	case pkg.MemberClassStarlink:
		member.Weight = 100
		member.Detect = "auto"
		member.Config = map[string]string{
			"check_interval":        "30s",
			"decision_interval":     "10s",
			"cooldown_period":       "5m",
			"min_uptime":            "2m",
			"switch_margin":         "20.0",
			"obstruction_threshold": "10.0",
			"outage_threshold":      "3",
		}

	case pkg.MemberClassCellular:
		member.Weight = 80
		member.Detect = "auto"
		member.Config = map[string]string{
			"check_interval":    "45s",
			"decision_interval": "15s",
			"cooldown_period":   "10m",
			"min_uptime":        "5m",
			"switch_margin":     "15.0",
			"signal_threshold":  "-110.0",
		}

	case pkg.MemberClassWiFi:
		member.Weight = 60
		member.Detect = "auto"
		member.Config = map[string]string{
			"check_interval":    "60s",
			"decision_interval": "20s",
			"cooldown_period":   "15m",
			"min_uptime":        "10m",
			"switch_margin":     "10.0",
			"signal_threshold":  "-70.0",
		}

	case pkg.MemberClassLAN:
		member.Weight = 40
		member.Detect = "auto"
		member.Config = map[string]string{
			"check_interval":    "90s",
			"decision_interval": "30s",
			"cooldown_period":   "20m",
			"min_uptime":        "15m",
			"switch_margin":     "5.0",
		}

	default: // Generic
		member.Weight = 20
		member.Detect = "auto"
		member.Config = map[string]string{
			"check_interval":    "120s",
			"decision_interval": "60s",
			"cooldown_period":   "30m",
			"min_uptime":        "20m",
			"switch_margin":     "5.0",
		}
	}

	return member, nil
}

// ValidateMember checks if a discovered member is valid and usable
func (d *Discoverer) ValidateMember(member pkg.Member) error {
	// Check if interface exists
	if !d.interfaceExists(member.Iface) {
		return fmt.Errorf("interface %s does not exist", member.Iface)
	}

	// Check if interface is up
	if !d.isInterfaceActive(member.Iface) {
		return fmt.Errorf("interface %s is not active", member.Iface)
	}

	// Class-specific validation
	switch member.Class {
	case pkg.MemberClassStarlink:
		return d.validateStarlinkMember(member)
	case pkg.MemberClassCellular:
		return d.validateCellularMember(member)
	case pkg.MemberClassWiFi:
		return d.validateWiFiMember(member)
	case pkg.MemberClassLAN:
		return d.validateLANMember(member)
	default:
		return d.validateGenericMember(member)
	}
}

// interfaceExists checks if a network interface exists
func (d *Discoverer) interfaceExists(iface string) bool {
	_, err := os.Stat(fmt.Sprintf("/sys/class/net/%s", iface))
	return err == nil
}

// validateStarlinkMember performs Starlink-specific validation
func (d *Discoverer) validateStarlinkMember(member pkg.Member) error {
	// Check if Starlink API is accessible
	// This would require actual network connectivity testing
	return nil
}

// validateCellularMember performs cellular-specific validation
func (d *Discoverer) validateCellularMember(member pkg.Member) error {
	// Check if cellular modem is available via ubus
	// This would require ubus integration
	return nil
}

// validateWiFiMember performs WiFi-specific validation
func (d *Discoverer) validateWiFiMember(member pkg.Member) error {
	// Check if wireless interface is available
	// This would require iw or iwinfo integration
	return nil
}

// validateLANMember performs LAN-specific validation
func (d *Discoverer) validateLANMember(member pkg.Member) error {
	// Basic Ethernet interface validation
	return nil
}

// validateGenericMember performs generic validation
func (d *Discoverer) validateGenericMember(member pkg.Member) error {
	// Basic interface validation
	return nil
}

// getMemberNames returns a list of member names
func getMemberNames(members []pkg.Member) []string {
	names := make([]string, len(members))
	for i, member := range members {
		names[i] = member.Name
	}
	return names
}

// RefreshMembers rediscoveries and validates existing members
func (d *Discoverer) RefreshMembers(existing []pkg.Member) ([]pkg.Member, error) {
	d.logger.Info("Refreshing member discovery")

	// Discover new members
	newMembers, err := d.DiscoverMembers()
	if err != nil {
		return nil, err
	}

	// Merge with existing members, preserving configuration
	merged := d.mergeMembers(existing, newMembers)

	// Validate all members
	var validMembers []pkg.Member
	for _, member := range merged {
		if err := d.ValidateMember(member); err != nil {
			d.logger.Warn("Member validation failed", map[string]interface{}{
				"member": member.Name,
				"error":  err.Error(),
			})
			continue
		}
		validMembers = append(validMembers, member)
	}

	d.logger.Info("Member refresh completed", map[string]interface{}{
		"total_members": len(validMembers),
		"valid_members": getMemberNames(validMembers),
	})

	return validMembers, nil
}

// mergeMembers merges existing and new members, preserving configuration
func (d *Discoverer) mergeMembers(existing, new []pkg.Member) []pkg.Member {
	// Create a map of existing members by name
	existingMap := make(map[string]pkg.Member)
	for _, member := range existing {
		existingMap[member.Name] = member
	}

	var merged []pkg.Member

	for _, newMember := range new {
		if existingMember, exists := existingMap[newMember.Name]; exists {
			// Preserve existing configuration but update interface and class
			existingMember.Iface = newMember.Iface
			existingMember.Class = newMember.Class
			existingMember.LastSeen = time.Now()
			merged = append(merged, existingMember)
		} else {
			// Add new member
			merged = append(merged, newMember)
		}
	}

	return merged
}
