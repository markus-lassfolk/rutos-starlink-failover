// Package collector implements generic ping-based metric collection
package collector

import (
	"context"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// PingCollector collects metrics using ping tests
type PingCollector struct {
	hosts    []string
	count    int
	timeout  time.Duration
	interval time.Duration
}

// NewPingCollector creates a new ping-based metrics collector
func NewPingCollector(hosts []string) *PingCollector {
	if len(hosts) == 0 {
		hosts = []string{"8.8.8.8", "1.1.1.1"} // Default DNS servers
	}

	return &PingCollector{
		hosts:    hosts,
		count:    3, // Send 3 pings
		timeout:  5 * time.Second,
		interval: 200 * time.Millisecond,
	}
}

// Class returns the interface class this collector handles
func (p *PingCollector) Class() string {
	return "generic"
}

// SupportsInterface checks if this collector can handle the given interface
func (p *PingCollector) SupportsInterface(interfaceName string) bool {
	// This is a fallback collector that can handle any interface
	return true
}

// Collect gathers ping-based metrics for the given member
func (p *PingCollector) Collect(ctx context.Context, member Member) (Metrics, error) {
	metrics := Metrics{
		Timestamp:     time.Now(),
		InterfaceName: member.InterfaceName,
		Class:         member.Class,
	}

	// Collect ping statistics from all hosts
	var latencies []float64
	var totalLoss float64
	var hostCount int

	for _, host := range p.hosts {
		pingResult, err := p.pingHost(ctx, host, member.InterfaceName)
		if err != nil {
			continue // Skip failed hosts
		}

		if pingResult.AvgLatency > 0 {
			latencies = append(latencies, pingResult.AvgLatency)
		}
		totalLoss += pingResult.PacketLoss
		hostCount++
	}

	if hostCount == 0 {
		return metrics, fmt.Errorf("failed to ping any hosts")
	}

	// Calculate aggregate metrics
	if len(latencies) > 0 {
		avgLatency := p.calculateMean(latencies)
		metrics.LatencyMs = &avgLatency

		jitter := p.calculateJitter(latencies)
		if jitter > 0 {
			metrics.JitterMs = &jitter
		}
	}

	avgLoss := totalLoss / float64(hostCount)
	metrics.PacketLossPct = &avgLoss

	return metrics, nil
}

// PingResult represents the result of a ping test
type PingResult struct {
	Host        string  `json:"host"`
	AvgLatency  float64 `json:"avg_latency_ms"`
	MinLatency  float64 `json:"min_latency_ms"`
	MaxLatency  float64 `json:"max_latency_ms"`
	PacketLoss  float64 `json:"packet_loss_pct"`
	PacketsSent int     `json:"packets_sent"`
	PacketsRecv int     `json:"packets_recv"`
}

// pingHost performs ping test to a specific host via the given interface
func (p *PingCollector) pingHost(ctx context.Context, host, interfaceName string) (*PingResult, error) {
	// Build ping command with interface binding and count
	args := []string{
		"-c", strconv.Itoa(p.count), // Count
		"-W", strconv.Itoa(int(p.timeout.Seconds())), // Timeout per packet
		"-i", fmt.Sprintf("%.1f", p.interval.Seconds()), // Interval between packets
	}

	// Add interface binding if supported
	// Note: -I option syntax varies between ping implementations
	if interfaceName != "" {
		args = append(args, "-I", interfaceName)
	}

	args = append(args, host)

	cmd := exec.CommandContext(ctx, "ping", args...)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ping failed: %w", err)
	}

	// Parse ping output
	result, err := p.parsePingOutput(string(output), host)
	if err != nil {
		return nil, fmt.Errorf("failed to parse ping output: %w", err)
	}

	return result, nil
}

// parsePingOutput parses ping command output to extract statistics
func (p *PingCollector) parsePingOutput(output, host string) (*PingResult, error) {
	result := &PingResult{
		Host: host,
	}

	lines := strings.Split(output, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)

		// Parse packet loss line: "3 packets transmitted, 3 received, 0% packet loss"
		if strings.Contains(line, "packets transmitted") && strings.Contains(line, "packet loss") {
			if err := p.parsePacketStats(line, result); err != nil {
				continue
			}
		}

		// Parse timing line: "rtt min/avg/max/mdev = 12.345/23.456/34.567/1.234 ms"
		if strings.Contains(line, "rtt") && strings.Contains(line, "min/avg/max") {
			if err := p.parseTimingStats(line, result); err != nil {
				continue
			}
		}
	}

	return result, nil
}

// parsePacketStats extracts packet transmission statistics
func (p *PingCollector) parsePacketStats(line string, result *PingResult) error {
	// Example: "3 packets transmitted, 3 received, 0% packet loss"
	parts := strings.Split(line, ",")

	for _, part := range parts {
		part = strings.TrimSpace(part)

		if strings.Contains(part, "packets transmitted") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				if sent, err := strconv.Atoi(fields[0]); err == nil {
					result.PacketsSent = sent
				}
			}
		}

		if strings.Contains(part, "received") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				if recv, err := strconv.Atoi(fields[0]); err == nil {
					result.PacketsRecv = recv
				}
			}
		}

		if strings.Contains(part, "packet loss") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				lossStr := strings.TrimSuffix(fields[0], "%")
				if loss, err := strconv.ParseFloat(lossStr, 64); err == nil {
					result.PacketLoss = loss
				}
			}
		}
	}

	return nil
}

// parseTimingStats extracts latency timing statistics
func (p *PingCollector) parseTimingStats(line string, result *PingResult) error {
	// Example: "rtt min/avg/max/mdev = 12.345/23.456/34.567/1.234 ms"
	if !strings.Contains(line, "=") {
		return fmt.Errorf("no timing data found")
	}

	parts := strings.Split(line, "=")
	if len(parts) < 2 {
		return fmt.Errorf("invalid timing format")
	}

	timingPart := strings.TrimSpace(parts[1])
	timingPart = strings.TrimSuffix(timingPart, " ms")

	values := strings.Split(timingPart, "/")
	if len(values) >= 3 {
		if min, err := strconv.ParseFloat(values[0], 64); err == nil {
			result.MinLatency = min
		}
		if avg, err := strconv.ParseFloat(values[1], 64); err == nil {
			result.AvgLatency = avg
		}
		if max, err := strconv.ParseFloat(values[2], 64); err == nil {
			result.MaxLatency = max
		}
	}

	return nil
}

// calculateMean calculates the mean of a slice of float64 values
func (p *PingCollector) calculateMean(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}

	sum := 0.0
	for _, v := range values {
		sum += v
	}

	return sum / float64(len(values))
}

// calculateJitter calculates jitter (standard deviation) of latency values
func (p *PingCollector) calculateJitter(latencies []float64) float64 {
	if len(latencies) < 2 {
		return 0
	}

	mean := p.calculateMean(latencies)
	sumSquaredDiffs := 0.0

	for _, latency := range latencies {
		diff := latency - mean
		sumSquaredDiffs += diff * diff
	}

	variance := sumSquaredDiffs / float64(len(latencies)-1)
	return math.Sqrt(variance)
}

// LANCollector is a specialized ping collector for LAN interfaces
type LANCollector struct {
	*PingCollector
}

// NewLANCollector creates a LAN-specific ping collector
func NewLANCollector(hosts []string) *LANCollector {
	if len(hosts) == 0 {
		// Use local gateway and common LAN services as default
		hosts = []string{"192.168.1.1", "10.0.0.1", "8.8.8.8"}
	}

	return &LANCollector{
		PingCollector: NewPingCollector(hosts),
	}
}

// Class returns the interface class this collector handles
func (l *LANCollector) Class() string {
	return "lan"
}

// SupportsInterface checks if this collector can handle the given interface
func (l *LANCollector) SupportsInterface(interfaceName string) bool {
	// Common LAN interface patterns
	patterns := []string{"eth", "br-", "lan", "ens", "enp"}

	ifLower := strings.ToLower(interfaceName)
	for _, pattern := range patterns {
		if strings.HasPrefix(ifLower, pattern) {
			return true
		}
	}

	return false
}
