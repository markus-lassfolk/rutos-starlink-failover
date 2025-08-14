package telem

import (
	"testing"
	"time"
)

func TestRAMCapDownsampling(t *testing.T) {
	cfg := Config{MaxSamplesPerMember: 100000, MaxEvents: 100000, RetentionHours: 24, MaxRAMMB: 1}
	s := NewStore(cfg)

	// Add many samples for two members
	now := time.Now()
	for i := 0; i < 10000; i++ {
		s.AddSample(Sample{Timestamp: now, Member: "wanA"})
		s.AddSample(Sample{Timestamp: now, Member: "wanB"})
	}
	stats := s.GetStats()
	est, _ := stats["estimated_bytes"].(int)
	if est == 0 {
		t.Fatalf("estimated bytes missing or zero")
	}
	if est > s.maxRAMMB*1024*1024 {
		t.Fatalf("estimated bytes still above cap: %v > %v", est, s.maxRAMMB*1024*1024)
	}

	// Increase cap and verify setter works
	if err := s.SetMaxRAMMB(4); err != nil {
		t.Fatalf("SetMaxRAMMB failed: %v", err)
	}
}
