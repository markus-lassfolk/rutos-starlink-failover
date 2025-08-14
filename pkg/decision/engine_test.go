package decision

import (
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"testing"
)

func TestScoreLatency(t *testing.T) {
	logger := logx.New("debug")
	eng := NewEngine(Config{}, *logger, nil, nil, nil, nil)

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

func TestCalculateInstantScoreClassPreference(t *testing.T) {
	cfg := Config{}
	logger := logx.New("debug")
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil)

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
	eng := NewEngine(cfg, *logger, nil, nil, nil, nil)

	eng.currentPrimary = "wan1"
	eng.members["wan1"] = &MemberState{Score: Score{EWMA: 80, Instant: 70}, Eligible: true}
	eng.members["wan2"] = &MemberState{Score: Score{Final: 90}, Eligible: true}

	if !eng.shouldPreemptiveSwitch("wan2") {
		t.Fatalf("expected predictive switch")
	}
}
