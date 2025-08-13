// Package controller provides mwan3 and netifd integration for failover control
package controller

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"starfail/pkg/logx"
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
	logger      *logx.Logger
	useMwan3    bool
	dryRun      bool
	cooldownS   int
	lastChange  time.Time
}

// Config for mwan3 controller
type Config struct {
	UseMwan3   bool `uci:"use_mwan3"`
	DryRun     bool `uci:"dry_run"`
	CooldownS  int  `uci:"cooldown_s"`
}

// NewController creates a new mwan3 controller
func NewController(config Config, logger *logx.Logger) *Controller {
	if config.CooldownS <= 0 {
		config.CooldownS = 30
	}

	return &Controller{
		logger:     logger,
		useMwan3:   config.UseMwan3,
		dryRun:     config.DryRun,
		cooldownS:  config.CooldownS,
		lastChange: time.Time{},
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

	cmd := exec.CommandContext(ctx, "uci", "show", "mwan3")
	output, err := cmd.Output()
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

		cmd := exec.CommandContext(ctx, "uci", "set", 
			fmt.Sprintf("mwan3.%s.metric=%d", m.Name, metric))
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to set metric for member %s: %w", m.Name, err)
		}
	}

	// Commit changes
	if err := exec.CommandContext(ctx, "uci", "commit", "mwan3").Run(); err != nil {
		return fmt.Errorf("failed to commit mwan3 config: %w", err)
	}

	// Restart mwan3 to apply changes
	if err := exec.CommandContext(ctx, "/etc/init.d/mwan3", "restart").Run(); err != nil {
		return fmt.Errorf("failed to restart mwan3: %w", err)
	}

	return nil
}

// setNetifacePrimary uses netifd/route metrics as fallback
func (c *Controller) setNetifacePrimary(ctx context.Context, member Member) error {
	// Use route metrics to prefer the target interface
	// Lower metric = higher priority in routing
	primaryMetric := 100
	backupMetric := 200

	// Get all network interfaces
	cmd := exec.CommandContext(ctx, "ubus", "call", "network.interface", "dump")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to get network interfaces: %w", err)
	}

	// This is a simplified implementation - in practice, we'd parse the JSON
	// and set route metrics for each interface appropriately
	c.logger.WithFields(logx.Fields{
		"member":         member.Name,
		"interface":      member.Interface,
		"primary_metric": primaryMetric,
		"backup_metric":  backupMetric,
	}).Info("setting route metrics for netifd")

	// Set the primary interface metric
	cmd = exec.CommandContext(ctx, "ubus", "call", "network.interface."+member.Interface, 
		"notify_proto", fmt.Sprintf(`{"metric":%d}`, primaryMetric))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to set metric for interface %s: %w", member.Interface, err)
	}

	return nil
}

// getMwan3Primary gets the current primary member from mwan3
func (c *Controller) getMwan3Primary(ctx context.Context) (*Member, error) {
	cmd := exec.CommandContext(ctx, "mwan3", "status")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get mwan3 status: %w", err)
	}

	// Parse mwan3 status output to find the active interface
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
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
	}

	return nil, fmt.Errorf("no active mwan3 interface found")
}

// getNetifacePrimary gets the current primary member from netifd
func (c *Controller) getNetifacePrimary(ctx context.Context) (*Member, error) {
	cmd := exec.CommandContext(ctx, "ubus", "call", "network.interface", "dump")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}

	// This is a simplified implementation - in practice, we'd parse the JSON
	// to find the interface with the lowest metric that's up
	c.logger.WithFields(logx.Fields{
		"output_length": len(output),
	}).Debug("got network interface dump")

	// For now, return a placeholder
	return &Member{
		Name:      "unknown",
		Interface: "unknown",
		Enabled:   true,
	}, nil
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
	cmd := exec.CommandContext(ctx, "ubus", "call", "network.interface", "dump")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}

	// This is a simplified implementation
	// In practice, we'd parse the JSON response to get actual interface details
	c.logger.WithFields(logx.Fields{
		"output_length": len(output),
	}).Debug("discovered network interfaces")

	// Return placeholder members for now
	return []Member{
		{
			Name:      "wan",
			Interface: "wan",
			Enabled:   true,
			Weight:    1,
			Policy:    "default",
		},
	}, nil
}

// ValidateConfig checks if mwan3/netifd is properly configured
func (c *Controller) ValidateConfig(ctx context.Context) error {
	if c.useMwan3 {
		// Check if mwan3 is installed and configured
		if err := exec.CommandContext(ctx, "which", "mwan3").Run(); err != nil {
			return fmt.Errorf("mwan3 not found: %w", err)
		}

		// Check if mwan3 config exists
		if err := exec.CommandContext(ctx, "uci", "show", "mwan3").Run(); err != nil {
			return fmt.Errorf("mwan3 config not found: %w", err)
		}
	} else {
		// Check if netifd is running
		if err := exec.CommandContext(ctx, "ubus", "call", "network.interface", "dump").Run(); err != nil {
			return fmt.Errorf("netifd not accessible: %w", err)
		}
	}

	return nil
}
