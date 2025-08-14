package collector

import (
	"context"
	"fmt"
	"math"
	"net"
	"time"

	"github.com/starfail/starfail/pkg"
)

// BaseCollector provides common functionality for all collectors
type BaseCollector struct {
	timeout        time.Duration
	targets        []string
	latencyHistory map[string][]float64
	historySize    int
}

// NewBaseCollector creates a new base collector
func NewBaseCollector(timeout time.Duration, targets []string) *BaseCollector {
	if len(targets) == 0 {
		targets = []string{"8.8.8.8", "1.1.1.1"}
	}
	if timeout == 0 {
		timeout = 5 * time.Second
	}

	return &BaseCollector{
		timeout:        timeout,
		targets:        targets,
		latencyHistory: make(map[string][]float64),
		historySize:    10,
	}
}

// CollectCommonMetrics collects common latency and loss metrics
func (bc *BaseCollector) CollectCommonMetrics(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	metrics := &pkg.Metrics{
		Timestamp: time.Now(),
	}

	// Collect latency and loss from multiple targets
	var totalLatency float64
	var totalLoss float64
	var validTargets int

	for _, target := range bc.targets {
		latency, loss, err := bc.pingTarget(ctx, target)
		if err != nil {
			continue
		}

		totalLatency += latency
		totalLoss += loss
		validTargets++
	}

	if validTargets == 0 {
		return nil, fmt.Errorf("no valid targets responded for member %s", member.Name)
	}

	// Calculate averages
	metrics.LatencyMS = totalLatency / float64(validTargets)
	metrics.LossPercent = totalLoss / float64(validTargets)

	// Calculate jitter based on latency history
	metrics.JitterMS = bc.calculateJitter(member.Name, metrics.LatencyMS)

	return metrics, nil
}

// pingTarget pings a single target and returns latency and loss
func (bc *BaseCollector) pingTarget(ctx context.Context, target string) (latency, loss float64, err error) {
	// Use TCP connect timing as fallback (ICMP might be blocked)
	start := time.Now()

	conn, err := net.DialTimeout("tcp", target+":80", bc.timeout)
	if err != nil {
		return 0, 100, err // 100% loss if can't connect
	}
	defer conn.Close()

	latency = float64(time.Since(start).Milliseconds())
	loss = 0 // TCP connect success = 0% loss

	return latency, loss, nil
}

// calculateJitter calculates jitter using a rolling window of latency samples
// It maintains a short history per member and returns the standard deviation
// of the collected latencies. If there are fewer than 2 samples, jitter is 0.
func (bc *BaseCollector) calculateJitter(memberName string, latency float64) float64 {
	history := append(bc.latencyHistory[memberName], latency)
	if len(history) > bc.historySize {
		history = history[len(history)-bc.historySize:]
	}
	bc.latencyHistory[memberName] = history

	if len(history) < 2 {
		return 0
	}

	var sum float64
	for _, v := range history {
		sum += v
	}
	mean := sum / float64(len(history))

	var variance float64
	for _, v := range history {
		diff := v - mean
		variance += diff * diff
	}
	variance /= float64(len(history))
	return math.Sqrt(variance)
}

// Validate validates a member for this collector
func (bc *BaseCollector) Validate(member *pkg.Member) error {
	if member == nil {
		return fmt.Errorf("member cannot be nil")
	}
	if member.Name == "" {
		return fmt.Errorf("member name cannot be empty")
	}
	if member.Iface == "" {
		return fmt.Errorf("member interface cannot be empty")
	}
	return nil
}

// CollectorFactory creates collectors based on member class
type CollectorFactory struct {
	config map[string]interface{}
}

// NewCollectorFactory creates a new collector factory
func NewCollectorFactory(config map[string]interface{}) *CollectorFactory {
	return &CollectorFactory{
		config: config,
	}
}

// CreateCollector creates a collector for the given member
func (cf *CollectorFactory) CreateCollector(member *pkg.Member) (pkg.Collector, error) {
	switch member.Class {
	case pkg.ClassStarlink:
		return NewStarlinkCollector(cf.config)
	case pkg.ClassCellular:
		return NewCellularCollector(cf.config)
	case pkg.ClassWiFi:
		return NewWiFiCollector(cf.config)
	case pkg.ClassLAN:
		return NewLANCollector(cf.config)
	case pkg.ClassOther:
		return NewGenericCollector(cf.config)
	default:
		return NewGenericCollector(cf.config)
	}
}

// GenericCollector is a fallback collector for unknown member types
type GenericCollector struct {
	*BaseCollector
}

// NewGenericCollector creates a new generic collector
func NewGenericCollector(config map[string]interface{}) (*GenericCollector, error) {
	timeout := 5 * time.Second
	if t, ok := config["timeout"].(time.Duration); ok {
		timeout = t
	}

	targets := []string{"8.8.8.8", "1.1.1.1"}
	if t, ok := config["targets"].([]string); ok {
		targets = t
	}

	return &GenericCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
	}, nil
}

// Collect collects metrics for a generic member
func (gc *GenericCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := gc.Validate(member); err != nil {
		return nil, err
	}

	return gc.CollectCommonMetrics(ctx, member)
}

// Validate validates a member for the generic collector
func (gc *GenericCollector) Validate(member *pkg.Member) error {
	return gc.BaseCollector.Validate(member)
}

// LANCollector collects metrics for LAN interfaces
type LANCollector struct {
	*BaseCollector
}

// NewLANCollector creates a new LAN collector
func NewLANCollector(config map[string]interface{}) (*LANCollector, error) {
	timeout := 3 * time.Second // LAN should be faster
	if t, ok := config["timeout"].(time.Duration); ok {
		timeout = t
	}

	targets := []string{"8.8.8.8", "1.1.1.1"}
	if t, ok := config["targets"].([]string); ok {
		targets = t
	}

	return &LANCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
	}, nil
}

// Collect collects metrics for a LAN member
func (lc *LANCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := lc.Validate(member); err != nil {
		return nil, err
	}

	return lc.CollectCommonMetrics(ctx, member)
}

// Validate validates a member for the LAN collector
func (lc *LANCollector) Validate(member *pkg.Member) error {
	return lc.BaseCollector.Validate(member)
}
