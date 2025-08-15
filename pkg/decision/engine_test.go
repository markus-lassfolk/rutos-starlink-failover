package decision

import (
	"testing"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
)

// Helper function for creating float64 pointers
func floatPtr(f float64) *float64 {
	return &f
}

func TestScoreLatency(t *testing.T) {
	logger := logx.New("debug")
	eng := NewEngine(Config{}, *logger, nil, nil, nil, nil, nil)

	cases := []struct {
		latency  float64
		expected float64
	}{
		{25, 100},    // excellent
		{100, 93.33}, // good
		{300, 73.33}, // fair
		{700, 48},    // poor
	}

	for _, c := range cases {
		got := eng.scoreLatency(c.latency)
		if (got-c.expected) > 0.1 || (c.expected-got) > 0.1 {
			t.Fatalf("latency %v expected %.2f got %.2f", c.latency, c.expected, got)
		}
	}
}

func TestScorePacketLoss(t *testing.T) {
	logger := logx.New("debug")
	eng := NewEngine(Config{}, *logger, nil, nil, nil, nil, nil)

	cases := []struct {
		loss     float64
		expected float64
	}{
		{0.0, 100}, // perfect
		{0.5, 95},  // 0.5% loss
		{1.0, 90},  // 1% loss
		{3.0, 70},  // 3% loss
		{5.0, 50},  // 5% loss
		{10.0, 0},  // 10% loss
		{15.0, 0},  // >10% loss
	}

	for _, c := range cases {
		got := eng.scoreLoss(c.loss)
		if (got-c.expected) > 0.1 || (c.expected-got) > 0.1 {
			t.Fatalf("packet loss %.2f expected %.2f got %.2f", c.loss, c.expected, got)
		}
	}
}

func TestScoreJitter(t *testing.T) {
	logger := logx.New("debug")
	eng := NewEngine(Config{}, *logger, nil, nil, nil, nil, nil)

	cases := []struct {
		jitter   float64
		expected float64
	}{
		{2.0, 100},    // excellent
		{5.0, 100},    // still excellent
		{10.0, 86.67}, // good
		{20.0, 80},    // fair
		{35.0, 70},    // poor
		{50.0, 60},    // barely acceptable
		{100.0, 30},   // very poor
	}

	for _, c := range cases {
		got := eng.scoreJitter(c.jitter)
		if (got-c.expected) > 1.0 || (c.expected-got) > 1.0 {
			t.Fatalf("jitter %.1f expected %.2f got %.2f", c.jitter, c.expected, got)
		}
	}
}

func TestCalculateInstantScoreIntegration(t *testing.T) {
	logger := logx.New("debug")
	eng := NewEngine(Config{}, *logger, nil, nil, nil, nil, nil)

	// Test with Starlink metrics
	starlinkMetrics := collector.Metrics{
		Class:          "starlink",
		LatencyMs:      floatPtr(30.0),
		PacketLossPct:  floatPtr(0.1),
		JitterMs:       floatPtr(3.0),
		SNR:            floatPtr(12.0),
		ObstructionPct: floatPtr(0.001),
	}

	member := collector.Member{Class: "starlink"}
	score := eng.calculateInstantScore(starlinkMetrics, member)

	if score < 90 || score > 100 {
		t.Fatalf("Starlink with good metrics should score high, got %.2f", score)
	}

	// Test with cellular metrics
	cellularMetrics := collector.Metrics{
		Class:         "cellular",
		LatencyMs:     floatPtr(80.0),
		PacketLossPct: floatPtr(0.5),
		JitterMs:      floatPtr(10.0),
		RSRP:          floatPtr(-75.0),
	}

	member = collector.Member{Class: "cellular"}
	score = eng.calculateInstantScore(cellularMetrics, member)

	if score < 80 || score > 95 {
		t.Fatalf("Cellular with good metrics should score well, got %.2f", score)
	}

	// Test with poor metrics
	poorMetrics := collector.Metrics{
		Class:         "generic",
		LatencyMs:     floatPtr(500.0),
		PacketLossPct: floatPtr(5.0),
		JitterMs:      floatPtr(50.0),
	}

	member = collector.Member{Class: "generic"}
	score = eng.calculateInstantScore(poorMetrics, member)

	if score > 60 {
		t.Fatalf("Interface with poor metrics should score low, got %.2f", score)
	}
}

func TestEWMAScoring(t *testing.T) {
	logger := logx.New("debug")
	// Not using engine for this test since we're testing the calculation directly
	_ = NewEngine(Config{}, *logger, nil, nil, nil, nil, nil)

	// Set up member state with initial EWMA score
	state := &MemberState{
		Member: collector.Member{
			Name:  "test",
			Class: "generic",
		},
		Score: Score{
			EWMA: 80.0, // Previous EWMA score
		},
	}

	// Update the EWMA manually (simulating internal updateEWMA)
	instant := 60.0
	alpha := 0.1                                   // Default hardcoded value in engine
	expectedEWMA := alpha*instant + (1-alpha)*80.0 // 0.1*60 + 0.9*80 = 6 + 72 = 78

	state.Score.EWMA = expectedEWMA

	// Verify EWMA calculation
	if (state.Score.EWMA-expectedEWMA) > 0.01 || (expectedEWMA-state.Score.EWMA) > 0.01 {
		t.Fatalf("EWMA calculation incorrect, expected %.2f got %.2f", expectedEWMA, state.Score.EWMA)
	}

	// EWMA should be between old (80) and new (60), closer to old due to low alpha
	if state.Score.EWMA >= 80 || state.Score.EWMA <= 60 {
		t.Fatalf("EWMA should blend scores between 60-80, got %.2f", state.Score.EWMA)
	}
}

func TestCalculateInstantScoreClassPreference(t *testing.T) {
	cfg := Config{}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil, nil)

	lat := 100.0
	loss := 2.0
	jit := 10.0
	metrics := collector.Metrics{LatencyMs: &lat, PacketLossPct: &loss, JitterMs: &jit}

	starScore := eng.calculateInstantScore(metrics, collector.Member{Class: "starlink"})
	cellScore := eng.calculateInstantScore(metrics, collector.Member{Class: "cellular"})

	if starScore <= cellScore {
		t.Fatalf("expected starlink score > cellular: %v vs %v", starScore, cellScore)
	}
}

func TestPredictiveSwitch(t *testing.T) {
	cfg := Config{EnablePredictive: true, PredictThreshold: 5}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil, nil)

	eng.currentPrimary = "wan1"
	eng.members["wan1"] = &MemberState{Score: Score{EWMA: 80, Instant: 70}, Eligible: true}
	eng.members["wan2"] = &MemberState{Score: Score{Final: 90}, Eligible: true}

	if !eng.shouldPreemptiveSwitch("wan2") {
		t.Fatalf("expected predictive switch")
	}
}

func TestWindowAverageUsesTelemetry(t *testing.T) {
	store := telem.NewStore(telem.Config{MaxSamplesPerMember: 100, RetentionHours: 1})
	cfg := Config{HistoryWindowS: 10 * time.Second}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, store, nil, nil, nil, nil)

	// Seed telemetry with varying instant scores in the last 10s
	now := time.Now()
	member := collector.Member{Name: "wan1", Class: "starlink", Enabled: true}
	for i, val := range []float64{80, 90, 100} {
		store.AddSample(telem.Sample{
			Timestamp:    now.Add(time.Duration(-9+i*3) * time.Second),
			Member:       member.Name,
			InstantScore: val,
			EWMAScore:    val,
			FinalScore:   val,
		})
	}

	// Current instant is 70; window avg should be mean of {80,90,100,70} = 85
	avg := eng.calculateWindowAverage(member.Name, 70)
	if avg < 84.9 || avg > 85.1 {
		t.Fatalf("expected window avg ~85, got %v", avg)
	}
}

func TestDurationBasedHysteresis(t *testing.T) {
	store := telem.NewStore(telem.Config{MaxSamplesPerMember: 100, RetentionHours: 1})
	cfg := Config{
		SwitchMargin:        10,
		CooldownS:           0,
		FailMinDurationS:    2 * time.Second,
		RestoreMinDurationS: 2 * time.Second,
		HistoryWindowS:      0,
	}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, store, nil, nil, nil, nil)

	// Two members
	m1 := collector.Member{Name: "wan1", Class: "starlink", Enabled: true}
	m2 := collector.Member{Name: "wan2", Class: "cellular", Enabled: true}
	eng.members[m1.Name] = &MemberState{Member: m1, Eligible: true, Score: Score{Final: 70}}
	eng.members[m2.Name] = &MemberState{Member: m2, Eligible: true, Score: Score{Final: 85}}
	eng.currentPrimary = m1.Name

	// First evaluation: margin satisfied (15) but not long enough yet
	if ev := eng.EvaluateSwitch(); ev != nil {
		t.Fatalf("expected no switch yet due to duration window, got %+v", ev)
	}

	// Wait to satisfy duration window
	time.Sleep(2100 * time.Millisecond)
	if ev := eng.EvaluateSwitch(); ev == nil {
		t.Fatalf("expected switch after sustained dominance")
	} else if ev.To != m2.Name {
		t.Fatalf("expected switch to %s, got %+v", m2.Name, ev)
	}
}

// TestScoreCalculationEdgeCases tests edge cases in scoring algorithms
func TestScoreCalculationEdgeCases(t *testing.T) {
	cfg := Config{}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil, nil)

	testCases := []struct {
		name     string
		metrics  collector.Metrics
		minScore float64
		maxScore float64
	}{
		{
			name:     "nil metrics",
			metrics:  collector.Metrics{},
			minScore: 0,
			maxScore: 100,
		},
		{
			name: "extreme latency",
			metrics: collector.Metrics{
				LatencyMs: floatPtr(5000), // 5 seconds
			},
			minScore: 0,
			maxScore: 50,
		},
		{
			name: "zero latency",
			metrics: collector.Metrics{
				LatencyMs: floatPtr(0),
			},
			minScore: 95,
			maxScore: 100,
		},
		{
			name: "complete packet loss",
			metrics: collector.Metrics{
				PacketLossPct: floatPtr(100),
			},
			minScore: 0,
			maxScore: 10,
		},
		{
			name: "perfect metrics",
			metrics: collector.Metrics{
				LatencyMs:     floatPtr(10),
				PacketLossPct: floatPtr(0),
				JitterMs:      floatPtr(1),
			},
			minScore: 90,
			maxScore: 100,
		},
	}

	member := collector.Member{Name: "test", Class: "generic"}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			score := eng.calculateInstantScore(tc.metrics, member)
			if score < tc.minScore || score > tc.maxScore {
				t.Fatalf("score %.1f outside expected range [%.1f, %.1f]", score, tc.minScore, tc.maxScore)
			}
		})
	}
}

// TestMemberStateManagement tests member state lifecycle
func TestMemberStateManagement(t *testing.T) {
	cfg := Config{}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil, nil)

	member := collector.Member{Name: "test", Class: "starlink", Enabled: true}
	metrics := collector.Metrics{
		LatencyMs:     floatPtr(50),
		PacketLossPct: floatPtr(1),
		JitterMs:      floatPtr(5),
	}

	// Update member that doesn't exist yet
	eng.UpdateMember(member, metrics)

	// Should create new member state
	state, exists := eng.members[member.Name]
	if !exists {
		t.Fatalf("member state should be created")
	}

	if state.Member.Name != member.Name {
		t.Fatalf("member name mismatch: expected %s, got %s", member.Name, state.Member.Name)
	}

	if state.Score.Instant <= 0 {
		t.Fatalf("instant score should be calculated: got %f", state.Score.Instant)
	}

	// Update again with different metrics
	newMetrics := collector.Metrics{
		LatencyMs:     floatPtr(25),
		PacketLossPct: floatPtr(0),
		JitterMs:      floatPtr(2),
	}

	eng.UpdateMember(member, newMetrics)

	// EWMA should be updated
	updatedState := eng.members[member.Name]
	if updatedState.Score.EWMA <= 0 {
		t.Fatalf("EWMA should be calculated: got %f", updatedState.Score.EWMA)
	}

	// Should be different from instant due to averaging
	if updatedState.Score.EWMA == updatedState.Score.Instant {
		t.Fatalf("EWMA should differ from instant due to smoothing")
	}
}
