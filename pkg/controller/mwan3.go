// Package controller provides mwan3 and netifd integration for failover control
package controller

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/retry"
)

// Member represents a mwan3 member configuration
type Member struct {
	Name      string `json:"name"`
	Interface string `json:"interface"`
	Metric    int    `json:"metric"`
	Weight    int    `json:"weight"`
	Policy    string `json:"policy"`
	Enabled   bool   `json:"enabled"`
}

// Controller manages mwan3 policies and member priorities
type Controller struct {
	logger     *logx.Logger
	useMwan3   bool
	dryRun     bool
	cooldownS  int
	lastChange time.Time
	// lastDesiredMember caches the last requested primary to avoid redundant operations
	lastDesiredMember string
	// runner abstracts command execution for testability
	run Runner
	// sleep allows injection in tests
	sleep func(d time.Duration)
}

// Config for mwan3 controller
type Config struct {
	UseMwan3  bool `uci:"use_mwan3"`
	DryRun    bool `uci:"dry_run"`
	CooldownS int  `uci:"cooldown_s"`
}

// NewController creates a new mwan3 controller
func NewController(config Config, logger *logx.Logger) *Controller {
	if config.CooldownS <= 0 {
		config.CooldownS = 30
	}

	// Conservative retry config for UCI/ubus operations
	retryConfig := retry.Config{
		MaxAttempts:   3,
		InitialDelay:  100 * time.Millisecond,
		MaxDelay:      1 * time.Second,
		BackoffFactor: 2.0,
	}

	return &Controller{
		logger:     logger,
		useMwan3:   config.UseMwan3,
		dryRun:     config.DryRun,
		cooldownS:  config.CooldownS,
		lastChange: time.Time{},
		run:        retry.NewRunner(retryConfig),
		sleep:      time.Sleep,
	}
}

// DiscoverMembers discovers mwan3 members from UCI configuration
func (c *Controller) DiscoverMembers(ctx context.Context) ([]Member, error) {
	c.logger.WithFields(logx.Fields{
		"component": "controller",
		"action":    "discover",
	}).Info("discovering mwan3 members")

	if !c.useMwan3 {
		c.logger.Info("mwan3 disabled, using netifd fallback")
		return c.discoverNetifaceMembers(ctx)
	}

	output, err := c.run.Output(ctx, "uci", "show", "mwan3")
	if err != nil {
		c.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Error("failed to read mwan3 config")
		return nil, fmt.Errorf("failed to read mwan3 config: %w", err)
	}

	return c.parseMwan3Config(string(output))
}

// SetPrimary sets the primary member for failover
func (c *Controller) SetPrimary(ctx context.Context, member Member) error {
	fields := logx.Fields{
		"component": "controller",
		"action":    "set_primary",
		"member":    member.Name,
		"interface": member.Interface,
		"policy":    member.Policy,
		"dry_run":   c.dryRun,
	}

	// Check cooldown
	if time.Since(c.lastChange) < time.Duration(c.cooldownS)*time.Second {
		remaining := time.Duration(c.cooldownS)*time.Second - time.Since(c.lastChange)
		c.logger.WithFields(fields).WithFields(logx.Fields{
			"cooldown_remaining_s": remaining.Seconds(),
		}).Warn("controller in cooldown, skipping change")
		return fmt.Errorf("controller in cooldown, %v remaining", remaining)
	}

	// Idempotency: if already targeted in dry-run, or current primary matches (any mode), no-op
	if c.dryRun && c.lastDesiredMember == member.Name {
		c.logger.WithFields(fields).Info("dry run: unchanged (already targeted as primary)")
		return nil
	}
	if !c.dryRun {
		if cur, err := c.GetCurrentPrimary(ctx); err == nil && cur != nil && cur.Name == member.Name {
			c.logger.WithFields(fields).Info("unchanged (already primary)")
			return nil
		}
	}

	c.logger.WithFields(fields).Info("setting primary member")

	if c.dryRun {
		c.logger.WithFields(fields).Info("dry run: would set primary member")
		return nil
	}

	var err error
	if c.useMwan3 {
		err = c.setMwan3Primary(ctx, member)
	} else {
		err = c.setNetifacePrimary(ctx, member)
	}

	if err != nil {
		c.logger.WithFields(fields).WithFields(logx.Fields{
			"error": err.Error(),
		}).Error("failed to set primary member")
		return err
	}

	c.lastChange = time.Now()
	c.lastDesiredMember = member.Name
	c.logger.WithFields(fields).Info("successfully set primary member")
	return nil
}

// GetCurrentPrimary returns the currently active primary member
func (c *Controller) GetCurrentPrimary(ctx context.Context) (*Member, error) {
	if c.useMwan3 {
		return c.getMwan3Primary(ctx)
	}
	return c.getNetifacePrimary(ctx)
}

// setMwan3Primary uses mwan3 to set the primary member
func (c *Controller) setMwan3Primary(ctx context.Context, member Member) error {
	// Set member metric to make it primary (lower metric = higher priority)
	primaryMetric := 1

	// First, get all members and set their metrics appropriately
	members, err := c.DiscoverMembers(ctx)
	if err != nil {
		return fmt.Errorf("failed to discover members: %w", err)
	}

	for _, m := range members {
		var metric int
		if m.Name == member.Name {
			metric = primaryMetric
		} else {
			metric = primaryMetric + 10 // Backup members get higher metric
		}

		if err := c.run.Run(ctx, "uci", "set",
			fmt.Sprintf("mwan3.%s.metric=%d", m.Name, metric)); err != nil {
			return fmt.Errorf("failed to set metric for member %s: %w", m.Name, err)
		}
	}

	// Commit changes
	if err := c.run.Run(ctx, "uci", "commit", "mwan3"); err != nil {
		return fmt.Errorf("failed to commit mwan3 config: %w", err)
	}

	// Restart mwan3 to apply changes
	if err := c.run.Run(ctx, "/etc/init.d/mwan3", "restart"); err != nil {
		return fmt.Errorf("failed to restart mwan3: %w", err)
	}

	return nil
}

// setNetifacePrimary uses netifd/route metrics as fallback
func (c *Controller) setNetifacePrimary(ctx context.Context, member Member) error {
	// Use UCI network.*.metric to prefer the target interface
	primaryMetric := 10
	backupMetric := 100

	// Discover interfaces via ubus dump
	members, err := c.discoverNetifaceMembers(ctx)
	if err != nil {
		return err
	}

	c.logger.WithFields(logx.Fields{
		"member":         member.Name,
		"interface":      member.Interface,
		"primary_metric": primaryMetric,
		"backup_metric":  backupMetric,
	}).Info("setting route metrics for netifd")

	// Apply metrics via UCI for all members
	for _, m := range members {
		metric := backupMetric
		if m.Interface == member.Interface {
			metric = primaryMetric
		}
		if err := c.run.Run(ctx, "uci", "set", fmt.Sprintf("network.%s.metric=%d", m.Interface, metric)); err != nil {
			return fmt.Errorf("failed to set metric for interface %s: %w", m.Interface, err)
		}
	}
	if err := c.run.Run(ctx, "uci", "commit", "network"); err != nil {
		return fmt.Errorf("failed to commit network config: %w", err)
	}
	if err := c.run.Run(ctx, "/etc/init.d/network", "reload"); err != nil {
		return fmt.Errorf("failed to reload network: %w", err)
	}

	// Verified apply with backoff: ensure default route now uses target interface
	var last string
	for attempt := 0; attempt < 5; attempt++ {
		out, err := c.run.Output(ctx, "ip", "-4", "route", "show", "default")
		if err == nil {
			dev := parseDefaultDev(string(out))
			last = dev
			if dev == member.Interface {
				return nil
			}
		}
		// backoff
		c.sleep(time.Duration(100*(1<<attempt)) * time.Millisecond)
	}
	return fmt.Errorf("verification failed: default route dev='%s', expected '%s'", last, member.Interface)
}

// getMwan3Primary gets the current primary member from mwan3
func (c *Controller) getMwan3Primary(ctx context.Context) (*Member, error) {
	// Try JSON first (mwan3 3.x+ supports this)
	if member, err := c.getMwan3PrimaryJSON(ctx); err == nil {
		return member, nil
	}

	// Fall back to text parsing for older mwan3 versions
	output, err := c.run.Output(ctx, "mwan3", "status")
	if err != nil {
		return nil, fmt.Errorf("failed to get mwan3 status: %w", err)
	}

	// Parse mwan3 status output to find the active interface
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		// Look for lines like "interface wan1 is online"
		if strings.Contains(line, "interface") && strings.Contains(line, "online") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				return &Member{
					Name:      parts[1],
					Interface: parts[1],
					Enabled:   true,
				}, nil
			}
		}
		// Also handle "wan1: interface is online and active"
		if strings.Contains(line, ": interface is online") {
			parts := strings.Split(line, ":")
			if len(parts) >= 1 {
				name := strings.TrimSpace(parts[0])
				return &Member{
					Name:      name,
					Interface: name,
					Enabled:   true,
				}, nil
			}
		}
	}

	return nil, fmt.Errorf("no active mwan3 interface found")
}

// getMwan3PrimaryJSON attempts to get primary via JSON output (mwan3 3.x+)
func (c *Controller) getMwan3PrimaryJSON(ctx context.Context) (*Member, error) {
	output, err := c.run.Output(ctx, "mwan3", "status", "--json")
	if err != nil {
		// JSON not supported, fall back to text
		return nil, err
	}

	// Parse JSON structure like:
	// {
	//   "interfaces": {
	//     "wan1": {
	//       "status": "online",
	//       "metric": 1,
	//       "weight": 1,
	//       "policy": "wan1_only"
	//     }
	//   }
	// }
	var status struct {
		Interfaces map[string]struct {
			Status string `json:"status"`
			Metric int    `json:"metric"`
			Weight int    `json:"weight"`
			Policy string `json:"policy"`
		} `json:"interfaces"`
	}

	if err := json.Unmarshal(output, &status); err != nil {
		return nil, fmt.Errorf("failed to parse mwan3 JSON status: %w", err)
	}

	// Find the interface with lowest metric (highest priority) that's online
	var primary *Member
	minMetric := int(^uint(0) >> 1) // max int

	for name, iface := range status.Interfaces {
		if iface.Status == "online" && iface.Metric < minMetric {
			minMetric = iface.Metric
			primary = &Member{
				Name:      name,
				Interface: name,
				Enabled:   true,
				Metric:    iface.Metric,
				Weight:    iface.Weight,
				Policy:    iface.Policy,
			}
		}
	}

	if primary == nil {
		return nil, fmt.Errorf("no online mwan3 interface found in JSON status")
	}

	return primary, nil
}

// getNetifacePrimary gets the current primary member from netifd
func (c *Controller) getNetifacePrimary(ctx context.Context) (*Member, error) {
	if _, err := c.run.Output(ctx, "ubus", "call", "network.interface", "dump"); err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}
	// Determine primary via default route 'ip route'
	out, err := c.run.Output(ctx, "ip", "-4", "route", "show", "default")
	if err != nil {
		// fall back to unknown
		return &Member{Name: "unknown", Interface: "unknown", Enabled: true}, nil
	}
	dev := parseDefaultDev(string(out))
	if dev == "" {
		return &Member{Name: "unknown", Interface: "unknown", Enabled: true}, nil
	}
	return &Member{Name: dev, Interface: dev, Enabled: true}, nil
}

// parseMwan3Config parses UCI mwan3 configuration output
func (c *Controller) parseMwan3Config(output string) ([]Member, error) {
	var members []Member
	memberMap := make(map[string]*Member)

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Parse UCI format: mwan3.member_name.option=value
		if !strings.HasPrefix(line, "mwan3.") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := parts[0]
		value := strings.Trim(parts[1], "'\"")

		// Extract member name and option
		keyParts := strings.Split(key, ".")
		if len(keyParts) < 3 {
			continue
		}

		memberName := keyParts[1]
		option := keyParts[2]

		// Get or create member
		if memberMap[memberName] == nil {
			memberMap[memberName] = &Member{
				Name:    memberName,
				Enabled: true, // Default to enabled
				Weight:  1,    // Default weight
			}
		}
		member := memberMap[memberName]

		// Set member properties based on option
		switch option {
		case "interface":
			member.Interface = value
		case "metric":
			// Parse metric if needed
			member.Metric = 1 // Default metric
		case "weight":
			// Parse weight if needed
			member.Weight = 1 // Default weight
		case "enabled":
			member.Enabled = value == "1" || value == "true"
		}
	}

	// Convert map to slice
	for _, member := range memberMap {
		if member.Interface != "" { // Only include members with interfaces
			members = append(members, *member)
		}
	}

	c.logger.WithFields(logx.Fields{
		"member_count": len(members),
	}).Info("parsed mwan3 configuration")

	return members, nil
}

// discoverNetifaceMembers discovers network interfaces from netifd as fallback
func (c *Controller) discoverNetifaceMembers(ctx context.Context) ([]Member, error) {
	output, err := c.run.Output(ctx, "ubus", "call", "network.interface", "dump")
	if err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}
	// Parse minimal JSON: { "interface": [ { "interface": "wan", "up": true, ... }, ... ] }
	var dump struct {
		Interfaces []struct {
			Name string `json:"interface"`
			Up   bool   `json:"up"`
		} `json:"interface"`
	}
	if err := json.Unmarshal(output, &dump); err != nil {
		// If parsing fails, return a sensible default
		c.logger.WithFields(logx.Fields{"error": err.Error()}).Warn("failed to parse ubus dump, falling back to default member")
		return []Member{{Name: "wan", Interface: "wan", Enabled: true, Weight: 1, Policy: "default"}}, nil
	}
	members := make([]Member, 0, len(dump.Interfaces))
	for _, it := range dump.Interfaces {
		if it.Name == "" {
			continue
		}
		members = append(members, Member{
			Name:      it.Name,
			Interface: it.Name,
			Enabled:   it.Up,
			Weight:    1,
			Policy:    "default",
		})
	}
	if len(members) == 0 {
		members = append(members, Member{Name: "wan", Interface: "wan", Enabled: true, Weight: 1, Policy: "default"})
	}
	return members, nil
}

// ValidateConfig checks if mwan3/netifd is properly configured
func (c *Controller) ValidateConfig(ctx context.Context) error {
	if c.useMwan3 {
		// Check if mwan3 is installed and configured
		if err := c.run.Run(ctx, "which", "mwan3"); err != nil {
			return fmt.Errorf("mwan3 not found: %w", err)
		}

		// Check if mwan3 config exists
		if err := c.run.Run(ctx, "uci", "show", "mwan3"); err != nil {
			return fmt.Errorf("mwan3 config not found: %w", err)
		}
	} else {
		// Check if netifd is running
		if err := c.run.Run(ctx, "ubus", "call", "network.interface", "dump"); err != nil {
			return fmt.Errorf("netifd not accessible: %w", err)
		}
	}

	return nil
}

// Runner abstracts command execution (std library only)
type Runner interface {
	Output(ctx context.Context, name string, args ...string) ([]byte, error)
	Run(ctx context.Context, name string, args ...string) error
}

// parseDefaultDev extracts the dev name from `ip route show default` output
var reDefaultDev = regexp.MustCompile(`\bdev\s+(\S+)`)

func parseDefaultDev(s string) string {
	m := reDefaultDev.FindStringSubmatch(s)
	if len(m) >= 2 {
		return m[1]
	}
	return ""
}

// test helpers (unexported): allow tests to inject runner and sleep
func (c *Controller) setRunnerForTest(r Runner)             { c.run = r }
func (c *Controller) setSleepForTest(f func(time.Duration)) { c.sleep = f }
