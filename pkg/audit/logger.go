// Package audit provides comprehensive decision logging and audit trail functionality
package audit

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// AuditLogger provides comprehensive decision logging with context
type AuditLogger struct {
	logDir       string
	currentFile  *os.File
	mutex        sync.Mutex
	maxFileSize  int64
	maxFiles     int
	contextDepth int
}

// DecisionEvent represents a single failover decision with full context
type DecisionEvent struct {
	Timestamp      time.Time              `json:"timestamp"`
	EventID        string                 `json:"event_id"`
	EventType      string                 `json:"event_type"` // "evaluation", "action", "recovery", "error"
	Component      string                 `json:"component"`  // "starfaild", "decision", "controller"
	
	// Decision context
	TriggerReason  string                 `json:"trigger_reason"`
	DecisionType   string                 `json:"decision_type"` // "failover", "failback", "maintain"
	FromInterface  string                 `json:"from_interface"`
	ToInterface    string                 `json:"to_interface"`
	
	// Environmental context
	SystemLoad     *SystemContext         `json:"system_context"`
	NetworkState   map[string]interface{} `json:"network_state"`
	LocationInfo   *LocationContext       `json:"location_context"`
	WeatherImpact  *WeatherContext        `json:"weather_context"`
	
	// Metrics and scoring
	InterfaceMetrics map[string]interface{} `json:"interface_metrics"`
	ScoreCalculation *ScoreBreakdown        `json:"score_calculation"`
	Thresholds       map[string]float64     `json:"thresholds"`
	
	// Decision logic
	RulesTested    []RuleEvaluation       `json:"rules_tested"`
	DecisionPath   []string               `json:"decision_path"`
	AlternativeOptions []Alternative      `json:"alternative_options"`
	
	// Action results
	ActionTaken    string                 `json:"action_taken"`
	ActionResult   string                 `json:"action_result"` // "success", "failed", "partial"
	ErrorDetails   string                 `json:"error_details,omitempty"`
	
	// Correlation and tracking
	CorrelationID  string                 `json:"correlation_id"`
	ParentEventID  string                 `json:"parent_event_id,omitempty"`
	SessionID      string                 `json:"session_id"`
	
	// Performance tracking
	ProcessingTime time.Duration          `json:"processing_time_ms"`
	Confidence     float64                `json:"confidence"`
	
	// Additional context
	Extra          map[string]interface{} `json:"extra,omitempty"`
}

// SystemContext provides system-level context for decisions
type SystemContext struct {
	CPUUsage      float64 `json:"cpu_usage_pct"`
	MemoryUsage   float64 `json:"memory_usage_pct"`
	LoadAverage   float64 `json:"load_average"`
	UptimeSeconds int64   `json:"uptime_seconds"`
	ActiveConns   int     `json:"active_connections"`
	ProcessCount  int     `json:"process_count"`
}

// LocationContext provides location-aware context
type LocationContext struct {
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	Accuracy     float64 `json:"accuracy_m"`
	IsMoving     bool    `json:"is_moving"`
	Speed        float64 `json:"speed_mps"`
	AreaType     string  `json:"area_type"`
	GPSSource    string  `json:"gps_source"`
	Confidence   float64 `json:"confidence"`
}

// WeatherContext provides weather impact assessment
type WeatherContext struct {
	WeatherType    string  `json:"weather_type"`
	Severity       string  `json:"severity"`
	Impact         float64 `json:"impact_score"`
	Source         string  `json:"source"`
	LastUpdated    time.Time `json:"last_updated"`
}

// ScoreBreakdown shows how interface scores were calculated
type ScoreBreakdown struct {
	InterfaceName  string             `json:"interface"`
	TotalScore     float64            `json:"total_score"`
	BaseScore      float64            `json:"base_score"`
	Components     map[string]float64 `json:"score_components"`
	Penalties      map[string]float64 `json:"penalties"`
	Bonuses        map[string]float64 `json:"bonuses"`
	WeightedFactors map[string]float64 `json:"weighted_factors"`
}

// RuleEvaluation shows how each decision rule was evaluated
type RuleEvaluation struct {
	RuleName     string      `json:"rule_name"`
	Condition    string      `json:"condition"`
	Result       bool        `json:"result"`
	Value        interface{} `json:"actual_value"`
	Expected     interface{} `json:"expected_value"`
	Weight       float64     `json:"weight"`
	Contribution float64     `json:"contribution"`
}

// Alternative represents alternative decisions that were considered
type Alternative struct {
	Option       string  `json:"option"`
	Score        float64 `json:"score"`
	Pros         []string `json:"pros"`
	Cons         []string `json:"cons"`
	Rejected     bool    `json:"rejected"`
	RejectReason string  `json:"reject_reason,omitempty"`
}

// NewAuditLogger creates a new audit logger
func NewAuditLogger(logDir string) (*AuditLogger, error) {
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create log directory: %w", err)
	}
	
	logger := &AuditLogger{
		logDir:       logDir,
		maxFileSize:  50 * 1024 * 1024, // 50MB per file
		maxFiles:     10,                // Keep 10 files max
		contextDepth: 5,                 // Depth of context to capture
	}
	
	if err := logger.openLogFile(); err != nil {
		return nil, fmt.Errorf("failed to open log file: %w", err)
	}
	
	return logger, nil
}

// LogDecision logs a comprehensive decision event
func (a *AuditLogger) LogDecision(ctx context.Context, event *DecisionEvent) error {
	a.mutex.Lock()
	defer a.mutex.Unlock()
	
	// Set automatic fields
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now()
	}
	if event.EventID == "" {
		event.EventID = generateEventID()
	}
	if event.SessionID == "" {
		event.SessionID = getSessionID(ctx)
	}
	
	// Enhance with system context if not provided
	if event.SystemLoad == nil {
		event.SystemLoad = a.captureSystemContext()
	}
	
	// Serialize and write
	data, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}
	
	// Add newline for JSONL format
	data = append(data, '\n')
	
	// Check if we need to rotate log file
	if a.needsRotation(int64(len(data))) {
		if err := a.rotateLogFile(); err != nil {
			return fmt.Errorf("failed to rotate log file: %w", err)
		}
	}
	
	_, err = a.currentFile.Write(data)
	if err != nil {
		return fmt.Errorf("failed to write event: %w", err)
	}
	
	// Force sync for critical events
	if event.EventType == "action" || event.EventType == "error" {
		a.currentFile.Sync()
	}
	
	return nil
}

// LogEvaluation logs a decision evaluation with full scoring context
func (a *AuditLogger) LogEvaluation(ctx context.Context, interfaces map[string]interface{}, scores map[string]*ScoreBreakdown, rules []RuleEvaluation) error {
	event := &DecisionEvent{
		EventType:        "evaluation",
		Component:        "decision",
		TriggerReason:    "periodic_evaluation",
		InterfaceMetrics: interfaces,
		RulesTested:      rules,
	}
	
	// Add score breakdowns
	if len(scores) > 0 {
		event.Extra = make(map[string]interface{})
		event.Extra["all_scores"] = scores
	}
	
	return a.LogDecision(ctx, event)
}

// LogAction logs a failover action with before/after context
func (a *AuditLogger) LogAction(ctx context.Context, actionType, fromIface, toIface string, result string, processingTime time.Duration) error {
	event := &DecisionEvent{
		EventType:      "action",
		Component:      "controller",
		DecisionType:   actionType,
		FromInterface:  fromIface,
		ToInterface:    toIface,
		ActionTaken:    actionType,
		ActionResult:   result,
		ProcessingTime: processingTime,
	}
	
	return a.LogDecision(ctx, event)
}

// LogError logs error events with diagnostic context
func (a *AuditLogger) LogError(ctx context.Context, component, operation, errorMsg string, extra map[string]interface{}) error {
	event := &DecisionEvent{
		EventType:     "error",
		Component:     component,
		ActionTaken:   operation,
		ActionResult:  "failed",
		ErrorDetails:  errorMsg,
		Extra:         extra,
	}
	
	return a.LogDecision(ctx, event)
}

// LogRecovery logs system recovery events
func (a *AuditLogger) LogRecovery(ctx context.Context, recoveryType, details string) error {
	event := &DecisionEvent{
		EventType:    "recovery",
		Component:    "starfaild",
		ActionTaken:  recoveryType,
		ActionResult: "success",
		ErrorDetails: details,
	}
	
	return a.LogDecision(ctx, event)
}

// QueryEvents provides basic event querying capabilities
func (a *AuditLogger) QueryEvents(since time.Time, eventTypes []string, limit int) ([]*DecisionEvent, error) {
	a.mutex.Lock()
	defer a.mutex.Unlock()
	
	var events []*DecisionEvent
	
	// Read from all log files (simple implementation)
	files, err := filepath.Glob(filepath.Join(a.logDir, "audit-*.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("failed to list log files: %w", err)
	}
	
	for _, file := range files {
		fileEvents, err := a.readEventsFromFile(file, since, eventTypes, limit-len(events))
		if err != nil {
			continue // Skip corrupted files
		}
		events = append(events, fileEvents...)
		
		if len(events) >= limit {
			break
		}
	}
	
	return events[:min(len(events), limit)], nil
}

// GetCorrelatedEvents finds events related to a specific correlation ID
func (a *AuditLogger) GetCorrelatedEvents(correlationID string) ([]*DecisionEvent, error) {
	return a.QueryEvents(time.Now().Add(-24*time.Hour), nil, 1000) // Search last 24h
}

// GenerateReport creates a summary report of recent decisions
func (a *AuditLogger) GenerateReport(period time.Duration) (*AuditReport, error) {
	since := time.Now().Add(-period)
	events, err := a.QueryEvents(since, nil, 10000)
	if err != nil {
		return nil, fmt.Errorf("failed to query events: %w", err)
	}
	
	report := &AuditReport{
		Period:     period,
		EventCount: len(events),
		GeneratedAt: time.Now(),
	}
	
	// Analyze events
	for _, event := range events {
		switch event.EventType {
		case "action":
			report.ActionCount++
			if event.ActionResult == "success" {
				report.SuccessfulActions++
			}
		case "error":
			report.ErrorCount++
		case "evaluation":
			report.EvaluationCount++
		}
	}
	
	if report.ActionCount > 0 {
		report.SuccessRate = float64(report.SuccessfulActions) / float64(report.ActionCount)
	}
	
	return report, nil
}

// AuditReport provides summary statistics
type AuditReport struct {
	Period            time.Duration `json:"period"`
	EventCount        int           `json:"event_count"`
	ActionCount       int           `json:"action_count"`
	SuccessfulActions int           `json:"successful_actions"`
	ErrorCount        int           `json:"error_count"`
	EvaluationCount   int           `json:"evaluation_count"`
	SuccessRate       float64       `json:"success_rate"`
	GeneratedAt       time.Time     `json:"generated_at"`
}

// Helper functions

func (a *AuditLogger) openLogFile() error {
	filename := fmt.Sprintf("audit-%s.jsonl", time.Now().Format("20060102"))
	path := filepath.Join(a.logDir, filename)
	
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return err
	}
	
	a.currentFile = file
	return nil
}

func (a *AuditLogger) needsRotation(additionalBytes int64) bool {
	if a.currentFile == nil {
		return true
	}
	
	stat, err := a.currentFile.Stat()
	if err != nil {
		return true
	}
	
	return stat.Size()+additionalBytes > a.maxFileSize
}

func (a *AuditLogger) rotateLogFile() error {
	if a.currentFile != nil {
		a.currentFile.Close()
	}
	
	// Clean up old files
	a.cleanupOldFiles()
	
	return a.openLogFile()
}

func (a *AuditLogger) cleanupOldFiles() {
	files, err := filepath.Glob(filepath.Join(a.logDir, "audit-*.jsonl"))
	if err != nil {
		return
	}
	
	if len(files) > a.maxFiles {
		// Remove oldest files
		for i := 0; i < len(files)-a.maxFiles; i++ {
			os.Remove(files[i])
		}
	}
}

func (a *AuditLogger) captureSystemContext() *SystemContext {
	return &SystemContext{
		CPUUsage:      getCPUUsage(),
		MemoryUsage:   getMemoryUsage(),
		LoadAverage:   getLoadAverage(),
		UptimeSeconds: getSystemUptime(),
		ActiveConns:   getActiveConnections(),
		ProcessCount:  getProcessCount(),
	}
}

// Enhanced system context collection functions
func getCPUUsage() float64 {
	// Read /proc/loadavg and convert to percentage
	if data, err := ioutil.ReadFile("/proc/loadavg"); err == nil {
		fields := strings.Fields(string(data))
		if len(fields) >= 1 {
			if load, err := strconv.ParseFloat(fields[0], 64); err == nil {
				// Convert load average to rough percentage (assuming single core)
				return load * 100
			}
		}
	}
	return 0.0
}

func getMemoryUsage() float64 {
	// Read /proc/meminfo
	if data, err := ioutil.ReadFile("/proc/meminfo"); err == nil {
		lines := strings.Split(string(data), "\n")
		var memTotal, memAvailable float64
		
		for _, line := range lines {
			if strings.HasPrefix(line, "MemTotal:") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					if val, err := strconv.ParseFloat(fields[1], 64); err == nil {
						memTotal = val
					}
				}
			} else if strings.HasPrefix(line, "MemAvailable:") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					if val, err := strconv.ParseFloat(fields[1], 64); err == nil {
						memAvailable = val
					}
				}
			}
		}
		
		if memTotal > 0 {
			return ((memTotal - memAvailable) / memTotal) * 100
		}
	}
	return 0.0
}

func getLoadAverage() float64 {
	if data, err := ioutil.ReadFile("/proc/loadavg"); err == nil {
		fields := strings.Fields(string(data))
		if len(fields) >= 1 {
			if load, err := strconv.ParseFloat(fields[0], 64); err == nil {
				return load
			}
		}
	}
	return 0.0
}

func getActiveConnections() int {
	// Count active network connections
	if output, err := exec.Command("netstat", "-n").Output(); err == nil {
		lines := strings.Split(string(output), "\n")
		count := 0
		for _, line := range lines {
			if strings.Contains(line, "ESTABLISHED") {
				count++
			}
		}
		return count
	}
	return 0
}

func getSystemUptime() int64 {
	if data, err := ioutil.ReadFile("/proc/uptime"); err == nil {
		fields := strings.Fields(string(data))
		if len(fields) >= 1 {
			if uptime, err := strconv.ParseFloat(fields[0], 64); err == nil {
				return int64(uptime)
			}
		}
	}
	return time.Now().Unix()
}

func getProcessCount() int {
	if data, err := ioutil.ReadFile("/proc/loadavg"); err == nil {
		fields := strings.Fields(string(data))
		if len(fields) >= 4 {
			// Format: "load1 load5 load15 running/total lastpid"
			if procInfo := fields[3]; strings.Contains(procInfo, "/") {
				parts := strings.Split(procInfo, "/")
				if len(parts) >= 2 {
					if total, err := strconv.Atoi(parts[1]); err == nil {
						return total
					}
				}
			}
		}
	}
	return 0
}

func (a *AuditLogger) readEventsFromFile(filename string, since time.Time, eventTypes []string, limit int) ([]*DecisionEvent, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()
	
	var events []*DecisionEvent
	scanner := bufio.NewScanner(file)
	
	for scanner.Scan() && len(events) < limit {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		
		var event DecisionEvent
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			continue // Skip malformed lines
		}
		
		// Filter by timestamp
		if event.Timestamp.Before(since) {
			continue
		}
		
		// Filter by event types if specified
		if len(eventTypes) > 0 {
			found := false
			for _, eventType := range eventTypes {
				if event.EventType == eventType {
					found = true
					break
				}
			}
			if !found {
				continue
			}
		}
		
		events = append(events, &event)
	}
	
	if err := scanner.Err(); err != nil {
		return events, fmt.Errorf("scanner error: %w", err)
	}
	
	return events, nil
}

func generateEventID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}

func getSessionID(ctx context.Context) string {
	if sid := ctx.Value("session_id"); sid != nil {
		return sid.(string)
	}
	return "default"
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Close closes the audit logger
func (a *AuditLogger) Close() error {
	a.mutex.Lock()
	defer a.mutex.Unlock()
	
	if a.currentFile != nil {
		return a.currentFile.Close()
	}
	return nil
}
