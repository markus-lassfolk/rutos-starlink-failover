package starlink

import (
	"context"
	"testing"
	"time"
)

func TestNewClient(t *testing.T) {
	tests := []struct {
		name     string
		dishIP   string
		dishPort int
		wantIP   string
		wantPort int
	}{
		{
			name:     "default values",
			dishIP:   "",
			dishPort: 0,
			wantIP:   "192.168.100.1",
			wantPort: 9200,
		},
		{
			name:     "custom values",
			dishIP:   "10.0.0.1",
			dishPort: 8080,
			wantIP:   "10.0.0.1",
			wantPort: 8080,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := NewClient(tt.dishIP, tt.dishPort)
			if client.dishIP != tt.wantIP {
				t.Errorf("NewClient() dishIP = %v, want %v", client.dishIP, tt.wantIP)
			}
			if client.dishPort != tt.wantPort {
				t.Errorf("NewClient() dishPort = %v, want %v", client.dishPort, tt.wantPort)
			}
			if client.client == nil {
				t.Error("NewClient() client is nil")
			}
		})
	}
}

func TestClient_GetStatus_Timeout(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	// Use short timeout to quickly test timeout behavior
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	
	_, err := client.GetStatus(ctx)
	// We expect this to fail since there's no actual Starlink dish
	if err == nil {
		t.Error("Expected error when connecting to non-existent Starlink dish")
	}
}

func TestClient_GetDiagnostics_Timeout(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	// Use short timeout to quickly test timeout behavior
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	
	_, err := client.GetDiagnostics(ctx)
	// We expect this to fail since there's no actual Starlink dish
	if err == nil {
		t.Error("Expected error when connecting to non-existent Starlink dish")
	}
}

func TestCreateGRPCPayload(t *testing.T) {
	client := NewClient("", 0)
	
	testData := []byte(`{"test": "data"}`)
	payload, err := client.createGRPCPayload(testData)
	
	if err != nil {
		t.Fatalf("createGRPCPayload() error = %v", err)
	}
	
	// Check payload structure:
	// [compression flag:1][length:4][data:length]
	expectedLen := 1 + 4 + len(testData)
	if len(payload) != expectedLen {
		t.Errorf("createGRPCPayload() payload length = %d, want %d", len(payload), expectedLen)
	}
	
	// Check compression flag (should be 0)
	if payload[0] != 0 {
		t.Errorf("createGRPCPayload() compression flag = %d, want 0", payload[0])
	}
}

func TestParseGRPCResponse(t *testing.T) {
	client := NewClient("", 0)
	
	// Create test gRPC frame with test data
	testData := []byte(`{"test": "response"}`)
	testFrame, err := client.createGRPCPayload(testData)
	if err != nil {
		t.Fatalf("Failed to create test frame: %v", err)
	}
	
	// Parse it back
	parsed, err := client.parseGRPCResponse(testFrame)
	if err != nil {
		t.Fatalf("parseGRPCResponse() error = %v", err)
	}
	
	if string(parsed) != string(testData) {
		t.Errorf("parseGRPCResponse() = %s, want %s", string(parsed), string(testData))
	}
}

func TestParseGRPCResponse_InvalidFrame(t *testing.T) {
	client := NewClient("", 0)
	
	tests := []struct {
		name    string
		frame   []byte
		wantErr bool
	}{
		{
			name:    "too short",
			frame:   []byte{0, 0, 0, 1},
			wantErr: true,
		},
		{
			name:    "length mismatch",
			frame:   []byte{0, 0, 0, 0, 10, 0x61, 0x62},
			wantErr: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := client.parseGRPCResponse(tt.frame)
			if (err != nil) != tt.wantErr {
				t.Errorf("parseGRPCResponse() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestClient_GetHistory_Timeout(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	
	_, err := client.GetHistory(ctx)
	if err == nil {
		t.Error("GetHistory() expected timeout error, got nil")
	}
}

func TestClient_GetDeviceInfo_Timeout(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	
	_, err := client.GetDeviceInfo(ctx)
	if err == nil {
		t.Error("GetDeviceInfo() expected timeout error, got nil")
	}
}

func TestClient_GetLocation_Timeout(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	
	_, err := client.GetLocation(ctx)
	if err == nil {
		t.Error("GetLocation() expected timeout error, got nil")
	}
}

func TestDishHistory_StructValidation(t *testing.T) {
	history := &DishHistory{
		Current:              uint32Ptr(42),
		PopPingDropRate:      []float64{0.1, 0.2, 0.3},
		PopPingLatencyMs:     []float64{10.5, 20.1, 15.8},
		DownlinkThroughputBps: []float64{100000, 150000, 120000},
		UplinkThroughputBps:  []float64{10000, 15000, 12000},
		SNR:                  []float64{8.5, 9.2, 7.8},
		Scheduled:            []bool{true, false, true},
		Obstructed:           []bool{false, true, false},
	}
	
	if history.Current == nil || *history.Current != 42 {
		t.Error("DishHistory Current field not set correctly")
	}
	if len(history.PopPingDropRate) != 3 {
		t.Error("DishHistory PopPingDropRate array not set correctly")
	}
	if len(history.SNR) != 3 {
		t.Error("DishHistory SNR array not set correctly")
	}
}

func TestDeviceInfo_StructValidation(t *testing.T) {
	info := &DeviceInfo{
		ID:                   stringPtr("DISH-123456"),
		HardwareVersion:      stringPtr("rev1_pre_production"),
		SoftwareVersion:      stringPtr("2023.26.0"),
		CountryCode:          stringPtr("US"),
		UtcOffsetS:           int32Ptr(-28800),
		SoftwarePartNumber:   stringPtr("1525-00001-01"),
		GenerationNumber:     uint32Ptr(2),
		DishCohoused:         boolPtr(false),
		UtcnsOffsetNs:        uint64Ptr(123456789),
	}
	
	if info.ID == nil || *info.ID != "DISH-123456" {
		t.Error("DeviceInfo ID field not set correctly")
	}
	if info.GenerationNumber == nil || *info.GenerationNumber != 2 {
		t.Error("DeviceInfo GenerationNumber field not set correctly")
	}
	if info.DishCohoused == nil || *info.DishCohoused != false {
		t.Error("DeviceInfo DishCohoused field not set correctly")
	}
}

func TestLocationData_StructValidation(t *testing.T) {
	location := &LocationData{
		LLA: &LLA{
			Lat: float64Ptr(37.7749),
			Lon: float64Ptr(-122.4194),
			Alt: float64Ptr(100.5),
		},
		ECEF: &ECEF{
			X: float64Ptr(1000.0),
			Y: float64Ptr(2000.0),
			Z: float64Ptr(3000.0),
		},
		Source: stringPtr("GPS"),
	}
	
	if location.LLA == nil {
		t.Error("LocationData LLA not set")
	}
	if location.LLA.Lat == nil || *location.LLA.Lat != 37.7749 {
		t.Error("LocationData LLA Lat not set correctly")
	}
	if location.ECEF == nil {
		t.Error("LocationData ECEF not set")
	}
	if location.Source == nil || *location.Source != "GPS" {
		t.Error("LocationData Source not set correctly")
	}
}

// Helper functions for creating pointers to basic types
func float64Ptr(v float64) *float64 { return &v }
func uint32Ptr(v uint32) *uint32 { return &v }
func int32Ptr(v int32) *int32    { return &v }
func uint64Ptr(v uint64) *uint64 { return &v }
func boolPtr(v bool) *bool       { return &v }
func stringPtr(v string) *string { return &v }
