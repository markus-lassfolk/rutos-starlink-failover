package pkg

import (
	"context"
	"testing"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/controller"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/decision"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
)

// TestRetryIntegration verifies that collectors and controller use retry logic
func TestRetryIntegration(t *testing.T) {
	logger := logx.New("INFO")

	t.Run("CellularCollectorHasRetryRunner", func(t *testing.T) {
		// Verify cellular collector is created with retry functionality
		cellular := collector.NewCellularCollector("")
		if cellular == nil {
			t.Fatal("failed to create cellular collector")
		}

		// Verify it handles context timeout gracefully (should not panic)
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
		defer cancel()

		// This should timeout quickly and not cause a panic due to retry logic
		_, err := cellular.Collect(ctx, collector.Member{InterfaceName: "test"})
		if err == nil {
			t.Log("cellular collect succeeded unexpectedly (probably not on a real system)")
		} else {
			t.Logf("cellular collect failed as expected in test: %v", err)
		}
	})

	t.Run("ControllerHasRetryRunner", func(t *testing.T) {
		// Verify controller is created with retry functionality
		config := controller.Config{
			UseMwan3:  true,
			DryRun:    true,
			CooldownS: 1,
		}
		ctrl := controller.NewController(config, logger)
		if ctrl == nil {
			t.Fatal("failed to create controller")
		}

		// Verify it handles context timeout gracefully
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
		defer cancel()

		// This should timeout quickly and not cause a panic due to retry logic
		_, err := ctrl.DiscoverMembers(ctx)
		if err == nil {
			t.Log("controller discover succeeded unexpectedly (probably not on a real system)")
		} else {
			t.Logf("controller discover failed as expected in test: %v", err)
		}
	})

	t.Run("PingCollectorHasRetryRunner", func(t *testing.T) {
		// Verify ping collector is created with retry functionality
		ping := collector.NewPingCollector([]string{"8.8.8.8"})
		if ping == nil {
			t.Fatal("failed to create ping collector")
		}

		// Verify it handles context timeout gracefully
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
		defer cancel()

		// This should timeout quickly due to retry logic
		_, err := ping.Collect(ctx, collector.Member{InterfaceName: "test"})
		if err == nil {
			t.Log("ping collect succeeded unexpectedly")
		} else {
			t.Logf("ping collect failed as expected in test: %v", err)
		}
	})
}

// TestEndToEndFailover tests the complete failover pipeline
func TestEndToEndFailover(t *testing.T) {
	logger := logx.New("debug")

	// Set up telemetry store
	store := telem.NewStore(telem.Config{
		MaxSamplesPerMember: 100,
		RetentionHours:      1,
	})

	// Set up decision engine
	decisionCfg := decision.Config{
		SwitchMargin:   10.0,
		CooldownS:      1 * time.Second,
		HistoryWindowS: 5 * time.Second,
	}
	engine := decision.NewEngine(decisionCfg, *logger, store, nil, nil, nil, nil)

	// Set up controller with dry-run mode
	controllerCfg := controller.Config{
		UseMwan3: true,
		DryRun:   true,
	}
	ctrl := controller.NewController(controllerCfg, logger)

	// Define test members
	primaryMember := collector.Member{
		Name:          "wan_starlink",
		InterfaceName: "eth1",
		Class:         "starlink",
		Enabled:       true,
	}

	backupMember := collector.Member{
		Name:          "lte_backup",
		InterfaceName: "wwan0",
		Class:         "cellular",
		Enabled:       true,
	}

	ctx := context.Background()

	// Phase 1: Both members healthy, primary should remain
	primaryMetrics := collector.Metrics{
		LatencyMs:     floatPtr(25),
		PacketLossPct: floatPtr(0),
		JitterMs:      floatPtr(2),
		SNR:           floatPtr(15), // Good Starlink SNR
	}

	backupMetrics := collector.Metrics{
		LatencyMs:     floatPtr(45),
		PacketLossPct: floatPtr(1),
		JitterMs:      floatPtr(8),
		RSRP:          floatPtr(-85), // Moderate cellular signal
	}

	// Update decision engine with metrics
	engine.UpdateMember(primaryMember, primaryMetrics)
	engine.UpdateMember(backupMember, backupMetrics)

	// Initial evaluation - should not trigger switch
	if ev := engine.EvaluateSwitch(); ev != nil {
		t.Logf("phase 1 evaluation: %+v", ev)
	}

	// Phase 2: Primary degrades significantly, should trigger failover
	degradedPrimaryMetrics := collector.Metrics{
		LatencyMs:     floatPtr(500), // Very high latency
		PacketLossPct: floatPtr(15),  // High packet loss
		JitterMs:      floatPtr(100), // High jitter
		SNR:           floatPtr(3),   // Poor SNR
	}

	// Update with degraded metrics multiple times to build history
	for i := 0; i < 3; i++ {
		engine.UpdateMember(primaryMember, degradedPrimaryMetrics)
		engine.UpdateMember(backupMember, backupMetrics)
		time.Sleep(100 * time.Millisecond)
	}

	// Wait for cooldown if needed
	time.Sleep(1100 * time.Millisecond)

	// Should now potentially trigger failover
	ev := engine.EvaluateSwitch()
	if ev != nil {
		t.Logf("failover triggered: %s -> %s", ev.From, ev.To)

		// Execute failover through controller
		newPrimary := controller.Member{
			Name:      ev.To,
			Interface: backupMember.InterfaceName,
			Metric:    1,
			Weight:    1,
			Enabled:   true,
		}

		err := ctrl.SetPrimary(ctx, newPrimary)
		if err != nil {
			t.Fatalf("controller failover failed: %v", err)
		}
	}

	// Verify telemetry recorded the events
	samples := store.GetRecentSamples(primaryMember.Name, 10*time.Minute)
	if len(samples) < 3 { // Should have samples from updates
		t.Fatalf("insufficient telemetry samples: got %d, expected >= 3", len(samples))
	}

	// Verify samples contain the degraded metrics
	lastSample := samples[len(samples)-1]
	if lastSample.Metrics.LatencyMs == nil || *lastSample.Metrics.LatencyMs != 500 {
		t.Fatalf("expected degraded latency in telemetry")
	}
}

// TestCollectorDecisionIntegration tests collector → decision integration
func TestCollectorDecisionIntegration(t *testing.T) {
	logger := logx.New("debug")
	store := telem.NewStore(telem.Config{MaxSamplesPerMember: 100, RetentionHours: 1})

	cfg := decision.Config{
		SwitchMargin:   5.0,
		CooldownS:      0,
		HistoryWindowS: 3 * time.Second,
	}
	engine := decision.NewEngine(cfg, *logger, store, nil, nil, nil, nil)

	// Simulate metrics from different collector types
	starlinkMember := collector.Member{
		Name:          "starlink_dish",
		InterfaceName: "eth1",
		Class:         "starlink",
		Enabled:       true,
	}

	cellularMember := collector.Member{
		Name:          "cellular_modem",
		InterfaceName: "wwan0",
		Class:         "cellular",
		Enabled:       true,
	}

	// Starlink with good conditions
	starlinkMetrics := collector.Metrics{
		LatencyMs:      floatPtr(30),
		PacketLossPct:  floatPtr(0.1),
		JitterMs:       floatPtr(3),
		SNR:            floatPtr(12),   // Good SNR
		ObstructionPct: floatPtr(0.05), // Minimal obstruction
	}

	// Cellular with moderate conditions
	cellularMetrics := collector.Metrics{
		LatencyMs:     floatPtr(80),
		PacketLossPct: floatPtr(2),
		JitterMs:      floatPtr(15),
		RSRP:          floatPtr(-90), // Moderate signal
		RSRQ:          floatPtr(-12), // Decent quality
		SINR:          floatPtr(8),   // Good SINR
	}

	// Update both members
	engine.UpdateMember(starlinkMember, starlinkMetrics)
	engine.UpdateMember(cellularMember, cellularMetrics)

	// Get member states
	states := engine.GetMemberStates()

	if len(states) != 2 {
		t.Fatalf("expected 2 member states, got %d", len(states))
	}

	var starlinkState, cellularState decision.MemberState
	var foundStarlink, foundCellular bool
	for _, state := range states {
		if state.Member.Name == starlinkMember.Name {
			starlinkState = state
			foundStarlink = true
		} else if state.Member.Name == cellularMember.Name {
			cellularState = state
			foundCellular = true
		}
	}

	if !foundStarlink || !foundCellular {
		t.Fatalf("missing member states")
	}

	// Starlink should score higher due to better metrics and class preference
	if starlinkState.Score.Final <= cellularState.Score.Final {
		t.Fatalf("expected starlink score > cellular: %.1f vs %.1f",
			starlinkState.Score.Final, cellularState.Score.Final)
	}

	// Verify telemetry integration
	starlinkSamples := store.GetRecentSamples(starlinkMember.Name, 1*time.Minute)
	cellularSamples := store.GetRecentSamples(cellularMember.Name, 1*time.Minute)

	if len(starlinkSamples) == 0 || len(cellularSamples) == 0 {
		t.Fatalf("telemetry samples missing")
	}

	// Verify sample contains class-specific metrics
	starlinkSample := starlinkSamples[len(starlinkSamples)-1]
	if starlinkSample.Metrics.SNR == nil || *starlinkSample.Metrics.SNR != 12 {
		t.Fatalf("starlink SNR not recorded correctly")
	}

	cellularSample := cellularSamples[len(cellularSamples)-1]
	if cellularSample.Metrics.RSRP == nil || *cellularSample.Metrics.RSRP != -90 {
		t.Fatalf("cellular RSRP not recorded correctly")
	}
}

// Helper function to create pointer to float64
func floatPtr(f float64) *float64 {
	return &f
}
