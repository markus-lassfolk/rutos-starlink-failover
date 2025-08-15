// Package gps provides location awareness and movement detection for failover intelligence
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
)

// GPSManager provides unified GPS data from multiple sources with movement detection
type GPSManager struct {
	lastPosition      *Position
	movementHistory   []MovementEvent
	locationClusters  []LocationCluster
	maxHistorySize    int
	movementThreshold float64 // meters
	starlinkIP        string  // Configurable Starlink dish IP
	starlinkPort      int     // Configurable Starlink dish port
}

// Position represents a GPS coordinate with metadata
type Position struct {
	Latitude   float64   `json:"latitude"`
	Longitude  float64   `json:"longitude"`
	Altitude   float64   `json:"altitude"`
	Accuracy   float64   `json:"accuracy_m"`
	Timestamp  time.Time `json:"timestamp"`
	Source     string    `json:"source"`
	Satellites int       `json:"satellites"`
	HDOP       float64   `json:"hdop"`
	Valid      bool      `json:"valid"`
}

// MovementEvent tracks location changes over time
type MovementEvent struct {
	FromPosition Position      `json:"from"`
	ToPosition   Position      `json:"to"`
	Distance     float64       `json:"distance_m"`
	Speed        float64       `json:"speed_mps"`
	Duration     time.Duration `json:"duration"`
	Timestamp    time.Time     `json:"timestamp"`
	Significant  bool          `json:"significant"` // >500m movement
}

// LocationCluster represents an area with performance history
type LocationCluster struct {
	Center       Position                 `json:"center"`
	Radius       float64                  `json:"radius_m"`
	Observations []PerformanceObservation `json:"observations"`
	QualityScore float64                  `json:"quality_score"`
	LastVisit    time.Time                `json:"last_visit"`
	VisitCount   int                      `json:"visit_count"`
}

// PerformanceObservation tracks performance at a specific location
type PerformanceObservation struct {
	Position       Position           `json:"position"`
	Timestamp      time.Time          `json:"timestamp"`
	InterfaceType  string             `json:"interface_type"`
	QualityMetrics map[string]float64 `json:"quality_metrics"`
	Issues         []string           `json:"issues"`
}

// LocationContext provides situational awareness for failover decisions
type LocationContext struct {
	CurrentPosition        *Position        `json:"current_position"`
	IsMoving               bool             `json:"is_moving"`
	MovementSpeed          float64          `json:"movement_speed_mps"`
	InKnownArea            bool             `json:"in_known_area"`
	CurrentCluster         *LocationCluster `json:"current_cluster,omitempty"`
	MovementDetected       bool             `json:"movement_detected"`
	ShouldResetObstruction bool             `json:"should_reset_obstruction"`
	AreaType               string           `json:"area_type"` // "stationary", "mobile", "high_obstruction", "clear_sky"
	Confidence             float64          `json:"confidence"`
	RecentMovement         []MovementEvent  `json:"recent_movement"`
}

// NewGPSManager creates a new GPS manager with Starlink configuration
func NewGPSManager(starlinkIP string, starlinkPort int) *GPSManager {
	// Set defaults if not provided
	if starlinkIP == "" {
		starlinkIP = "192.168.100.1"
	}
	if starlinkPort == 0 {
		starlinkPort = 9200
	}

	return &GPSManager{
		maxHistorySize: 100, // Keep last 100 movement events
		starlinkIP:     starlinkIP,
		starlinkPort:   starlinkPort,
	}
}

// GetCurrentPosition retrieves GPS position from available sources
func (g *GPSManager) GetCurrentPosition(ctx context.Context) (*Position, error) {
	// Try multiple sources in priority order
	sources := []func(context.Context) (*Position, error){
		g.getStarlinkGPS,
		g.getRUTOSGPS,
		g.getSystemGPS,
	}

	var lastError error
	for _, getPos := range sources {
		if pos, err := getPos(ctx); err == nil && pos != nil && pos.Valid {
			g.updatePosition(pos)
			return pos, nil
		} else if err != nil {
			lastError = err
		}
	}

	// Return last known position if available
	if g.lastPosition != nil {
		return g.lastPosition, nil
	}

	return nil, fmt.Errorf("no GPS sources available: %v", lastError)
}

// GetLocationContext provides comprehensive location intelligence
func (g *GPSManager) GetLocationContext(ctx context.Context) (*LocationContext, error) {
	currentPos, err := g.GetCurrentPosition(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get current position: %w", err)
	}

	context := &LocationContext{
		CurrentPosition: currentPos,
		IsMoving:        g.isCurrentlyMoving(),
		MovementSpeed:   g.getCurrentSpeed(),
		InKnownArea:     g.isInKnownArea(currentPos),
		AreaType:        g.classifyArea(currentPos),
		Confidence:      g.calculateConfidence(currentPos),
		RecentMovement:  g.getRecentMovement(10), // Last 10 events
	}

	return context, nil
}

// isCurrentlyMoving determines if device is in motion based on recent positions
func (g *GPSManager) isCurrentlyMoving() bool {
	if len(g.movementHistory) < 2 {
		return false
	}

	// Check movement in last 5 minutes
	cutoff := time.Now().Add(-5 * time.Minute)
	recentMovement := 0.0
	count := 0

	for i := len(g.movementHistory) - 1; i >= 0; i-- {
		event := g.movementHistory[i]
		if event.Timestamp.Before(cutoff) {
			break
		}
		recentMovement += event.Distance
		count++
	}

	// Moving if average speed > 1 m/s (~3.6 km/h) in recent history
	if count > 0 {
		avgSpeed := recentMovement / float64(count) / 300 // 5min window
		return avgSpeed > 1.0
	}

	return false
}

// getCurrentSpeed calculates current movement speed
func (g *GPSManager) getCurrentSpeed() float64 {
	if len(g.movementHistory) < 1 {
		return 0.0
	}

	// Use most recent movement event
	recent := g.movementHistory[len(g.movementHistory)-1]
	return recent.Speed
}

// isInKnownArea checks if current position is in a previously learned area
func (g *GPSManager) isInKnownArea(pos *Position) bool {
	// Simple implementation - could be enhanced with learned areas
	// For now, consider "known" if we have high accuracy GPS
	return pos.Accuracy < 10.0 && pos.Satellites >= 4
}

// classifyArea determines the type of area based on position and context
func (g *GPSManager) classifyArea(pos *Position) string {
	if !pos.Valid {
		return "unknown"
	}

	// Simple classification based on movement patterns
	if g.isCurrentlyMoving() {
		if g.getCurrentSpeed() > 10.0 { // > 36 km/h
			return "highway"
		}
		return "mobile"
	}

	// Stationary classification based on GPS quality
	if pos.Accuracy < 5.0 && pos.Satellites >= 6 {
		return "clear_sky"
	} else if pos.Accuracy > 20.0 || pos.Satellites < 4 {
		return "high_obstruction"
	}

	return "stationary"
}

// calculateConfidence returns confidence level in location data
func (g *GPSManager) calculateConfidence(pos *Position) float64 {
	if !pos.Valid {
		return 0.0
	}

	confidence := 1.0

	// Reduce confidence based on accuracy
	if pos.Accuracy > 50.0 {
		confidence *= 0.3
	} else if pos.Accuracy > 20.0 {
		confidence *= 0.6
	} else if pos.Accuracy > 10.0 {
		confidence *= 0.8
	}

	// Reduce confidence based on satellite count
	if pos.Satellites < 4 {
		confidence *= 0.4
	} else if pos.Satellites < 6 {
		confidence *= 0.7
	}

	// Boost confidence for recent data
	age := time.Since(pos.Timestamp)
	if age > 5*time.Minute {
		confidence *= 0.5
	} else if age > time.Minute {
		confidence *= 0.8
	}

	return confidence
}

// getRecentMovement returns the most recent movement events
func (g *GPSManager) getRecentMovement(count int) []MovementEvent {
	if len(g.movementHistory) <= count {
		return g.movementHistory
	}

	return g.movementHistory[len(g.movementHistory)-count:]
}

// updatePosition updates internal state with new position
func (g *GPSManager) updatePosition(newPos *Position) {
	if g.lastPosition != nil {
		// Calculate movement
		distance := haversineDistance(
			g.lastPosition.Latitude, g.lastPosition.Longitude,
			newPos.Latitude, newPos.Longitude,
		)

		duration := newPos.Timestamp.Sub(g.lastPosition.Timestamp)
		speed := 0.0
		if duration.Seconds() > 0 {
			speed = distance / duration.Seconds()
		}

		// Only record significant movements (> 5m or > 30s)
		if distance > 5.0 || duration > 30*time.Second {
			event := MovementEvent{
				FromPosition: *g.lastPosition,
				ToPosition:   *newPos,
				Distance:     distance,
				Speed:        speed,
				Duration:     duration,
				Timestamp:    newPos.Timestamp,
			}

			g.movementHistory = append(g.movementHistory, event)

			// Trim history to max size
			if len(g.movementHistory) > g.maxHistorySize {
				g.movementHistory = g.movementHistory[1:]
			}
		}
	}

	g.lastPosition = newPos
}

// getStarlinkGPS gets GPS data from Starlink dish using configured IP and port
func (g *GPSManager) getStarlinkGPS(ctx context.Context) (*Position, error) {
	// Use grpcurl to get location from Starlink with configured endpoint
	endpoint := fmt.Sprintf("%s:%d", g.starlinkIP, g.starlinkPort)
	cmd := exec.CommandContext(ctx, "grpcurl", "-plaintext", "-d",
		`{"get_location":{}}`,
		endpoint,
		"SpaceX.API.Device.Device/Handle")

	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("starlink GPS failed: %w", err)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(output, &resp); err != nil {
		return nil, fmt.Errorf("failed to parse Starlink GPS: %w", err)
	}

	if location, ok := resp["getLocation"].(map[string]interface{}); ok {
		pos := &Position{
			Source:    "starlink",
			Timestamp: time.Now(),
		}

		if lat, ok := location["lla"].(map[string]interface{})["lat"].(float64); ok {
			pos.Latitude = lat
		}
		if lon, ok := location["lla"].(map[string]interface{})["lon"].(float64); ok {
			pos.Longitude = lon
		}
		if alt, ok := location["lla"].(map[string]interface{})["alt"].(float64); ok {
			pos.Altitude = alt
		}
		if acc, ok := location["sigma"].(float64); ok {
			pos.Accuracy = acc
		}

		pos.Valid = pos.Latitude != 0 && pos.Longitude != 0
		return pos, nil
	}

	return nil, fmt.Errorf("no location data in Starlink response")
}

// getRUTOSGPS gets GPS data from RUTOS system
func (g *GPSManager) getRUTOSGPS(ctx context.Context) (*Position, error) {
	// Try ubus call for GPS
	cmd := exec.CommandContext(ctx, "ubus", "call", "gps", "info")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("RUTOS GPS ubus failed: %w", err)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(output, &resp); err != nil {
		return nil, fmt.Errorf("failed to parse RUTOS GPS: %w", err)
	}

	pos := &Position{
		Source:    "rutos",
		Timestamp: time.Now(),
	}

	if lat, ok := resp["latitude"].(string); ok {
		if val, err := strconv.ParseFloat(lat, 64); err == nil {
			pos.Latitude = val
		}
	}
	if lon, ok := resp["longitude"].(string); ok {
		if val, err := strconv.ParseFloat(lon, 64); err == nil {
			pos.Longitude = val
		}
	}
	if alt, ok := resp["altitude"].(string); ok {
		if val, err := strconv.ParseFloat(alt, 64); err == nil {
			pos.Altitude = val
		}
	}
	if sats, ok := resp["satellites"].(string); ok {
		if val, err := strconv.Atoi(sats); err == nil {
			pos.Satellites = val
		}
	}
	if hdop, ok := resp["hdop"].(string); ok {
		if val, err := strconv.ParseFloat(hdop, 64); err == nil {
			pos.HDOP = val
			// Estimate accuracy from HDOP
			pos.Accuracy = val * 5.0 // Rough conversion
		}
	}

	// Check if GPS fix is valid
	if fix, ok := resp["fix"].(string); ok {
		pos.Valid = fix == "3D" || fix == "2D"
	}

	if pos.Latitude != 0 && pos.Longitude != 0 && pos.Valid {
		return pos, nil
	}

	return nil, fmt.Errorf("no valid GPS fix from RUTOS")
}

// getSystemGPS gets GPS data from system GPSD
func (g *GPSManager) getSystemGPS(ctx context.Context) (*Position, error) {
	// Try gpspipe for NMEA data
	cmd := exec.CommandContext(ctx, "timeout", "3", "gpspipe", "-w", "-n", "5")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("gpspipe failed: %w", err)
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "TPV") {
			var tpv map[string]interface{}
			if err := json.Unmarshal([]byte(line), &tpv); err == nil {
				if class, ok := tpv["class"].(string); ok && class == "TPV" {
					pos := &Position{
						Source:    "gpsd",
						Timestamp: time.Now(),
					}

					if lat, ok := tpv["lat"].(float64); ok {
						pos.Latitude = lat
					}
					if lon, ok := tpv["lon"].(float64); ok {
						pos.Longitude = lon
					}
					if alt, ok := tpv["alt"].(float64); ok {
						pos.Altitude = alt
					}
					if epy, ok := tpv["epy"].(float64); ok {
						pos.Accuracy = epy
					}

					if mode, ok := tpv["mode"].(float64); ok {
						pos.Valid = mode >= 2 // 2D or 3D fix
					}

					if pos.Latitude != 0 && pos.Longitude != 0 && pos.Valid {
						return pos, nil
					}
				}
			}
		}
	}

	return nil, fmt.Errorf("no valid GPS data from gpsd")
}

// haversineDistance calculates the distance between two GPS coordinates
func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadius = 6371000 // meters

	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadius * c
}
