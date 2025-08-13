// Package logx provides structured logging for the starfail daemon with monitoring support
package logx

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"time"
)

// ANSI color codes for console output
const (
	ColorReset  = "\033[0m"
	ColorBold   = "\033[1m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorCyan   = "\033[36m"
	ColorGray   = "\033[37m"
)

// LogLevel represents the logging level
type LogLevel int

const (
	TraceLevel LogLevel = iota
	DebugLevel
	InfoLevel
	WarnLevel
	ErrorLevel
)

// Fields is a type alias for structured logging fields
type Fields map[string]interface{}

// Config holds logger configuration
type Config struct {
	Level    string `json:"level"`
	Format   string `json:"format"`   // "json" or "console"
	Output   string `json:"output"`   // "stdout", "syslog", or file path
	Monitor  bool   `json:"monitor"`  // Enable monitoring mode
	NoColor  bool   `json:"no_color"` // Disable colors in console format
	FilePath string `json:"file_path,omitempty"`
}

// Logger provides structured logging with monitoring capabilities
type Logger struct {
	level     LogLevel
	logger    *log.Logger
	config    Config
	syslogger interface{} // Platform-specific syslog writer (Unix only)
	fields    map[string]interface{}
	writer    io.Writer
}

// New creates a new structured logger (backward compatibility)
func New(levelStr string) *Logger {
	config := Config{
		Level:  levelStr,
		Format: "json",
		Output: "syslog",
	}
	return NewWithConfig(config)
}

// NewWithConfig creates a new logger with full configuration
func NewWithConfig(config Config) *Logger {
	level := parseLevel(config.Level)

	// Determine output writer
	var writer io.Writer = os.Stdout
	if config.Output == "syslog" {
		writer = os.Stdout // Will also go to syslog
	} else if config.Output != "stdout" && config.Output != "" {
		// File output
		if file, err := os.OpenFile(config.Output, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644); err == nil {
			writer = file
		}
	}

	l := &Logger{
		level:  level,
		logger: log.New(writer, "", 0), // No prefix, we'll format everything
		config: config,
		fields: make(map[string]interface{}),
		writer: writer,
	}

	// Initialize syslog (platform-specific)
	l.initSyslog()

	return l
}

// NewWithFields creates a logger with persistent contextual fields
func NewWithFields(levelStr string, fields map[string]interface{}) *Logger {
	l := New(levelStr)
	for k, v := range fields {
		l.fields[k] = v
	}
	return l
}

// WithFields returns a new logger with additional persistent fields
func (l *Logger) WithFields(fields map[string]interface{}) *Logger {
	newFields := make(map[string]interface{})

	// Copy existing fields
	for k, v := range l.fields {
		newFields[k] = v
	}

	// Add new fields
	for k, v := range fields {
		newFields[k] = v
	}

	return &Logger{
		level:     l.level,
		logger:    l.logger,
		config:    l.config,
		syslogger: l.syslogger,
		fields:    newFields,
		writer:    l.writer,
	}
}

// WithField returns a new logger with an additional persistent field
func (l *Logger) WithField(key string, value interface{}) *Logger {
	return l.WithFields(map[string]interface{}{key: value})
}

// SetLevel changes the logging level
func (l *Logger) SetLevel(levelStr string) {
	l.level = parseLevel(levelStr)
}

// parseLevel converts string to LogLevel
func parseLevel(levelStr string) LogLevel {
	switch strings.ToLower(levelStr) {
	case "trace":
		return TraceLevel
	case "debug":
		return DebugLevel
	case "info":
		return InfoLevel
	case "warn", "warning":
		return WarnLevel
	case "error":
		return ErrorLevel
	default:
		return InfoLevel
	}
}

// logEntry represents a structured log entry
type logEntry struct {
	Timestamp string                 `json:"ts"`
	Level     string                 `json:"level"`
	Message   string                 `json:"msg"`
	Component string                 `json:"component,omitempty"`
	Module    string                 `json:"module,omitempty"`
	Fields    map[string]interface{} `json:",inline,omitempty"`
}

// log outputs a structured log entry with format selection
func (l *Logger) log(level LogLevel, msg string, keysAndValues ...interface{}) {
	if level < l.level {
		return
	}

	timestamp := time.Now().UTC()

	// Create log entry
	entry := logEntry{
		Timestamp: timestamp.Format(time.RFC3339),
		Level:     levelString(level),
		Message:   msg,
		Fields:    make(map[string]interface{}),
	}

	// Add persistent fields first
	for k, v := range l.fields {
		entry.Fields[k] = v
	}

	// Parse key-value pairs from arguments
	for i := 0; i < len(keysAndValues); i += 2 {
		if i+1 < len(keysAndValues) {
			key := fmt.Sprintf("%v", keysAndValues[i])
			entry.Fields[key] = keysAndValues[i+1]
		}
	}

	// Output based on format
	if l.config.Format == "console" {
		l.logConsole(level, timestamp, msg, entry.Fields)
	} else {
		l.logJSON(entry)
	}

	// Also send to syslog if available and not monitoring mode
	if !l.config.Monitor {
		jsonBytes, _ := json.Marshal(entry)
		l.logToSyslog(level, string(jsonBytes))
	}
}

// logJSON outputs a JSON formatted log entry
func (l *Logger) logJSON(entry logEntry) {
	jsonBytes, err := json.Marshal(entry)
	if err != nil {
		// Fallback to simple log if JSON marshaling fails
		l.logger.Printf("LOG_ERROR: failed to marshal log entry: %v", err)
		return
	}
	l.logger.Println(string(jsonBytes))
}

// logConsole outputs a human-readable console log entry
func (l *Logger) logConsole(level LogLevel, timestamp time.Time, msg string, fields map[string]interface{}) {
	// Build color prefix
	levelColor := l.getLevelColor(level)
	levelStr := levelString(level)

	// Format timestamp for console (shorter format)
	timeStr := timestamp.Format("15:04:05.000")

	// Reset color if no color mode
	reset := ColorReset
	if l.config.NoColor {
		levelColor = ""
		reset = ""
	}

	// Build base message
	baseMsg := fmt.Sprintf("%s[%s]%s %s %s%s%s",
		ColorGray, timeStr, reset,
		levelColor+strings.ToUpper(levelStr)+reset,
		ColorBold, msg, reset)

	// Add fields if present
	if len(fields) > 0 {
		var fieldParts []string
		for k, v := range fields {
			fieldParts = append(fieldParts, fmt.Sprintf("%s=%v", k, v))
		}
		if len(fieldParts) > 0 {
			fieldsStr := strings.Join(fieldParts, " ")
			if !l.config.NoColor {
				fieldsStr = ColorCyan + fieldsStr + reset
			}
			baseMsg += " " + fieldsStr
		}
	}

	l.logger.Println(baseMsg)
}

// getLevelColor returns the ANSI color code for a log level
func (l *Logger) getLevelColor(level LogLevel) string {
	if l.config.NoColor {
		return ""
	}

	switch level {
	case TraceLevel:
		return ColorGray
	case DebugLevel:
		return ColorBlue
	case InfoLevel:
		return ColorGreen
	case WarnLevel:
		return ColorYellow
	case ErrorLevel:
		return ColorRed
	default:
		return ColorReset
	}
}

// levelString converts LogLevel to string
func levelString(level LogLevel) string {
	switch level {
	case TraceLevel:
		return "trace"
	case DebugLevel:
		return "debug"
	case InfoLevel:
		return "info"
	case WarnLevel:
		return "warn"
	case ErrorLevel:
		return "error"
	default:
		return "unknown"
	}
}

// Debug logs a debug message
func (l *Logger) Debug(msg string, keysAndValues ...interface{}) {
	l.log(DebugLevel, msg, keysAndValues...)
}

// Info logs an info message
func (l *Logger) Info(msg string, keysAndValues ...interface{}) {
	l.log(InfoLevel, msg, keysAndValues...)
}

// Warn logs a warning message
func (l *Logger) Warn(msg string, keysAndValues ...interface{}) {
	l.log(WarnLevel, msg, keysAndValues...)
}

// Error logs an error message
func (l *Logger) Error(msg string, keysAndValues ...interface{}) {
	l.log(ErrorLevel, msg, keysAndValues...)
}
