package collector

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/starfail/starfail/pkg"
)

// TestStarlinkCollector_Collect tests the enhanced Starlink collector
func TestStarlinkCollector_Collect(t *testing.T) {
	// Create mock Starlink API server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/status" {
			http.NotFound(w, r)
			return
		}

		// Mock comprehensive Starlink API response
		response := StarlinkAPIResponse{
			Status: struct {
				ObstructionStats struct {
					CurrentlyObstructed              bool      `json:"currentlyObstructed"`
					FractionObstructed               float64   `json:"fractionObstructed"`
					Last24hObstructedS               int       `json:"last24hObstructedS"`
					ValidS                           int       `json:"validS"`
					WedgeFractionObstructed          []float64 `json:"wedgeFractionObstructed"`
					WedgeAbsFractionObstructed       []float64 `json:"wedgeAbsFractionObstructed"`
					TimeObstructed                   float64   `json:"timeObstructed"`
					PatchesValid                     int       `json:"patchesValid"`
					AvgProlongedObstructionIntervalS float64   `json:"avgProlongedObstructionIntervalS"`
				} `json:"obstructionStats"`
				Outage struct {
					LastOutageS    int `json:"lastOutageS"`
					OutageCount    int `json:"outageCount"`
					OutageDuration int `json:"outageDuration"`
				} `json:"outage"`
				PopPingLatencyMs      float64 `json:"popPingLatencyMs"`
				DownlinkThroughputBps float64 `json:"downlinkThroughputBps"`
				UplinkThroughputBps   float64 `json:"uplinkThroughputBps"`
				PopPingDropRate       float64 `json:"popPingDropRate"`
				SnrDb                 float64 `json:"snrDb"`
				SecondsSinceLastSnr   int     `json:"secondsSinceLastSnr"`
				HardwareSelfTest      struct {
					Passed       bool     `json:"passed"`
					TestResults  []string `json:"testResults"`
					LastTestTime int64    `json:"lastTestTime"`
				} `json:"hardwareSelfTest"`
				Thermal struct {
					Temperature     float64 `json:"temperature"`
					ThermalThrottle bool    `json:"thermalThrottle"`
					ThermalShutdown bool    `json:"thermalShutdown"`
				} `json:"thermal"`
				Power struct {
					PowerDraw  float64 `json:"powerDraw"`
					Voltage    float64 `json:"voltage"`
					PowerState string  `json:"powerState"`
				} `json:"power"`
				BandwidthRestrictions struct {
					Restricted      bool    `json:"restricted"`
					RestrictionType string  `json:"restrictionType"`
					MaxDownloadMbps float64 `json:"maxDownloadMbps"`
					MaxUploadMbps   float64 `json:"maxUploadMbps"`
				} `json:"bandwidthRestrictions"`
				System struct {
					UptimeS         int      `json:"uptimeS"`
					AlertsActive    []string `json:"alertsActive"`
					ScheduledReboot bool     `json:"scheduledReboot"`
					RebootTimeS     int64    `json:"rebootTimeS"`
					SoftwareVersion string   `json:"softwareVersion"`
					HardwareVersion string   `json:"hardwareVersion"`
				} `json:"system"`
				GPS struct {
					Latitude  float64 `json:"latitude"`
					Longitude float64 `json:"longitude"`
					Altitude  float64 `json:"altitude"`
					GPSValid  bool    `json:"gpsValid"`
					GPSLocked bool    `json:"gpsLocked"`
				} `json:"gps"`
			}{
				ObstructionStats: struct {
					CurrentlyObstructed              bool      `json:"currentlyObstructed"`
					FractionObstructed               float64   `json:"fractionObstructed"`
					Last24hObstructedS               int       `json:"last24hObstructedS"`
					ValidS                           int       `json:"validS"`
					WedgeFractionObstructed          []float64 `json:"wedgeFractionObstructed"`
					WedgeAbsFractionObstructed       []float64 `json:"wedgeAbsFractionObstructed"`
					TimeObstructed                   float64   `json:"timeObstructed"`
					PatchesValid                     int       `json:"patchesValid"`
					AvgProlongedObstructionIntervalS float64   `json:"avgProlongedObstructionIntervalS"`
				}{
					CurrentlyObstructed:              false,
					FractionObstructed:               0.02,
					Last24hObstructedS:               120,
					ValidS:                           3600,
					TimeObstructed:                   45.5,
					PatchesValid:                     95,
					AvgProlongedObstructionIntervalS: 15.2,
				},
				Outage: struct {
					LastOutageS    int `json:"lastOutageS"`
					OutageCount    int `json:"outageCount"`
					OutageDuration int `json:"outageDuration"`
				}{
					LastOutageS:    0,
					OutageCount:    2,
					OutageDuration: 45,
				},
				PopPingLatencyMs:      28.5,
				DownlinkThroughputBps: 150000000,
				UplinkThroughputBps:   12000000,
				PopPingDropRate:       0.001,
				SnrDb:                 12.5,
				SecondsSinceLastSnr:   5,
				HardwareSelfTest: struct {
					Passed       bool     `json:"passed"`
					TestResults  []string `json:"testResults"`
					LastTestTime int64    `json:"lastTestTime"`
				}{
					Passed:       true,
					TestResults:  []string{"antenna_ok", "modem_ok", "power_ok"},
					LastTestTime: time.Now().Unix(),
				},
				Thermal: struct {
					Temperature     float64 `json:"temperature"`
					ThermalThrottle bool    `json:"thermalThrottle"`
					ThermalShutdown bool    `json:"thermalShutdown"`
				}{
					Temperature:     45.2,
					ThermalThrottle: false,
					ThermalShutdown: false,
				},
				Power: struct {
					PowerDraw  float64 `json:"powerDraw"`
					Voltage    float64 `json:"voltage"`
					PowerState string  `json:"powerState"`
				}{
					PowerDraw:  85.4,
					Voltage:    54.2,
					PowerState: "normal",
				},
				BandwidthRestrictions: struct {
					Restricted      bool    `json:"restricted"`
					RestrictionType string  `json:"restrictionType"`
					MaxDownloadMbps float64 `json:"maxDownloadMbps"`
					MaxUploadMbps   float64 `json:"maxUploadMbps"`
				}{
					Restricted:      false,
					RestrictionType: "",
					MaxDownloadMbps: 0,
					MaxUploadMbps:   0,
				},
				System: struct {
					UptimeS         int      `json:"uptimeS"`
					AlertsActive    []string `json:"alertsActive"`
					ScheduledReboot bool     `json:"scheduledReboot"`
					RebootTimeS     int64    `json:"rebootTimeS"`
					SoftwareVersion string   `json:"softwareVersion"`
					HardwareVersion string   `json:"hardwareVersion"`
				}{
					UptimeS:         86400,
					AlertsActive:    []string{},
					ScheduledReboot: false,
					RebootTimeS:     0,
					SoftwareVersion: "2024.12.1",
					HardwareVersion: "rev2_proto3",
				},
				GPS: struct {
					Latitude  float64 `json:"latitude"`
					Longitude float64 `json:"longitude"`
					Altitude  float64 `json:"altitude"`
					GPSValid  bool    `json:"gpsValid"`
					GPSLocked bool    `json:"gpsLocked"`
				}{
					Latitude:  37.7749,
					Longitude: -122.4194,
					Altitude:  50.0,
					GPSValid:  true,
					GPSLocked: true,
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}))
	defer server.Close()

	// Create Starlink collector with mock server
	config := map[string]interface{}{
		"timeout": 5 * time.Second,
		"targets": []string{"127.0.0.1"}, // Use localhost to avoid network issues
	}

	collector, err := NewStarlinkCollector(config)
	if err != nil {
		t.Fatalf("Failed to create Starlink collector: %v", err)
	}

	// Override API host to use mock server
	collector.apiHost = server.URL[7:] // Remove "http://"

	// Test Starlink-specific metrics collection directly (bypass common metrics)
	ctx := context.Background()
	starlinkMetrics, err := collector.collectStarlinkMetrics(ctx)
	if err != nil {
		t.Fatalf("collectStarlinkMetrics failed: %v", err)
	}

	// Verify Starlink-specific metrics
	metrics := starlinkMetrics

	// Verify basic metrics
	if metrics == nil {
		t.Fatal("Expected non-nil metrics")
	}

	if metrics.ObstructionPct == nil {
		t.Error("Expected obstruction percentage")
	} else if *metrics.ObstructionPct != 2.0 { // 0.02 * 100
		t.Errorf("Expected obstruction 2.0%%, got %.1f%%", *metrics.ObstructionPct)
	}

	if metrics.Outages == nil {
		t.Error("Expected outages count")
	} else if *metrics.Outages != 2 {
		t.Errorf("Expected 2 outages, got %d", *metrics.Outages)
	}

	if metrics.LatencyMS != 28.5 {
		t.Errorf("Expected latency 28.5ms, got %.1fms", metrics.LatencyMS)
	}

	if metrics.LossPercent != 0.1 { // 0.001 * 100
		t.Errorf("Expected loss 0.1%%, got %.1f%%", metrics.LossPercent)
	}

	if metrics.SNR == nil {
		t.Error("Expected SNR value")
	} else if *metrics.SNR != 12 { // int(12.5) = 12
		t.Errorf("Expected SNR 12dB, got %ddB", *metrics.SNR)
	}

	// Verify enhanced metrics using proper struct fields
	if metrics.UptimeS == nil {
		t.Error("Expected uptime")
	} else if *metrics.UptimeS != 86400 {
		t.Errorf("Expected uptime 86400s, got %ds", *metrics.UptimeS)
	}

	if metrics.HardwareSelfTest == nil {
		t.Error("Expected hardware self test result")
	} else if *metrics.HardwareSelfTest != "passed" {
		t.Errorf("Expected hardware test passed, got %s", *metrics.HardwareSelfTest)
	}

	if metrics.ThermalThrottle == nil {
		t.Error("Expected thermal throttle status")
	} else if *metrics.ThermalThrottle != false {
		t.Errorf("Expected thermal throttle false, got %v", *metrics.ThermalThrottle)
	}

	if metrics.GPSValid == nil {
		t.Error("Expected GPS valid status")
	} else if *metrics.GPSValid != true {
		t.Errorf("Expected GPS valid true, got %v", *metrics.GPSValid)
	}

	if metrics.GPSLatitude == nil {
		t.Error("Expected GPS latitude")
	} else if *metrics.GPSLatitude != 37.7749 {
		t.Errorf("Expected GPS latitude 37.7749, got %f", *metrics.GPSLatitude)
	}

	if metrics.ObstructionTimePct == nil {
		t.Error("Expected obstruction time percentage")
	}

	if metrics.ObstructionPatchesValid == nil {
		t.Error("Expected obstruction patches valid")
	}

	t.Logf("✅ Enhanced Starlink collector test passed with comprehensive metrics")
}

// TestStarlinkCollector_CheckHardwareHealth tests hardware health assessment
func TestStarlinkCollector_CheckHardwareHealth(t *testing.T) {
	tests := []struct {
		name            string
		temperature     float64
		thermalThrottle bool
		thermalShutdown bool
		voltage         float64
		snrDb           float64
		scheduledReboot bool
		alertsActive    []string
		expectedHealth  string
		expectedAlerts  int
	}{
		{
			name:            "healthy system",
			temperature:     45.0,
			thermalThrottle: false,
			thermalShutdown: false,
			voltage:         54.0,
			snrDb:           15.0,
			scheduledReboot: false,
			alertsActive:    []string{},
			expectedHealth:  "healthy",
			expectedAlerts:  0,
		},
		{
			name:            "thermal warning",
			temperature:     72.0,
			thermalThrottle: false,
			thermalShutdown: false,
			voltage:         54.0,
			snrDb:           15.0,
			scheduledReboot: false,
			alertsActive:    []string{},
			expectedHealth:  "healthy",
			expectedAlerts:  1,
		},
		{
			name:            "thermal throttling",
			temperature:     75.0,
			thermalThrottle: true,
			thermalShutdown: false,
			voltage:         54.0,
			snrDb:           15.0,
			scheduledReboot: false,
			alertsActive:    []string{},
			expectedHealth:  "degraded",
			expectedAlerts:  2,
		},
		{
			name:            "critical system",
			temperature:     80.0,
			thermalThrottle: true,
			thermalShutdown: true,
			voltage:         45.0, // Low voltage
			snrDb:           3.0,  // Low SNR
			scheduledReboot: true,
			alertsActive:    []string{"hardware_fault", "signal_degraded"},
			expectedHealth:  "critical",
			expectedAlerts:  6,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create mock server for this test case
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				response := StarlinkAPIResponse{
					Status: struct {
						ObstructionStats struct {
							CurrentlyObstructed              bool      `json:"currentlyObstructed"`
							FractionObstructed               float64   `json:"fractionObstructed"`
							Last24hObstructedS               int       `json:"last24hObstructedS"`
							ValidS                           int       `json:"validS"`
							WedgeFractionObstructed          []float64 `json:"wedgeFractionObstructed"`
							WedgeAbsFractionObstructed       []float64 `json:"wedgeAbsFractionObstructed"`
							TimeObstructed                   float64   `json:"timeObstructed"`
							PatchesValid                     int       `json:"patchesValid"`
							AvgProlongedObstructionIntervalS float64   `json:"avgProlongedObstructionIntervalS"`
						} `json:"obstructionStats"`
						Outage struct {
							LastOutageS    int `json:"lastOutageS"`
							OutageCount    int `json:"outageCount"`
							OutageDuration int `json:"outageDuration"`
						} `json:"outage"`
						PopPingLatencyMs      float64 `json:"popPingLatencyMs"`
						DownlinkThroughputBps float64 `json:"downlinkThroughputBps"`
						UplinkThroughputBps   float64 `json:"uplinkThroughputBps"`
						PopPingDropRate       float64 `json:"popPingDropRate"`
						SnrDb                 float64 `json:"snrDb"`
						SecondsSinceLastSnr   int     `json:"secondsSinceLastSnr"`
						HardwareSelfTest      struct {
							Passed       bool     `json:"passed"`
							TestResults  []string `json:"testResults"`
							LastTestTime int64    `json:"lastTestTime"`
						} `json:"hardwareSelfTest"`
						Thermal struct {
							Temperature     float64 `json:"temperature"`
							ThermalThrottle bool    `json:"thermalThrottle"`
							ThermalShutdown bool    `json:"thermalShutdown"`
						} `json:"thermal"`
						Power struct {
							PowerDraw  float64 `json:"powerDraw"`
							Voltage    float64 `json:"voltage"`
							PowerState string  `json:"powerState"`
						} `json:"power"`
						BandwidthRestrictions struct {
							Restricted      bool    `json:"restricted"`
							RestrictionType string  `json:"restrictionType"`
							MaxDownloadMbps float64 `json:"maxDownloadMbps"`
							MaxUploadMbps   float64 `json:"maxUploadMbps"`
						} `json:"bandwidthRestrictions"`
						System struct {
							UptimeS         int      `json:"uptimeS"`
							AlertsActive    []string `json:"alertsActive"`
							ScheduledReboot bool     `json:"scheduledReboot"`
							RebootTimeS     int64    `json:"rebootTimeS"`
							SoftwareVersion string   `json:"softwareVersion"`
							HardwareVersion string   `json:"hardwareVersion"`
						} `json:"system"`
						GPS struct {
							Latitude  float64 `json:"latitude"`
							Longitude float64 `json:"longitude"`
							Altitude  float64 `json:"altitude"`
							GPSValid  bool    `json:"gpsValid"`
							GPSLocked bool    `json:"gpsLocked"`
						} `json:"gps"`
					}{
						SnrDb: tt.snrDb,
						HardwareSelfTest: struct {
							Passed       bool     `json:"passed"`
							TestResults  []string `json:"testResults"`
							LastTestTime int64    `json:"lastTestTime"`
						}{
							Passed: true,
						},
						Thermal: struct {
							Temperature     float64 `json:"temperature"`
							ThermalThrottle bool    `json:"thermalThrottle"`
							ThermalShutdown bool    `json:"thermalShutdown"`
						}{
							Temperature:     tt.temperature,
							ThermalThrottle: tt.thermalThrottle,
							ThermalShutdown: tt.thermalShutdown,
						},
						Power: struct {
							PowerDraw  float64 `json:"powerDraw"`
							Voltage    float64 `json:"voltage"`
							PowerState string  `json:"powerState"`
						}{
							Voltage: tt.voltage,
						},
						System: struct {
							UptimeS         int      `json:"uptimeS"`
							AlertsActive    []string `json:"alertsActive"`
							ScheduledReboot bool     `json:"scheduledReboot"`
							RebootTimeS     int64    `json:"rebootTimeS"`
							SoftwareVersion string   `json:"softwareVersion"`
							HardwareVersion string   `json:"hardwareVersion"`
						}{
							AlertsActive:    tt.alertsActive,
							ScheduledReboot: tt.scheduledReboot,
						},
						ObstructionStats: struct {
							CurrentlyObstructed              bool      `json:"currentlyObstructed"`
							FractionObstructed               float64   `json:"fractionObstructed"`
							Last24hObstructedS               int       `json:"last24hObstructedS"`
							ValidS                           int       `json:"validS"`
							WedgeFractionObstructed          []float64 `json:"wedgeFractionObstructed"`
							WedgeAbsFractionObstructed       []float64 `json:"wedgeAbsFractionObstructed"`
							TimeObstructed                   float64   `json:"timeObstructed"`
							PatchesValid                     int       `json:"patchesValid"`
							AvgProlongedObstructionIntervalS float64   `json:"avgProlongedObstructionIntervalS"`
						}{
							FractionObstructed:               0.01,
							AvgProlongedObstructionIntervalS: 10.0,
						},
					},
				}

				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(response)
			}))
			defer server.Close()

			config := map[string]interface{}{
				"timeout": 5 * time.Second,
			}

			collector, err := NewStarlinkCollector(config)
			if err != nil {
				t.Fatalf("Failed to create collector: %v", err)
			}

			collector.apiHost = server.URL[7:] // Remove "http://"

			health, err := collector.CheckHardwareHealth(context.Background())
			if err != nil {
				t.Fatalf("CheckHardwareHealth failed: %v", err)
			}

			if health.OverallHealth != tt.expectedHealth {
				t.Errorf("Expected health %s, got %s", tt.expectedHealth, health.OverallHealth)
			}

			if len(health.PredictiveAlerts) != tt.expectedAlerts {
				t.Errorf("Expected %d alerts, got %d: %v", tt.expectedAlerts, len(health.PredictiveAlerts), health.PredictiveAlerts)
			}

			t.Logf("✅ %s: health=%s, alerts=%d", tt.name, health.OverallHealth, len(health.PredictiveAlerts))
		})
	}
}

// TestStarlinkCollector_DetectPredictiveFailure tests predictive failure detection
func TestStarlinkCollector_DetectPredictiveFailure(t *testing.T) {
	collector, err := NewStarlinkCollector(map[string]interface{}{})
	if err != nil {
		t.Fatalf("Failed to create collector: %v", err)
	}

	// Test with insufficient data
	t.Run("insufficient_data", func(t *testing.T) {
		metrics := []*pkg.Metrics{
			{Timestamp: time.Now()},
		}

		assessment := collector.DetectPredictiveFailure(context.Background(), metrics)
		if assessment.FailureRisk != "unknown" {
			t.Errorf("Expected unknown risk with insufficient data, got %s", assessment.FailureRisk)
		}
	})

	// Test obstruction acceleration
	t.Run("obstruction_acceleration", func(t *testing.T) {
		obstruction1 := 1.0
		obstruction2 := 4.0
		obstruction3 := 7.0

		metrics := []*pkg.Metrics{
			{Timestamp: time.Now().Add(-2 * time.Minute), ObstructionPct: &obstruction1},
			{Timestamp: time.Now().Add(-1 * time.Minute), ObstructionPct: &obstruction2},
			{Timestamp: time.Now(), ObstructionPct: &obstruction3},
		}

		assessment := collector.DetectPredictiveFailure(context.Background(), metrics)
		if assessment.FailureRisk != "high" {
			t.Errorf("Expected high risk for obstruction acceleration, got %s", assessment.FailureRisk)
		}

		found := false
		for _, trigger := range assessment.Triggers {
			if trigger == "obstruction_acceleration" {
				found = true
				break
			}
		}
		if !found {
			t.Error("Expected obstruction_acceleration trigger")
		}
	})

	// Test SNR degradation
	t.Run("snr_degradation", func(t *testing.T) {
		snr1 := 15
		snr2 := 12
		snr3 := 9

		metrics := []*pkg.Metrics{
			{Timestamp: time.Now().Add(-2 * time.Minute), SNR: &snr1},
			{Timestamp: time.Now().Add(-1 * time.Minute), SNR: &snr2},
			{Timestamp: time.Now(), SNR: &snr3},
		}

		assessment := collector.DetectPredictiveFailure(context.Background(), metrics)
		if assessment.FailureRisk == "low" {
			t.Errorf("Expected elevated risk for SNR degradation, got %s", assessment.FailureRisk)
		}

		found := false
		for _, trigger := range assessment.Triggers {
			if trigger == "snr_degradation" {
				found = true
				break
			}
		}
		if !found {
			t.Error("Expected snr_degradation trigger")
		}
	})

	// Test thermal issues
	t.Run("thermal_issues", func(t *testing.T) {
		thermalThrottleFalse := false
		thermalThrottleTrue := true
		thermalShutdownFalse := false

		metrics := []*pkg.Metrics{
			{
				Timestamp:       time.Now().Add(-2 * time.Minute),
				ThermalThrottle: &thermalThrottleFalse,
				ThermalShutdown: &thermalShutdownFalse,
			},
			{
				Timestamp:       time.Now().Add(-1 * time.Minute),
				ThermalThrottle: &thermalThrottleTrue,
				ThermalShutdown: &thermalShutdownFalse,
			},
			{
				Timestamp:       time.Now(),
				ThermalThrottle: &thermalThrottleTrue,
				ThermalShutdown: &thermalShutdownFalse,
			},
		}

		assessment := collector.DetectPredictiveFailure(context.Background(), metrics)
		if assessment.FailureRisk != "high" {
			t.Errorf("Expected high risk for thermal issues, got %s", assessment.FailureRisk)
		}

		found := false
		for _, trigger := range assessment.Triggers {
			if trigger == "thermal_degradation" {
				found = true
				break
			}
		}
		if !found {
			t.Error("Expected thermal_degradation trigger")
		}
	})

	t.Log("✅ Predictive failure detection tests passed")
}

// BenchmarkStarlinkCollector_Collect benchmarks the enhanced collector
func BenchmarkStarlinkCollector_Collect(b *testing.B) {
	// Create simple mock server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		response := StarlinkAPIResponse{} // Minimal response
		json.NewEncoder(w).Encode(response)
	}))
	defer server.Close()

	collector, err := NewStarlinkCollector(map[string]interface{}{
		"timeout": 1 * time.Second,
	})
	if err != nil {
		b.Fatalf("Failed to create collector: %v", err)
	}

	collector.apiHost = server.URL[7:]

	member := &pkg.Member{
		Name:  "starlink_bench",
		Iface: "wan_starlink",
		Class: pkg.ClassStarlink,
	}

	ctx := context.Background()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = collector.Collect(ctx, member)
	}
}
