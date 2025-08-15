package gps

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
)

// GPSCollectorImpl implements the GPSCollector interface
type GPSCollectorImpl struct {
	logger    *logx.Logger
	config    *GPSConfig
	lastKnown *pkg.GPSData
	sources   []GPSSource
}

// GPSConfig represents GPS collector configuration
type GPSConfig struct {
	Enabled             bool     `json:"enabled"`
	SourcePriority      []string `json:"source_priority"`       // ["rutos", "starlink", "cellular"]
	MovementThresholdM  float64  `json:"movement_threshold_m"`  // Movement detection threshold in meters
	AccuracyThresholdM  float64  `json:"accuracy_threshold_m"`  // Minimum accuracy required
	StalenessThresholdS int64    `json:"staleness_threshold_s"` // Maximum age for GPS data
	CollectionIntervalS int      `json:"collection_interval_s"` // Collection interval
	MovementDetection   bool     `json:"movement_detection"`    // Enable movement detection
	LocationClustering  bool     `json:"location_clustering"`   // Enable location clustering
	RetryAttempts       int      `json:"retry_attempts"`        // Number of retry attempts
	RetryDelayS         int      `json:"retry_delay_s"`         // Delay between retries
}

// GPSSource represents a GPS data source
type GPSSource interface {
	GetName() string
	GetPriority() int
	CollectGPS(ctx context.Context) (*pkg.GPSData, error)
	IsAvailable(ctx context.Context) bool
}

// RutOSGPSSource collects GPS data from RutOS/RUTOS sources
type RutOSGPSSource struct {
	logger   *logx.Logger
	priority int
}

// StarlinkGPSSource collects GPS data from Starlink API
type StarlinkGPSSource struct {
	logger    *logx.Logger
	priority  int
	apiHost   string
	collector interface{} // Reference to Starlink collector
}

// CellularGPSSource collects GPS data from cellular modem
type CellularGPSSource struct {
	logger   *logx.Logger
	priority int
}

// NewGPSCollector creates a new GPS data collector
func NewGPSCollector(config *GPSConfig, logger *logx.Logger) *GPSCollectorImpl {
	if config == nil {
		config = DefaultGPSConfig()
	}

	collector := &GPSCollectorImpl{
		logger:  logger,
		config:  config,
		sources: []GPSSource{},
	}

	// Initialize GPS sources based on priority
	for i, sourceName := range config.SourcePriority {
		switch sourceName {
		case "rutos":
			source := &RutOSGPSSource{
				logger:   logger,
				priority: i,
			}
			collector.sources = append(collector.sources, source)
		case "starlink":
			source := &StarlinkGPSSource{
				logger:   logger,
				priority: i,
				apiHost:  "192.168.100.1",
			}
			collector.sources = append(collector.sources, source)
		case "cellular":
			source := &CellularGPSSource{
				logger:   logger,
				priority: i,
			}
			collector.sources = append(collector.sources, source)
		}
	}

	return collector
}

// DefaultGPSConfig returns default GPS collector configuration
func DefaultGPSConfig() *GPSConfig {
	return &GPSConfig{
		Enabled:             true,
		SourcePriority:      []string{"rutos", "starlink", "cellular"},
		MovementThresholdM:  500.0, // 500 meters movement threshold
		AccuracyThresholdM:  50.0,  // 50 meters accuracy threshold
		StalenessThresholdS: 300,   // 5 minutes staleness threshold
		CollectionIntervalS: 60,    // 1 minute collection interval
		MovementDetection:   true,
		LocationClustering:  true,
		RetryAttempts:       3,
		RetryDelayS:         5,
	}
}

// CollectGPS collects GPS data from the best available source
func (gc *GPSCollectorImpl) CollectGPS(ctx context.Context) (*pkg.GPSData, error) {
	if !gc.config.Enabled {
		return nil, fmt.Errorf("GPS collection is disabled")
	}

	var lastError error

	// Try each source in priority order
	for _, source := range gc.sources {
		if !source.IsAvailable(ctx) {
			gc.logger.LogDebugVerbose("gps_source_unavailable", map[string]interface{}{
				"source": source.GetName(),
			})
			continue
		}

		// Attempt to collect GPS data with retries
		for attempt := 0; attempt < gc.config.RetryAttempts; attempt++ {
			gpsData, err := source.CollectGPS(ctx)
			if err != nil {
				lastError = err
				gc.logger.LogDebugVerbose("gps_collection_attempt_failed", map[string]interface{}{
					"source":  source.GetName(),
					"attempt": attempt + 1,
					"error":   err.Error(),
				})

				if attempt < gc.config.RetryAttempts-1 {
					time.Sleep(time.Duration(gc.config.RetryDelayS) * time.Second)
				}
				continue
			}

			// Validate GPS data quality
			if err := gc.ValidateGPS(gpsData); err != nil {
				gc.logger.LogDebugVerbose("gps_validation_failed", map[string]interface{}{
					"source": source.GetName(),
					"error":  err.Error(),
				})
				lastError = err
				continue
			}

			// Check for movement if enabled
			if gc.config.MovementDetection && gc.lastKnown != nil {
				distance := gc.calculateDistance(gc.lastKnown, gpsData)
				if distance > gc.config.MovementThresholdM {
					gc.logger.LogStateChange("gps_collector", "stationary", "moving", "movement_detected", map[string]interface{}{
						"distance_m":    distance,
						"threshold_m":   gc.config.MovementThresholdM,
						"from_lat":      gc.lastKnown.Latitude,
						"from_lon":      gc.lastKnown.Longitude,
						"to_lat":        gpsData.Latitude,
						"to_lon":        gpsData.Longitude,
						"movement_time": time.Since(gc.lastKnown.Timestamp).Seconds(),
					})
				}
			}

			// Update last known position
			gc.lastKnown = gpsData

			gc.logger.LogVerbose("gps_collection_success", map[string]interface{}{
				"source":     source.GetName(),
				"latitude":   gpsData.Latitude,
				"longitude":  gpsData.Longitude,
				"accuracy":   gpsData.Accuracy,
				"satellites": gpsData.Satellites,
				"valid":      gpsData.Valid,
			})

			return gpsData, nil
		}
	}

	if lastError != nil {
		return nil, fmt.Errorf("failed to collect GPS data from any source: %w", lastError)
	}

	return nil, fmt.Errorf("no GPS sources available")
}

// ValidateGPS validates GPS data quality
func (gc *GPSCollectorImpl) ValidateGPS(gps *pkg.GPSData) error {
	if gps == nil {
		return fmt.Errorf("GPS data is nil")
	}

	if !gps.Valid {
		return fmt.Errorf("GPS data is marked as invalid")
	}

	// Check coordinate bounds
	if gps.Latitude < -90 || gps.Latitude > 90 {
		return fmt.Errorf("invalid latitude: %f", gps.Latitude)
	}
	if gps.Longitude < -180 || gps.Longitude > 180 {
		return fmt.Errorf("invalid longitude: %f", gps.Longitude)
	}

	// Check accuracy threshold
	if gps.Accuracy > gc.config.AccuracyThresholdM {
		return fmt.Errorf("GPS accuracy too low: %f > %f", gps.Accuracy, gc.config.AccuracyThresholdM)
	}

	// Check staleness
	if time.Since(gps.Timestamp).Seconds() > float64(gc.config.StalenessThresholdS) {
		return fmt.Errorf("GPS data too stale: %v", time.Since(gps.Timestamp))
	}

	return nil
}

// GetBestSource returns the name of the best available GPS source
func (gc *GPSCollectorImpl) GetBestSource() string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, source := range gc.sources {
		if source.IsAvailable(ctx) {
			return source.GetName()
		}
	}

	return "none"
}

// calculateDistance calculates the distance between two GPS coordinates using Haversine formula
func (gc *GPSCollectorImpl) calculateDistance(from, to *pkg.GPSData) float64 {
	const earthRadiusM = 6371000 // Earth's radius in meters

	lat1Rad := from.Latitude * math.Pi / 180
	lat2Rad := to.Latitude * math.Pi / 180
	deltaLatRad := (to.Latitude - from.Latitude) * math.Pi / 180
	deltaLonRad := (to.Longitude - from.Longitude) * math.Pi / 180

	a := math.Sin(deltaLatRad/2)*math.Sin(deltaLatRad/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLonRad/2)*math.Sin(deltaLonRad/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusM * c
}

// DetectMovement checks if significant movement has occurred
func (gc *GPSCollectorImpl) DetectMovement(current *pkg.GPSData) (bool, float64) {
	if gc.lastKnown == nil {
		return false, 0
	}

	distance := gc.calculateDistance(gc.lastKnown, current)
	return distance > gc.config.MovementThresholdM, distance
}

// RutOSGPSSource implementation

// GetName returns the source name
func (rs *RutOSGPSSource) GetName() string {
	return "rutos"
}

// GetPriority returns the source priority
func (rs *RutOSGPSSource) GetPriority() int {
	return rs.priority
}

// IsAvailable checks if RutOS GPS is available
func (rs *RutOSGPSSource) IsAvailable(ctx context.Context) bool {
	// Check if gsmctl command is available
	cmd := exec.CommandContext(ctx, "which", "gsmctl")
	return cmd.Run() == nil
}

// CollectGPS collects GPS data from RutOS
func (rs *RutOSGPSSource) CollectGPS(ctx context.Context) (*pkg.GPSData, error) {
	// Try multiple RutOS GPS collection methods

	// Method 1: gsmctl GPS info
	if gpsData, err := rs.collectFromGsmctl(ctx); err == nil {
		return gpsData, nil
	}

	// Method 2: ubus GPS call
	if gpsData, err := rs.collectFromUbus(ctx); err == nil {
		return gpsData, nil
	}

	// Method 3: Direct GPS device reading
	if gpsData, err := rs.collectFromGPSDevice(ctx); err == nil {
		return gpsData, nil
	}

	return nil, fmt.Errorf("failed to collect GPS data from RutOS")
}

// collectFromGsmctl collects GPS data using gsmctl command
func (rs *RutOSGPSSource) collectFromGsmctl(ctx context.Context) (*pkg.GPSData, error) {
	cmd := exec.CommandContext(ctx, "gsmctl", "-A", "AT+CGPSINFO")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("gsmctl command failed: %w", err)
	}

	return rs.parseGsmctlOutput(string(output))
}

// collectFromUbus collects GPS data using ubus
func (rs *RutOSGPSSource) collectFromUbus(ctx context.Context) (*pkg.GPSData, error) {
	cmd := exec.CommandContext(ctx, "ubus", "call", "gps", "info")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ubus GPS call failed: %w", err)
	}

	var ubusResp map[string]interface{}
	if err := json.Unmarshal(output, &ubusResp); err != nil {
		return nil, fmt.Errorf("failed to parse ubus GPS response: %w", err)
	}

	return rs.parseUbusGPSResponse(ubusResp)
}

// collectFromGPSDevice collects GPS data directly from GPS device
func (rs *RutOSGPSSource) collectFromGPSDevice(ctx context.Context) (*pkg.GPSData, error) {
	// Try common GPS device paths
	devices := []string{"/dev/ttyUSB1", "/dev/ttyUSB2", "/dev/ttyACM0"}

	for _, device := range devices {
		_ = exec.CommandContext(ctx, "cat", device)
		// This would need proper NMEA parsing in production
		// For now, return an error to fall back to other methods
	}

	return nil, fmt.Errorf("no GPS device found")
}

// parseGsmctlOutput parses gsmctl GPS output
func (rs *RutOSGPSSource) parseGsmctlOutput(output string) (*pkg.GPSData, error) {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.Contains(line, "+CGPSINFO:") {
			// Parse CGPSINFO response
			// Format: +CGPSINFO: lat,N,lon,E,date,time,alt,speed,course
			parts := strings.Split(strings.TrimPrefix(line, "+CGPSINFO: "), ",")
			if len(parts) >= 9 {
				lat, _ := strconv.ParseFloat(parts[0], 64)
				lon, _ := strconv.ParseFloat(parts[2], 64)
				alt, _ := strconv.ParseFloat(parts[6], 64)

				// Convert from DDMM.MMMM to decimal degrees
				lat = rs.convertToDecimalDegrees(lat)
				lon = rs.convertToDecimalDegrees(lon)

				return &pkg.GPSData{
					Latitude:  lat,
					Longitude: lon,
					Altitude:  alt,
					Accuracy:  10.0, // Assume 10m accuracy
					Source:    "rutos",
					Valid:     lat != 0 && lon != 0,
					Timestamp: time.Now(),
				}, nil
			}
		}
	}

	return nil, fmt.Errorf("no valid GPS data in gsmctl output")
}

// parseUbusGPSResponse parses ubus GPS response
func (rs *RutOSGPSSource) parseUbusGPSResponse(response map[string]interface{}) (*pkg.GPSData, error) {
	gpsData := &pkg.GPSData{
		Source:    "rutos",
		Timestamp: time.Now(),
	}

	if lat, ok := response["latitude"].(float64); ok {
		gpsData.Latitude = lat
	}
	if lon, ok := response["longitude"].(float64); ok {
		gpsData.Longitude = lon
	}
	if alt, ok := response["altitude"].(float64); ok {
		gpsData.Altitude = alt
	}
	if acc, ok := response["accuracy"].(float64); ok {
		gpsData.Accuracy = acc
	}
	if sats, ok := response["satellites"].(float64); ok {
		gpsData.Satellites = int(sats)
	}

	gpsData.Valid = gpsData.Latitude != 0 && gpsData.Longitude != 0

	return gpsData, nil
}

// convertToDecimalDegrees converts DDMM.MMMM to decimal degrees
func (rs *RutOSGPSSource) convertToDecimalDegrees(coord float64) float64 {
	degrees := math.Floor(coord / 100)
	minutes := coord - (degrees * 100)
	return degrees + (minutes / 60)
}

// StarlinkGPSSource implementation

// GetName returns the source name
func (ss *StarlinkGPSSource) GetName() string {
	return "starlink"
}

// GetPriority returns the source priority
func (ss *StarlinkGPSSource) GetPriority() int {
	return ss.priority
}

// IsAvailable checks if Starlink GPS is available
func (ss *StarlinkGPSSource) IsAvailable(ctx context.Context) bool {
	// Simple connectivity test to Starlink API
	cmd := exec.CommandContext(ctx, "ping", "-c", "1", "-W", "2", ss.apiHost)
	return cmd.Run() == nil
}

// CollectGPS collects GPS data from Starlink API
func (ss *StarlinkGPSSource) CollectGPS(ctx context.Context) (*pkg.GPSData, error) {
	// This would integrate with the Starlink collector
	// For now, return mock data
	return &pkg.GPSData{
		Latitude:   47.6062,
		Longitude:  -122.3321,
		Altitude:   100.0,
		Accuracy:   3.0,
		Source:     "starlink",
		Satellites: 8,
		Valid:      true,
		Timestamp:  time.Now(),
	}, nil
}

// CellularGPSSource implementation

// GetName returns the source name
func (cs *CellularGPSSource) GetName() string {
	return "cellular"
}

// GetPriority returns the source priority
func (cs *CellularGPSSource) GetPriority() int {
	return cs.priority
}

// IsAvailable checks if cellular GPS is available
func (cs *CellularGPSSource) IsAvailable(ctx context.Context) bool {
	// Check if cellular modem with GPS is available
	cmd := exec.CommandContext(ctx, "ls", "/dev/ttyUSB*")
	return cmd.Run() == nil
}

// CollectGPS collects GPS data from cellular modem
func (cs *CellularGPSSource) CollectGPS(ctx context.Context) (*pkg.GPSData, error) {
	// Try AT commands for GPS data
	cmd := exec.CommandContext(ctx, "gsmctl", "-A", "AT+CGNSINF")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("cellular GPS command failed: %w", err)
	}

	return cs.parseCellularGPSOutput(string(output))
}

// parseCellularGPSOutput parses cellular GPS output
func (cs *CellularGPSSource) parseCellularGPSOutput(output string) (*pkg.GPSData, error) {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.Contains(line, "+CGNSINF:") {
			// Parse CGNSINF response
			parts := strings.Split(strings.TrimPrefix(line, "+CGNSINF: "), ",")
			if len(parts) >= 15 {
				if parts[1] == "1" { // GPS fix available
					lat, _ := strconv.ParseFloat(parts[3], 64)
					lon, _ := strconv.ParseFloat(parts[4], 64)
					alt, _ := strconv.ParseFloat(parts[5], 64)
					sats, _ := strconv.Atoi(parts[14])

					return &pkg.GPSData{
						Latitude:   lat,
						Longitude:  lon,
						Altitude:   alt,
						Accuracy:   15.0, // Assume 15m accuracy for cellular GPS
						Source:     "cellular",
						Satellites: sats,
						Valid:      lat != 0 && lon != 0,
						Timestamp:  time.Now(),
					}, nil
				}
			}
		}
	}

	return nil, fmt.Errorf("no valid GPS data in cellular output")
}
