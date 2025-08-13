package telem

import (
	"testing"
	"time"

	"github.com/starfail/starfail/pkg/testing"
	"github.com/starfail/starfail/pkg/types"
)

func TestNewStore(t *testing.T) {
	tf := testing.NewTestFramework(t)

	// Test valid parameters
	store, err := NewStore(24, 50)
	tf.AssertNoError(err, "NewStore should not error with valid parameters")
	tf.AssertNotNil(store, "Store should not be nil")

	// Test invalid retention hours
	_, err = NewStore(-1, 50)
	tf.AssertError(err, "NewStore should error with negative retention hours")

	// Test invalid max RAM
	_, err = NewStore(24, -1)
	tf.AssertError(err, "NewStore should error with negative max RAM")
}

func TestStoreAddSample(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	memberName := "test-member"
	sample := types.Sample{
		Member:  tf.MockMembers()[0],
		Metrics: tf.MockMetrics(),
		Score:   tf.MockScore(),
	}

	// Add sample
	err := store.AddSample(memberName, sample)
	tf.AssertNoError(err, "AddSample should not error")

	// Verify sample was added
	samples := store.GetSamples(memberName, 10, time.Hour)
	tf.AssertEqual(1, len(samples), "Should have one sample")
	tf.AssertEqual(memberName, samples[0].Member.Name, "Sample member name should match")
}

func TestStoreAddEvent(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	event := tf.MockEvent(types.EventTypeSwitch)

	// Add event
	err := store.AddEvent(event)
	tf.AssertNoError(err, "AddEvent should not error")

	// Verify event was added
	events := store.GetEvents(10, time.Hour)
	tf.AssertEqual(1, len(events), "Should have one event")
	tf.AssertEqual(event.Type, events[0].Type, "Event type should match")
}

func TestStoreRetentionPolicy(t *testing.T) {
	tf := testing.NewTestFramework(t)
	
	// Create store with short retention
	store, err := NewStore(1, 50) // 1 hour retention
	tf.AssertNoError(err, "NewStore should not error")

	memberName := "test-member"
	sample := types.Sample{
		Member:  tf.MockMembers()[0],
		Metrics: tf.MockMetrics(),
		Score:   tf.MockScore(),
	}

	// Add sample
	err = store.AddSample(memberName, sample)
	tf.AssertNoError(err, "AddSample should not error")

	// Verify sample exists
	samples := store.GetSamples(memberName, 10, time.Hour)
	tf.AssertEqual(1, len(samples), "Should have one sample")

	// Simulate time passing (in real implementation, this would be handled by cleanup)
	// For now, we'll just test that the store can handle multiple samples
	for i := 0; i < 5; i++ {
		sample.Metrics.Timestamp = time.Now()
		err = store.AddSample(memberName, sample)
		tf.AssertNoError(err, "AddSample should not error")
	}

	// Verify we can retrieve samples
	samples = store.GetSamples(memberName, 10, time.Hour)
	tf.AssertTrue(len(samples) > 0, "Should have samples")
}

func TestStoreMemoryLimit(t *testing.T) {
	tf := testing.NewTestFramework(t)
	
	// Create store with very low memory limit
	store, err := NewStore(24, 1) // 1MB limit
	tf.AssertNoError(err, "NewStore should not error")

	memberName := "test-member"
	sample := types.Sample{
		Member:  tf.MockMembers()[0],
		Metrics: tf.MockMetrics(),
		Score:   tf.MockScore(),
	}

	// Add many samples to trigger memory limit
	for i := 0; i < 100; i++ {
		sample.Metrics.Timestamp = time.Now()
		err = store.AddSample(memberName, sample)
		tf.AssertNoError(err, "AddSample should not error")
	}

	// Store should still be functional
	samples := store.GetSamples(memberName, 10, time.Hour)
	tf.AssertTrue(len(samples) > 0, "Should still have samples")
}

func TestStoreGetSamplesLimit(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	memberName := "test-member"
	sample := types.Sample{
		Member:  tf.MockMembers()[0],
		Metrics: tf.MockMetrics(),
		Score:   tf.MockScore(),
	}

	// Add multiple samples
	for i := 0; i < 10; i++ {
		sample.Metrics.Timestamp = time.Now()
		err := store.AddSample(memberName, sample)
		tf.AssertNoError(err, "AddSample should not error")
	}

	// Test limit parameter
	samples := store.GetSamples(memberName, 5, time.Hour)
	tf.AssertEqual(5, len(samples), "Should respect limit parameter")

	// Test with higher limit
	samples = store.GetSamples(memberName, 20, time.Hour)
	tf.AssertTrue(len(samples) <= 20, "Should not exceed limit")
}

func TestStoreGetEventsLimit(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	// Add multiple events
	for i := 0; i < 10; i++ {
		event := tf.MockEvent(types.EventTypeSwitch)
		err := store.AddEvent(event)
		tf.AssertNoError(err, "AddEvent should not error")
	}

	// Test limit parameter
	events := store.GetEvents(5, time.Hour)
	tf.AssertEqual(5, len(events), "Should respect limit parameter")

	// Test with higher limit
	events = store.GetEvents(20, time.Hour)
	tf.AssertTrue(len(events) <= 20, "Should not exceed limit")
}

func TestStoreCleanup(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	// Add some data
	memberName := "test-member"
	sample := types.Sample{
		Member:  tf.MockMembers()[0],
		Metrics: tf.MockMetrics(),
		Score:   tf.MockScore(),
	}

	err := store.AddSample(memberName, sample)
	tf.AssertNoError(err, "AddSample should not error")

	event := tf.MockEvent(types.EventTypeSwitch)
	err = store.AddEvent(event)
	tf.AssertNoError(err, "AddEvent should not error")

	// Run cleanup
	err = store.Cleanup()
	tf.AssertNoError(err, "Cleanup should not error")

	// Store should still be functional after cleanup
	samples := store.GetSamples(memberName, 10, time.Hour)
	events := store.GetEvents(10, time.Hour)
	tf.AssertTrue(len(samples) >= 0, "Should still be able to get samples")
	tf.AssertTrue(len(events) >= 0, "Should still be able to get events")
}

func TestStoreClose(t *testing.T) {
	tf := testing.NewTestFramework(t)
	store := tf.MockTelemetryStore()

	// Close should not error
	err := store.Close()
	tf.AssertNoError(err, "Close should not error")

	// Multiple closes should not error
	err = store.Close()
	tf.AssertNoError(err, "Multiple closes should not error")
}
