// Package obstruction provides predictive Starlink obstruction analysis and management
package obstruction

import (
	"context"
	"fmt"
	"math"
	"time"
)

// ObstructionManager provides predictive obstruction analysis
type ObstructionManager struct {
	history          []ObstructionSample
	maxHistorySize   int
	predictionWindow time.Duration
	models           map[string]*PredictionModel
}

// ObstructionSample represents a point-in-time obstruction measurement with enhanced data
type ObstructionSample struct {
	Timestamp                        time.Time `json:"timestamp"`
	ObstructionPct                   float64   `json:"obstruction_pct"`
	SNR                              float64   `json:"snr"`
	TimeObstructed                   float64   `json:"time_obstructed"`
	AvgProlongedObstructionIntervalS float64   `json:"avg_prolonged_obstruction_interval_s"`
	PatchesValid                     bool      `json:"patches_valid"`
	ValidS                           float64   `json:"valid_s"`
	Latitude                         float64   `json:"latitude"`
	Longitude                        float64   `json:"longitude"`
	Altitude                         float64   `json:"altitude"`
	Azimuth                          float64   `json:"azimuth"`
	Elevation                        float64   `json:"elevation"`
	MovementSpeed                    float64   `json:"movement_speed_mps"`
	WeatherCode                      string    `json:"weather_code"`
	SatelliteID                      string    `json:"satellite_id"`
	BeamID                           string    `json:"beam_id"`

	// Trend analysis fields
	ObstructionRate float64 `json:"obstruction_rate_pct_per_min"`
	SNRRate         float64 `json:"snr_rate_db_per_min"`
}

// PredictionModel represents different obstruction prediction algorithms
type PredictionModel struct {
	Name        string                 `json:"name"`
	Type        string                 `json:"type"` // "temporal", "spatial", "weather", "hybrid"
	Accuracy    float64                `json:"accuracy"`
	LastTrained time.Time              `json:"last_trained"`
	Parameters  map[string]interface{} `json:"parameters"`
	SampleCount int                    `json:"sample_count"`
}

// ObstructionPrediction represents a future obstruction forecast
type ObstructionPrediction struct {
	Timestamp      time.Time     `json:"timestamp"`
	PredictedPct   float64       `json:"predicted_obstruction_pct"`
	Confidence     float64       `json:"confidence"`
	PredictionType string        `json:"prediction_type"`
	Model          string        `json:"model"`
	Factors        []string      `json:"contributing_factors"`
	Severity       string        `json:"severity"` // "low", "medium", "high", "critical"
	Duration       time.Duration `json:"expected_duration"`
	Recommendation string        `json:"recommendation"`
}

// ObstructionAnalysis provides comprehensive obstruction intelligence
type ObstructionAnalysis struct {
	CurrentState    *ObstructionState        `json:"current_state"`
	ShortTerm       []*ObstructionPrediction `json:"short_term_forecast"`  // Next 1 hour
	MediumTerm      []*ObstructionPrediction `json:"medium_term_forecast"` // Next 6 hours
	LocationProfile *LocationProfile         `json:"location_profile"`
	Patterns        *ObstructionPatterns     `json:"patterns"`
	Recommendations []string                 `json:"recommendations"`
	Confidence      float64                  `json:"overall_confidence"`
}

// ObstructionState represents current obstruction status
type ObstructionState struct {
	Current       float64       `json:"current_obstruction_pct"`
	Trend         string        `json:"trend"` // "improving", "worsening", "stable"
	TrendRate     float64       `json:"trend_rate_pct_per_min"`
	Duration      time.Duration `json:"current_duration"`
	Severity      string        `json:"severity"`
	PrimaryFactor string        `json:"primary_factor"`
}

// LocationProfile analyzes obstruction patterns for current location
type LocationProfile struct {
	LocationHash     string             `json:"location_hash"`
	SampleCount      int                `json:"sample_count"`
	AvgObstruction   float64            `json:"avg_obstruction_pct"`
	MaxObstruction   float64            `json:"max_obstruction_pct"`
	CommonDirections []DirectionStat    `json:"common_obstruction_directions"`
	TimePatterns     map[string]float64 `json:"time_of_day_patterns"`
	SeasonalTrends   map[string]float64 `json:"seasonal_trends"`
	Reliability      float64            `json:"reliability_score"`
}

// DirectionStat represents obstruction statistics by direction
type DirectionStat struct {
	Azimuth        float64 `json:"azimuth"`
	Elevation      float64 `json:"elevation"`
	ObstructionPct float64 `json:"avg_obstruction_pct"`
	Frequency      int     `json:"frequency"`
}

// ObstructionPatterns identifies recurring obstruction patterns
type ObstructionPatterns struct {
	DailyPatterns    []TimePattern      `json:"daily_patterns"`
	WeatherPatterns  []WeatherPattern   `json:"weather_patterns"`
	MovementPatterns []MovementPattern  `json:"movement_patterns"`
	SeasonalFactors  map[string]float64 `json:"seasonal_factors"`
}

// TimePattern represents time-based obstruction patterns
type TimePattern struct {
	StartTime      string  `json:"start_time"` // "HH:MM"
	EndTime        string  `json:"end_time"`
	AvgObstruction float64 `json:"avg_obstruction_pct"`
	Frequency      int     `json:"frequency"`
	Confidence     float64 `json:"confidence"`
}

// WeatherPattern represents weather-related obstruction patterns
type WeatherPattern struct {
	WeatherType     string        `json:"weather_type"`
	ImpactFactor    float64       `json:"impact_factor"`
	TypicalDuration time.Duration `json:"typical_duration"`
	Confidence      float64       `json:"confidence"`
}

// MovementPattern represents movement-related obstruction patterns
type MovementPattern struct {
	MovementType string  `json:"movement_type"` // "stationary", "slow", "highway"
	SpeedRange   string  `json:"speed_range"`
	ImpactFactor float64 `json:"impact_factor"`
	Confidence   float64 `json:"confidence"`
}

// NewObstructionManager creates a new obstruction analysis manager
func NewObstructionManager() *ObstructionManager {
	return &ObstructionManager{
		maxHistorySize:   10000, // Keep 10K samples
		predictionWindow: 6 * time.Hour,
		models: map[string]*PredictionModel{
			"temporal": {Name: "temporal", Type: "temporal", Accuracy: 0.7},
			"spatial":  {Name: "spatial", Type: "spatial", Accuracy: 0.6},
			"weather":  {Name: "weather", Type: "weather", Accuracy: 0.5},
			"hybrid":   {Name: "hybrid", Type: "hybrid", Accuracy: 0.8},
		},
	}
}

// AddSample adds a new obstruction measurement to the analysis
func (o *ObstructionManager) AddSample(sample ObstructionSample) {
	o.history = append(o.history, sample)

	// Trim history to max size
	if len(o.history) > o.maxHistorySize {
		o.history = o.history[1:]
	}

	// Update models periodically
	if len(o.history)%100 == 0 {
		o.updateModels()
	}
}

// AnalyzeObstruction provides comprehensive obstruction analysis
func (o *ObstructionManager) AnalyzeObstruction(ctx context.Context, currentLat, currentLon float64) (*ObstructionAnalysis, error) {
	if len(o.history) < 10 {
		return nil, fmt.Errorf("insufficient data for analysis")
	}

	analysis := &ObstructionAnalysis{
		CurrentState:    o.analyzeCurrentState(),
		LocationProfile: o.analyzeLocationProfile(currentLat, currentLon),
		Patterns:        o.identifyPatterns(),
	}

	// Generate predictions
	shortTerm, err := o.predictShortTerm(ctx, 1*time.Hour)
	if err == nil {
		analysis.ShortTerm = shortTerm
	}

	mediumTerm, err := o.predictMediumTerm(ctx, 6*time.Hour)
	if err == nil {
		analysis.MediumTerm = mediumTerm
	}

	// Generate recommendations
	analysis.Recommendations = o.generateRecommendations(analysis)
	analysis.Confidence = o.calculateOverallConfidence(analysis)

	return analysis, nil
}

// PredictObstruction predicts future obstruction for a specific time and location
func (o *ObstructionManager) PredictObstruction(ctx context.Context, targetTime time.Time, lat, lon float64) (*ObstructionPrediction, error) {
	if len(o.history) < 50 {
		return nil, fmt.Errorf("insufficient historical data")
	}

	// Use hybrid model for best accuracy
	prediction := &ObstructionPrediction{
		Timestamp:      targetTime,
		Model:          "hybrid",
		PredictionType: "comprehensive",
	}

	// Temporal prediction component
	temporalPct := o.predictTemporal(targetTime)

	// Spatial prediction component
	spatialPct := o.predictSpatial(lat, lon)

	// Weather prediction component
	weatherPct := o.predictWeather(targetTime)

	// Combine predictions using weighted average
	weights := map[string]float64{
		"temporal": 0.4,
		"spatial":  0.35,
		"weather":  0.25,
	}

	prediction.PredictedPct = temporalPct*weights["temporal"] +
		spatialPct*weights["spatial"] +
		weatherPct*weights["weather"]

	// Calculate confidence based on data quality and consistency
	prediction.Confidence = o.calculatePredictionConfidence(targetTime, lat, lon)

	// Classify severity
	prediction.Severity = o.classifySeverity(prediction.PredictedPct)

	// Estimate duration
	prediction.Duration = o.estimateDuration(prediction.PredictedPct, prediction.Severity)

	// Generate recommendation
	prediction.Recommendation = o.generateActionRecommendation(prediction)

	// Identify contributing factors
	prediction.Factors = o.identifyContributingFactors(targetTime, lat, lon)

	return prediction, nil
}

// analyzeCurrentState analyzes current obstruction trends
func (o *ObstructionManager) analyzeCurrentState() *ObstructionState {
	if len(o.history) == 0 {
		return nil
	}

	latest := o.history[len(o.history)-1]
	state := &ObstructionState{
		Current: latest.ObstructionPct,
	}

	// Analyze trend over last 10 minutes
	cutoff := latest.Timestamp.Add(-10 * time.Minute)
	var recentSamples []ObstructionSample

	for i := len(o.history) - 1; i >= 0; i-- {
		if o.history[i].Timestamp.Before(cutoff) {
			break
		}
		recentSamples = append(recentSamples, o.history[i])
	}

	if len(recentSamples) >= 3 {
		first := recentSamples[len(recentSamples)-1].ObstructionPct
		last := recentSamples[0].ObstructionPct
		duration := recentSamples[0].Timestamp.Sub(recentSamples[len(recentSamples)-1].Timestamp)

		if duration.Minutes() > 0 {
			state.TrendRate = (last - first) / duration.Minutes()

			if state.TrendRate > 0.5 {
				state.Trend = "worsening"
			} else if state.TrendRate < -0.5 {
				state.Trend = "improving"
			} else {
				state.Trend = "stable"
			}
		}
	}

	// Calculate current event duration
	state.Duration = o.calculateEventDuration(latest.ObstructionPct)
	state.Severity = o.classifySeverity(state.Current)
	state.PrimaryFactor = o.identifyPrimaryFactor(latest)

	return state
}

// analyzeLocationProfile creates a profile for the current location
func (o *ObstructionManager) analyzeLocationProfile(lat, lon float64) *LocationProfile {
	// Group samples by location (within ~100m)
	locationSamples := o.getSamplesNearLocation(lat, lon, 0.001) // ~100m radius

	if len(locationSamples) < 5 {
		return &LocationProfile{
			LocationHash: fmt.Sprintf("%.4f,%.4f", lat, lon),
			SampleCount:  len(locationSamples),
			Reliability:  0.0,
		}
	}

	profile := &LocationProfile{
		LocationHash:     fmt.Sprintf("%.4f,%.4f", lat, lon),
		SampleCount:      len(locationSamples),
		CommonDirections: o.analyzeDirections(locationSamples),
		TimePatterns:     o.analyzeTimePatterns(locationSamples),
		SeasonalTrends:   o.analyzeSeasonalTrends(locationSamples),
	}

	// Calculate statistics
	var total, max float64
	for _, sample := range locationSamples {
		total += sample.ObstructionPct
		if sample.ObstructionPct > max {
			max = sample.ObstructionPct
		}
	}

	profile.AvgObstruction = total / float64(len(locationSamples))
	profile.MaxObstruction = max
	profile.Reliability = math.Min(1.0, float64(len(locationSamples))/100.0)

	return profile
}

// identifyPatterns identifies recurring obstruction patterns
func (o *ObstructionManager) identifyPatterns() *ObstructionPatterns {
	patterns := &ObstructionPatterns{
		DailyPatterns:    o.analyzeDailyPatterns(),
		WeatherPatterns:  o.analyzeWeatherPatterns(),
		MovementPatterns: o.analyzeMovementPatterns(),
		SeasonalFactors:  o.analyzeSeasonalFactors(),
	}

	return patterns
}

// Helper prediction methods

func (o *ObstructionManager) predictTemporal(targetTime time.Time) float64 {
	// Simple time-based prediction using historical hourly averages
	hour := targetTime.Hour()

	var hourSamples []float64
	for _, sample := range o.history {
		if sample.Timestamp.Hour() == hour {
			hourSamples = append(hourSamples, sample.ObstructionPct)
		}
	}

	if len(hourSamples) == 0 {
		return 10.0 // Default assumption
	}

	// Calculate average for this hour
	var total float64
	for _, pct := range hourSamples {
		total += pct
	}

	return total / float64(len(hourSamples))
}

func (o *ObstructionManager) predictSpatial(lat, lon float64) float64 {
	// Predict based on location history
	nearby := o.getSamplesNearLocation(lat, lon, 0.01) // ~1km radius

	if len(nearby) == 0 {
		return 15.0 // Default for unknown locations
	}

	var total float64
	for _, sample := range nearby {
		total += sample.ObstructionPct
	}

	return total / float64(len(nearby))
}

func (o *ObstructionManager) predictWeather(targetTime time.Time) float64 {
	// Enhanced weather prediction using time patterns and historical correlation

	// If no historical weather data, use time-based estimation
	if len(o.history) < 10 {
		// Basic weather impact estimation by time of day and season
		hour := targetTime.Hour()
		month := targetTime.Month()

		// Early morning often has dew/fog issues
		if hour >= 5 && hour <= 8 {
			return 12.0
		}

		// Winter months typically have more weather impact
		if month >= 11 || month <= 2 {
			return 15.0
		}

		// Summer clear conditions
		if month >= 6 && month <= 8 && hour >= 10 && hour <= 16 {
			return 3.0
		}

		return 8.0 // Default assumption
	}

	// Use historical weather patterns
	weatherPatterns := o.analyzeWeatherPatterns()
	if len(weatherPatterns) > 0 {
		// Find the most likely weather pattern for this time
		var avgImpact float64
		var count int

		for _, pattern := range weatherPatterns {
			// Weight by confidence and recency
			avgImpact += pattern.ImpactFactor * pattern.Confidence * 10.0 // Convert to percentage
			count++
		}

		if count > 0 {
			return avgImpact / float64(count)
		}
	}

	// Fallback to seasonal trends
	seasonalFactors := o.analyzeSeasonalFactors()
	month := targetTime.Month()
	var season string

	switch {
	case month >= 3 && month <= 5:
		season = "spring"
	case month >= 6 && month <= 8:
		season = "summer"
	case month >= 9 && month <= 11:
		season = "fall"
	default:
		season = "winter"
	}

	if factor, exists := seasonalFactors[season]; exists {
		return factor
	}

	return 8.0 // Default
}

func (o *ObstructionManager) predictShortTerm(ctx context.Context, duration time.Duration) ([]*ObstructionPrediction, error) {
	var predictions []*ObstructionPrediction

	// Generate predictions for every 15 minutes
	interval := 15 * time.Minute
	steps := int(duration / interval)

	// Get current location if available
	currentLat, currentLon := 0.0, 0.0
	if len(o.history) > 0 {
		latest := o.history[len(o.history)-1]
		currentLat = latest.Latitude
		currentLon = latest.Longitude
	}

	for i := 1; i <= steps; i++ {
		targetTime := time.Now().Add(time.Duration(i) * interval)

		// Use enhanced multi-model prediction
		temporalPct := o.predictTemporal(targetTime)
		spatialPct := o.predictSpatial(currentLat, currentLon)
		weatherPct := o.predictWeather(targetTime)

		// Weighted combination for short-term (more weight on temporal patterns)
		predictedPct := temporalPct*0.5 + spatialPct*0.3 + weatherPct*0.2

		pred := &ObstructionPrediction{
			Timestamp:      targetTime,
			PredictedPct:   predictedPct,
			Confidence:     0.8 - (float64(i) * 0.1), // Decreasing confidence over time
			PredictionType: "short_term",
			Model:          "hybrid",
			Factors:        []string{"temporal_pattern", "location_history"},
		}

		pred.Severity = o.classifySeverity(pred.PredictedPct)
		pred.Duration = o.estimateDuration(pred.PredictedPct, pred.Severity)
		pred.Recommendation = o.generateActionRecommendation(pred)

		predictions = append(predictions, pred)
	}

	return predictions, nil
}

func (o *ObstructionManager) predictMediumTerm(ctx context.Context, duration time.Duration) ([]*ObstructionPrediction, error) {
	var predictions []*ObstructionPrediction

	// Generate predictions for every hour
	interval := 1 * time.Hour
	steps := int(duration / interval)

	for i := 1; i <= steps; i++ {
		targetTime := time.Now().Add(time.Duration(i) * interval)

		pred := &ObstructionPrediction{
			Timestamp:      targetTime,
			PredictedPct:   o.predictTemporal(targetTime),
			Confidence:     0.6, // Lower confidence for longer predictions
			PredictionType: "medium_term",
			Model:          "temporal",
		}

		pred.Severity = o.classifySeverity(pred.PredictedPct)
		predictions = append(predictions, pred)
	}

	return predictions, nil
}

// Helper methods

func (o *ObstructionManager) getSamplesNearLocation(lat, lon, radiusDeg float64) []ObstructionSample {
	var nearby []ObstructionSample

	for _, sample := range o.history {
		distance := math.Sqrt(math.Pow(sample.Latitude-lat, 2) + math.Pow(sample.Longitude-lon, 2))
		if distance <= radiusDeg {
			nearby = append(nearby, sample)
		}
	}

	return nearby
}

func (o *ObstructionManager) classifySeverity(obstructionPct float64) string {
	if obstructionPct >= 50 {
		return "critical"
	} else if obstructionPct >= 25 {
		return "high"
	} else if obstructionPct >= 10 {
		return "medium"
	}
	return "low"
}

func (o *ObstructionManager) calculateEventDuration(currentPct float64) time.Duration {
	// Calculate how long current obstruction level has been active
	threshold := currentPct * 0.8 // Within 20% of current level

	for i := len(o.history) - 1; i >= 0; i-- {
		if math.Abs(o.history[i].ObstructionPct-currentPct) > threshold {
			return time.Since(o.history[i].Timestamp)
		}
	}

	return time.Since(o.history[0].Timestamp)
}

func (o *ObstructionManager) identifyPrimaryFactor(sample ObstructionSample) string {
	// Enhanced factor identification based on multiple criteria
	factors := make(map[string]float64)

	// Movement factor
	if sample.MovementSpeed > 15 {
		factors["high_speed_movement"] = 0.8
	} else if sample.MovementSpeed > 5 {
		factors["movement"] = 0.6
	}

	// Elevation factor
	if sample.Elevation < 20 {
		factors["very_low_elevation"] = 0.9
	} else if sample.Elevation < 35 {
		factors["low_elevation"] = 0.7
	}

	// Signal quality factor
	if sample.SNR < 3 {
		factors["very_poor_signal"] = 0.8
	} else if sample.SNR < 6 {
		factors["poor_signal"] = 0.6
	}

	// Weather factor (if weather code available)
	if sample.WeatherCode != "" {
		switch sample.WeatherCode {
		case "rain", "snow", "storm":
			factors["severe_weather"] = 0.9
		case "clouds", "overcast":
			factors["weather"] = 0.5
		}
	}

	// Obstruction level factor
	if sample.ObstructionPct > 75 {
		factors["severe_obstruction"] = 0.8
	} else if sample.ObstructionPct > 50 {
		factors["major_obstruction"] = 0.7
	}

	// Find the highest scoring factor
	if len(factors) == 0 {
		return "environmental"
	}

	var bestFactor string
	var bestScore float64

	for factor, score := range factors {
		if score > bestScore {
			bestScore = score
			bestFactor = factor
		}
	}

	return bestFactor
}

func (o *ObstructionManager) generateRecommendations(analysis *ObstructionAnalysis) []string {
	var recommendations []string

	if analysis.CurrentState != nil {
		switch analysis.CurrentState.Severity {
		case "critical":
			recommendations = append(recommendations, "Consider immediate failover to backup connection")
			recommendations = append(recommendations, "Check for physical obstructions blocking dish view")
		case "high":
			recommendations = append(recommendations, "Monitor closely for failover opportunity")
			recommendations = append(recommendations, "Verify dish pointing and snow/ice accumulation")
		case "medium":
			recommendations = append(recommendations, "Normal monitoring sufficient")
		}
	}

	return recommendations
}

func (o *ObstructionManager) calculateOverallConfidence(analysis *ObstructionAnalysis) float64 {
	confidence := 0.8

	if analysis.LocationProfile != nil {
		confidence *= analysis.LocationProfile.Reliability
	}

	return confidence
}

func (o *ObstructionManager) calculatePredictionConfidence(targetTime time.Time, lat, lon float64) float64 {
	confidence := 1.0

	// Reduce confidence based on time distance into future
	timeDiff := time.Until(targetTime)
	if timeDiff > 6*time.Hour {
		confidence *= 0.3
	} else if timeDiff > 3*time.Hour {
		confidence *= 0.5
	} else if timeDiff > 1*time.Hour {
		confidence *= 0.7
	}

	// Increase confidence if we have location-specific data
	locationSamples := o.getSamplesNearLocation(lat, lon, 0.01)
	if len(locationSamples) > 50 {
		confidence *= 1.2
	} else if len(locationSamples) > 20 {
		confidence *= 1.1
	} else if len(locationSamples) < 5 {
		confidence *= 0.6
	}

	// Reduce confidence if we have limited overall data
	if len(o.history) < 100 {
		confidence *= 0.6
	} else if len(o.history) < 500 {
		confidence *= 0.8
	}

	// Cap at 1.0
	return math.Min(1.0, confidence)
}

func (o *ObstructionManager) estimateDuration(predictionPct float64, severity string) time.Duration {
	// Estimate based on severity
	switch severity {
	case "critical":
		return 30 * time.Minute
	case "high":
		return 15 * time.Minute
	case "medium":
		return 5 * time.Minute
	default:
		return 2 * time.Minute
	}
}

func (o *ObstructionManager) generateActionRecommendation(pred *ObstructionPrediction) string {
	switch pred.Severity {
	case "critical":
		return "Prepare for immediate failover"
	case "high":
		return "Consider proactive failover"
	case "medium":
		return "Monitor and prepare backup"
	default:
		return "No action needed"
	}
}

func (o *ObstructionManager) identifyContributingFactors(targetTime time.Time, lat, lon float64) []string {
	return []string{"temporal_pattern", "location_profile"}
}

// Placeholder implementations for complex analysis methods
func (o *ObstructionManager) analyzeDirections(samples []ObstructionSample) []DirectionStat {
	directionMap := make(map[int]*DirectionStat) // Group by azimuth in 30-degree buckets

	for _, sample := range samples {
		bucket := int(sample.Azimuth/30) * 30 // Round to nearest 30-degree bucket

		if stat, exists := directionMap[bucket]; exists {
			stat.ObstructionPct = (stat.ObstructionPct*float64(stat.Frequency) + sample.ObstructionPct) / float64(stat.Frequency+1)
			stat.Frequency++
		} else {
			directionMap[bucket] = &DirectionStat{
				Azimuth:        float64(bucket),
				Elevation:      sample.Elevation,
				ObstructionPct: sample.ObstructionPct,
				Frequency:      1,
			}
		}
	}

	var stats []DirectionStat
	for _, stat := range directionMap {
		if stat.Frequency >= 3 { // Only include directions with enough samples
			stats = append(stats, *stat)
		}
	}

	return stats
}

func (o *ObstructionManager) analyzeTimePatterns(samples []ObstructionSample) map[string]float64 {
	hourlyStats := make(map[int][]float64)

	// Group samples by hour of day
	for _, sample := range samples {
		hour := sample.Timestamp.Hour()
		hourlyStats[hour] = append(hourlyStats[hour], sample.ObstructionPct)
	}

	patterns := make(map[string]float64)
	for hour, values := range hourlyStats {
		if len(values) >= 5 { // Need minimum samples
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))
			patterns[fmt.Sprintf("%02d:00", hour)] = avg
		}
	}

	return patterns
}

func (o *ObstructionManager) analyzeSeasonalTrends(samples []ObstructionSample) map[string]float64 {
	monthlyStats := make(map[time.Month][]float64)

	// Group samples by month
	for _, sample := range samples {
		month := sample.Timestamp.Month()
		monthlyStats[month] = append(monthlyStats[month], sample.ObstructionPct)
	}

	trends := make(map[string]float64)
	for month, values := range monthlyStats {
		if len(values) >= 10 { // Need sufficient samples
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))
			trends[month.String()] = avg
		}
	}

	return trends
}

func (o *ObstructionManager) analyzeDailyPatterns() []TimePattern {
	if len(o.history) < 50 {
		return nil
	}

	hourlyData := make(map[int][]float64)

	// Group by hour of day
	for _, sample := range o.history {
		hour := sample.Timestamp.Hour()
		hourlyData[hour] = append(hourlyData[hour], sample.ObstructionPct)
	}

	var patterns []TimePattern
	for hour, values := range hourlyData {
		if len(values) >= 5 {
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))

			// Only include significant patterns (deviation from overall average)
			if avg > 15.0 || avg < 5.0 {
				patterns = append(patterns, TimePattern{
					StartTime:      fmt.Sprintf("%02d:00", hour),
					EndTime:        fmt.Sprintf("%02d:59", hour),
					AvgObstruction: avg,
					Frequency:      len(values),
					Confidence:     math.Min(1.0, float64(len(values))/20.0),
				})
			}
		}
	}

	return patterns
}

func (o *ObstructionManager) analyzeWeatherPatterns() []WeatherPattern {
	weatherMap := make(map[string][]float64)

	// Group by weather code
	for _, sample := range o.history {
		if sample.WeatherCode != "" {
			weatherMap[sample.WeatherCode] = append(weatherMap[sample.WeatherCode], sample.ObstructionPct)
		}
	}

	var patterns []WeatherPattern
	for weatherType, values := range weatherMap {
		if len(values) >= 5 {
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))

			// Calculate impact factor (relative to clear weather baseline)
			impactFactor := avg / 10.0 // Assume 10% is baseline

			patterns = append(patterns, WeatherPattern{
				WeatherType:     weatherType,
				ImpactFactor:    impactFactor,
				TypicalDuration: 30 * time.Minute, // Estimate
				Confidence:      math.Min(1.0, float64(len(values))/20.0),
			})
		}
	}

	return patterns
}

func (o *ObstructionManager) analyzeMovementPatterns() []MovementPattern {
	speedRanges := map[string][2]float64{
		"stationary": {0, 1},
		"walking":    {1, 5},
		"driving":    {5, 25},
		"highway":    {25, 100},
	}

	movementData := make(map[string][]float64)

	// Categorize samples by movement speed
	for _, sample := range o.history {
		for movementType, speedRange := range speedRanges {
			if sample.MovementSpeed >= speedRange[0] && sample.MovementSpeed < speedRange[1] {
				movementData[movementType] = append(movementData[movementType], sample.ObstructionPct)
				break
			}
		}
	}

	var patterns []MovementPattern
	for movementType, values := range movementData {
		if len(values) >= 5 {
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))

			speedRange := speedRanges[movementType]
			patterns = append(patterns, MovementPattern{
				MovementType: movementType,
				SpeedRange:   fmt.Sprintf("%.1f-%.1f m/s", speedRange[0], speedRange[1]),
				ImpactFactor: avg / 10.0, // Relative to 10% baseline
				Confidence:   math.Min(1.0, float64(len(values))/20.0),
			})
		}
	}

	return patterns
}

func (o *ObstructionManager) analyzeSeasonalFactors() map[string]float64 {
	seasonalData := make(map[string][]float64)

	for _, sample := range o.history {
		month := sample.Timestamp.Month()
		var season string

		switch {
		case month >= 3 && month <= 5:
			season = "spring"
		case month >= 6 && month <= 8:
			season = "summer"
		case month >= 9 && month <= 11:
			season = "fall"
		default:
			season = "winter"
		}

		seasonalData[season] = append(seasonalData[season], sample.ObstructionPct)
	}

	factors := make(map[string]float64)
	for season, values := range seasonalData {
		if len(values) >= 10 {
			var total float64
			for _, val := range values {
				total += val
			}
			avg := total / float64(len(values))
			factors[season] = avg
		}
	}

	return factors
}

// updateModels updates the internal prediction models based on collected data
func (o *ObstructionManager) updateModels() {
	// Update models based on recent data patterns
	if len(o.history) > 100 { // Only update with sufficient data
		// Update temporal prediction model
		if model, exists := o.models["temporal"]; exists {
			model.SampleCount = len(o.history)
			model.LastTrained = time.Now()
			
			// Calculate recent accuracy based on predictions vs actual results
			// This is a simplified accuracy calculation
			recentSamples := o.history
			if len(recentSamples) > 50 {
				recentSamples = o.history[len(o.history)-50:] // Last 50 samples
			}
			
			// Simple accuracy metric: how often trend predictions were correct
			correctPredictions := 0
			for i := 1; i < len(recentSamples); i++ {
				current := recentSamples[i].ObstructionPct
				previous := recentSamples[i-1].ObstructionPct
				
				// Check if trend direction was correct
				if (current > previous && recentSamples[i].ObstructionRate > 0) ||
				   (current < previous && recentSamples[i].ObstructionRate < 0) ||
				   (math.Abs(current-previous) < 0.5 && math.Abs(recentSamples[i].ObstructionRate) < 0.1) {
					correctPredictions++
				}
			}
			
			if len(recentSamples) > 1 {
				model.Accuracy = float64(correctPredictions) / float64(len(recentSamples)-1)
			}
			
			// Update model parameters based on recent patterns
			if model.Parameters == nil {
				model.Parameters = make(map[string]interface{})
			}
			model.Parameters["last_update"] = time.Now()
			model.Parameters["sample_count"] = len(o.history)
		}
	}
	
	// Update spatial prediction models if location data is available
	if len(o.history) > 0 {
		lastSample := o.history[len(o.history)-1]
		if lastSample.Latitude != 0 && lastSample.Longitude != 0 {
			if model, exists := o.models["spatial"]; exists {
				model.LastTrained = time.Now()
				model.SampleCount = len(o.history)
			}
		}
	}
}
