package collector

import (
	"context"
	"testing"
	"time"

	"github.com/starfail/starfail/pkg"
)

func TestStarlinkCollector_Collect(t *testing.T) {
	tests := []struct {
		name        string
		member      *pkg.Member
		wantErr     bool
		wantMetrics bool
	}{
		{
			name: "valid starlink member",
			member: &pkg.Member{
				Name:     "starlink_test",
				Class:    "starlink",
				Iface:    "wan_starlink",
				Eligible: true,
				Weight:   100,
			},
			wantErr:     false,
			wantMetrics: true,
		},
		{
			name:        "invalid member - nil",
			member:      nil,
			wantErr:     true,
			wantMetrics: false,
		},
		{
			name: "invalid member - empty name",
			member: &pkg.Member{
				Name:  "",
				Class: "starlink",
				Iface: "wan_starlink",
			},
			wantErr:     true,
			wantMetrics: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create collector with test config
			config := map[string]interface{}{
				"api_host": "127.0.0.1", // Use localhost for testing
				"timeout":  time.Second * 5,
			}

			sc, err := NewStarlinkCollector(config)
			if err != nil {
				t.Fatalf("NewStarlinkCollector() error = %v", err)
			}

			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			metrics, err := sc.Collect(ctx, tt.member)

			if (err != nil) != tt.wantErr {
				t.Errorf("StarlinkCollector.Collect() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.wantMetrics && metrics == nil {
				t.Error("StarlinkCollector.Collect() expected metrics but got nil")
			}

			if !tt.wantMetrics && metrics != nil {
				t.Error("StarlinkCollector.Collect() expected no metrics but got some")
			}

			// Validate metrics structure if we expect metrics
			if tt.wantMetrics && metrics != nil {
				if metrics.Timestamp.IsZero() {
					t.Error("Expected non-zero timestamp in metrics")
				}
				if metrics.LatencyMS < 0 {
					t.Error("Expected non-negative latency")
				}
				if metrics.LossPercent < 0 || metrics.LossPercent > 100 {
					t.Error("Expected loss percentage between 0-100")
				}
			}
		})
	}
}

func TestStarlinkCollector_NativeGRPC(t *testing.T) {
	tests := []struct {
		name    string
		apiHost string
		wantErr bool
	}{
		{
			name:    "valid connection - localhost",
			apiHost: "127.0.0.1",
			wantErr: true, // Expected to fail since no real Starlink on localhost
		},
		{
			name:    "invalid host",
			apiHost: "invalid.host.example",
			wantErr: true,
		},
		{
			name:    "starlink default",
			apiHost: "192.168.100.1",
			wantErr: false, // May succeed if real Starlink is present
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]interface{}{
				"api_host": tt.apiHost,
				"timeout":  time.Second * 2, // Short timeout for tests
			}

			sc, err := NewStarlinkCollector(config)
			if err != nil {
				t.Fatalf("NewStarlinkCollector() error = %v", err)
			}

			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()

			response, err := sc.callStarlinkNativeGRPC(ctx)

			if tt.wantErr && err == nil {
				t.Errorf("callStarlinkNativeGRPC() expected error but got none")
			}

			if !tt.wantErr && err != nil {
				t.Logf("callStarlinkNativeGRPC() error = %v (may be expected if no Starlink present)", err)
			}

			// If we got a response, validate its structure
			if response != nil {
				if response.Status.DeviceInfo.ID == "" {
					t.Error("Expected device ID in response")
				}
				if response.Status.PopPingLatencyMs < 0 {
					t.Error("Expected non-negative latency")
				}
			}
		})
	}
}

func TestStarlinkCollector_ProtobufParsing(t *testing.T) {
	tests := []struct {
		name     string
		data     []byte
		wantErr  bool
		wantData bool
	}{
		{
			name:     "empty data",
			data:     []byte{},
			wantErr:  true,
			wantData: false,
		},
		{
			name:     "too short data",
			data:     []byte{0x01, 0x02},
			wantErr:  true,
			wantData: false,
		},
		{
			name: "mock protobuf data",
			data: []byte{
				0x0A, 0x10, // Field 1, length 16
				0x08, 0x96, 0x01, // Field 1: varint 150
				0x15, 0x00, 0x00, 0x34, 0x42, // Field 2: float 45.0
				0x1D, 0x9A, 0x99, 0x19, 0x3F, // Field 3: float 0.6
				0x25, 0x00, 0x00, 0x08, 0x41, // Field 4: float 8.5
			},
			wantErr:  false,
			wantData: true,
		},
		{
			name:     "simple varint field",
			data:     []byte{0x08, 0x96, 0x01}, // Field 1: varint 150
			wantErr:  false,
			wantData: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]interface{}{}
			sc, err := NewStarlinkCollector(config)
			if err != nil {
				t.Fatalf("NewStarlinkCollector() error = %v", err)
			}

			response, err := sc.parseProtobufResponse(tt.data)

			if (err != nil) != tt.wantErr {
				t.Errorf("parseProtobufResponse() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.wantData && response == nil {
				t.Error("parseProtobufResponse() expected response but got nil")
			}

			if !tt.wantData && response != nil {
				t.Error("parseProtobufResponse() expected no response but got some")
			}

			// Validate response structure if we expect data
			if tt.wantData && response != nil {
				// Check that we have reasonable default values
				if response.Status.DeviceInfo.ID == "" {
					t.Error("Expected device ID in parsed response")
				}
			}
		})
	}
}

func TestStarlinkCollector_CreateRequest(t *testing.T) {
	config := map[string]interface{}{}
	sc, err := NewStarlinkCollector(config)
	if err != nil {
		t.Fatalf("NewStarlinkCollector() error = %v", err)
	}

	// Test basic request creation
	request, err := sc.createStarlinkRequest()
	if err != nil {
		t.Errorf("createStarlinkRequest() error = %v", err)
	}

	if len(request) == 0 {
		t.Error("createStarlinkRequest() returned empty request")
	}

	// Test alternative requests
	requests := sc.createAlternativeStarlinkRequests()
	if len(requests) == 0 {
		t.Error("createAlternativeStarlinkRequests() returned no requests")
	}

	for i, req := range requests {
		if len(req) == 0 {
			t.Errorf("Alternative request %d is empty", i)
		}
	}
}

func TestStarlinkCollector_ProtobufFieldParsing(t *testing.T) {
	tests := []struct {
		name       string
		data       []byte
		wantFields int
		wantErr    bool
	}{
		{
			name:       "empty data",
			data:       []byte{},
			wantFields: 0,
			wantErr:    false,
		},
		{
			name:       "single varint field",
			data:       []byte{0x08, 0x96, 0x01}, // Field 1: varint 150
			wantFields: 1,
			wantErr:    false,
		},
		{
			name:       "multiple fields",
			data:       []byte{0x08, 0x96, 0x01, 0x10, 0xC8, 0x01}, // Field 1: 150, Field 2: 200
			wantFields: 2,
			wantErr:    false,
		},
		{
			name:       "string field",
			data:       []byte{0x12, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F}, // Field 2: "hello"
			wantFields: 1,
			wantErr:    false,
		},
		{
			name:       "malformed data",
			data:       []byte{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}, // Invalid varint
			wantFields: 0,
			wantErr:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]interface{}{}
			sc, err := NewStarlinkCollector(config)
			if err != nil {
				t.Fatalf("NewStarlinkCollector() error = %v", err)
			}

			fields, err := sc.parseProtobufFields(tt.data)

			if (err != nil) != tt.wantErr {
				t.Errorf("parseProtobufFields() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if len(fields) != tt.wantFields {
				t.Errorf("parseProtobufFields() got %d fields, want %d", len(fields), tt.wantFields)
			}
		})
	}
}

func TestStarlinkCollector_FloatExtraction(t *testing.T) {
	config := map[string]interface{}{}
	sc, err := NewStarlinkCollector(config)
	if err != nil {
		t.Fatalf("NewStarlinkCollector() error = %v", err)
	}

	// Test data with known float values (IEEE 754)
	testData := []byte{
		0x00, 0x00, 0x34, 0x42, // float32: 45.0
		0x9A, 0x99, 0x19, 0x3F, // float32: 0.6
		0x00, 0x00, 0x08, 0x41, // float32: 8.5
		0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x46, 0x40, // float64: 45.0
	}

	floats := sc.extractFloatsFromBytes(testData)

	if len(floats) == 0 {
		t.Error("extractFloatsFromBytes() found no floats in test data")
	}

	// Check that we found reasonable values
	foundReasonable := false
	for _, f := range floats {
		if f > 40 && f < 50 { // Should find 45.0
			foundReasonable = true
			break
		}
	}

	if !foundReasonable {
		t.Errorf("extractFloatsFromBytes() didn't find expected float values, got: %v", floats)
	}
}

// Benchmark tests for performance validation
func BenchmarkStarlinkCollector_ParseProtobuf(b *testing.B) {
	config := map[string]interface{}{}
	sc, _ := NewStarlinkCollector(config)

	// Mock protobuf data
	testData := []byte{
		0x0A, 0x10, // Field 1, length 16
		0x08, 0x96, 0x01, // Field 1: varint 150
		0x15, 0x00, 0x00, 0x34, 0x42, // Field 2: float 45.0
		0x1D, 0x9A, 0x99, 0x19, 0x3F, // Field 3: float 0.6
		0x25, 0x00, 0x00, 0x08, 0x41, // Field 4: float 8.5
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = sc.parseProtobufResponse(testData)
	}
}

func BenchmarkStarlinkCollector_CreateRequest(b *testing.B) {
	config := map[string]interface{}{}
	sc, _ := NewStarlinkCollector(config)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = sc.createStarlinkRequest()
	}
}
