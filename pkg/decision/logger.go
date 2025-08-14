package decision

import (
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/logx"
)

// DecisionLogger logs all decision evaluations to CSV files
type DecisionLogger struct {
	mu sync.RWMutex

	// Configuration
	enabled   bool
	outputDir string
	maxSizeMB int
	retention time.Duration

	// Dependencies
	logger *logx.Logger

	// State
	currentFile *os.File
	csvWriter   *csv.Writer
	currentSize int64
	startTime   time.Time
}

// DecisionLogEntry represents a single decision log entry
type DecisionLogEntry struct {
	Timestamp     time.Time `csv:"timestamp"`
	DecisionID    string    `csv:"decision_id"`
	Type          string    `csv:"type"` // evaluation|soft_failover|hard_failover|restore|maintenance
	CurrentMember string    `csv:"current_member"`
	TargetMember  string    `csv:"target_member"`
	Action        string    `csv:"action"` // switch|stay|wait
	Reason        string    `csv:"reason"`
	TriggerReason string    `csv:"trigger_reason"` // predictive|threshold|manual|scheduled

	// Scoring Details
	CurrentScore float64 `csv:"current_score"`
	TargetScore  float64 `csv:"target_score"`
	ScoreDelta   float64 `csv:"score_delta"`
	SwitchMargin float64 `csv:"switch_margin"`

	// Quality Factors
	LatencyFactor float64 `csv:"latency_factor"`
	LossFactor    float64 `csv:"loss_factor"`
	JitterFactor  float64 `csv:"jitter_factor"`
	SignalFactor  float64 `csv:"signal_factor"`
	ClassFactor   float64 `csv:"class_factor"`

	// Timing & Hysteresis
	BadWindowS  float64 `csv:"bad_window_s"`
	GoodWindowS float64 `csv:"good_window_s"`
	CooldownS   float64 `csv:"cooldown_s"`
	WarmupS     float64 `csv:"warmup_s"`

	// Predictive Information
	PredictiveRisk   float64 `csv:"predictive_risk"`
	PredictiveConf   float64 `csv:"predictive_confidence"`
	PredictiveMethod string  `csv:"predictive_method"`
	TrendLatency     float64 `csv:"trend_latency"`
	TrendLoss        float64 `csv:"trend_loss"`
	TrendScore       float64 `csv:"trend_score"`

	// Location Context (if available)
	GPSLatitude     *float64 `csv:"gps_latitude"`
	GPSLongitude    *float64 `csv:"gps_longitude"`
	GPSAccuracy     *float64 `csv:"gps_accuracy"`
	LocationCluster string   `csv:"location_cluster"`

	// Additional Context
	MemberCount     int     `csv:"member_count"`
	EligibleCount   int     `csv:"eligible_count"`
	Success         bool    `csv:"success"`
	ErrorMessage    string  `csv:"error_message"`
	ExecutionTimeMs float64 `csv:"execution_time_ms"`
}

// NewDecisionLogger creates a new decision logger
func NewDecisionLogger(config *DecisionLoggerConfig, logger *logx.Logger) (*DecisionLogger, error) {
	if !config.Enabled {
		return &DecisionLogger{
			enabled: false,
			logger:  logger,
		}, nil
	}

	// Ensure output directory exists
	if err := os.MkdirAll(config.OutputDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create output directory: %w", err)
	}

	dl := &DecisionLogger{
		enabled:   true,
		outputDir: config.OutputDir,
		maxSizeMB: config.MaxSizeMB,
		retention: config.Retention,
		logger:    logger,
		startTime: time.Now(),
	}

	// Initialize CSV file
	if err := dl.initializeCSVFile(); err != nil {
		return nil, fmt.Errorf("failed to initialize CSV file: %w", err)
	}

	return dl, nil
}

// DecisionLoggerConfig represents decision logger configuration
type DecisionLoggerConfig struct {
	Enabled   bool          `json:"enabled"`
	OutputDir string        `json:"output_dir"`
	MaxSizeMB int           `json:"max_size_mb"`
	Retention time.Duration `json:"retention"`
}

// LogDecision logs a decision evaluation
func (dl *DecisionLogger) LogDecision(entry *DecisionLogEntry) error {
	if !dl.enabled {
		return nil
	}

	dl.mu.Lock()
	defer dl.mu.Unlock()

	// Check if we need to rotate the file
	if err := dl.checkRotation(); err != nil {
		dl.logger.Error("Failed to check file rotation", "error", err)
		return err
	}

	// Write CSV record
	record := dl.entryToCSVRecord(entry)
	if err := dl.csvWriter.Write(record); err != nil {
		dl.logger.Error("Failed to write CSV record", "error", err)
		return err
	}

	// Flush to disk
	dl.csvWriter.Flush()
	if err := dl.csvWriter.Error(); err != nil {
		dl.logger.Error("Failed to flush CSV writer", "error", err)
		return err
	}

	// Update current size
	if dl.currentFile != nil {
		if stat, err := dl.currentFile.Stat(); err == nil {
			dl.currentSize = stat.Size()
		}
	}

	return nil
}

// LogEvaluation logs a decision evaluation (even if no action was taken)
func (dl *DecisionLogger) LogEvaluation(
	decisionID string,
	current *pkg.Member,
	target *pkg.Member,
	currentScore *pkg.Score,
	targetScore *pkg.Score,
	action string,
	reason string,
	context map[string]interface{},
) error {
	if !dl.enabled {
		return nil
	}

	entry := &DecisionLogEntry{
		Timestamp:     time.Now(),
		DecisionID:    decisionID,
		Type:          "evaluation",
		Action:        action,
		Reason:        reason,
		MemberCount:   getIntFromContext(context, "member_count"),
		EligibleCount: getIntFromContext(context, "eligible_count"),
		Success:       true,
	}

	// Fill in member information
	if current != nil {
		entry.CurrentMember = current.Name
	}
	if target != nil {
		entry.TargetMember = target.Name
	}

	// Fill in scoring information
	if currentScore != nil {
		entry.CurrentScore = currentScore.Final
	}
	if targetScore != nil {
		entry.TargetScore = targetScore.Final
		entry.ScoreDelta = targetScore.Final - entry.CurrentScore
	}

	// Extract quality factors from context
	if qf, ok := context["quality_factors"].(map[string]float64); ok {
		entry.LatencyFactor = qf["latency"]
		entry.LossFactor = qf["loss"]
		entry.JitterFactor = qf["jitter"]
		entry.SignalFactor = qf["signal"]
		entry.ClassFactor = qf["class"]
	}

	// Extract timing information from context
	entry.BadWindowS = getFloatFromContext(context, "bad_window_s")
	entry.GoodWindowS = getFloatFromContext(context, "good_window_s")
	entry.CooldownS = getFloatFromContext(context, "cooldown_s")
	entry.WarmupS = getFloatFromContext(context, "warmup_s")
	entry.SwitchMargin = getFloatFromContext(context, "switch_margin")

	// Extract predictive information from context
	if pred, ok := context["prediction"].(map[string]interface{}); ok {
		entry.PredictiveRisk = getFloatFromMap(pred, "risk")
		entry.PredictiveConf = getFloatFromMap(pred, "confidence")
		entry.PredictiveMethod = getStringFromMap(pred, "method")
	}

	// Extract trend information from context
	if trend, ok := context["trend"].(map[string]float64); ok {
		entry.TrendLatency = trend["latency"]
		entry.TrendLoss = trend["loss"]
		entry.TrendScore = trend["score"]
	}

	// Extract GPS information from context
	if gps, ok := context["gps"].(map[string]interface{}); ok {
		if lat, ok := gps["latitude"].(float64); ok {
			entry.GPSLatitude = &lat
		}
		if lon, ok := gps["longitude"].(float64); ok {
			entry.GPSLongitude = &lon
		}
		if acc, ok := gps["accuracy"].(float64); ok {
			entry.GPSAccuracy = &acc
		}
		entry.LocationCluster = getStringFromMap(gps, "cluster")
	}

	// Extract trigger reason from context
	entry.TriggerReason = getStringFromContext(context, "trigger_reason")

	// Extract execution time from context
	entry.ExecutionTimeMs = getFloatFromContext(context, "execution_time_ms")

	return dl.LogDecision(entry)
}

// LogFailover logs a successful failover action
func (dl *DecisionLogger) LogFailover(
	decisionID string,
	from *pkg.Member,
	to *pkg.Member,
	reason string,
	triggerReason string,
	executionTimeMs float64,
	context map[string]interface{},
) error {
	if !dl.enabled {
		return nil
	}

	entry := &DecisionLogEntry{
		Timestamp:       time.Now(),
		DecisionID:      decisionID,
		Type:            "hard_failover",
		CurrentMember:   from.Name,
		TargetMember:    to.Name,
		Action:          "switch",
		Reason:          reason,
		TriggerReason:   triggerReason,
		Success:         true,
		ExecutionTimeMs: executionTimeMs,
	}

	// Fill in additional context
	dl.fillContextData(entry, context)

	return dl.LogDecision(entry)
}

// LogFailure logs a failed decision or action
func (dl *DecisionLogger) LogFailure(
	decisionID string,
	action string,
	reason string,
	errorMsg string,
	context map[string]interface{},
) error {
	if !dl.enabled {
		return nil
	}

	entry := &DecisionLogEntry{
		Timestamp:    time.Now(),
		DecisionID:   decisionID,
		Type:         "evaluation",
		Action:       action,
		Reason:       reason,
		Success:      false,
		ErrorMessage: errorMsg,
	}

	// Fill in additional context
	dl.fillContextData(entry, context)

	return dl.LogDecision(entry)
}

// initializeCSVFile creates a new CSV file and writes headers
func (dl *DecisionLogger) initializeCSVFile() error {
	filename := fmt.Sprintf("starfail_decisions_%s.csv", time.Now().Format("20060102_150405"))
	filepath := filepath.Join(dl.outputDir, filename)

	file, err := os.Create(filepath)
	if err != nil {
		return fmt.Errorf("failed to create CSV file: %w", err)
	}

	dl.currentFile = file
	dl.csvWriter = csv.NewWriter(file)
	dl.currentSize = 0

	// Write CSV headers
	headers := []string{
		"timestamp", "decision_id", "type", "current_member", "target_member",
		"action", "reason", "trigger_reason", "current_score", "target_score",
		"score_delta", "switch_margin", "latency_factor", "loss_factor",
		"jitter_factor", "signal_factor", "class_factor", "bad_window_s",
		"good_window_s", "cooldown_s", "warmup_s", "predictive_risk",
		"predictive_confidence", "predictive_method", "trend_latency",
		"trend_loss", "trend_score", "gps_latitude", "gps_longitude",
		"gps_accuracy", "location_cluster", "member_count", "eligible_count",
		"success", "error_message", "execution_time_ms",
	}

	if err := dl.csvWriter.Write(headers); err != nil {
		file.Close()
		return fmt.Errorf("failed to write CSV headers: %w", err)
	}

	dl.csvWriter.Flush()
	dl.logger.Info("Initialized decision CSV log file", "file", filepath)

	return nil
}

// checkRotation checks if the current file needs to be rotated
func (dl *DecisionLogger) checkRotation() error {
	if dl.currentFile == nil {
		return dl.initializeCSVFile()
	}

	// Check file size
	if dl.currentSize > int64(dl.maxSizeMB)*1024*1024 {
		dl.logger.Info("Rotating CSV log file due to size limit", "size_mb", dl.currentSize/1024/1024)
		return dl.rotateFile()
	}

	// Check age (rotate daily)
	if time.Since(dl.startTime) > 24*time.Hour {
		dl.logger.Info("Rotating CSV log file due to age")
		return dl.rotateFile()
	}

	return nil
}

// rotateFile closes current file and creates a new one
func (dl *DecisionLogger) rotateFile() error {
	// Close current file
	if dl.currentFile != nil {
		dl.csvWriter.Flush()
		dl.currentFile.Close()
	}

	// Clean up old files
	dl.cleanupOldFiles()

	// Create new file
	dl.startTime = time.Now()
	return dl.initializeCSVFile()
}

// cleanupOldFiles removes old CSV files beyond retention period
func (dl *DecisionLogger) cleanupOldFiles() {
	files, err := filepath.Glob(filepath.Join(dl.outputDir, "starfail_decisions_*.csv"))
	if err != nil {
		dl.logger.Error("Failed to list CSV files for cleanup", "error", err)
		return
	}

	cutoff := time.Now().Add(-dl.retention)
	for _, file := range files {
		if stat, err := os.Stat(file); err == nil {
			if stat.ModTime().Before(cutoff) {
				if err := os.Remove(file); err != nil {
					dl.logger.Error("Failed to remove old CSV file", "file", file, "error", err)
				} else {
					dl.logger.Info("Removed old CSV file", "file", file)
				}
			}
		}
	}
}

// entryToCSVRecord converts a DecisionLogEntry to a CSV record
func (dl *DecisionLogger) entryToCSVRecord(entry *DecisionLogEntry) []string {
	return []string{
		entry.Timestamp.Format(time.RFC3339),
		entry.DecisionID,
		entry.Type,
		entry.CurrentMember,
		entry.TargetMember,
		entry.Action,
		entry.Reason,
		entry.TriggerReason,
		fmt.Sprintf("%.2f", entry.CurrentScore),
		fmt.Sprintf("%.2f", entry.TargetScore),
		fmt.Sprintf("%.2f", entry.ScoreDelta),
		fmt.Sprintf("%.2f", entry.SwitchMargin),
		fmt.Sprintf("%.3f", entry.LatencyFactor),
		fmt.Sprintf("%.3f", entry.LossFactor),
		fmt.Sprintf("%.3f", entry.JitterFactor),
		fmt.Sprintf("%.3f", entry.SignalFactor),
		fmt.Sprintf("%.3f", entry.ClassFactor),
		fmt.Sprintf("%.1f", entry.BadWindowS),
		fmt.Sprintf("%.1f", entry.GoodWindowS),
		fmt.Sprintf("%.1f", entry.CooldownS),
		fmt.Sprintf("%.1f", entry.WarmupS),
		fmt.Sprintf("%.3f", entry.PredictiveRisk),
		fmt.Sprintf("%.3f", entry.PredictiveConf),
		entry.PredictiveMethod,
		fmt.Sprintf("%.2f", entry.TrendLatency),
		fmt.Sprintf("%.2f", entry.TrendLoss),
		fmt.Sprintf("%.2f", entry.TrendScore),
		dl.formatOptionalFloat(entry.GPSLatitude),
		dl.formatOptionalFloat(entry.GPSLongitude),
		dl.formatOptionalFloat(entry.GPSAccuracy),
		entry.LocationCluster,
		fmt.Sprintf("%d", entry.MemberCount),
		fmt.Sprintf("%d", entry.EligibleCount),
		fmt.Sprintf("%t", entry.Success),
		entry.ErrorMessage,
		fmt.Sprintf("%.1f", entry.ExecutionTimeMs),
	}
}

// fillContextData fills entry with data from context map
func (dl *DecisionLogger) fillContextData(entry *DecisionLogEntry, context map[string]interface{}) {
	entry.MemberCount = getIntFromContext(context, "member_count")
	entry.EligibleCount = getIntFromContext(context, "eligible_count")
	entry.SwitchMargin = getFloatFromContext(context, "switch_margin")

	// Extract quality factors
	if qf, ok := context["quality_factors"].(map[string]float64); ok {
		entry.LatencyFactor = qf["latency"]
		entry.LossFactor = qf["loss"]
		entry.JitterFactor = qf["jitter"]
		entry.SignalFactor = qf["signal"]
		entry.ClassFactor = qf["class"]
	}

	// Extract predictive information
	if pred, ok := context["prediction"].(map[string]interface{}); ok {
		entry.PredictiveRisk = getFloatFromMap(pred, "risk")
		entry.PredictiveConf = getFloatFromMap(pred, "confidence")
		entry.PredictiveMethod = getStringFromMap(pred, "method")
	}

	// Extract GPS information
	if gps, ok := context["gps"].(map[string]interface{}); ok {
		if lat, ok := gps["latitude"].(float64); ok {
			entry.GPSLatitude = &lat
		}
		if lon, ok := gps["longitude"].(float64); ok {
			entry.GPSLongitude = &lon
		}
		if acc, ok := gps["accuracy"].(float64); ok {
			entry.GPSAccuracy = &acc
		}
		entry.LocationCluster = getStringFromMap(gps, "cluster")
	}
}

// formatOptionalFloat formats an optional float64 pointer
func (dl *DecisionLogger) formatOptionalFloat(f *float64) string {
	if f == nil {
		return ""
	}
	return fmt.Sprintf("%.6f", *f)
}

// Close closes the decision logger
func (dl *DecisionLogger) Close() error {
	if !dl.enabled {
		return nil
	}

	dl.mu.Lock()
	defer dl.mu.Unlock()

	if dl.csvWriter != nil {
		dl.csvWriter.Flush()
	}

	if dl.currentFile != nil {
		return dl.currentFile.Close()
	}

	return nil
}

// Helper functions for extracting values from context maps
func getIntFromContext(context map[string]interface{}, key string) int {
	if val, ok := context[key].(int); ok {
		return val
	}
	return 0
}

func getFloatFromContext(context map[string]interface{}, key string) float64 {
	if val, ok := context[key].(float64); ok {
		return val
	}
	return 0.0
}

func getStringFromContext(context map[string]interface{}, key string) string {
	if val, ok := context[key].(string); ok {
		return val
	}
	return ""
}

func getFloatFromMap(m map[string]interface{}, key string) float64 {
	if val, ok := m[key].(float64); ok {
		return val
	}
	return 0.0
}

func getStringFromMap(m map[string]interface{}, key string) string {
	if val, ok := m[key].(string); ok {
		return val
	}
	return ""
}
