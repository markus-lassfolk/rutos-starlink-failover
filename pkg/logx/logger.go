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
	level  LogLevel
	logger *log.Logger
}

// New creates a new structured logger
func New(levelStr string) *Logger {
	level := parseLevel(levelStr)
	return &Logger{
		level:  level,
		logger: log.New(os.Stdout, "", 0), // No prefix, we'll format everything in JSON
	}
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

	// Parse key-value pairs
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

	l.logger.Println(string(jsonBytes))
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
