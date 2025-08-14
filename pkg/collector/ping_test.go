package collector

import "testing"

func TestCalculateMean(t *testing.T) {
	pc := NewPingCollector(nil)
	values := []float64{10, 20, 30}
	if m := pc.calculateMean(values); m != 20 {
		t.Fatalf("expected 20 got %v", m)
	}
}

func TestCalculateJitter(t *testing.T) {
	pc := NewPingCollector(nil)
	latencies := []float64{10, 20, 30, 20}
	jitter := pc.calculateJitter(latencies)
	if jitter <= 0 {
		t.Fatalf("expected positive jitter got %v", jitter)
	}
}

func TestLANSupportsInterface(t *testing.T) {
	lc := NewLANCollector(nil)
	if !lc.SupportsInterface("eth0") {
		t.Fatalf("expected eth0 supported")
	}
	if lc.SupportsInterface("wwan0") {
		t.Fatalf("did not expect wwan0 supported")
	}
}
