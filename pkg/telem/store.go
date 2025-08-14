// Package telem provides short-term telemetry storage and event logging
package telem

import (
	"fmt"
	"encoding/json"
	"sync"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
)

// Sample represents a timestamped metric sample with computed scores
type Sample struct {
	Timestamp    time.Time         `json:"timestamp"`
	Member       string            `json:"member"`
	Metrics      collector.Metrics `json:"metrics"`
	InstantScore float64           `json:"instant_score"`
	EWMAScore    float64           `json:"ewma_score"`
	FinalScore   float64           `json:"final_score"`
}

// Event represents a system event (state changes, errors, etc.)
type Event struct {
	Timestamp time.Time   `json:"timestamp"`
	Level     string      `json:"level"`
	Type      string      `json:"type"`
	Member    string      `json:"member,omitempty"`
	Message   string      `json:"message"`
	Data      interface{} `json:"data,omitempty"`
}

// Store manages in-memory telemetry data with bounded retention
type Store struct {
	mu            sync.RWMutex
	samples       map[string][]Sample // member -> samples
	events        []Event
	maxSamples    int
	maxEvents     int
	retentionTime time.Duration
	maxRAMMB      int
}

// Config for telemetry store
type Config struct {
	MaxSamplesPerMember int `uci:"max_samples_per_member"`
	MaxEvents           int `uci:"max_events"`
	RetentionHours      int `uci:"retention_hours"`
	MaxRAMMB            int `uci:"max_ram_mb"`
}

// NewStore creates a new telemetry store with the given configuration
func NewStore(config Config) *Store {
	if config.MaxSamplesPerMember <= 0 {
		config.MaxSamplesPerMember = 1000
	}
	if config.MaxEvents <= 0 {
		config.MaxEvents = 500
	}
	if config.RetentionHours <= 0 {
		config.RetentionHours = 24
	}
	if config.MaxRAMMB <= 0 {
		config.MaxRAMMB = 10
	}

	return &Store{
		samples:       make(map[string][]Sample),
		events:        make([]Event, 0, config.MaxEvents),
		maxSamples:    config.MaxSamplesPerMember,
		maxEvents:     config.MaxEvents,
		retentionTime: time.Duration(config.RetentionHours) * time.Hour,
		maxRAMMB:      config.MaxRAMMB,
	}
}

// AddSample stores a new metric sample for a member
func (s *Store) AddSample(sample Sample) {
	s.mu.Lock()
	defer s.mu.Unlock()

	member := sample.Member
	if s.samples[member] == nil {
		s.samples[member] = make([]Sample, 0, s.maxSamples)
	}

	// Add the new sample
	s.samples[member] = append(s.samples[member], sample)

	// Enforce size limits
	if len(s.samples[member]) > s.maxSamples {
		// Keep the most recent samples
		copy(s.samples[member], s.samples[member][len(s.samples[member])-s.maxSamples:])
		s.samples[member] = s.samples[member][:s.maxSamples]
	}

	// Clean old samples
	s.cleanOldSamples(member)

	// Enforce RAM cap (approximate) after adding
	s.enforceRAMCapLocked()
}

// AddEvent stores a new system event
func (s *Store) AddEvent(event Event) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.events = append(s.events, event)

	// Enforce size limits
	if len(s.events) > s.maxEvents {
		// Keep the most recent events
		copy(s.events, s.events[len(s.events)-s.maxEvents:])
		s.events = s.events[:s.maxEvents]
	}

	// Enforce RAM cap (approximate) after adding
	s.enforceRAMCapLocked()
}

// GetSamples returns recent samples for a member
func (s *Store) GetSamples(member string, limit int) []Sample {
	s.mu.RLock()
	defer s.mu.RUnlock()

	samples := s.samples[member]
	if samples == nil {
		return nil
	}

	if limit <= 0 || limit >= len(samples) {
		// Return a copy of all samples
		result := make([]Sample, len(samples))
		copy(result, samples)
		return result
	}

	// Return the most recent samples
	start := len(samples) - limit
	result := make([]Sample, limit)
	copy(result, samples[start:])
	return result
}

// GetRecentSamples returns samples for a member within a time window
func (s *Store) GetRecentSamples(member string, since time.Duration) []Sample {
	s.mu.RLock()
	defer s.mu.RUnlock()

	samples := s.samples[member]
	if samples == nil {
		return nil
	}

	cutoff := time.Now().Add(-since)
	var result []Sample

	for _, sample := range samples {
		if sample.Timestamp.After(cutoff) {
			result = append(result, sample)
		}
	}

	return result
}

// GetEvents returns recent events
func (s *Store) GetEvents(limit int) []Event {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if limit <= 0 || limit >= len(s.events) {
		// Return a copy of all events
		result := make([]Event, len(s.events))
		copy(result, s.events)
		return result
	}

	// Return the most recent events
	start := len(s.events) - limit
	result := make([]Event, limit)
	copy(result, s.events[start:])
	return result
}

// GetMembers returns a list of all members with stored samples
func (s *Store) GetMembers() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	members := make([]string, 0, len(s.samples))
	for member := range s.samples {
		members = append(members, member)
	}
	return members
}

// Cleanup removes old data based on retention policy
func (s *Store) Cleanup() {
	s.mu.Lock()
	defer s.mu.Unlock()

	for member := range s.samples {
		s.cleanOldSamples(member)
	}

	s.cleanOldEvents()
}

// cleanOldSamples removes samples older than retention time for a member
func (s *Store) cleanOldSamples(member string) {
	cutoff := time.Now().Add(-s.retentionTime)
	samples := s.samples[member]

	// Find the first sample to keep
	keepIndex := 0
	for i, sample := range samples {
		if sample.Timestamp.After(cutoff) {
			keepIndex = i
			break
		}
		keepIndex = i + 1
	}

	if keepIndex > 0 {
		// Remove old samples
		copy(samples, samples[keepIndex:])
		s.samples[member] = samples[:len(samples)-keepIndex]
	}
}

// cleanOldEvents removes events older than retention time
func (s *Store) cleanOldEvents() {
	cutoff := time.Now().Add(-s.retentionTime)

	// Find the first event to keep
	keepIndex := 0
	for i, event := range s.events {
		if event.Timestamp.After(cutoff) {
			keepIndex = i
			break
		}
		keepIndex = i + 1
	}

	if keepIndex > 0 {
		// Remove old events
		copy(s.events, s.events[keepIndex:])
		s.events = s.events[:len(s.events)-keepIndex]
	}
}

// GetStats returns storage statistics
func (s *Store) GetStats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	memberStats := make(map[string]int)
	totalSamples := 0
	for member, samples := range s.samples {
		memberStats[member] = len(samples)
		totalSamples += len(samples)
	}

	estBytes := s.estimateBytesLocked()

	return map[string]interface{}{
		"total_samples":   totalSamples,
		"total_events":    len(s.events),
		"member_samples":  memberStats,
		"retention_hours": s.retentionTime.Hours(),
		"max_ram_mb":      s.maxRAMMB,
		"estimated_bytes": estBytes,
	}
}

// ExportJSON exports all data as JSON for debugging/analysis
func (s *Store) ExportJSON() ([]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	export := struct {
		Timestamp time.Time              `json:"timestamp"`
		Samples   map[string][]Sample    `json:"samples"`
		Events    []Event                `json:"events"`
		Stats     map[string]interface{} `json:"stats"`
	}{
		Timestamp: time.Now(),
		Samples:   s.samples,
		Events:    s.events,
		Stats:     s.GetStats(),
	}

	return json.Marshal(export)
}

// --- RAM cap enforcement helpers ---

// estimateBytesLocked returns an approximate memory usage for telemetry content.
// It assumes a conservative size per sample/event to avoid exceeding the cap.
func (s *Store) estimateBytesLocked() int {
	const (
		bytesPerSample = 320 // rough estimate including maps/struct overhead
		bytesPerEvent  = 160
	)
	totalSamples := 0
	for _, arr := range s.samples {
		totalSamples += len(arr)
	}
	return totalSamples*bytesPerSample + len(s.events)*bytesPerEvent
}

// enforceRAMCapLocked downsamples old samples/events when the estimated memory
// exceeds the configured maxRAMMB cap. Must be called with s.mu locked.
func (s *Store) enforceRAMCapLocked() {
	if s.maxRAMMB <= 0 {
		return
	}
	capBytes := s.maxRAMMB * 1024 * 1024
	// Try up to a few rounds of downsampling to get under cap
	for i := 0; i < 5; i++ {
		if s.estimateBytesLocked() <= capBytes {
			return
		}
		// Downsample each member's older samples by factor 2
		for m, arr := range s.samples {
			if len(arr) <= 200 {
				continue
			}
			s.samples[m] = downsampleKeepRecent(arr, 2, 100)
		}
		// Trim older events by half if still above cap
		if len(s.events) > 200 && s.estimateBytesLocked() > capBytes {
			keep := len(s.events) / 2
			copy(s.events, s.events[len(s.events)-keep:])
			s.events = s.events[:keep]
		}
	}
}

// downsampleKeepRecent keeps the last recentKeep items intact and downsamples
// the older portion by keeping every nth item. The order is preserved.
func downsampleKeepRecent[T any](in []T, n int, recentKeep int) []T {
	if n <= 1 || len(in) <= recentKeep {
		return in
	}
	if recentKeep < 0 {
		recentKeep = 0
	}
	cutoff := len(in) - recentKeep
	if cutoff < 0 {
		cutoff = 0
	}
	older := in[:cutoff]
	newer := in[cutoff:]
	// keep every nth from older
	kept := make([]T, 0, len(older)/n+len(newer))
	for i := 0; i < len(older); i++ {
		if i%n == 0 {
			kept = append(kept, older[i])
		}
	}
	kept = append(kept, newer...)
	return kept
}

// SetMaxRAMMB updates the RAM cap and enforces it immediately.
func (s *Store) SetMaxRAMMB(mb int) error {
	if mb < 4 || mb > 128 {
		return fmt.Errorf("max_ram_mb must be between 4-128, got %d", mb)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.maxRAMMB = mb
	s.enforceRAMCapLocked()
	return nil
}
