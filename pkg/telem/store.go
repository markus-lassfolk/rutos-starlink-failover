package telem

import (
	"fmt"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
)

// Store manages telemetry data in RAM with ring buffers
type Store struct {
	mu sync.RWMutex

	// Configuration
	retentionHours int
	maxRAMMB       int

	// Ring buffers
	samples map[string]*RingBuffer // per-member samples
	events  *RingBuffer            // system events

	// Memory tracking
	memoryUsage int64
	lastCleanup time.Time
}

// RingBuffer implements a thread-safe ring buffer with time-based retention
type RingBuffer struct {
	mu       sync.RWMutex
	data     []interface{}
	capacity int
	head     int
	tail     int
	size     int
	lastAdd  time.Time
}

// Sample represents a telemetry sample with metadata
type Sample struct {
	Member    string                 `json:"member"`
	Timestamp time.Time              `json:"timestamp"`
	Metrics   map[string]interface{} `json:"metrics"`
	Score     *pkg.Score             `json:"score,omitempty"`
}

// NewStore creates a new telemetry store
func NewStore(retentionHours, maxRAMMB int) (*Store, error) {
	if retentionHours < 1 || retentionHours > 168 {
		return nil, fmt.Errorf("retention_hours must be between 1 and 168")
	}
	if maxRAMMB < 1 || maxRAMMB > 128 {
		return nil, fmt.Errorf("max_ram_mb must be between 1 and 128")
	}

	store := &Store{
		retentionHours: retentionHours,
		maxRAMMB:       maxRAMMB,
		samples:        make(map[string]*RingBuffer),
		events:         NewRingBuffer(1000), // 1000 events max
		lastCleanup:    time.Now(),
	}

	return store, nil
}

// AddSample adds a sample for a member
func (s *Store) AddSample(member string, metrics *pkg.Metrics, score *pkg.Score) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Ensure ring buffer exists for this member
	if s.samples[member] == nil {
		s.samples[member] = NewRingBuffer(1000) // 1000 samples per member
	}

	// Create sample
	sample := &Sample{
		Member:    member,
		Timestamp: time.Now(),
		Metrics:   metricsToMap(metrics),
		Score:     score,
	}

	// Add to ring buffer
	s.samples[member].Add(sample)

	// Check memory pressure
	s.checkMemoryPressure()

	return nil
}

// AddEvent adds a system event
func (s *Store) AddEvent(event *pkg.Event) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.events.Add(event)

	// Check memory pressure
	s.checkMemoryPressure()

	return nil
}

// GetSamples returns samples for a member within a time window
func (s *Store) GetSamples(member string, since time.Time) ([]*Sample, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	buffer, exists := s.samples[member]
	if !exists {
		return []*Sample{}, nil
	}

	// Convert interface{} to []*Sample
	items := buffer.GetSince(since)
	samples := make([]*Sample, 0, len(items))
	for _, item := range items {
		if sample, ok := item.(*Sample); ok {
			samples = append(samples, sample)
		}
	}

	return samples, nil
}

// GetEvents returns events within a time window
func (s *Store) GetEvents(since time.Time, limit int) ([]*pkg.Event, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	events := s.events.GetSince(since)
	if limit > 0 && len(events) > limit {
		events = events[:limit]
	}

	result := make([]*pkg.Event, len(events))
	for i, event := range events {
		if e, ok := event.(*pkg.Event); ok {
			result[i] = e
		}
	}

	return result, nil
}

// GetMembers returns all member names with samples
func (s *Store) GetMembers() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	members := make([]string, 0, len(s.samples))
	for member := range s.samples {
		members = append(members, member)
	}

	return members
}

// GetMemoryUsage returns current memory usage in MB
func (s *Store) GetMemoryUsage() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return int(s.memoryUsage / 1024 / 1024)
}

// Cleanup removes old data based on retention policy
func (s *Store) Cleanup() {
	s.mu.Lock()
	defer s.mu.Unlock()

	cutoff := time.Now().Add(-time.Duration(s.retentionHours) * time.Hour)

	// Cleanup samples
	for member, buffer := range s.samples {
		buffer.RemoveBefore(cutoff)
		if buffer.Size() == 0 {
			delete(s.samples, member)
		}
	}

	// Cleanup events
	s.events.RemoveBefore(cutoff)

	// Update memory usage
	s.updateMemoryUsage()
}

// Close cleans up resources
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Clear all data
	s.samples = make(map[string]*RingBuffer)
	s.events = nil
	s.memoryUsage = 0

	return nil
}

// checkMemoryPressure checks if we need to reduce memory usage
func (s *Store) checkMemoryPressure() {
	s.updateMemoryUsage()

	if s.memoryUsage > int64(s.maxRAMMB*1024*1024) {
		// Memory pressure - downsample old data
		s.downsample()
	}

	// Periodic cleanup
	if time.Since(s.lastCleanup) > time.Hour {
		s.Cleanup()
		s.lastCleanup = time.Now()
	}
}

// updateMemoryUsage estimates current memory usage
func (s *Store) updateMemoryUsage() {
	var usage int64

	// Estimate samples memory
	for _, buffer := range s.samples {
		usage += int64(buffer.Size() * 512) // Rough estimate per sample
	}

	// Estimate events memory
	usage += int64(s.events.Size() * 256) // Rough estimate per event

	s.memoryUsage = usage
}

// downsample reduces memory usage by keeping every Nth sample
func (s *Store) downsample() {
	// Keep every 3rd sample for old data
	for _, buffer := range s.samples {
		buffer.Downsample(3)
	}
}

// metricsToMap converts metrics to a map for storage
func metricsToMap(metrics *pkg.Metrics) map[string]interface{} {
	if metrics == nil {
		return nil
	}

	result := map[string]interface{}{
		"lat_ms":    metrics.LatencyMS,
		"loss_pct":  metrics.LossPercent,
		"jitter_ms": metrics.JitterMS,
	}

	if metrics.ObstructionPct != nil {
		result["obstruction_pct"] = *metrics.ObstructionPct
	}
	if metrics.Outages != nil {
		result["outages"] = *metrics.Outages
	}
	if metrics.RSRP != nil {
		result["rsrp"] = *metrics.RSRP
	}
	if metrics.RSRQ != nil {
		result["rsrq"] = *metrics.RSRQ
	}
	if metrics.SINR != nil {
		result["sinr"] = *metrics.SINR
	}
	if metrics.SignalStrength != nil {
		result["signal"] = *metrics.SignalStrength
	}
	if metrics.NoiseLevel != nil {
		result["noise"] = *metrics.NoiseLevel
	}
	if metrics.SNR != nil {
		result["snr"] = *metrics.SNR
	}
	if metrics.Bitrate != nil {
		result["bitrate"] = *metrics.Bitrate
	}
	if metrics.NetworkType != nil {
		result["network_type"] = *metrics.NetworkType
	}
	if metrics.Roaming != nil {
		result["roaming"] = *metrics.Roaming
	}
	if metrics.Operator != nil {
		result["operator"] = *metrics.Operator
	}
	if metrics.Band != nil {
		result["band"] = *metrics.Band
	}
	if metrics.CellID != nil {
		result["cell_id"] = *metrics.CellID
	}

	return result
}

// NewRingBuffer creates a new ring buffer
func NewRingBuffer(capacity int) *RingBuffer {
	return &RingBuffer{
		data:     make([]interface{}, capacity),
		capacity: capacity,
		head:     0,
		tail:     0,
		size:     0,
	}
}

// Add adds an item to the ring buffer
func (rb *RingBuffer) Add(item interface{}) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	rb.data[rb.tail] = item
	rb.tail = (rb.tail + 1) % rb.capacity
	rb.lastAdd = time.Now()

	if rb.size < rb.capacity {
		rb.size++
	} else {
		rb.head = (rb.head + 1) % rb.capacity
	}
}

// GetSince returns items since the given time
func (rb *RingBuffer) GetSince(since time.Time) []interface{} {
	rb.mu.RLock()
	defer rb.mu.RUnlock()

	var result []interface{}

	for i := 0; i < rb.size; i++ {
		idx := (rb.head + i) % rb.capacity
		item := rb.data[idx]

		if sample, ok := item.(*Sample); ok {
			if sample.Timestamp.After(since) {
				result = append(result, sample)
			}
		} else if event, ok := item.(*pkg.Event); ok {
			if event.Timestamp.After(since) {
				result = append(result, event)
			}
		}
	}

	return result
}

// RemoveBefore removes items before the given time
func (rb *RingBuffer) RemoveBefore(before time.Time) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	// Simple approach: just reset if all data is old
	allOld := true
	for i := 0; i < rb.size; i++ {
		idx := (rb.head + i) % rb.capacity
		item := rb.data[idx]

		if sample, ok := item.(*Sample); ok {
			if sample.Timestamp.After(before) {
				allOld = false
				break
			}
		} else if event, ok := item.(*pkg.Event); ok {
			if event.Timestamp.After(before) {
				allOld = false
				break
			}
		}
	}

	if allOld {
		rb.head = 0
		rb.tail = 0
		rb.size = 0
	}
}

// Downsample keeps every Nth item
func (rb *RingBuffer) Downsample(n int) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	if rb.size == 0 {
		return
	}

	newData := make([]interface{}, rb.capacity)
	newSize := 0
	newHead := 0

	for i := 0; i < rb.size; i += n {
		idx := (rb.head + i) % rb.capacity
		newData[newSize] = rb.data[idx]
		newSize++
	}

	rb.data = newData
	rb.head = newHead
	rb.tail = newSize % rb.capacity
	rb.size = newSize
}

// Size returns the current number of items
func (rb *RingBuffer) Size() int {
	rb.mu.RLock()
	defer rb.mu.RUnlock()
	return rb.size
}

// Capacity returns the buffer capacity
func (rb *RingBuffer) Capacity() int {
	return rb.capacity
}
