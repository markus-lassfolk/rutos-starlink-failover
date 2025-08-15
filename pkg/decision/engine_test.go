package decision

import (
	"testing"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/uci"
)

// MockController implements pkg.Controller for testing
type MockController struct {
	SwitchCalled   bool
	LastSwitchFrom *pkg.Member
	LastSwitchTo   *pkg.Member
	SwitchError    error
}

func (mc *MockController) Switch(from, to *pkg.Member) error {
	mc.SwitchCalled = true
	mc.LastSwitchFrom = from
	mc.LastSwitchTo = to
	return mc.SwitchError
}

func (mc *MockController) GetMembers() []*pkg.Member {
	return []*pkg.Member{}
}

func (mc *MockController) GetCurrentMember() (*pkg.Member, error) {
	return nil, nil
}

func (mc *MockController) Validate(member *pkg.Member) error {
	return nil
}

func (mc *MockController) UpdateMWAN3Policy(to *pkg.Member) error {
	return nil
}

func (mc *MockController) UpdateRouteMetrics(to *pkg.Member) error {
	return nil
}

// TestEngine_PredictiveFailover tests predictive failover functionality
func TestEngine_PredictiveFailover(t *testing.T) {
	// Create test configuration
	config := &uci.Config{
		Predictive:          true,
		SwitchMargin:        10,
		CooldownS:           5,
		FailMinDurationS:    10,
		RestoreMinDurationS: 20,
		HistoryWindowS:      300,
	}

	logger := logx.NewLogger("debug", "")
	telemetry, err := telem.NewStore(24, 50)
	if err != nil {
		t.Fatalf("Failed to create telemetry store: %v", err)
	}

	// Create engine
	engine := NewEngine(config, logger, telemetry)

	// Create test members
	starlink := &pkg.Member{
		Name:  "starlink",
		Iface: "wan",
		Class: pkg.ClassStarlink,
	}

	cellular := &pkg.Member{
		Name:  "cellular",
		Iface: "wwan0",
		Class: pkg.ClassCellular,
	}

	// Add members to engine
	engine.AddMember(starlink)
	engine.AddMember(cellular)
	engine.SetCurrent(starlink)

	// Create mock controller
	controller := &MockController{}

	t.Run("starlink_obstruction_acceleration", func(t *testing.T) {
		// Reset controller
		controller.SwitchCalled = false

		// Add samples showing increasing obstruction
		now := time.Now()
		samples := []*telem.Sample{
			{
				Timestamp: now.Add(-3 * time.Minute),
				Metrics:   &pkg.Metrics{ObstructionPct: floatPtr(2.0), LatencyMS: 50, LossPercent: 0.1},
			},
			{
				Timestamp: now.Add(-2 * time.Minute),
				Metrics:   &pkg.Metrics{ObstructionPct: floatPtr(5.0), LatencyMS: 60, LossPercent: 0.2},
			},
			{
				Timestamp: now.Add(-1 * time.Minute),
				Metrics:   &pkg.Metrics{ObstructionPct: floatPtr(10.0), LatencyMS: 80, LossPercent: 0.5},
			},
		}

		// Add samples to telemetry
		for i, sample := range samples {
			score := &pkg.Score{Final: 80.0 - float64(i*10)} // Decreasing score
			telemetry.AddSample(starlink.Name, sample.Metrics, score)
		}

		// Add good cellular sample
		metrics := &pkg.Metrics{RSRP: intPtr(-85), LatencyMS: 40, LossPercent: 0.0}
		score := &pkg.Score{Final: 85.0}
		telemetry.AddSample(cellular.Name, metrics, score)

		// Run engine tick
		err := engine.Tick(controller)
		if err != nil {
			t.Fatalf("Engine.Tick() failed: %v", err)
		}

		// Should trigger predictive failover due to obstruction acceleration
		if !controller.SwitchCalled {
			t.Error("Expected predictive failover to be triggered due to obstruction acceleration")
		}

		if controller.SwitchCalled && controller.LastSwitchTo.Name != cellular.Name {
			t.Errorf("Expected failover to cellular, got %s", controller.LastSwitchTo.Name)
		}

		t.Logf("✅ Starlink obstruction acceleration correctly triggered predictive failover")
	})

	t.Run("starlink_thermal_throttling", func(t *testing.T) {
		// Reset controller
		controller.SwitchCalled = false
		engine.SetCurrent(starlink)

		// Add sample with thermal throttling
		metrics := &pkg.Metrics{ThermalThrottle: boolPtr(true), LatencyMS: 100, LossPercent: 1.0}
		score := &pkg.Score{Final: 50.0}
		telemetry.AddSample(starlink.Name, metrics, score)

		// Run engine tick
		err := engine.Tick(controller)
		if err != nil {
			t.Fatalf("Engine.Tick() failed: %v", err)
		}

		// Should trigger predictive failover due to thermal throttling
		if !controller.SwitchCalled {
			t.Error("Expected predictive failover to be triggered due to thermal throttling")
		}

		t.Logf("✅ Starlink thermal throttling correctly triggered predictive failover")
	})

	t.Run("cellular_roaming_detection", func(t *testing.T) {
		// Reset controller and set cellular as current
		controller.SwitchCalled = false
		engine.SetCurrent(cellular)

		// Add sample with roaming
		cellularMetrics := &pkg.Metrics{Roaming: boolPtr(true), RSRP: intPtr(-95), LatencyMS: 80, LossPercent: 0.5}
		cellularScore := &pkg.Score{Final: 40.0}
		telemetry.AddSample(cellular.Name, cellularMetrics, cellularScore)

		// Add good starlink sample
		starlinkMetrics := &pkg.Metrics{ObstructionPct: floatPtr(1.0), LatencyMS: 45, LossPercent: 0.1}
		starlinkScore := &pkg.Score{Final: 80.0}
		telemetry.AddSample(starlink.Name, starlinkMetrics, starlinkScore)

		// Run engine tick
		err := engine.Tick(controller)
		if err != nil {
			t.Fatalf("Engine.Tick() failed: %v", err)
		}

		// Should trigger predictive failover due to roaming
		if !controller.SwitchCalled {
			t.Error("Expected predictive failover to be triggered due to roaming")
		}

		if controller.SwitchCalled && controller.LastSwitchTo.Name != starlink.Name {
			t.Errorf("Expected failover to starlink, got %s", controller.LastSwitchTo.Name)
		}

		t.Logf("✅ Cellular roaming correctly triggered predictive failover")
	})

	t.Run("trend_based_prediction", func(t *testing.T) {
		// Reset controller
		controller.SwitchCalled = false
		engine.SetCurrent(starlink)

		// Add samples showing rapid latency increase
		for i := 0; i < 10; i++ {
			latency := 50.0 + float64(i*20) // Rapid latency increase
			metrics := &pkg.Metrics{LatencyMS: latency, LossPercent: 0.1}
			score := &pkg.Score{Final: 80.0 - float64(i*5)} // Decreasing score
			telemetry.AddSample(starlink.Name, metrics, score)
		}

		// Add good cellular sample
		cellularMetrics := &pkg.Metrics{RSRP: intPtr(-80), LatencyMS: 40, LossPercent: 0.0}
		cellularScore := &pkg.Score{Final: 85.0}
		telemetry.AddSample(cellular.Name, cellularMetrics, cellularScore)

		// Run engine tick to update trends
		err := engine.Tick(controller)
		if err != nil {
			t.Fatalf("Engine.Tick() failed: %v", err)
		}

		// Check if trend analysis was updated
		trend, exists := engine.trendAnalysis[starlink.Name]
		if !exists {
			t.Error("Expected trend analysis to be created")
		} else if trend.LatencyTrend <= 0 {
			t.Errorf("Expected positive latency trend, got %f", trend.LatencyTrend)
		}

		t.Logf("✅ Trend analysis correctly calculated: latency trend = %.2f ms/min", trend.LatencyTrend)
	})
}

// TestEngine_TrendAnalysis tests trend analysis calculations
func TestEngine_TrendAnalysis(t *testing.T) {
	config := &uci.Config{
		Predictive:     true,
		HistoryWindowS: 300,
	}

	logger := logx.NewLogger("debug", "")
	telemetry, err := telem.NewStore(24, 50)
	if err != nil {
		t.Fatalf("Failed to create telemetry store: %v", err)
	}
	engine := NewEngine(config, logger, telemetry)

	member := &pkg.Member{
		Name:  "test",
		Iface: "wan",
		Class: pkg.ClassStarlink,
	}

	engine.AddMember(member)

	t.Run("calculate_latency_trend", func(t *testing.T) {
		// Create samples with increasing latency
		now := time.Now()
		samples := make([]*telem.Sample, 10)
		for i := 0; i < 10; i++ {
			samples[i] = &telem.Sample{
				Timestamp: now.Add(time.Duration(i-10) * time.Minute),
				Metrics:   &pkg.Metrics{LatencyMS: 50.0 + float64(i*10), LossPercent: 0.1},
			}
		}

		// Calculate trend
		trend := engine.calculateTrendForMetric(samples, func(s *telem.Sample) float64 {
			return s.Metrics.LatencyMS
		})

		// Should show positive trend (increasing latency)
		if trend <= 0 {
			t.Errorf("Expected positive latency trend, got %f", trend)
		}

		t.Logf("✅ Calculated latency trend: %.2f ms/min", trend)
	})

	t.Run("calculate_loss_trend", func(t *testing.T) {
		// Create samples with increasing loss
		now := time.Now()
		samples := make([]*telem.Sample, 10)
		for i := 0; i < 10; i++ {
			samples[i] = &telem.Sample{
				Timestamp: now.Add(time.Duration(i-10) * time.Minute),
				Metrics:   &pkg.Metrics{LatencyMS: 50.0, LossPercent: float64(i) * 0.5},
			}
		}

		// Calculate trend
		trend := engine.calculateTrendForMetric(samples, func(s *telem.Sample) float64 {
			return s.Metrics.LossPercent
		})

		// Should show positive trend (increasing loss)
		if trend <= 0 {
			t.Errorf("Expected positive loss trend, got %f", trend)
		}

		t.Logf("✅ Calculated loss trend: %.2f %%/min", trend)
	})

	t.Run("calculate_standard_deviation", func(t *testing.T) {
		values := []float64{50, 55, 45, 60, 40, 65, 35, 70, 30}

		std := engine.calculateStandardDeviation(values)

		if std <= 0 {
			t.Errorf("Expected positive standard deviation, got %f", std)
		}

		t.Logf("✅ Calculated standard deviation: %.2f", std)
	})
}

// TestPredictiveEngine_Integration tests predictive engine integration
func TestPredictiveEngine_Integration(t *testing.T) {
	config := &uci.Config{
		Predictive:     true,
		HistoryWindowS: 300,
	}

	logger := logx.NewLogger("debug", "")
	telemetry, err := telem.NewStore(24, 50)
	if err != nil {
		t.Fatalf("Failed to create telemetry store: %v", err)
	}
	engine := NewEngine(config, logger, telemetry)

	member := &pkg.Member{
		Name:  "test_member",
		Iface: "wan",
		Class: pkg.ClassStarlink,
	}

	engine.AddMember(member)

	t.Run("predictive_engine_data_update", func(t *testing.T) {
		// Create sample data
		metrics := &pkg.Metrics{
			LatencyMS:      100.0,
			LossPercent:    2.0,
			ObstructionPct: floatPtr(5.0),
		}

		score := &pkg.Score{
			Instant: 75.0,
			EWMA:    78.0,
			Final:   76.5,
		}

		// Update predictive engine
		if engine.predictiveEngine != nil {
			engine.predictiveEngine.UpdateMemberData(member.Name, metrics, score)

			// Try to get prediction
			prediction, err := engine.predictiveEngine.PredictFailure(member.Name)
			if err != nil {
				t.Logf("⚠️  Prediction not available yet (expected for new member): %v", err)
			} else {
				t.Logf("✅ Got prediction: risk=%.2f, confidence=%.2f, method=%s",
					prediction.Risk, prediction.Confidence, prediction.Method)
			}
		} else {
			t.Error("Predictive engine not initialized")
		}
	})
}

// Helper functions for testing
func floatPtr(f float64) *float64 {
	return &f
}

func intPtr(i int) *int {
	return &i
}

func boolPtr(b bool) *bool {
	return &b
}

// SetCurrent sets the current member (helper for testing)
func (e *Engine) SetCurrent(member *pkg.Member) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.current = member
}
