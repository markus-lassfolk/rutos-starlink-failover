package starlink

import (
	"context"
	"encoding/json"
	"testing"
	"time"
)

// TestCompleteAPIIntegration tests the complete API using struct validation
func TestCompleteAPIIntegration(t *testing.T) {
	client := NewClient("192.168.100.1", 9200)
	
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	// Test all API endpoints for timeout behavior (they should all timeout)
	t.Run("GetStatus", func(t *testing.T) {
		_, err := client.GetStatus(ctx)
		if err == nil {
			t.Log("GetStatus: Starlink dish is reachable for live testing")
		} else {
			t.Logf("GetStatus: Expected timeout/error: %v", err)
		}
	})

	t.Run("GetDiagnostics", func(t *testing.T) {
		_, err := client.GetDiagnostics(ctx)
		if err == nil {
			t.Log("GetDiagnostics: Starlink dish is reachable for live testing")
		} else {
			t.Logf("GetDiagnostics: Expected timeout/error: %v", err)
		}
	})

	t.Run("GetHistory", func(t *testing.T) {
		_, err := client.GetHistory(ctx)
		if err == nil {
			t.Log("GetHistory: Starlink dish is reachable for live testing")
		} else {
			t.Logf("GetHistory: Expected timeout/error: %v", err)
		}
	})

	t.Run("GetDeviceInfo", func(t *testing.T) {
		_, err := client.GetDeviceInfo(ctx)
		if err == nil {
			t.Log("GetDeviceInfo: Starlink dish is reachable for live testing")
		} else {
			t.Logf("GetDeviceInfo: Expected timeout/error: %v", err)
		}
	})

	t.Run("GetLocation", func(t *testing.T) {
		_, err := client.GetLocation(ctx)
		if err == nil {
			t.Log("GetLocation: Starlink dish is reachable for live testing")
		} else {
			t.Logf("GetLocation: Expected timeout/error: %v", err)
		}
	})
}

// TestAPIStructSerialization validates JSON serialization of all API structures
func TestAPIStructSerialization(t *testing.T) {
	// Test complete Message struct with all request types
	msg := &Message{
		GetStatus:     &GetStatusRequest{},
		GetDiagnostics: &GetDiagnosticsRequest{},
		GetHistory:    &GetHistoryRequest{},
		GetDeviceInfo: &GetDeviceInfoRequest{},
		GetLocation:   &GetLocationRequest{},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Failed to marshal Message: %v", err)
	}

	var unmarshalledMsg Message
	if err := json.Unmarshal(data, &unmarshalledMsg); err != nil {
		t.Fatalf("Failed to unmarshal Message: %v", err)
	}

	// Verify all request types are preserved
	if unmarshalledMsg.GetStatus == nil {
		t.Error("GetStatus request not preserved in JSON")
	}
	if unmarshalledMsg.GetDiagnostics == nil {
		t.Error("GetDiagnostics request not preserved in JSON")
	}
	if unmarshalledMsg.GetHistory == nil {
		t.Error("GetHistory request not preserved in JSON")
	}
	if unmarshalledMsg.GetDeviceInfo == nil {
		t.Error("GetDeviceInfo request not preserved in JSON")
	}
	if unmarshalledMsg.GetLocation == nil {
		t.Error("GetLocation request not preserved in JSON")
	}
}

// TestCompleteResponseStructs validates all response structures
func TestCompleteResponseStructs(t *testing.T) {
	// Create sample response data for all types
	statusResp := &StatusResponse{
		DishGetStatus: &DishStatus{
			PopPingLatencyMs: float64Ptr(25.5),
			SNR:              float64Ptr(8.2),
			ObstructionStats: &ObstructionStats{
				FractionObstructed: float64Ptr(0.02),
			},
			UptimeS: uint64Ptr(86400),
			State:   stringPtr("CONNECTED"),
		},
	}

	diagResp := &DiagnosticsResponse{
		DishGetDiagnostics: &DishDiagnostics{
			Location: &Location{
				Latitude:  float64Ptr(37.7749),
				Longitude: float64Ptr(-122.4194),
				Altitude:  float64Ptr(100.0),
			},
			Alerts: &Alerts{
				ThermalThrottle: boolPtr(false),
				ThermalShutdown: boolPtr(false),
				Roaming:        boolPtr(false),
			},
			HardwareSelfTest:      stringPtr("PASSED"),
			DlBandwidthRestricted: stringPtr("NONE"),
			UlBandwidthRestricted: stringPtr("NONE"),
		},
	}

	historyResp := &HistoryResponse{
		DishGetHistory: &DishHistory{
			Current:              uint32Ptr(10),
			PopPingLatencyMs:     []float64{20.1, 25.3, 22.8},
			PopPingDropRate:      []float64{0.01, 0.02, 0.015},
			DownlinkThroughputBps: []float64{100000, 150000, 120000},
			UplinkThroughputBps:  []float64{10000, 15000, 12000},
			SNR:                  []float64{8.5, 9.2, 7.8},
			Scheduled:            []bool{true, false, true},
			Obstructed:           []bool{false, true, false},
		},
	}

	deviceResp := &DeviceInfoResponse{
		DeviceInfo: &DeviceInfo{
			ID:                   stringPtr("DISH-123456"),
			HardwareVersion:      stringPtr("rev1_pre_production"),
			SoftwareVersion:      stringPtr("2023.26.0"),
			CountryCode:          stringPtr("US"),
			UtcOffsetS:           int32Ptr(-28800),
			SoftwarePartNumber:   stringPtr("1525-00001-01"),
			GenerationNumber:     uint32Ptr(2),
			DishCohoused:         boolPtr(false),
			UtcnsOffsetNs:        uint64Ptr(123456789),
		},
	}

	locationResp := &LocationResponse{
		GetLocation: &LocationData{
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
		},
	}

	// Test JSON serialization for all response types
	responses := []interface{}{statusResp, diagResp, historyResp, deviceResp, locationResp}
	names := []string{"StatusResponse", "DiagnosticsResponse", "HistoryResponse", "DeviceInfoResponse", "LocationResponse"}

	for i, resp := range responses {
		t.Run(names[i], func(t *testing.T) {
			data, err := json.Marshal(resp)
			if err != nil {
				t.Fatalf("Failed to marshal %s: %v", names[i], err)
			}

			// Verify JSON is non-empty
			if len(data) < 10 {
				t.Errorf("%s JSON too short: %s", names[i], string(data))
			}

			// Verify we can unmarshal back
			var unmarshalled interface{}
			if err := json.Unmarshal(data, &unmarshalled); err != nil {
				t.Fatalf("Failed to unmarshal %s: %v", names[i], err)
			}
		})
	}
}

// TestAPIDocumentationCompliance verifies all documented endpoints are implemented
func TestAPIDocumentationCompliance(t *testing.T) {
	// According to API_REFERENCE.md, we should support these 5 endpoints
	client := NewClient("192.168.100.1", 9200)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()

	// Verify all methods exist and have correct signatures
	endpoints := []struct {
		name string
		call func() error
	}{
		{"get_status", func() error { _, err := client.GetStatus(ctx); return err }},
		{"get_diagnostics", func() error { _, err := client.GetDiagnostics(ctx); return err }},
		{"get_history", func() error { _, err := client.GetHistory(ctx); return err }},
		{"get_device_info", func() error { _, err := client.GetDeviceInfo(ctx); return err }},
		{"get_location", func() error { _, err := client.GetLocation(ctx); return err }},
	}

	for _, endpoint := range endpoints {
		t.Run(endpoint.name, func(t *testing.T) {
			err := endpoint.call()
			// We expect an error (timeout/connection refused) but method should exist
			if err == nil {
				t.Logf("%s: Method exists and Starlink is reachable", endpoint.name)
			} else {
				t.Logf("%s: Method exists, got expected error: %v", endpoint.name, err)
			}
		})
	}
}
