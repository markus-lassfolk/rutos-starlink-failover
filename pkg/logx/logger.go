// Package logx provides structured logging for the starfail daemon
package logx

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"
)

// LogLevel represents the logging level
type LogLevel int

const (
	DebugLevel LogLevel = iota
	InfoLevel
	WarnLevel
	ErrorLevel
)

// Logger provides structured JSON logging
type Logger struct {
	level     LogLevel
	logger    *log.Logger
	syslogger interface{} // Platform-specific syslog writer (Unix only)
	fields    map[string]interface{}
}

// New creates a new structured logger
func New(levelStr string) *Logger {
	level := parseLevel(levelStr)
	l := &Logger{
		level:  level,
		logger: log.New(os.Stdout, "", 0), // No prefix, we'll format everything in JSON
		fields: make(map[string]interface{}),
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
		syslogger: l.syslogger,
		fields:    newFields,
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

// log outputs a structured log entry
func (l *Logger) log(level LogLevel, msg string, keysAndValues ...interface{}) {
	if level < l.level {
		return
	}

	entry := logEntry{
		Timestamp: time.Now().UTC().Format(time.RFC3339),
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

	// Marshal to JSON
	jsonBytes, err := json.Marshal(entry)
	if err != nil {
		// Fallback to simple log if JSON marshaling fails
		l.logger.Printf("LOG_ERROR: failed to marshal log entry: %v", err)
		return
	}

	jsonStr := string(jsonBytes)
	
	// Output to stdout (for procd/logread)
	l.logger.Println(jsonStr)
	
	// Also send to syslog if available (Unix only)
	l.logToSyslog(level, jsonStr)
}

// levelString converts LogLevel to string
func levelString(level LogLevel) string {
	switch level {
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
