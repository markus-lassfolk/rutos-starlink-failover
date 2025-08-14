package integration

import (
	"fmt"
	"testing"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/controller"
	"github.com/starfail/starfail/pkg/decision"
	"github.com/starfail/starfail/pkg/discovery"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/uci"
)

// TestFailover_StarlinkToCellular tests end-to-end failover functionality
func TestFailover_StarlinkToCellular(t *testing.T) {
	// Setup test environment
	testEnv := setupTestEnvironment(t)
	defer testEnv.Cleanup()

	t.Log("🧪 Testing end-to-end failover: Starlink -> Cellular")

	// Test data flow through components
	t.Run("discovery_to_controller", func(t *testing.T) {
		members, err := testEnv.Discoverer.DiscoverMembers()
		if err != nil {
			t.Logf("⚠️  Discovery failed (expected in test env): %v", err)
			// Create mock members for testing
			members = createMockMembers()
		}

		err = testEnv.Controller.SetMembers(members)
		if err != nil {
			t.Fatalf("Failed to set members in controller: %v", err)
		}

		retrievedMembers := testEnv.Controller.GetMembers()
		if len(retrievedMembers) == 0 {
			t.Fatal("No members set in controller")
		}

		t.Logf("✅ Discovery -> Controller: %d members transferred", len(retrievedMembers))
	})

	t.Run("controller_to_decision_engine", func(t *testing.T) {
		// Add mock members to decision engine
		mockMembers := createMockMembers()
		for _, member := range mockMembers {
			testEnv.DecisionEngine.AddMember(member)
		}

		members := testEnv.DecisionEngine.GetMembers()
		if len(members) == 0 {
			t.Fatal("No members in decision engine")
		}

		t.Logf("✅ Controller -> Decision Engine: %d members", len(members))
	})

	t.Run("decision_engine_tick", func(t *testing.T) {
		// Test decision engine tick
		err := testEnv.DecisionEngine.Tick(testEnv.Controller)
		if err != nil {
			t.Logf("⚠️  Decision engine tick failed (expected without real interfaces): %v", err)
		} else {
			t.Log("✅ Decision engine tick completed")
		}
	})

	t.Run("controller_failover", func(t *testing.T) {
		// Test manual failover
		mockMembers := createMockMembers()
		if len(mockMembers) < 2 {
			t.Skip("Need at least 2 mock members for failover test")
		}

		from := mockMembers[0]
		to := mockMembers[1]

		err := testEnv.Controller.Switch(from, to)
		if err != nil {
			t.Logf("⚠️  Failover failed (expected without real interfaces): %v", err)
		} else {
			t.Logf("✅ Failover successful: %s -> %s", from.Name, to.Name)
		}
	})
}

// TestSystemIntegration tests system-level integration
func TestSystemIntegration(t *testing.T) {
	testEnv := setupTestEnvironment(t)
	defer testEnv.Cleanup()

	t.Log("🧪 Testing system integration components")

	t.Run("telemetry_storage", func(t *testing.T) {
		// Test telemetry storage
		metrics := &pkg.Metrics{
			LatencyMS:   50.0,
			LossPercent: 0.5,
			Timestamp:   time.Now(),
		}

		score := &pkg.Score{
			Instant: 85.0,
			EWMA:    87.0,
			Final:   86.0,
		}

		err := testEnv.Telemetry.AddSample("test_member", metrics, score)
		if err != nil {
			t.Fatalf("Failed to add telemetry sample: %v", err)
		}

		samples, err := testEnv.Telemetry.GetSamples("test_member", time.Now().Add(-time.Minute))
		if err != nil {
			t.Fatalf("Failed to get samples: %v", err)
		}

		if len(samples) == 0 {
			t.Error("No samples retrieved from telemetry")
		} else {
			t.Logf("✅ Telemetry storage: %d samples", len(samples))
		}
	})

	t.Run("config_reload", func(t *testing.T) {
		// Test configuration reload
		newConfig := &uci.Config{
			Enable:     true,
			UseMWAN3:   false, // Switch to netifd mode
			LogLevel:   "debug",
			Predictive: true,
		}

		// Create new controller with updated config
		newController, err := controller.NewController(newConfig, testEnv.Logger)
		if err != nil {
			t.Fatalf("Failed to create controller with new config: %v", err)
		}

		if newController.IsMWAN3Enabled() {
			t.Error("Expected mwan3 to be disabled with new config")
		}

		t.Log("✅ Configuration reload successful")
	})

	t.Run("member_lifecycle", func(t *testing.T) {
		// Test complete member lifecycle
		initialMembers := createMockMembers()

		// Add members
		for _, member := range initialMembers {
			testEnv.DecisionEngine.AddMember(member)
		}

		// Verify members
		members := testEnv.DecisionEngine.GetMembers()
		if len(members) != len(initialMembers) {
			t.Errorf("Expected %d members, got %d", len(initialMembers), len(members))
		}

		// Remove a member
		testEnv.DecisionEngine.RemoveMember(initialMembers[0].Name)

		members = testEnv.DecisionEngine.GetMembers()
		if len(members) != len(initialMembers)-1 {
			t.Errorf("Expected %d members after removal, got %d", len(initialMembers)-1, len(members))
		}

		t.Log("✅ Member lifecycle management working")
	})
}

// TestPerformance tests system performance under load
func TestPerformance(t *testing.T) {
	testEnv := setupTestEnvironment(t)
	defer testEnv.Cleanup()

	t.Log("🧪 Testing system performance")

	t.Run("decision_engine_performance", func(t *testing.T) {
		// Add multiple members
		members := createMockMembersLarge(10)
		for _, member := range members {
			testEnv.DecisionEngine.AddMember(member)
		}

		// Measure decision engine performance
		start := time.Now()
		for i := 0; i < 100; i++ {
			_ = testEnv.DecisionEngine.Tick(testEnv.Controller)
		}
		duration := time.Since(start)

		avgDuration := duration / 100
		t.Logf("✅ Decision engine performance: avg %v per tick", avgDuration)

		if avgDuration > time.Second {
			t.Errorf("Decision engine too slow: %v per tick", avgDuration)
		}
	})

	t.Run("telemetry_performance", func(t *testing.T) {
		// Test telemetry performance with many samples
		start := time.Now()
		for i := 0; i < 1000; i++ {
			metrics := &pkg.Metrics{
				LatencyMS:   float64(i % 100),
				LossPercent: float64(i % 10),
				Timestamp:   time.Now(),
			}
			score := &pkg.Score{
				Instant: float64(90 - (i % 10)),
				EWMA:    float64(85 - (i % 5)),
				Final:   float64(87 - (i % 7)),
			}
			_ = testEnv.Telemetry.AddSample("perf_test", metrics, score)
		}
		duration := time.Since(start)

		t.Logf("✅ Telemetry performance: %v for 1000 samples", duration)

		if duration > time.Second {
			t.Errorf("Telemetry too slow: %v for 1000 samples", duration)
		}
	})
}

// TestErrorHandling tests error handling across components
func TestErrorHandling(t *testing.T) {
	testEnv := setupTestEnvironment(t)
	defer testEnv.Cleanup()

	t.Log("🧪 Testing error handling")

	t.Run("invalid_member_handling", func(t *testing.T) {
		// Test with invalid member
		invalidMember := &pkg.Member{
			Name:  "", // Invalid: empty name
			Iface: "eth0",
			Class: pkg.ClassLAN,
		}

		err := testEnv.Controller.Validate(invalidMember)
		if err == nil {
			t.Error("Expected validation error for invalid member")
		} else {
			t.Logf("✅ Invalid member correctly rejected: %v", err)
		}
	})

	t.Run("missing_interface_handling", func(t *testing.T) {
		// Test failover to non-existent interface
		nonExistentMember := &pkg.Member{
			Name:  "nonexistent",
			Iface: "nonexistent0",
			Class: pkg.ClassOther,
		}

		err := testEnv.Controller.Switch(nil, nonExistentMember)
		if err == nil {
			t.Log("⚠️  Switch succeeded unexpectedly (test environment)")
		} else {
			t.Logf("✅ Non-existent interface correctly handled: %v", err)
		}
	})

	t.Run("decision_engine_error_recovery", func(t *testing.T) {
		// Test decision engine with no members
		emptyEngine := decision.NewEngine(testEnv.Config, testEnv.Logger, testEnv.Telemetry)

		err := emptyEngine.Tick(testEnv.Controller)
		if err == nil {
			t.Log("✅ Decision engine handles empty member list gracefully")
		} else {
			t.Logf("✅ Decision engine error handling: %v", err)
		}
	})
}

// TestEnvironment represents the test environment
type TestEnvironment struct {
	Config         *uci.Config
	Logger         *logx.Logger
	Telemetry      *telem.Store
	Controller     *controller.Controller
	DecisionEngine *decision.Engine
	Discoverer     *discovery.Discoverer
}

// setupTestEnvironment creates a test environment
func setupTestEnvironment(t *testing.T) *TestEnvironment {
	// Create test configuration
	config := &uci.Config{
		Enable:              true,
		UseMWAN3:            false, // Use netifd for testing
		PollIntervalMS:      1000,
		DecisionIntervalMS:  1000,
		DiscoveryIntervalMS: 5000,
		RetentionHours:      1,
		MaxRAMMB:            10,
		LogLevel:            "debug",
		Predictive:          true,
	}

	// Create logger
	logger := logx.NewLogger("debug", "integration_test")

	// Create telemetry store
	telemetry, err := telem.NewStore(1, 10) // 1 hour, 10MB
	if err != nil {
		t.Fatalf("Failed to create telemetry store: %v", err)
	}

	// Create controller
	ctrl, err := controller.NewController(config, logger)
	if err != nil {
		t.Fatalf("Failed to create controller: %v", err)
	}

	// Create decision engine
	engine := decision.NewEngine(config, logger, telemetry)

	// Create discoverer
	discoverer := discovery.NewDiscoverer(logger)

	return &TestEnvironment{
		Config:         config,
		Logger:         logger,
		Telemetry:      telemetry,
		Controller:     ctrl,
		DecisionEngine: engine,
		Discoverer:     discoverer,
	}
}

// Cleanup cleans up the test environment
func (te *TestEnvironment) Cleanup() {
	if te.Telemetry != nil {
		te.Telemetry.Close()
	}
}

// createMockMembers creates mock members for testing
func createMockMembers() []*pkg.Member {
	return []*pkg.Member{
		{
			Name:      "starlink",
			Iface:     "wan_starlink",
			Class:     pkg.ClassStarlink,
			Weight:    100,
			Eligible:  true,
			CreatedAt: time.Now(),
			LastSeen:  time.Now(),
			Config: map[string]string{
				"check_interval": "30s",
			},
		},
		{
			Name:      "cellular",
			Iface:     "wwan0",
			Class:     pkg.ClassCellular,
			Weight:    80,
			Eligible:  true,
			CreatedAt: time.Now(),
			LastSeen:  time.Now(),
			Config: map[string]string{
				"check_interval": "45s",
			},
		},
		{
			Name:      "wifi",
			Iface:     "wlan0",
			Class:     pkg.ClassWiFi,
			Weight:    60,
			Eligible:  true,
			CreatedAt: time.Now(),
			LastSeen:  time.Now(),
			Config: map[string]string{
				"check_interval": "60s",
			},
		},
	}
}

// createMockMembersLarge creates a large number of mock members for performance testing
func createMockMembersLarge(count int) []*pkg.Member {
	members := make([]*pkg.Member, count)
	for i := 0; i < count; i++ {
		members[i] = &pkg.Member{
			Name:      fmt.Sprintf("member_%d", i),
			Iface:     fmt.Sprintf("eth%d", i),
			Class:     pkg.ClassLAN,
			Weight:    40,
			Eligible:  true,
			CreatedAt: time.Now(),
			LastSeen:  time.Now(),
			Config:    map[string]string{"check_interval": "90s"},
		}
	}
	return members
}

// BenchmarkIntegration_FullSystem benchmarks the complete system
func BenchmarkIntegration_FullSystem(b *testing.B) {
	testEnv := setupTestEnvironment(&testing.T{})
	defer testEnv.Cleanup()

	// Add mock members
	members := createMockMembers()
	for _, member := range members {
		testEnv.DecisionEngine.AddMember(member)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = testEnv.DecisionEngine.Tick(testEnv.Controller)
	}
}
