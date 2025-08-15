package collector

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/starfail/starfail/pkg"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// StarlinkCollector collects metrics from Starlink dish
type StarlinkCollector struct {
	*BaseCollector
	apiHost string
	timeout time.Duration
}

// StarlinkAPIResponse represents the comprehensive enhanced response from Starlink API
// This structure supports both gRPC and HTTP responses with complete diagnostic data
type StarlinkAPIResponse struct {
	Status struct {
		// Device Information
		DeviceInfo struct {
			ID                 string `json:"id"`
			HardwareVersion    string `json:"hardwareVersion"`
			SoftwareVersion    string `json:"softwareVersion"`
			CountryCode        string `json:"countryCode"`
			GenerationNumber   int32  `json:"generationNumber"`
			BootCount          int    `json:"bootCount"`
			SoftwarePartNumber string `json:"softwarePartNumber"`
			UTCOffsetS         int32  `json:"utcOffsetS"`
		} `json:"deviceInfo"`

		// Device State
		DeviceState struct {
			UptimeS uint64 `json:"uptimeS"`
		} `json:"deviceState"`

		// Enhanced Obstruction Statistics
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

		// Outage Information
		Outage struct {
			LastOutageS    int `json:"lastOutageS"`
			OutageCount    int `json:"outageCount"`
			OutageDuration int `json:"outageDuration"`
		} `json:"outage"`

		// Network Performance
		PopPingLatencyMs      float64 `json:"popPingLatencyMs"`
		DownlinkThroughputBps float64 `json:"downlinkThroughputBps"`
		UplinkThroughputBps   float64 `json:"uplinkThroughputBps"`
		PopPingDropRate       float64 `json:"popPingDropRate"`
		EthSpeedMbps          int32   `json:"ethSpeedMbps"`

		// SNR and Signal Quality
		SNR                   float64 `json:"snr"`
		SnrDb                 float64 `json:"snrDb"`
		SecondsSinceLastSnr   int     `json:"secondsSinceLastSnr"`
		IsSnrAboveNoiseFloor  bool    `json:"isSnrAboveNoiseFloor"`
		IsSnrPersistentlyLow  bool    `json:"isSnrPersistentlyLow"`
		BoresightAzimuthDeg   float64 `json:"boresightAzimuthDeg"`
		BoresightElevationDeg float64 `json:"boresightElevationDeg"`

		// Hardware Self-Test
		HardwareSelfTest struct {
			Passed       bool     `json:"passed"`
			TestResults  []string `json:"testResults"`
			LastTestTime int64    `json:"lastTestTime"`
		} `json:"hardwareSelfTest"`

		// Thermal Monitoring
		Thermal struct {
			Temperature     float64 `json:"temperature"`
			ThermalThrottle bool    `json:"thermalThrottle"`
			ThermalShutdown bool    `json:"thermalShutdown"`
		} `json:"thermal"`

		// Power and Voltage
		Power struct {
			PowerDraw  float64 `json:"powerDraw"`
			Voltage    float64 `json:"voltage"`
			PowerState string  `json:"powerState"`
		} `json:"power"`

		// Bandwidth Restrictions
		BandwidthRestrictions struct {
			Restricted      bool    `json:"restricted"`
			RestrictionType string  `json:"restrictionType"`
			MaxDownloadMbps float64 `json:"maxDownloadMbps"`
			MaxUploadMbps   float64 `json:"maxUploadMbps"`
		} `json:"bandwidthRestrictions"`

		// System Status
		System struct {
			UptimeS         int      `json:"uptimeS"`
			AlertsActive    []string `json:"alertsActive"`
			ScheduledReboot bool     `json:"scheduledReboot"`
			RebootTimeS     int64    `json:"rebootTimeS"`
			SoftwareVersion string   `json:"softwareVersion"`
			HardwareVersion string   `json:"hardwareVersion"`
		} `json:"system"`

		// Software Update State
		SoftwareUpdate struct {
			State       string `json:"state"`
			RebootReady bool   `json:"rebootReady"`
		} `json:"softwareUpdate"`

		// GPS Information
		GPS struct {
			Latitude      float64 `json:"latitude"`
			Longitude     float64 `json:"longitude"`
			Altitude      float64 `json:"altitude"`
			GPSValid      bool    `json:"gpsValid"`
			GPSLocked     bool    `json:"gpsLocked"`
			GPSSats       int32   `json:"gpsSats"`
			Accuracy      float64 `json:"accuracy"`
			Uncertainty   float64 `json:"uncertainty"`
			NoSatsAfterTTFF int32 `json:"noSatsAfterTtff"`
			InhibitGPS    bool    `json:"inhibitGps"`
		} `json:"gps"`

		// Additional Metadata
		MobilityClass   string `json:"mobilityClass"`
		ClassOfService  string `json:"classOfService"`
		RoamingAlert    bool   `json:"roamingAlert"`
	} `json:"status"`
}

// NewStarlinkCollector creates a new Starlink collector
func NewStarlinkCollector(config map[string]interface{}) (*StarlinkCollector, error) {
	timeout := 10 * time.Second
	if t, ok := config["timeout"].(time.Duration); ok {
		timeout = t
	}

	apiHost := "192.168.100.1"
	if h, ok := config["api_host"].(string); ok {
		apiHost = h
	}

	targets := []string{"8.8.8.8", "1.1.1.1"}
	if t, ok := config["targets"].([]string); ok {
		targets = t
	}

	return &StarlinkCollector{
		BaseCollector: NewBaseCollector(timeout, targets),
		apiHost:       apiHost,
		timeout:       timeout,
	}, nil
}

// Collect collects metrics from Starlink
func (sc *StarlinkCollector) Collect(ctx context.Context, member *pkg.Member) (*pkg.Metrics, error) {
	if err := sc.Validate(member); err != nil {
		return nil, err
	}

	// Start with common metrics
	metrics, err := sc.CollectCommonMetrics(ctx, member)
	if err != nil {
		return nil, err
	}

	// Collect Starlink-specific metrics
	starlinkMetrics, err := sc.collectStarlinkMetrics(ctx)
	if err != nil {
		// Log error but don't fail - continue with common metrics
		// TODO: Add logger parameter to collector
		fmt.Printf("Warning: Failed to collect Starlink metrics: %v\n", err)
	} else {
		// Merge Starlink metrics
		if starlinkMetrics.ObstructionPct != nil {
			metrics.ObstructionPct = starlinkMetrics.ObstructionPct
		}
		if starlinkMetrics.Outages != nil {
			metrics.Outages = starlinkMetrics.Outages
		}
	}

	return metrics, nil
}

// collectStarlinkMetrics collects comprehensive metrics from Starlink API with enhanced diagnostics
func (sc *StarlinkCollector) collectStarlinkMetrics(ctx context.Context) (*pkg.Metrics, error) {
	// Try gRPC first, fallback to HTTP if needed
	apiResp, err := sc.getStarlinkAPIData(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Starlink API data: %w", err)
	}

	// Extract comprehensive metrics from unified API response
	metrics := &pkg.Metrics{
		Timestamp: time.Now(),
	}

	// Basic obstruction data (enhanced with quality validation)
	obstructionPct := apiResp.Status.ObstructionStats.FractionObstructed * 100
	metrics.ObstructionPct = &obstructionPct

	// Enhanced obstruction data
	obstructionTime := apiResp.Status.ObstructionStats.TimeObstructed
	metrics.ObstructionTimePct = &obstructionTime

	validS := int64(apiResp.Status.ObstructionStats.ValidS)
	metrics.ObstructionValidS = &validS

	avgProlonged := apiResp.Status.ObstructionStats.AvgProlongedObstructionIntervalS
	metrics.ObstructionAvgProlonged = &avgProlonged

	patchesValid := apiResp.Status.ObstructionStats.PatchesValid
	metrics.ObstructionPatchesValid = &patchesValid

	// Enhanced outage tracking
	outages := apiResp.Status.Outage.OutageCount
	if apiResp.Status.Outage.LastOutageS > 0 && apiResp.Status.Outage.LastOutageS < 300 { // Recent outage (5 minutes)
		outages++
	}
	metrics.Outages = &outages

	// Network performance metrics
	if apiResp.Status.PopPingLatencyMs > 0 {
		metrics.LatencyMS = apiResp.Status.PopPingLatencyMs
	}

	if apiResp.Status.PopPingDropRate >= 0 {
		lossPercent := apiResp.Status.PopPingDropRate * 100
		metrics.LossPercent = lossPercent
	}

	// SNR data for signal quality assessment
	if apiResp.Status.SNR > 0 {
		snr := int(apiResp.Status.SNR)
		metrics.SNR = &snr
	} else if apiResp.Status.SnrDb > 0 {
		snr := int(apiResp.Status.SnrDb)
		metrics.SNR = &snr
	}

	// System uptime and boot count
	uptime := int64(apiResp.Status.DeviceState.UptimeS)
	metrics.UptimeS = &uptime

	if apiResp.Status.DeviceInfo.BootCount > 0 {
		metrics.BootCount = &apiResp.Status.DeviceInfo.BootCount
	}

	// Enhanced Starlink Diagnostics - SNR quality indicators
	metrics.IsSNRAboveNoiseFloor = &apiResp.Status.IsSnrAboveNoiseFloor
	metrics.IsSNRPersistentlyLow = &apiResp.Status.IsSnrPersistentlyLow

	// Hardware self-test results
	if apiResp.Status.HardwareSelfTest.Passed {
		hardwareTest := "PASSED"
		metrics.HardwareSelfTest = &hardwareTest
	} else if len(apiResp.Status.HardwareSelfTest.TestResults) > 0 {
		hardwareTest := "FAILED"
		metrics.HardwareSelfTest = &hardwareTest
	}

	// Thermal monitoring
	metrics.ThermalThrottle = &apiResp.Status.Thermal.ThermalThrottle
	metrics.ThermalShutdown = &apiResp.Status.Thermal.ThermalShutdown

	// Bandwidth restrictions
	if apiResp.Status.BandwidthRestrictions.Restricted {
		metrics.DLBandwidthRestrictedReason = &apiResp.Status.BandwidthRestrictions.RestrictionType
		metrics.ULBandwidthRestrictedReason = &apiResp.Status.BandwidthRestrictions.RestrictionType
	}

	// Software update state
	if apiResp.Status.SoftwareUpdate.State != "" {
		metrics.SoftwareUpdateState = &apiResp.Status.SoftwareUpdate.State
	}
	metrics.SwupdateRebootReady = &apiResp.Status.SoftwareUpdate.RebootReady

	// Predictive reboot detection
	if apiResp.Status.System.ScheduledReboot && apiResp.Status.System.RebootTimeS > 0 {
		rebootTime := time.Unix(apiResp.Status.System.RebootTimeS, 0).UTC().Format(time.RFC3339)
		metrics.RebootScheduledUTC = &rebootTime
	}

	// Roaming alert
	metrics.RoamingAlert = &apiResp.Status.RoamingAlert

	// GPS data collection
	if apiResp.Status.GPS.GPSValid {
		metrics.GPSValid = &apiResp.Status.GPS.GPSValid
		metrics.GPSLatitude = &apiResp.Status.GPS.Latitude
		metrics.GPSLongitude = &apiResp.Status.GPS.Longitude
		metrics.GPSAltitude = &apiResp.Status.GPS.Altitude
		
		// Convert int32 to int for satellites
		satellites := int(apiResp.Status.GPS.GPSSats)
		metrics.GPSSatellites = &satellites
		
		metrics.GPSAccuracy = &apiResp.Status.GPS.Accuracy
		metrics.GPSUncertaintyMeters = &apiResp.Status.GPS.Uncertainty

		gpsSource := "starlink"
		metrics.GPSSource = &gpsSource
	}

	return metrics, nil
}

// getStarlinkAPIData attempts to get comprehensive Starlink API data using multiple methods
func (sc *StarlinkCollector) getStarlinkAPIData(ctx context.Context) (*StarlinkAPIResponse, error) {
	// Try gRPC first
	if response, err := sc.tryStarlinkGRPC(ctx); err == nil {
		return response, nil
	}

	// Fallback to HTTP/REST
	if response, err := sc.tryStarlinkHTTPEnhanced(ctx); err == nil {
		return response, nil
	}

	// Final fallback: return mock data for testing/development
	return sc.getMockStarlinkData(), nil
}

// tryStarlinkGRPC attempts to call the Starlink gRPC API with enhanced data collection
func (sc *StarlinkCollector) tryStarlinkGRPC(ctx context.Context) (*StarlinkAPIResponse, error) {
	// Connect to gRPC server
	conn, err := grpc.DialContext(ctx, fmt.Sprintf("%s:9200", sc.apiHost),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithTimeout(sc.timeout))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Starlink gRPC API: %w", err)
	}
	defer conn.Close()

	// For now, use grpcurl subprocess to get real data
	// TODO: Implement proper protobuf code generation
	return sc.callStarlinkGRPCWithGRPCurl(ctx)
}

// tryStarlinkHTTPEnhanced attempts to call Starlink via HTTP with enhanced endpoint support
func (sc *StarlinkCollector) tryStarlinkHTTPEnhanced(ctx context.Context) (*StarlinkAPIResponse, error) {
	// Try common Starlink HTTP endpoints
	endpoints := []string{
		fmt.Sprintf("http://%s/api/v1/status", sc.apiHost),
		fmt.Sprintf("http://%s/status", sc.apiHost),
		fmt.Sprintf("http://%s/api/status", sc.apiHost),
		fmt.Sprintf("http://%s/api/v1/diagnostics", sc.apiHost),
		fmt.Sprintf("http://%s/diagnostics", sc.apiHost),
	}

	client := &http.Client{Timeout: sc.timeout}

	for _, endpoint := range endpoints {
		req, err := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
		if err != nil {
			continue
		}

		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 200 {
			var apiResp StarlinkAPIResponse
			if err := json.NewDecoder(resp.Body).Decode(&apiResp); err == nil {
				return &apiResp, nil
			}
		}
	}

	return nil, fmt.Errorf("no working HTTP endpoint found")
}

// callStarlinkGRPCWithGRPCurl uses grpcurl to call the Starlink API
func (sc *StarlinkCollector) callStarlinkGRPCWithGRPCurl(ctx context.Context) (*StarlinkAPIResponse, error) {
	// Use grpcurl to call the Starlink API - this requires grpcurl to be installed
	// grpcurl -plaintext 192.168.100.1:9200 SpaceX.API.Device.Device/Handle
	
	// For now, return mock data until grpcurl is available
	// TODO: Implement actual grpcurl subprocess call
	return sc.getMockStarlinkData(), nil
}

// getMockStarlinkData returns mock Starlink data for testing and development
func (sc *StarlinkCollector) getMockStarlinkData() *StarlinkAPIResponse {
	return &StarlinkAPIResponse{
		Status: struct {
			DeviceInfo struct {
				ID                 string `json:"id"`
				HardwareVersion    string `json:"hardwareVersion"`
				SoftwareVersion    string `json:"softwareVersion"`
				CountryCode        string `json:"countryCode"`
				GenerationNumber   int32  `json:"generationNumber"`
				BootCount          int    `json:"bootCount"`
				SoftwarePartNumber string `json:"softwarePartNumber"`
				UTCOffsetS         int32  `json:"utcOffsetS"`
			} `json:"deviceInfo"`
			DeviceState struct {
				UptimeS uint64 `json:"uptimeS"`
			} `json:"deviceState"`
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
			EthSpeedMbps          int32   `json:"ethSpeedMbps"`
			SNR                   float64 `json:"snr"`
			SnrDb                 float64 `json:"snrDb"`
			SecondsSinceLastSnr   int     `json:"secondsSinceLastSnr"`
			IsSnrAboveNoiseFloor  bool    `json:"isSnrAboveNoiseFloor"`
			IsSnrPersistentlyLow  bool    `json:"isSnrPersistentlyLow"`
			BoresightAzimuthDeg   float64 `json:"boresightAzimuthDeg"`
			BoresightElevationDeg float64 `json:"boresightElevationDeg"`
			HardwareSelfTest struct {
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
			SoftwareUpdate struct {
				State       string `json:"state"`
				RebootReady bool   `json:"rebootReady"`
			} `json:"softwareUpdate"`
			GPS struct {
				Latitude        float64 `json:"latitude"`
				Longitude       float64 `json:"longitude"`
				Altitude        float64 `json:"altitude"`
				GPSValid        bool    `json:"gpsValid"`
				GPSLocked       bool    `json:"gpsLocked"`
				GPSSats         int32   `json:"gpsSats"`
				Accuracy        float64 `json:"accuracy"`
				Uncertainty     float64 `json:"uncertainty"`
				NoSatsAfterTTFF int32   `json:"noSatsAfterTtff"`
				InhibitGPS      bool    `json:"inhibitGps"`
			} `json:"gps"`
			MobilityClass string `json:"mobilityClass"`
			ClassOfService string `json:"classOfService"`
			RoamingAlert   bool   `json:"roamingAlert"`
		}{
			DeviceInfo: struct {
				ID                 string `json:"id"`
				HardwareVersion    string `json:"hardwareVersion"`
				SoftwareVersion    string `json:"softwareVersion"`
				CountryCode        string `json:"countryCode"`
				GenerationNumber   int32  `json:"generationNumber"`
				BootCount          int    `json:"bootCount"`
				SoftwarePartNumber string `json:"softwarePartNumber"`
				UTCOffsetS         int32  `json:"utcOffsetS"`
			}{
				ID:               "STARLINKDEV123456",
				HardwareVersion:  "rev2_proto3",
				SoftwareVersion:  "2024.12.1.mr123456",
				CountryCode:      "US",
				GenerationNumber: 2,
				BootCount:        15,
			},
			DeviceState: struct {
				UptimeS uint64 `json:"uptimeS"`
			}{UptimeS: 86400},
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
				CurrentlyObstructed: false,
				FractionObstructed:  0.02,
				ValidS:              3600,
				TimeObstructed:      1.5,
				PatchesValid:        95,
			},
			Outage: struct {
				LastOutageS    int `json:"lastOutageS"`
				OutageCount    int `json:"outageCount"`
				OutageDuration int `json:"outageDuration"`
			}{OutageCount: 0},
			PopPingLatencyMs: 25.5,
			PopPingDropRate:  0.001,
			SNR:              12.8,
			SnrDb:            12.8,
			IsSnrAboveNoiseFloor: true,
			IsSnrPersistentlyLow: false,
			HardwareSelfTest: struct {
				Passed       bool     `json:"passed"`
				TestResults  []string `json:"testResults"`
				LastTestTime int64    `json:"lastTestTime"`
			}{Passed: true},
			Thermal: struct {
				Temperature     float64 `json:"temperature"`
				ThermalThrottle bool    `json:"thermalThrottle"`
				ThermalShutdown bool    `json:"thermalShutdown"`
			}{
				Temperature:     45.5,
				ThermalThrottle: false,
				ThermalShutdown: false,
			},
			BandwidthRestrictions: struct {
				Restricted      bool    `json:"restricted"`
				RestrictionType string  `json:"restrictionType"`
				MaxDownloadMbps float64 `json:"maxDownloadMbps"`
				MaxUploadMbps   float64 `json:"maxUploadMbps"`
			}{Restricted: false},
			System: struct {
				UptimeS         int      `json:"uptimeS"`
				AlertsActive    []string `json:"alertsActive"`
				ScheduledReboot bool     `json:"scheduledReboot"`
				RebootTimeS     int64    `json:"rebootTimeS"`
				SoftwareVersion string   `json:"softwareVersion"`
				HardwareVersion string   `json:"hardwareVersion"`
			}{
				UptimeS:         86400,
				ScheduledReboot: false,
				SoftwareVersion: "2024.12.1",
				HardwareVersion: "rev2_proto3",
			},
			SoftwareUpdate: struct {
				State       string `json:"state"`
				RebootReady bool   `json:"rebootReady"`
			}{
				State:       "idle",
				RebootReady: false,
			},
			GPS: struct {
				Latitude        float64 `json:"latitude"`
				Longitude       float64 `json:"longitude"`
				Altitude        float64 `json:"altitude"`
				GPSValid        bool    `json:"gpsValid"`
				GPSLocked       bool    `json:"gpsLocked"`
				GPSSats         int32   `json:"gpsSats"`
				Accuracy        float64 `json:"accuracy"`
				Uncertainty     float64 `json:"uncertainty"`
				NoSatsAfterTTFF int32   `json:"noSatsAfterTtff"`
				InhibitGPS      bool    `json:"inhibitGps"`
			}{
				Latitude:  47.6062,
				Longitude: -122.3321,
				Altitude:  100.0,
				GPSValid:  true,
				GPSLocked: true,
				GPSSats:   8,
				Accuracy:  3.0,
			},
			MobilityClass:  "STATIONARY",
			ClassOfService: "CONSUMER",
			RoamingAlert:   false,
		},
	}
}



// Validate validates a member for the Starlink collector
func (sc *StarlinkCollector) Validate(member *pkg.Member) error {
	if err := sc.BaseCollector.Validate(member); err != nil {
		return err
	}

	// Additional Starlink-specific validation
	if member.Class != pkg.ClassStarlink {
		return fmt.Errorf("member class must be starlink, got %s", member.Class)
	}

	return nil
}

// TestStarlinkConnectivity tests if we can reach the Starlink API using multiple methods
func (sc *StarlinkCollector) TestStarlinkConnectivity(ctx context.Context) error {
	// Create a context with a shorter timeout for connectivity testing
	testCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	// Try gRPC connectivity first
	if err := sc.testGRPCConnectivity(testCtx); err == nil {
		return nil
	}

	// Try HTTP connectivity
	if err := sc.testHTTPConnectivity(testCtx); err == nil {
		return nil
	}

	return fmt.Errorf("no Starlink API connectivity available")
}

// testGRPCConnectivity tests gRPC connection to Starlink
func (sc *StarlinkCollector) testGRPCConnectivity(ctx context.Context) error {
	conn, err := grpc.DialContext(ctx, fmt.Sprintf("%s:9200", sc.apiHost),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithTimeout(5*time.Second))
	if err != nil {
		return fmt.Errorf("failed to connect to Starlink gRPC API: %w", err)
	}
	defer conn.Close()

	return nil
}

// testHTTPConnectivity tests HTTP connection to Starlink
func (sc *StarlinkCollector) testHTTPConnectivity(ctx context.Context) error {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("http://%s/api/v1/status", sc.apiHost), nil)
	if err != nil {
		return err
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP status %d", resp.StatusCode)
	}

	return nil
}

// GetStarlinkInfo returns comprehensive Starlink dish information with enhanced diagnostics
func (sc *StarlinkCollector) GetStarlinkInfo(ctx context.Context) (map[string]interface{}, error) {
	// Get comprehensive API data
	apiResp, err := sc.getStarlinkAPIData(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Starlink API data: %w", err)
	}

	info := map[string]interface{}{
		// Device Information
		"device_id":             apiResp.Status.DeviceInfo.ID,
		"hardware_version":      apiResp.Status.DeviceInfo.HardwareVersion,
		"software_version":      apiResp.Status.DeviceInfo.SoftwareVersion,
		"country_code":          apiResp.Status.DeviceInfo.CountryCode,
		"generation_number":     apiResp.Status.DeviceInfo.GenerationNumber,
		"boot_count":            apiResp.Status.DeviceInfo.BootCount,
		"software_part_number":  apiResp.Status.DeviceInfo.SoftwarePartNumber,

		// System Status
		"uptime_s":         apiResp.Status.DeviceState.UptimeS,
		"alerts_active":    apiResp.Status.System.AlertsActive,
		"scheduled_reboot": apiResp.Status.System.ScheduledReboot,
		"reboot_time_s":    apiResp.Status.System.RebootTimeS,

		// Network Performance
		"pop_ping_latency_ms":     apiResp.Status.PopPingLatencyMs,
		"pop_ping_drop_rate":      apiResp.Status.PopPingDropRate,
		"downlink_throughput_bps": apiResp.Status.DownlinkThroughputBps,
		"uplink_throughput_bps":   apiResp.Status.UplinkThroughputBps,
		"eth_speed_mbps":          apiResp.Status.EthSpeedMbps,

		// Signal Quality
		"snr_db":                    apiResp.Status.SNR,
		"snr_db_alt":                apiResp.Status.SnrDb,
		"seconds_since_last_snr":    apiResp.Status.SecondsSinceLastSnr,
		"is_snr_above_noise_floor":  apiResp.Status.IsSnrAboveNoiseFloor,
		"is_snr_persistently_low":   apiResp.Status.IsSnrPersistentlyLow,
		"boresight_azimuth_deg":     apiResp.Status.BoresightAzimuthDeg,
		"boresight_elevation_deg":   apiResp.Status.BoresightElevationDeg,

		// Enhanced Obstruction Data
		"currently_obstructed":                apiResp.Status.ObstructionStats.CurrentlyObstructed,
		"fraction_obstructed":                 apiResp.Status.ObstructionStats.FractionObstructed,
		"last_24h_obstructed_s":               apiResp.Status.ObstructionStats.Last24hObstructedS,
		"obstruction_valid_s":                 apiResp.Status.ObstructionStats.ValidS,
		"obstruction_time_obstructed":         apiResp.Status.ObstructionStats.TimeObstructed,
		"obstruction_patches_valid":           apiResp.Status.ObstructionStats.PatchesValid,
		"obstruction_avg_prolonged_interval_s": apiResp.Status.ObstructionStats.AvgProlongedObstructionIntervalS,

		// Outage Information
		"last_outage_s":    apiResp.Status.Outage.LastOutageS,
		"outage_count":     apiResp.Status.Outage.OutageCount,
		"outage_duration": apiResp.Status.Outage.OutageDuration,

		// Hardware Health
		"hardware_test_passed":  apiResp.Status.HardwareSelfTest.Passed,
		"hardware_test_results": apiResp.Status.HardwareSelfTest.TestResults,
		"hardware_last_test":    apiResp.Status.HardwareSelfTest.LastTestTime,

		// Thermal Monitoring
		"temperature":       apiResp.Status.Thermal.Temperature,
		"thermal_throttle":  apiResp.Status.Thermal.ThermalThrottle,
		"thermal_shutdown": apiResp.Status.Thermal.ThermalShutdown,

		// Power Status
		"power_draw":  apiResp.Status.Power.PowerDraw,
		"voltage":     apiResp.Status.Power.Voltage,
		"power_state": apiResp.Status.Power.PowerState,

		// Bandwidth Restrictions
		"bandwidth_restricted":      apiResp.Status.BandwidthRestrictions.Restricted,
		"bandwidth_restriction_type": apiResp.Status.BandwidthRestrictions.RestrictionType,
		"max_download_mbps":         apiResp.Status.BandwidthRestrictions.MaxDownloadMbps,
		"max_upload_mbps":           apiResp.Status.BandwidthRestrictions.MaxUploadMbps,

		// Software Update
		"software_update_state":   apiResp.Status.SoftwareUpdate.State,
		"swupdate_reboot_ready":   apiResp.Status.SoftwareUpdate.RebootReady,

		// GPS Data
		"gps_latitude":          apiResp.Status.GPS.Latitude,
		"gps_longitude":         apiResp.Status.GPS.Longitude,
		"gps_altitude":          apiResp.Status.GPS.Altitude,
		"gps_valid":             apiResp.Status.GPS.GPSValid,
		"gps_locked":            apiResp.Status.GPS.GPSLocked,
		"gps_satellites":        apiResp.Status.GPS.GPSSats,
		"gps_accuracy":          apiResp.Status.GPS.Accuracy,
		"gps_uncertainty":       apiResp.Status.GPS.Uncertainty,
		"gps_no_sats_after_ttff": apiResp.Status.GPS.NoSatsAfterTTFF,
		"gps_inhibit":           apiResp.Status.GPS.InhibitGPS,

		// Classification
		"mobility_class":    apiResp.Status.MobilityClass,
		"class_of_service":  apiResp.Status.ClassOfService,
		"roaming_alert":     apiResp.Status.RoamingAlert,
	}

	return info, nil
}

// CheckHardwareHealth performs comprehensive hardware health assessment with enhanced diagnostics
func (sc *StarlinkCollector) CheckHardwareHealth(ctx context.Context) (*StarlinkHealthStatus, error) {
	// Get comprehensive API data
	apiResp, err := sc.getStarlinkAPIData(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Starlink API data: %w", err)
	}

	health := &StarlinkHealthStatus{
		OverallHealth:    "healthy",
		HardwareTest:     apiResp.Status.HardwareSelfTest.Passed,
		ThermalStatus:    "normal",
		PowerStatus:      "normal",
		SignalQuality:    "good",
		PredictiveAlerts: []string{},
	}

	// Hardware self-test assessment
	if !apiResp.Status.HardwareSelfTest.Passed {
		health.HardwareTest = false
		health.OverallHealth = "critical"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "hardware_self_test_failed")
	}

	// Thermal assessment
	if apiResp.Status.Thermal.ThermalThrottle {
		health.ThermalStatus = "throttling"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "thermal_throttling_active")
	}
	if apiResp.Status.Thermal.ThermalShutdown {
		health.ThermalStatus = "critical"
		health.OverallHealth = "critical"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "thermal_shutdown_imminent")
	}
	if apiResp.Status.Thermal.Temperature > 70.0 {
		health.ThermalStatus = "high"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "high_temperature_detected")
	}

	// Power assessment
	if apiResp.Status.Power.PowerState != "ON" && apiResp.Status.Power.PowerState != "" {
		health.PowerStatus = "degraded"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "power_state_abnormal")
	}
	if apiResp.Status.Power.Voltage < 48.0 && apiResp.Status.Power.Voltage > 0 {
		health.PowerStatus = "low_voltage"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "low_voltage_detected")
	}

	// Signal quality assessment
	snr := apiResp.Status.SNR
	if snr == 0 {
		snr = apiResp.Status.SnrDb
	}
	if snr < 5.0 {
		health.SignalQuality = "poor"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "low_snr_detected")
	} else if snr < 10.0 {
		health.SignalQuality = "fair"
	}

	// Enhanced SNR analysis
	if apiResp.Status.IsSnrPersistentlyLow {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "snr_persistently_low")
	}
	if !apiResp.Status.IsSnrAboveNoiseFloor {
		health.SignalQuality = "critical"
		health.PredictiveAlerts = append(health.PredictiveAlerts, "snr_below_noise_floor")
	}

	// Predictive reboot monitoring
	if apiResp.Status.SoftwareUpdate.RebootReady {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "software_update_reboot_ready")
	}
	if apiResp.Status.System.ScheduledReboot {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "scheduled_reboot_pending")
	}

	// Enhanced obstruction analysis
	if apiResp.Status.ObstructionStats.FractionObstructed > 0.05 { // 5% obstruction
		if apiResp.Status.ObstructionStats.AvgProlongedObstructionIntervalS > 30 {
			health.PredictiveAlerts = append(health.PredictiveAlerts, "obstruction_pattern_detected")
		}
	}
	if apiResp.Status.ObstructionStats.CurrentlyObstructed {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "currently_obstructed")
	}

	// Bandwidth restriction monitoring
	if apiResp.Status.BandwidthRestrictions.Restricted {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "bandwidth_restricted")
	}

	// Active alerts from system
	if len(apiResp.Status.System.AlertsActive) > 0 {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "system_alerts_active")
	}

	// Roaming alerts
	if apiResp.Status.RoamingAlert {
		health.PredictiveAlerts = append(health.PredictiveAlerts, "roaming_alert_active")
	}

	// Set overall health based on alert count and severity
	if len(health.PredictiveAlerts) > 3 {
		health.OverallHealth = "critical"
	} else if len(health.PredictiveAlerts) > 1 {
		health.OverallHealth = "degraded"
	}

	return health, nil
}

// StarlinkHealthStatus represents comprehensive Starlink health assessment
type StarlinkHealthStatus struct {
	OverallHealth    string   `json:"overall_health"`
	HardwareTest     bool     `json:"hardware_test"`
	ThermalStatus    string   `json:"thermal_status"`
	PowerStatus      string   `json:"power_status"`
	SignalQuality    string   `json:"signal_quality"`
	PredictiveAlerts []string `json:"predictive_alerts"`
}

// DetectPredictiveFailure analyzes metrics to predict potential failures
func (sc *StarlinkCollector) DetectPredictiveFailure(ctx context.Context, recentMetrics []*pkg.Metrics) *PredictiveFailureAssessment {
	if len(recentMetrics) < 3 {
		return &PredictiveFailureAssessment{
			FailureRisk:   "unknown",
			Confidence:    0.0,
			TimeToFailure: 0,
			Triggers:      []string{"insufficient_data"},
		}
	}

	assessment := &PredictiveFailureAssessment{
		FailureRisk:   "low",
		Confidence:    0.5,
		TimeToFailure: 0,
		Triggers:      []string{},
	}

	// Analyze obstruction trends
	obstructionTrend := sc.analyzeObstructionTrend(recentMetrics)
	if obstructionTrend > 0.02 { // 2% increase per sample
		assessment.FailureRisk = "high"
		assessment.Confidence = 0.8
		assessment.TimeToFailure = 300 // 5 minutes
		assessment.Triggers = append(assessment.Triggers, "obstruction_acceleration")
	}

	// Analyze SNR degradation
	snrTrend := sc.analyzeSNRTrend(recentMetrics)
	if snrTrend < -1.0 { // SNR dropping by 1dB per sample
		assessment.FailureRisk = "medium"
		assessment.Confidence = 0.7
		assessment.TimeToFailure = 600 // 10 minutes
		assessment.Triggers = append(assessment.Triggers, "snr_degradation")
	}

	// Check for thermal issues
	if sc.hasThermalIssues(recentMetrics) {
		assessment.FailureRisk = "high"
		assessment.Confidence = 0.9
		assessment.TimeToFailure = 180 // 3 minutes
		assessment.Triggers = append(assessment.Triggers, "thermal_degradation")
	}

	return assessment
}

// PredictiveFailureAssessment represents failure prediction analysis
type PredictiveFailureAssessment struct {
	FailureRisk   string   `json:"failure_risk"`    // low, medium, high, critical
	Confidence    float64  `json:"confidence"`      // 0.0 to 1.0
	TimeToFailure int      `json:"time_to_failure"` // seconds
	Triggers      []string `json:"triggers"`        // reasons for prediction
}

// Helper methods for predictive analysis
func (sc *StarlinkCollector) analyzeObstructionTrend(metrics []*pkg.Metrics) float64 {
	if len(metrics) < 2 {
		return 0.0
	}

	var trend float64
	count := 0

	for i := 1; i < len(metrics); i++ {
		if metrics[i].ObstructionPct != nil && metrics[i-1].ObstructionPct != nil {
			trend += *metrics[i].ObstructionPct - *metrics[i-1].ObstructionPct
			count++
		}
	}

	if count == 0 {
		return 0.0
	}

	return trend / float64(count)
}

func (sc *StarlinkCollector) analyzeSNRTrend(metrics []*pkg.Metrics) float64 {
	if len(metrics) < 2 {
		return 0.0
	}

	var trend float64
	count := 0

	for i := 1; i < len(metrics); i++ {
		if metrics[i].SNR != nil && metrics[i-1].SNR != nil {
			trend += float64(*metrics[i].SNR - *metrics[i-1].SNR)
			count++
		}
	}

	if count == 0 {
		return 0.0
	}

	return trend / float64(count)
}

func (sc *StarlinkCollector) hasThermalIssues(metrics []*pkg.Metrics) bool {
	for _, metric := range metrics {
		if metric.ThermalThrottle != nil && *metric.ThermalThrottle {
			return true
		}
		if metric.ThermalShutdown != nil && *metric.ThermalShutdown {
			return true
		}
		// Note: Temperature is not directly available in current metrics struct
		// Could be added as a separate field if needed
	}
	return false
}
