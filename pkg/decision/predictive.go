package decision

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sync"
	"time"

	"github.com/sajari/regression"
	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
)

// PredictiveEngine implements advanced predictive failover algorithms
type PredictiveEngine struct {
	mu sync.RWMutex

	// Configuration
	config *PredictiveConfig

	// Dependencies
	logger *logx.Logger

	// State
	models          map[string]*PredictiveModel
	trends          map[string]*TrendAnalysis
	patterns        map[string]*Pattern
	mlPredictor     *MLPredictor
	anomalyDetector *AnomalyDetector

	// Historical data
	historicalData map[string][]DataPoint
	maxDataPoints  int
}

// PredictiveConfig represents predictive engine configuration
type PredictiveConfig struct {
	Enabled             bool          `json:"enabled"`
	LookbackWindow      time.Duration `json:"lookback_window"`
	PredictionHorizon   time.Duration `json:"prediction_horizon"`
	ConfidenceThreshold float64       `json:"confidence_threshold"`
	AnomalyThreshold    float64       `json:"anomaly_threshold"`
	TrendSensitivity    float64       `json:"trend_sensitivity"`
	PatternMinSamples   int           `json:"pattern_min_samples"`
	MLEnabled           bool          `json:"ml_enabled"`
	MLModelPath         string        `json:"ml_model_path"`
}

// AnomalyDetector detects anomalies in member behavior
type AnomalyDetector struct {
	mu sync.RWMutex

	// Statistical models
	baselineStats map[string]*BaselineStats
	anomalyScores map[string][]float64

	// Configuration
	windowSize  int
	sensitivity float64
	updateRate  float64
}

// BaselineStats represents baseline statistics for anomaly detection
type BaselineStats struct {
	MeanLatency float64
	StdLatency  float64
	MeanLoss    float64
	StdLoss     float64
	MeanJitter  float64
	StdJitter   float64
	MeanScore   float64
	StdScore    float64
	LastUpdate  time.Time
	SampleCount int
}

// MLPredictor implements machine learning-based prediction
type MLPredictor struct {
	mu sync.RWMutex

	// Model state
	models  map[string]*MLModel
	trained bool

	// Configuration
	modelType   string
	features    []string
	hyperparams map[string]interface{}

	// Persistence
	modelPath string
	logger    *logx.Logger
}

// MLModel represents a machine learning model
type MLModel struct {
	MemberName   string
	ModelType    string
	Features     []string
	Weights      []float64
	Bias         float64
	Accuracy     float64
	LastTrained  time.Time
	TrainingData []TrainingSample
}

// TrainingSample represents a training sample for ML
type TrainingSample struct {
	Features  []float64
	Target    float64
	Weight    float64
	Timestamp time.Time
}

// NewPredictiveEngine creates a new predictive engine
func NewPredictiveEngine(config *PredictiveConfig, logger *logx.Logger) *PredictiveEngine {
	engine := &PredictiveEngine{
		config:         config,
		logger:         logger,
		models:         make(map[string]*PredictiveModel),
		trends:         make(map[string]*TrendAnalysis),
		patterns:       make(map[string]*Pattern),
		historicalData: make(map[string][]DataPoint),
		maxDataPoints:  1000,
	}

	if config.MLEnabled {
		engine.mlPredictor = NewMLPredictor(config.MLModelPath, logger)
	}

	engine.anomalyDetector = NewAnomalyDetector(config.AnomalyThreshold, logger)

	return engine
}

// UpdateMemberData updates historical data for a member
func (pe *PredictiveEngine) UpdateMemberData(memberName string, metrics *pkg.Metrics, score *pkg.Score) {
	pe.mu.Lock()
	defer pe.mu.Unlock()

	// Create data point
	dp := DataPoint{
		Timestamp: time.Now(),
		Latency:   metrics.LatencyMS,
		Loss:      metrics.LossPercent,
		Score:     score.Final,
		Status:    "healthy", // TODO: determine actual status
	}

	// Add to historical data
	if pe.historicalData[memberName] == nil {
		pe.historicalData[memberName] = make([]DataPoint, 0)
	}

	pe.historicalData[memberName] = append(pe.historicalData[memberName], dp)

	// Trim old data
	if len(pe.historicalData[memberName]) > pe.maxDataPoints {
		pe.historicalData[memberName] = pe.historicalData[memberName][len(pe.historicalData[memberName])-pe.maxDataPoints:]
	}

	// Update models
	pe.updateModels(memberName, dp)
}

// PredictFailure predicts the likelihood of failure for a member
func (pe *PredictiveEngine) PredictFailure(memberName string) (*FailurePrediction, error) {
	pe.mu.RLock()
	defer pe.mu.RUnlock()

	if !pe.config.Enabled {
		return &FailurePrediction{
			Risk:       0.0,
			Confidence: 0.0,
			Horizon:    pe.config.PredictionHorizon,
		}, nil
	}

	// Get historical data
	data, exists := pe.historicalData[memberName]
	if !exists || len(data) < pe.config.PatternMinSamples {
		return &FailurePrediction{
			Risk:       0.0,
			Confidence: 0.0,
			Horizon:    pe.config.PredictionHorizon,
		}, nil
	}

	// Calculate multiple prediction methods
	predictions := make([]*FailurePrediction, 0)

	// 1. Trend-based prediction
	if trendPred := pe.predictFromTrend(memberName, data); trendPred != nil {
		predictions = append(predictions, trendPred)
	}

	// 2. Pattern-based prediction
	if patternPred := pe.predictFromPattern(memberName, data); patternPred != nil {
		predictions = append(predictions, patternPred)
	}

	// 3. Anomaly-based prediction
	if anomalyPred := pe.predictFromAnomaly(memberName, data); anomalyPred != nil {
		predictions = append(predictions, anomalyPred)
	}

	// 4. ML-based prediction
	if pe.config.MLEnabled && pe.mlPredictor != nil {
		if mlPred := pe.predictFromML(memberName, data); mlPred != nil {
			predictions = append(predictions, mlPred)
		}
	}

	// Combine predictions using ensemble method
	return pe.combinePredictions(predictions), nil
}

// predictFromTrend predicts failure based on trend analysis
func (pe *PredictiveEngine) predictFromTrend(memberName string, data []DataPoint) *FailurePrediction {
	if len(data) < 10 {
		return nil
	}

	// Calculate trend for different metrics
	latencyTrend := pe.calculateTrend(data, func(dp DataPoint) float64 { return dp.Latency })
	lossTrend := pe.calculateTrend(data, func(dp DataPoint) float64 { return dp.Loss })
	scoreTrend := pe.calculateTrend(data, func(dp DataPoint) float64 { return dp.Score })

	// Determine risk based on trends
	risk := 0.0
	confidence := 0.0

	// Latency trend analysis
	if latencyTrend > pe.config.TrendSensitivity {
		risk += 0.3
		confidence += 0.2
	}

	// Loss trend analysis
	if lossTrend > pe.config.TrendSensitivity {
		risk += 0.4
		confidence += 0.3
	}

	// Score trend analysis
	if scoreTrend < -pe.config.TrendSensitivity {
		risk += 0.3
		confidence += 0.2
	}

	// Normalize risk and confidence
	risk = math.Min(risk, 1.0)
	confidence = math.Min(confidence, 1.0)

	return &FailurePrediction{
		Risk:       risk,
		Confidence: confidence,
		Method:     "trend",
		Horizon:    pe.config.PredictionHorizon,
		Details: map[string]interface{}{
			"latency_trend": latencyTrend,
			"loss_trend":    lossTrend,
			"score_trend":   scoreTrend,
		},
	}
}

// predictFromPattern predicts failure based on pattern detection
func (pe *PredictiveEngine) predictFromPattern(memberName string, data []DataPoint) *FailurePrediction {
	pattern, exists := pe.patterns[memberName]
	if !exists {
		return nil
	}

	// Check if current behavior matches known failure patterns
	patternMatch := pe.calculatePatternMatch(data, pattern)

	if patternMatch > 0.7 {
		return &FailurePrediction{
			Risk:       patternMatch,
			Confidence: pattern.Confidence,
			Method:     "pattern",
			Horizon:    pe.config.PredictionHorizon,
			Details: map[string]interface{}{
				"pattern_type":  pattern.Type,
				"pattern_match": patternMatch,
			},
		}
	}

	return nil
}

// predictFromAnomaly predicts failure based on anomaly detection
func (pe *PredictiveEngine) predictFromAnomaly(memberName string, data []DataPoint) *FailurePrediction {
	if len(data) < 5 {
		return nil
	}

	// Get recent data points
	recentData := data[len(data)-5:]

	// Calculate anomaly scores
	anomalyScores := make([]float64, len(recentData))
	for i, dp := range recentData {
		anomalyScores[i] = pe.anomalyDetector.CalculateAnomalyScore(memberName, dp)
	}

	// Calculate average anomaly score
	avgAnomaly := 0.0
	for _, score := range anomalyScores {
		avgAnomaly += score
	}
	avgAnomaly /= float64(len(anomalyScores))

	// Determine risk based on anomaly score
	risk := math.Min(avgAnomaly, 1.0)
	confidence := math.Min(avgAnomaly*0.8, 1.0)

	if risk > pe.config.AnomalyThreshold {
		return &FailurePrediction{
			Risk:       risk,
			Confidence: confidence,
			Method:     "anomaly",
			Horizon:    pe.config.PredictionHorizon,
			Details: map[string]interface{}{
				"anomaly_score": avgAnomaly,
				"threshold":     pe.config.AnomalyThreshold,
			},
		}
	}

	return nil
}

// predictFromML predicts failure using machine learning
func (pe *PredictiveEngine) predictFromML(memberName string, data []DataPoint) *FailurePrediction {
	if pe.mlPredictor == nil || !pe.mlPredictor.IsTrained(memberName) {
		return nil
	}

	// Prepare features from recent data
	features := pe.extractFeatures(data)

	// Make prediction
	prediction, confidence, err := pe.mlPredictor.Predict(memberName, features)
	if err != nil {
		pe.logger.Error("ML prediction failed", "member", memberName, "error", err)
		return nil
	}

	return &FailurePrediction{
		Risk:       prediction,
		Confidence: confidence,
		Method:     "ml",
		Horizon:    pe.config.PredictionHorizon,
		Details: map[string]interface{}{
			"ml_model": pe.mlPredictor.GetModelType(memberName),
			"features": len(features),
		},
	}
}

// combinePredictions combines multiple predictions using ensemble method
func (pe *PredictiveEngine) combinePredictions(predictions []*FailurePrediction) *FailurePrediction {
	if len(predictions) == 0 {
		return &FailurePrediction{
			Risk:       0.0,
			Confidence: 0.0,
			Horizon:    pe.config.PredictionHorizon,
		}
	}

	if len(predictions) == 1 {
		return predictions[0]
	}

	// Weighted average based on confidence
	totalWeight := 0.0
	weightedRisk := 0.0
	weightedConfidence := 0.0

	for _, pred := range predictions {
		weight := pred.Confidence
		totalWeight += weight
		weightedRisk += pred.Risk * weight
		weightedConfidence += pred.Confidence * weight
	}

	if totalWeight == 0 {
		return &FailurePrediction{
			Risk:       0.0,
			Confidence: 0.0,
			Horizon:    pe.config.PredictionHorizon,
		}
	}

	return &FailurePrediction{
		Risk:       weightedRisk / totalWeight,
		Confidence: weightedConfidence / totalWeight,
		Method:     "ensemble",
		Horizon:    pe.config.PredictionHorizon,
		Details: map[string]interface{}{
			"num_predictions": len(predictions),
			"methods":         pe.getPredictionMethods(predictions),
		},
	}
}

// calculateTrend calculates the trend of a metric over time
func (pe *PredictiveEngine) calculateTrend(data []DataPoint, extractor func(DataPoint) float64) float64 {
	if len(data) < 2 {
		return 0.0
	}

	// Use linear regression to calculate trend
	x := make([]float64, len(data))
	y := make([]float64, len(data))

	for i, dp := range data {
		x[i] = float64(dp.Timestamp.Unix())
		y[i] = extractor(dp)
	}

	// Calculate linear regression
	n := float64(len(x))
	sumX := 0.0
	sumY := 0.0
	sumXY := 0.0
	sumX2 := 0.0

	for i := 0; i < len(x); i++ {
		sumX += x[i]
		sumY += y[i]
		sumXY += x[i] * y[i]
		sumX2 += x[i] * x[i]
	}

	slope := (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)

	// Normalize slope to per-minute change
	return slope / 60.0
}

// calculatePatternMatch calculates how well current data matches a pattern
func (pe *PredictiveEngine) calculatePatternMatch(data []DataPoint, pattern *Pattern) float64 {
	// Simplified pattern matching
	// In a full implementation, this would use more sophisticated algorithms

	if len(data) < 5 {
		return 0.0
	}

	// Calculate similarity based on recent data
	_ = data[len(data)-5:] // recentData - placeholder for future enhancement

	// For now, return a simple similarity score
	// This could be enhanced with DTW, correlation analysis, etc.
	return 0.5 // Placeholder
}

// extractFeatures extracts features from data for ML prediction
func (pe *PredictiveEngine) extractFeatures(data []DataPoint) []float64 {
	if len(data) < 10 {
		return make([]float64, 10) // Return zero features if insufficient data
	}

	features := make([]float64, 0)

	// Recent metrics
	recent := data[len(data)-1]
	features = append(features, recent.Latency, recent.Loss, recent.Score)

	// Statistical features from recent window
	window := data[len(data)-10:]

	// Mean values
	meanLatency := 0.0
	meanLoss := 0.0
	meanScore := 0.0

	for _, dp := range window {
		meanLatency += dp.Latency
		meanLoss += dp.Loss
		meanScore += dp.Score
	}

	features = append(features, meanLatency/10.0, meanLoss/10.0, meanScore/10.0)

	// Trend features
	latencyTrend := pe.calculateTrend(window, func(dp DataPoint) float64 { return dp.Latency })
	lossTrend := pe.calculateTrend(window, func(dp DataPoint) float64 { return dp.Loss })
	scoreTrend := pe.calculateTrend(window, func(dp DataPoint) float64 { return dp.Score })

	features = append(features, latencyTrend, lossTrend, scoreTrend)

	// Volatility features
	latencyStd := pe.calculateStd(window, func(dp DataPoint) float64 { return dp.Latency })
	features = append(features, latencyStd)

	return features
}

// calculateStd calculates standard deviation
func (pe *PredictiveEngine) calculateStd(data []DataPoint, extractor func(DataPoint) float64) float64 {
	if len(data) < 2 {
		return 0.0
	}

	// Calculate mean
	mean := 0.0
	for _, dp := range data {
		mean += extractor(dp)
	}
	mean /= float64(len(data))

	// Calculate variance
	variance := 0.0
	for _, dp := range data {
		diff := extractor(dp) - mean
		variance += diff * diff
	}
	variance /= float64(len(data))

	return math.Sqrt(variance)
}

// updateModels updates predictive models with new data
func (pe *PredictiveEngine) updateModels(memberName string, dp DataPoint) {
	// Update trend analysis
	if pe.trends[memberName] == nil {
		pe.trends[memberName] = &TrendAnalysis{
			MemberName:     memberName,
			LastCalculated: time.Now(),
			Window:         pe.config.LookbackWindow,
		}
	}

	// Update pattern detection
	pe.updatePatterns(memberName, dp)

	// Update ML model if enabled
	if pe.config.MLEnabled && pe.mlPredictor != nil {
		pe.mlPredictor.UpdateModel(memberName, dp)
	}

	// Update anomaly detector
	pe.anomalyDetector.UpdateBaseline(memberName, dp)
}

// updatePatterns updates pattern detection
func (pe *PredictiveEngine) updatePatterns(memberName string, dp DataPoint) {
	// Simplified pattern detection
	// In a full implementation, this would use more sophisticated algorithms

	data := pe.historicalData[memberName]
	if len(data) < 20 {
		return
	}

	// Detect cyclic patterns
	if pe.detectCyclicPattern(data) {
		pe.patterns[memberName] = &Pattern{
			ID:          fmt.Sprintf("%s_cyclic_%d", memberName, time.Now().Unix()),
			MemberName:  memberName,
			Type:        "cyclic",
			Confidence:  0.7,
			StartTime:   time.Now().Add(-pe.config.LookbackWindow),
			EndTime:     time.Now(),
			Description: "Detected cyclic behavior pattern",
		}
	}

	// Detect deteriorating patterns
	if pe.detectDeterioratingPattern(data) {
		pe.patterns[memberName] = &Pattern{
			ID:          fmt.Sprintf("%s_deteriorating_%d", memberName, time.Now().Unix()),
			MemberName:  memberName,
			Type:        "deteriorating",
			Confidence:  0.8,
			StartTime:   time.Now().Add(-pe.config.LookbackWindow),
			EndTime:     time.Now(),
			Description: "Detected deteriorating performance pattern",
		}
	}
}

// detectCyclicPattern detects cyclic patterns in data
func (pe *PredictiveEngine) detectCyclicPattern(data []DataPoint) bool {
	// Simplified cyclic pattern detection
	// In a full implementation, this would use FFT or autocorrelation

	if len(data) < 20 {
		return false
	}

	// Check for periodic variations in latency
	latencies := make([]float64, len(data))
	for i, dp := range data {
		latencies[i] = dp.Latency
	}

	// Simple periodicity check
	// This is a placeholder - real implementation would be more sophisticated
	return false
}

// detectDeterioratingPattern detects deteriorating performance patterns
func (pe *PredictiveEngine) detectDeterioratingPattern(data []DataPoint) bool {
	if len(data) < 10 {
		return false
	}

	// Check if recent scores are consistently lower than earlier scores
	recentScores := data[len(data)-5:]
	earlierScores := data[len(data)-10 : len(data)-5]

	recentAvg := 0.0
	earlierAvg := 0.0

	for _, dp := range recentScores {
		recentAvg += dp.Score
	}
	recentAvg /= float64(len(recentScores))

	for _, dp := range earlierScores {
		earlierAvg += dp.Score
	}
	earlierAvg /= float64(len(earlierScores))

	// Check if recent average is significantly lower
	return (earlierAvg - recentAvg) > 10.0
}

// getPredictionMethods returns the methods used in predictions
func (pe *PredictiveEngine) getPredictionMethods(predictions []*FailurePrediction) []string {
	methods := make([]string, len(predictions))
	for i, pred := range predictions {
		methods[i] = pred.Method
	}
	return methods
}

// FailurePrediction represents a failure prediction
type FailurePrediction struct {
	Risk       float64                `json:"risk"`
	Confidence float64                `json:"confidence"`
	Method     string                 `json:"method"`
	Horizon    time.Duration          `json:"horizon"`
	Details    map[string]interface{} `json:"details,omitempty"`
}

// NewAnomalyDetector creates a new anomaly detector
func NewAnomalyDetector(sensitivity float64, logger *logx.Logger) *AnomalyDetector {
	return &AnomalyDetector{
		baselineStats: make(map[string]*BaselineStats),
		anomalyScores: make(map[string][]float64),
		windowSize:    100,
		sensitivity:   sensitivity,
		updateRate:    0.1,
	}
}

// CalculateAnomalyScore calculates the anomaly score for a data point
func (ad *AnomalyDetector) CalculateAnomalyScore(memberName string, dp DataPoint) float64 {
	ad.mu.RLock()
	baseline, exists := ad.baselineStats[memberName]
	ad.mu.RUnlock()

	if !exists {
		return 0.0
	}

	// Calculate z-scores for different metrics
	latencyZ := math.Abs((dp.Latency - baseline.MeanLatency) / baseline.StdLatency)
	lossZ := math.Abs((dp.Loss - baseline.MeanLoss) / baseline.StdLoss)
	scoreZ := math.Abs((dp.Score - baseline.MeanScore) / baseline.StdScore)

	// Combine z-scores (weighted average)
	anomalyScore := (latencyZ*0.4 + lossZ*0.4 + scoreZ*0.2) / 3.0

	// Normalize to 0-1 range
	return math.Min(anomalyScore, 1.0)
}

// UpdateBaseline updates the baseline statistics
func (ad *AnomalyDetector) UpdateBaseline(memberName string, dp DataPoint) {
	ad.mu.Lock()
	defer ad.mu.Unlock()

	baseline, exists := ad.baselineStats[memberName]
	if !exists {
		baseline = &BaselineStats{
			MeanLatency: dp.Latency,
			MeanLoss:    dp.Loss,
			MeanJitter:  0.0, // Would need jitter data
			MeanScore:   dp.Score,
			LastUpdate:  time.Now(),
			SampleCount: 1,
		}
		ad.baselineStats[memberName] = baseline
		return
	}

	// Update running statistics
	baseline.SampleCount++
	_ = float64(baseline.SampleCount) // n - placeholder for future use

	// Update means using exponential moving average
	baseline.MeanLatency = baseline.MeanLatency*(1-ad.updateRate) + dp.Latency*ad.updateRate
	baseline.MeanLoss = baseline.MeanLoss*(1-ad.updateRate) + dp.Loss*ad.updateRate
	baseline.MeanScore = baseline.MeanScore*(1-ad.updateRate) + dp.Score*ad.updateRate

	// Update standard deviations (simplified)
	// In a full implementation, this would use proper variance calculation
	baseline.StdLatency = baseline.StdLatency * 0.9
	baseline.StdLoss = baseline.StdLoss * 0.9
	baseline.StdScore = baseline.StdScore * 0.9

	baseline.LastUpdate = time.Now()
}

// NewMLPredictor creates a new ML predictor
func NewMLPredictor(modelPath string, logger *logx.Logger) *MLPredictor {
	mlp := &MLPredictor{
		models:      make(map[string]*MLModel),
		trained:     false,
		modelType:   "linear",
		features:    []string{"latency", "loss", "score", "trend"},
		hyperparams: make(map[string]interface{}),
		modelPath:   modelPath,
		logger:      logger,
	}

	if modelPath != "" {
		if err := mlp.loadModels(); err != nil {
			logger.Warn(fmt.Sprintf("failed to load ML models: %v", err))
		}
	}

	return mlp
}

// IsTrained checks if a model is trained for a member
func (mlp *MLPredictor) IsTrained(memberName string) bool {
	mlp.mu.RLock()
	defer mlp.mu.RUnlock()

	model, exists := mlp.models[memberName]
	return exists && model.LastTrained.After(time.Now().Add(-24*time.Hour))
}

// Predict makes a prediction using ML
func (mlp *MLPredictor) Predict(memberName string, features []float64) (float64, float64, error) {
	mlp.mu.RLock()
	model, exists := mlp.models[memberName]
	mlp.mu.RUnlock()

	if !exists {
		return 0.0, 0.0, fmt.Errorf("no model found for member %s", memberName)
	}

	// Simple linear prediction
	if len(features) != len(model.Weights) {
		return 0.0, 0.0, fmt.Errorf("feature count mismatch")
	}

	prediction := model.Bias
	for i, feature := range features {
		prediction += feature * model.Weights[i]
	}

	// Normalize prediction to 0-1 range
	prediction = math.Max(0.0, math.Min(1.0, prediction))

	return prediction, model.Accuracy, nil
}

// UpdateModel updates the ML model with new data
func (mlp *MLPredictor) UpdateModel(memberName string, dp DataPoint) {
	// Simplified model update
	// In a full implementation, this would use proper ML training algorithms

	mlp.mu.Lock()
	defer mlp.mu.Unlock()

	model, exists := mlp.models[memberName]
	if !exists {
		model = &MLModel{
			MemberName:   memberName,
			ModelType:    mlp.modelType,
			Features:     mlp.features,
			Weights:      make([]float64, len(mlp.features)),
			Bias:         0.0,
			Accuracy:     0.5,
			LastTrained:  time.Now(),
			TrainingData: make([]TrainingSample, 0),
		}
		mlp.models[memberName] = model
	}

	// Add training sample with simple failure label based on score
	target := 0.0
	if dp.Score < 50 {
		target = 1.0
	}
	sample := TrainingSample{
		Features:  []float64{dp.Latency, dp.Loss, dp.Score, 0.0},
		Target:    target,
		Weight:    1.0,
		Timestamp: dp.Timestamp,
	}

	model.TrainingData = append(model.TrainingData, sample)

	// Retrain model periodically
	if len(model.TrainingData) >= 20 {
		mlp.retrainModel(model)
		model.TrainingData = model.TrainingData[:0]
	}
}

// retrainModel retrains the ML model
func (mlp *MLPredictor) retrainModel(model *MLModel) {
	// Retrain using linear regression on collected samples
	var r regression.Regression
	r.SetObserved("failure")
	for i, name := range model.Features {
		r.SetVar(i, name)
	}

	// Train regression with collected samples
	for _, sample := range model.TrainingData {
		r.Train(regression.DataPoint(sample.Target, sample.Features))
	}

	if err := r.Run(); err != nil {
		mlp.logger.Warn(fmt.Sprintf("model training failed for %s: %v", model.MemberName, err))
		return
	}

	coeffs := r.GetCoeffs()
	if len(coeffs) > 0 {
		model.Bias = coeffs[0]
		model.Weights = coeffs[1:]
	}

	model.Accuracy = r.R2
	model.LastTrained = time.Now()
	mlp.trained = true

	if err := mlp.saveModels(); err != nil {
		mlp.logger.Warn(fmt.Sprintf("failed to save ML models: %v", err))
	}
}

// GetModelType returns the model type for a member
func (mlp *MLPredictor) GetModelType(memberName string) string {
	mlp.mu.RLock()
	defer mlp.mu.RUnlock()

	if model, exists := mlp.models[memberName]; exists {
		return model.ModelType
	}
	return "unknown"
}

// loadModels loads model definitions from disk
func (mlp *MLPredictor) loadModels() error {
	data, err := os.ReadFile(mlp.modelPath)
	if err != nil {
		return err
	}

	var stored []*MLModel
	if err := json.Unmarshal(data, &stored); err != nil {
		return err
	}

	mlp.mu.Lock()
	defer mlp.mu.Unlock()
	for _, m := range stored {
		mlp.models[m.MemberName] = m
	}
	mlp.trained = len(stored) > 0
	return nil
}

// saveModels persists model definitions to disk
func (mlp *MLPredictor) saveModels() error {
	if mlp.modelPath == "" {
		return nil
	}

	mlp.mu.RLock()
	defer mlp.mu.RUnlock()
	models := make([]*MLModel, 0, len(mlp.models))
	for _, m := range mlp.models {
		models = append(models, m)
	}
	data, err := json.MarshalIndent(models, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(mlp.modelPath, data, 0o644)
}
