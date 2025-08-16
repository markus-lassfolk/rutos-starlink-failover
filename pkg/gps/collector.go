package gps

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/collector"
	"github.com/starfail/starfail/pkg/logx"
	"google.golang.org/grpc"
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
	apiPort   int
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
				apiPort:  9200,
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
	// Use Windows ping syntax (-n for count, -w for timeout in ms)
	cmd := exec.CommandContext(ctx, "ping", "-n", "1", "-w", "2000", ss.apiHost)
	return cmd.Run() == nil
}

// CollectGPS collects GPS data from Starlink API
func (ss *StarlinkGPSSource) CollectGPS(ctx context.Context) (*pkg.GPSData, error) {
	// Use the existing Starlink collector to get location data
	config := map[string]interface{}{
		"api_host": ss.apiHost,
		"api_port": ss.apiPort,
		"timeout":  10 * time.Second,
	}
	
	starlinkCollector, err := collector.NewStarlinkCollector(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create Starlink collector: %w", err)
	}
	
	// Call the get_location method
	locationResponse, err := starlinkCollector.TestStarlinkMethod(ctx, "get_location")
	if err != nil {
		return nil, fmt.Errorf("failed to get location from Starlink: %w", err)
	}
	
	// Parse the JSON response
	return ss.parseLocationResponse(locationResponse)
}

// getStarlinkGPSData gets GPS coordinates from Starlink gRPC API
func (ss *StarlinkGPSSource) getStarlinkGPSData(ctx context.Context) (*pkg.GPSData, error) {
	// Connect to Starlink gRPC API
	conn, err := grpc.DialContext(ctx, fmt.Sprintf("%s:%d", ss.apiHost, ss.apiPort),
		grpc.WithInsecure(),
		grpc.WithTimeout(10*time.Second))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Starlink API: %w", err)
	}
	defer conn.Close()

	// Try to call get_location method
	locationData, err := ss.callStarlinkLocationMethod(ctx, conn)
	if err != nil {
		return nil, fmt.Errorf("failed to get location data: %w", err)
	}

	return locationData, nil
}

// callStarlinkLocationMethod calls the Starlink location gRPC method
func (ss *StarlinkGPSSource) callStarlinkLocationMethod(ctx context.Context, conn *grpc.ClientConn) (*pkg.GPSData, error) {
	// Prepare request for get_location
	request := ss.createLocationRequest()

	// Call the gRPC method
	var response []byte
	err := conn.Invoke(ctx, "/SpaceX.API.Device.Device/Handle", request, &response)
	if err != nil {
		return nil, fmt.Errorf("gRPC call failed: %w", err)
	}

	// Parse the JSON response
	return ss.parseLocationResponse(string(response))
}

// createLocationRequest creates a protobuf request for location data
func (ss *StarlinkGPSSource) createLocationRequest() []byte {
	// Create a basic protobuf request for get_location
	// Field 13 is typically the get_location request in Starlink API
	request := []byte{}

	// Add field 13 (get_location) with empty message
	request = append(request, 0x6A) // Field 13, wire type 2 (length-delimited)
	request = append(request, 0x00) // Length 0 (empty message)

	return request
}

// parseLocationResponse parses GPS data from Starlink JSON response
func (ss *StarlinkGPSSource) parseLocationResponse(jsonResponse string) (*pkg.GPSData, error) {
	// Parse the JSON response
	var response map[string]interface{}
	if err := json.Unmarshal([]byte(jsonResponse), &response); err != nil {
		return nil, fmt.Errorf("failed to parse JSON response: %w", err)
	}

	// Extract the getLocation data
	getLocation, ok := response["getLocation"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("getLocation field not found in response")
	}

	// Extract the lla (latitude, longitude, altitude) data
	lla, ok := getLocation["lla"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("lla field not found in getLocation")
	}

	// Extract coordinates
	lat, ok := lla["lat"].(float64)
	if !ok {
		return nil, fmt.Errorf("latitude not found or invalid")
	}

	lon, ok := lla["lon"].(float64)
	if !ok {
		return nil, fmt.Errorf("longitude not found or invalid")
	}

	alt, ok := lla["alt"].(float64)
	if !ok {
		alt = 0 // Default altitude if not available
	}

	// Extract additional GPS info
	source, _ := getLocation["source"].(string)
	if source == "" {
		source = "GNC_FUSED" // Default Starlink GPS source
	}

	sigmaM, _ := getLocation["sigmaM"].(float64)
	if sigmaM == 0 {
		sigmaM = 5.0 // Default accuracy if not provided
	}

	gpsData := &pkg.GPSData{
		Latitude:  lat,
		Longitude: lon,
		Altitude:  alt,
		Accuracy:  sigmaM,
		Source:    "starlink",
		Valid:     lat != 0 && lon != 0,
		Timestamp: time.Now(),
		Satellites: 0, // Starlink doesn't provide satellite count in location response
	}

	return gpsData, nil
}

// Helper methods for protobuf parsing
func (ss *StarlinkGPSSource) readVarint(data []byte, offset int) (uint64, int, error) {
	var result uint64
	var shift uint
	bytesRead := 0

	for i := offset; i < len(data) && bytesRead < 10; i++ {
		b := data[i]
		bytesRead++

		result |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return result, bytesRead, nil
		}
		shift += 7
	}

	return 0, 0, fmt.Errorf("invalid varint")
}

func (ss *StarlinkGPSSource) readUint32(data []byte) uint32 {
	return uint32(data[0]) | uint32(data[1])<<8 | uint32(data[2])<<16 | uint32(data[3])<<24
}

func (ss *StarlinkGPSSource) readUint64(data []byte) uint64 {
	return uint64(data[0]) | uint64(data[1])<<8 | uint64(data[2])<<16 | uint64(data[3])<<24 |
		uint64(data[4])<<32 | uint64(data[5])<<40 | uint64(data[6])<<48 | uint64(data[7])<<56
}

// LocationCluster represents a cluster of GPS locations with performance data
type LocationCluster struct {
	ID        string    `json:"id"`
	CenterLat float64   `json:"center_lat"`
	CenterLon float64   `json:"center_lon"`
	Radius    float64   `json:"radius_meters"`
	Locations int       `json:"location_count"`
	FirstSeen time.Time `json:"first_seen"`
	LastSeen  time.Time `json:"last_seen"`

	// Performance metrics for this cluster
	AvgLatency      float64 `json:"avg_latency_ms"`
	AvgLoss         float64 `json:"avg_loss_percent"`
	AvgObstruction  float64 `json:"avg_obstruction_percent"`
	IssueCount      int     `json:"issue_count"`
	ProblematicArea bool    `json:"problematic_area"`
}

// MovementDetector tracks location changes and detects significant movement
type MovementDetector struct {
	lastLocation      *pkg.GPSData
	movementThreshold float64 // meters
	logger            *logx.Logger
	onMovement        func(oldLocation, newLocation *pkg.GPSData, distance float64)
}

// NewMovementDetector creates a new movement detector
func NewMovementDetector(thresholdMeters float64, logger *logx.Logger) *MovementDetector {
	return &MovementDetector{
		movementThreshold: thresholdMeters,
		logger:            logger,
	}
}

// SetMovementCallback sets callback function for movement events
func (md *MovementDetector) SetMovementCallback(callback func(oldLocation, newLocation *pkg.GPSData, distance float64)) {
	md.onMovement = callback
}

// CheckMovement checks if location has changed significantly
func (md *MovementDetector) CheckMovement(newLocation *pkg.GPSData) bool {
	if md.lastLocation == nil {
		md.lastLocation = newLocation
		md.logger.Info("Initial location recorded",
			"lat", newLocation.Latitude,
			"lon", newLocation.Longitude,
			"source", newLocation.Source)
		return false
	}

	// Calculate distance between locations
	distance := md.calculateDistance(md.lastLocation, newLocation)

	if distance > md.movementThreshold {
		md.logger.Info("Significant movement detected",
			"distance_meters", distance,
			"threshold_meters", md.movementThreshold,
			"old_lat", md.lastLocation.Latitude,
			"old_lon", md.lastLocation.Longitude,
			"new_lat", newLocation.Latitude,
			"new_lon", newLocation.Longitude)

		// Trigger callback if set
		if md.onMovement != nil {
			md.onMovement(md.lastLocation, newLocation, distance)
		}

		// Update last location
		md.lastLocation = newLocation
		return true
	}

	return false
}

// calculateDistance calculates the distance between two GPS points using Haversine formula
func (md *MovementDetector) calculateDistance(loc1, loc2 *pkg.GPSData) float64 {
	const earthRadius = 6371000 // Earth radius in meters

	lat1Rad := loc1.Latitude * math.Pi / 180
	lat2Rad := loc2.Latitude * math.Pi / 180
	deltaLatRad := (loc2.Latitude - loc1.Latitude) * math.Pi / 180
	deltaLonRad := (loc2.Longitude - loc1.Longitude) * math.Pi / 180

	a := math.Sin(deltaLatRad/2)*math.Sin(deltaLatRad/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLonRad/2)*math.Sin(deltaLonRad/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadius * c
}

// LocationClustering manages location clusters and performance correlation
type LocationClustering struct {
	clusters      map[string]*LocationCluster
	clusterRadius float64 // meters
	logger        *logx.Logger
	mu            sync.RWMutex
}

// NewLocationClustering creates a new location clustering manager
func NewLocationClustering(clusterRadiusMeters float64, logger *logx.Logger) *LocationClustering {
	return &LocationClustering{
		clusters:      make(map[string]*LocationCluster),
		clusterRadius: clusterRadiusMeters,
		logger:        logger,
	}
}

// AddLocationData adds GPS location with performance metrics to clustering
func (lc *LocationClustering) AddLocationData(gpsData *pkg.GPSData, metrics *pkg.Metrics) {
	lc.mu.Lock()
	defer lc.mu.Unlock()

	// Find existing cluster or create new one
	cluster := lc.findOrCreateCluster(gpsData)

	// Update cluster with performance data
	if metrics != nil {
		cluster.Locations++
		cluster.LastSeen = time.Now()

		// Update performance metrics (simple averaging for now)
		cluster.AvgLatency = (cluster.AvgLatency*float64(cluster.Locations-1) + metrics.LatencyMS) / float64(cluster.Locations)
		cluster.AvgLoss = (cluster.AvgLoss*float64(cluster.Locations-1) + metrics.LossPercent) / float64(cluster.Locations)

		if metrics.ObstructionPct != nil {
			cluster.AvgObstruction = (cluster.AvgObstruction*float64(cluster.Locations-1) + *metrics.ObstructionPct) / float64(cluster.Locations)
		}

		// Check if this is a problematic area
		if metrics.LossPercent > 5 || metrics.LatencyMS > 1000 || (metrics.ObstructionPct != nil && *metrics.ObstructionPct > 15) {
			cluster.IssueCount++

			// Mark as problematic if >30% of samples have issues
			if float64(cluster.IssueCount)/float64(cluster.Locations) > 0.3 {
				cluster.ProblematicArea = true
				lc.logger.Warn("Problematic area detected",
					"cluster_id", cluster.ID,
					"lat", cluster.CenterLat,
					"lon", cluster.CenterLon,
					"issue_rate", float64(cluster.IssueCount)/float64(cluster.Locations))
			}
		}
	}
}

// findOrCreateCluster finds existing cluster or creates new one
func (lc *LocationClustering) findOrCreateCluster(gpsData *pkg.GPSData) *LocationCluster {
	// Look for existing cluster within radius
	for _, cluster := range lc.clusters {
		distance := lc.calculateClusterDistance(gpsData.Latitude, gpsData.Longitude, cluster.CenterLat, cluster.CenterLon)
		if distance <= lc.clusterRadius {
			return cluster
		}
	}

	// Create new cluster
	clusterID := fmt.Sprintf("cluster_%d_%d",
		int(gpsData.Latitude*1000000),
		int(gpsData.Longitude*1000000))

	cluster := &LocationCluster{
		ID:        clusterID,
		CenterLat: gpsData.Latitude,
		CenterLon: gpsData.Longitude,
		Radius:    lc.clusterRadius,
		FirstSeen: time.Now(),
		LastSeen:  time.Now(),
		Locations: 0,
	}

	lc.clusters[clusterID] = cluster
	lc.logger.Info("New location cluster created",
		"cluster_id", clusterID,
		"lat", gpsData.Latitude,
		"lon", gpsData.Longitude)

	return cluster
}

// calculateClusterDistance calculates distance between point and cluster center
func (lc *LocationClustering) calculateClusterDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadius = 6371000 // Earth radius in meters

	lat1Rad := lat1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	deltaLatRad := (lat2 - lat1) * math.Pi / 180
	deltaLonRad := (lon2 - lon1) * math.Pi / 180

	a := math.Sin(deltaLatRad/2)*math.Sin(deltaLatRad/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLonRad/2)*math.Sin(deltaLonRad/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadius * c
}

// GetClusters returns all location clusters
func (lc *LocationClustering) GetClusters() map[string]*LocationCluster {
	lc.mu.RLock()
	defer lc.mu.RUnlock()

	// Return copy of clusters
	clusters := make(map[string]*LocationCluster)
	for k, v := range lc.clusters {
		clusters[k] = v
	}
	return clusters
}

// GetProblematicAreas returns clusters marked as problematic
func (lc *LocationClustering) GetProblematicAreas() []*LocationCluster {
	lc.mu.RLock()
	defer lc.mu.RUnlock()

	var problematic []*LocationCluster
	for _, cluster := range lc.clusters {
		if cluster.ProblematicArea {
			problematic = append(problematic, cluster)
		}
	}
	return problematic
}

// IsInProblematicArea checks if current location is in a known problematic area
func (lc *LocationClustering) IsInProblematicArea(gpsData *pkg.GPSData) (*LocationCluster, bool) {
	lc.mu.RLock()
	defer lc.mu.RUnlock()

	for _, cluster := range lc.clusters {
		if cluster.ProblematicArea {
			distance := lc.calculateClusterDistance(gpsData.Latitude, gpsData.Longitude, cluster.CenterLat, cluster.CenterLon)
			if distance <= cluster.Radius {
				return cluster, true
			}
		}
	}
	return nil, false
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
