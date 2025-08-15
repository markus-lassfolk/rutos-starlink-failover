package gps

import (
	"fmt"
	"math"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
)

// MovementDetector handles movement detection and related actions
type MovementDetector struct {
	logger            *logx.Logger
	config            *MovementConfig
	lastKnownLocation *pkg.GPSData
	movementHistory   []*MovementEvent
	isStationary      bool
	stationaryTime    time.Time
}

// MovementConfig represents movement detection configuration
type MovementConfig struct {
	Enabled                    bool    `json:"enabled"`
	MovementThresholdM         float64 `json:"movement_threshold_m"`          // Minimum distance to consider movement
	StationaryThresholdM       float64 `json:"stationary_threshold_m"`        // Maximum distance to consider stationary
	MovementTimeWindowS        int     `json:"movement_time_window_s"`        // Time window for movement analysis
	MinMovementDurationS       int     `json:"min_movement_duration_s"`       // Minimum duration to confirm movement
	StationaryTimeoutS         int     `json:"stationary_timeout_s"`          // Time to wait before confirming stationary
	ObstructionMapResetEnabled bool    `json:"obstruction_map_reset_enabled"` // Enable obstruction map reset on movement
	MovementHistorySize        int     `json:"movement_history_size"`         // Number of movement events to keep
	VelocityCalculationEnabled bool    `json:"velocity_calculation_enabled"`  // Enable velocity calculation
	AccelerationThresholdMPS2  float64 `json:"acceleration_threshold_mps2"`   // Acceleration threshold for alerts
}

// MovementEvent represents a movement detection event
type MovementEvent struct {
	Timestamp       time.Time    `json:"timestamp"`
	FromLocation    *pkg.GPSData `json:"from_location"`
	ToLocation      *pkg.GPSData `json:"to_location"`
	Distance        float64      `json:"distance"`         // Distance in meters
	Duration        float64      `json:"duration"`         // Duration in seconds
	Velocity        float64      `json:"velocity"`         // Velocity in m/s
	Acceleration    float64      `json:"acceleration"`     // Acceleration in m/s²
	MovementType    string       `json:"movement_type"`    // stationary|slow|normal|fast|rapid
	ActionTriggered string       `json:"action_triggered"` // Action taken due to movement
}

// MovementStatus represents current movement status
type MovementStatus struct {
	IsMoving              bool             `json:"is_moving"`
	IsStationary          bool             `json:"is_stationary"`
	CurrentLocation       *pkg.GPSData     `json:"current_location"`
	LastKnownLocation     *pkg.GPSData     `json:"last_known_location"`
	DistanceFromLast      float64          `json:"distance_from_last"`
	CurrentVelocity       float64          `json:"current_velocity"`
	CurrentAcceleration   float64          `json:"current_acceleration"`
	StationaryDuration    float64          `json:"stationary_duration"`
	RecentMovementHistory []*MovementEvent `json:"recent_movement_history"`
	MovementSummary       *MovementSummary `json:"movement_summary"`
}

// MovementSummary provides summary statistics about movement
type MovementSummary struct {
	TotalDistance       float64   `json:"total_distance"`        // Total distance traveled
	MaxVelocity         float64   `json:"max_velocity"`          // Maximum velocity observed
	AvgVelocity         float64   `json:"avg_velocity"`          // Average velocity
	MaxAcceleration     float64   `json:"max_acceleration"`      // Maximum acceleration
	MovementEvents      int       `json:"movement_events"`       // Number of movement events
	StationaryPeriods   int       `json:"stationary_periods"`    // Number of stationary periods
	LastMovementTime    time.Time `json:"last_movement_time"`    // Time of last significant movement
	TotalMovementTime   float64   `json:"total_movement_time"`   // Total time spent moving
	TotalStationaryTime float64   `json:"total_stationary_time"` // Total time spent stationary
}

// NewMovementDetector creates a new movement detector
func NewMovementDetector(config *MovementConfig, logger *logx.Logger) *MovementDetector {
	if config == nil {
		config = DefaultMovementConfig()
	}

	return &MovementDetector{
		logger:          logger,
		config:          config,
		movementHistory: make([]*MovementEvent, 0, config.MovementHistorySize),
		isStationary:    true,
		stationaryTime:  time.Now(),
	}
}

// DefaultMovementConfig returns default movement detection configuration
func DefaultMovementConfig() *MovementConfig {
	return &MovementConfig{
		Enabled:                    true,
		MovementThresholdM:         500.0, // 500 meters triggers obstruction map reset
		StationaryThresholdM:       50.0,  // 50 meters considered stationary
		MovementTimeWindowS:        300,   // 5 minutes analysis window
		MinMovementDurationS:       60,    // 1 minute minimum movement duration
		StationaryTimeoutS:         600,   // 10 minutes to confirm stationary
		ObstructionMapResetEnabled: true,  // Enable obstruction map reset
		MovementHistorySize:        100,   // Keep last 100 movement events
		VelocityCalculationEnabled: true,  // Enable velocity calculation
		AccelerationThresholdMPS2:  2.0,   // 2 m/s² acceleration alert threshold
	}
}

// ProcessLocationUpdate processes a new GPS location and detects movement
func (md *MovementDetector) ProcessLocationUpdate(location *pkg.GPSData) (*MovementEvent, error) {
	if !md.config.Enabled {
		return nil, nil
	}

	if location == nil || !location.Valid {
		return nil, fmt.Errorf("invalid GPS location data")
	}

	md.logger.LogDataFlow("movement_detector", "gps_update", "location", 1, map[string]interface{}{
		"latitude":  location.Latitude,
		"longitude": location.Longitude,
		"accuracy":  location.Accuracy,
		"source":    location.Source,
	})

	// If this is the first location, just store it
	if md.lastKnownLocation == nil {
		md.lastKnownLocation = location
		md.stationaryTime = time.Now()
		return nil, nil
	}

	// Calculate distance and time since last update
	distance := md.calculateDistance(md.lastKnownLocation, location)
	timeDiff := location.Timestamp.Sub(md.lastKnownLocation.Timestamp).Seconds()

	if timeDiff <= 0 {
		return nil, fmt.Errorf("invalid time sequence in GPS data")
	}

	// Calculate velocity and acceleration
	velocity := distance / timeDiff
	acceleration := md.calculateAcceleration(velocity, timeDiff)

	// Determine movement type
	movementType := md.classifyMovement(distance, velocity)

	// Create movement event
	event := &MovementEvent{
		Timestamp:    time.Now(),
		FromLocation: md.lastKnownLocation,
		ToLocation:   location,
		Distance:     distance,
		Duration:     timeDiff,
		Velocity:     velocity,
		Acceleration: acceleration,
		MovementType: movementType,
	}

	// Process movement detection logic
	md.processMovementLogic(event)

	// Update movement history
	md.addMovementEvent(event)

	// Update last known location
	md.lastKnownLocation = location

	return event, nil
}

// calculateDistance calculates distance between two GPS coordinates
func (md *MovementDetector) calculateDistance(from, to *pkg.GPSData) float64 {
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

// calculateAcceleration calculates acceleration based on velocity change
func (md *MovementDetector) calculateAcceleration(currentVelocity, timeDiff float64) float64 {
	if len(md.movementHistory) == 0 {
		return 0
	}

	lastEvent := md.movementHistory[len(md.movementHistory)-1]
	velocityChange := currentVelocity - lastEvent.Velocity
	return velocityChange / timeDiff
}

// classifyMovement classifies the type of movement based on distance and velocity
func (md *MovementDetector) classifyMovement(distance, velocity float64) string {
	if distance < md.config.StationaryThresholdM {
		return "stationary"
	} else if velocity < 1.0 { // < 1 m/s (3.6 km/h)
		return "slow"
	} else if velocity < 5.0 { // < 5 m/s (18 km/h)
		return "normal"
	} else if velocity < 15.0 { // < 15 m/s (54 km/h)
		return "fast"
	} else {
		return "rapid"
	}
}

// processMovementLogic processes movement detection logic and triggers actions
func (md *MovementDetector) processMovementLogic(event *MovementEvent) {
	wasStationary := md.isStationary

	// Update stationary status
	if event.Distance < md.config.StationaryThresholdM {
		if !md.isStationary {
			md.stationaryTime = time.Now()
		}
		md.isStationary = true
	} else if event.Distance >= md.config.MovementThresholdM {
		md.isStationary = false
	}

	// Log state changes
	if wasStationary != md.isStationary {
		md.logger.LogStateChange("movement_detector",
			map[bool]string{true: "stationary", false: "moving"}[wasStationary],
			map[bool]string{true: "stationary", false: "moving"}[md.isStationary],
			"movement_state_changed", map[string]interface{}{
				"distance":      event.Distance,
				"velocity":      event.Velocity,
				"movement_type": event.MovementType,
				"threshold_m":   md.config.MovementThresholdM,
			})
	}

	// Trigger obstruction map reset if significant movement detected
	if md.config.ObstructionMapResetEnabled && event.Distance >= md.config.MovementThresholdM {
		event.ActionTriggered = "obstruction_map_reset"
		md.logger.LogVerbose("movement_action_triggered", map[string]interface{}{
			"action":    "obstruction_map_reset",
			"distance":  event.Distance,
			"threshold": md.config.MovementThresholdM,
			"from_lat":  event.FromLocation.Latitude,
			"from_lon":  event.FromLocation.Longitude,
			"to_lat":    event.ToLocation.Latitude,
			"to_lon":    event.ToLocation.Longitude,
		})
	}

	// Check for high acceleration alerts
	if md.config.VelocityCalculationEnabled &&
		math.Abs(event.Acceleration) > md.config.AccelerationThresholdMPS2 {
		md.logger.LogVerbose("high_acceleration_detected", map[string]interface{}{
			"acceleration":  event.Acceleration,
			"threshold":     md.config.AccelerationThresholdMPS2,
			"velocity":      event.Velocity,
			"movement_type": event.MovementType,
		})
	}
}

// addMovementEvent adds a movement event to the history
func (md *MovementDetector) addMovementEvent(event *MovementEvent) {
	md.movementHistory = append(md.movementHistory, event)

	// Maintain history size limit
	if len(md.movementHistory) > md.config.MovementHistorySize {
		md.movementHistory = md.movementHistory[1:]
	}
}

// GetMovementStatus returns the current movement status
func (md *MovementDetector) GetMovementStatus() *MovementStatus {
	status := &MovementStatus{
		IsMoving:           !md.isStationary,
		IsStationary:       md.isStationary,
		CurrentLocation:    md.lastKnownLocation,
		LastKnownLocation:  md.lastKnownLocation,
		StationaryDuration: time.Since(md.stationaryTime).Seconds(),
		MovementSummary:    md.calculateMovementSummary(),
	}

	// Get recent movement history (last 10 events)
	historySize := len(md.movementHistory)
	startIndex := 0
	if historySize > 10 {
		startIndex = historySize - 10
	}
	status.RecentMovementHistory = md.movementHistory[startIndex:]

	// Calculate current metrics
	if len(md.movementHistory) > 0 {
		lastEvent := md.movementHistory[len(md.movementHistory)-1]
		status.DistanceFromLast = lastEvent.Distance
		status.CurrentVelocity = lastEvent.Velocity
		status.CurrentAcceleration = lastEvent.Acceleration
	}

	return status
}

// calculateMovementSummary calculates summary statistics
func (md *MovementDetector) calculateMovementSummary() *MovementSummary {
	summary := &MovementSummary{}

	if len(md.movementHistory) == 0 {
		return summary
	}

	var totalDistance, totalVelocity, totalMovementTime, totalStationaryTime float64
	var maxVelocity, maxAcceleration float64
	var movementEvents, stationaryPeriods int
	var lastMovementTime time.Time

	for _, event := range md.movementHistory {
		totalDistance += event.Distance
		totalVelocity += event.Velocity

		if event.Velocity > maxVelocity {
			maxVelocity = event.Velocity
		}

		if math.Abs(event.Acceleration) > maxAcceleration {
			maxAcceleration = math.Abs(event.Acceleration)
		}

		if event.MovementType != "stationary" {
			movementEvents++
			totalMovementTime += event.Duration
			if event.Timestamp.After(lastMovementTime) {
				lastMovementTime = event.Timestamp
			}
		} else {
			stationaryPeriods++
			totalStationaryTime += event.Duration
		}
	}

	summary.TotalDistance = totalDistance
	summary.MaxVelocity = maxVelocity
	summary.MaxAcceleration = maxAcceleration
	summary.MovementEvents = movementEvents
	summary.StationaryPeriods = stationaryPeriods
	summary.LastMovementTime = lastMovementTime
	summary.TotalMovementTime = totalMovementTime
	summary.TotalStationaryTime = totalStationaryTime

	if len(md.movementHistory) > 0 {
		summary.AvgVelocity = totalVelocity / float64(len(md.movementHistory))
	}

	return summary
}

// ShouldResetObstructionMap determines if obstruction map should be reset
func (md *MovementDetector) ShouldResetObstructionMap() bool {
	if !md.config.Enabled || !md.config.ObstructionMapResetEnabled {
		return false
	}

	// Check if we have recent significant movement
	cutoff := time.Now().Add(-time.Duration(md.config.MovementTimeWindowS) * time.Second)

	for i := len(md.movementHistory) - 1; i >= 0; i-- {
		event := md.movementHistory[i]
		if event.Timestamp.Before(cutoff) {
			break
		}

		if event.Distance >= md.config.MovementThresholdM &&
			event.ActionTriggered == "obstruction_map_reset" {
			return true
		}
	}

	return false
}

// GetMovementTrend analyzes recent movement trend
func (md *MovementDetector) GetMovementTrend() map[string]interface{} {
	if len(md.movementHistory) < 3 {
		return map[string]interface{}{
			"trend": "insufficient_data",
		}
	}

	// Analyze last few events for trend
	recentEvents := md.movementHistory
	if len(recentEvents) > 10 {
		recentEvents = recentEvents[len(recentEvents)-10:]
	}

	var velocitySum, accelerationSum float64
	var movingCount, stationaryCount int

	for _, event := range recentEvents {
		velocitySum += event.Velocity
		accelerationSum += event.Acceleration

		if event.MovementType == "stationary" {
			stationaryCount++
		} else {
			movingCount++
		}
	}

	avgVelocity := velocitySum / float64(len(recentEvents))
	avgAcceleration := accelerationSum / float64(len(recentEvents))

	trend := "stable"
	if avgAcceleration > 0.5 {
		trend = "accelerating"
	} else if avgAcceleration < -0.5 {
		trend = "decelerating"
	} else if movingCount > stationaryCount {
		trend = "mobile"
	} else if stationaryCount > movingCount {
		trend = "stationary"
	}

	return map[string]interface{}{
		"trend":              trend,
		"avg_velocity":       avgVelocity,
		"avg_acceleration":   avgAcceleration,
		"moving_events":      movingCount,
		"stationary_events":  stationaryCount,
		"recent_event_count": len(recentEvents),
	}
}

// ResetMovementHistory clears the movement history
func (md *MovementDetector) ResetMovementHistory() {
	md.movementHistory = make([]*MovementEvent, 0, md.config.MovementHistorySize)
	md.logger.LogVerbose("movement_history_reset", map[string]interface{}{
		"reason": "manual_reset",
	})
}

// IsSignificantMovement checks if a distance represents significant movement
func (md *MovementDetector) IsSignificantMovement(distance float64) bool {
	return distance >= md.config.MovementThresholdM
}

// GetDistanceFromLastKnown calculates distance from last known location
func (md *MovementDetector) GetDistanceFromLastKnown(location *pkg.GPSData) float64 {
	if md.lastKnownLocation == nil || location == nil {
		return 0
	}
	return md.calculateDistance(md.lastKnownLocation, location)
}
