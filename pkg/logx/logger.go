package logx

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/sirupsen/logrus"
)

// Logger provides structured JSON logging
type Logger struct {
	logger *logrus.Logger
}

// NewLogger creates a new structured logger
func NewLogger() *Logger {
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{
		TimestampFormat: time.RFC3339,
		FieldMap: logrus.FieldMap{
			logrus.FieldKeyTime:  "ts",
			logrus.FieldKeyLevel: "level",
			logrus.FieldKeyMsg:   "msg",
		},
	})
	logger.SetOutput(os.Stdout)
	logger.SetLevel(logrus.InfoLevel)

	return &Logger{logger: logger}
}

// SetLevel sets the logging level
func (l *Logger) SetLevel(level string) {
	switch level {
	case "debug":
		l.logger.SetLevel(logrus.DebugLevel)
	case "info":
		l.logger.SetLevel(logrus.InfoLevel)
	case "warn":
		l.logger.SetLevel(logrus.WarnLevel)
	case "error":
		l.logger.SetLevel(logrus.ErrorLevel)
	default:
		l.logger.SetLevel(logrus.InfoLevel)
	}
}

// SetOutput sets the output destination
func (l *Logger) SetOutput(w io.Writer) {
	l.logger.SetOutput(w)
}

// Debug logs a debug message with fields
func (l *Logger) Debug(msg string, fields ...interface{}) {
	l.logger.WithFields(parseFields(fields...)).Debug(msg)
}

// Info logs an info message with fields
func (l *Logger) Info(msg string, fields ...interface{}) {
	l.logger.WithFields(parseFields(fields...)).Info(msg)
}

// Warn logs a warning message with fields
func (l *Logger) Warn(msg string, fields ...interface{}) {
	l.logger.WithFields(parseFields(fields...)).Warn(msg)
}

// Error logs an error message with fields
func (l *Logger) Error(msg string, fields ...interface{}) {
	l.logger.WithFields(parseFields(fields...)).Error(msg)
}

// WithField returns a logger with a single field
func (l *Logger) WithField(key string, value interface{}) *Logger {
	return &Logger{logger: l.logger.WithField(key, value).Logger}
}

// WithFields returns a logger with multiple fields
func (l *Logger) WithFields(fields map[string]interface{}) *Logger {
	return &Logger{logger: l.logger.WithFields(logrus.Fields(fields)).Logger}
}

// parseFields converts variadic arguments to logrus.Fields
func parseFields(fields ...interface{}) logrus.Fields {
	result := make(logrus.Fields)
	
	for i := 0; i < len(fields); i += 2 {
		if i+1 < len(fields) {
			key, ok := fields[i].(string)
			if ok {
				result[key] = fields[i+1]
			}
		}
	}
	
	return result
}

// LogEvent logs a structured event
func (l *Logger) LogEvent(eventType, member string, data map[string]interface{}) {
	fields := logrus.Fields{
		"event_type": eventType,
		"member":     member,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("event")
}

// LogMetrics logs member metrics
func (l *Logger) LogMetrics(member string, metrics map[string]interface{}) {
	fields := logrus.Fields{
		"member": member,
	}
	
	for k, v := range metrics {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Debug("metrics")
}

// LogDecision logs a decision event
func (l *Logger) LogDecision(decisionType, from, to string, data map[string]interface{}) {
	fields := logrus.Fields{
		"decision_type": decisionType,
		"from":          from,
		"to":            to,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("decision")
}

// LogDiscovery logs member discovery events
func (l *Logger) LogDiscovery(member, class, iface string, data map[string]interface{}) {
	fields := logrus.Fields{
		"member": member,
		"class":  class,
		"iface":  iface,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("discovery")
}

// LogError logs an error with context
func (l *Logger) LogError(err error, context map[string]interface{}) {
	fields := logrus.Fields{
		"error": err.Error(),
	}
	
	for k, v := range context {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Error("error")
}

// LogConfig logs configuration changes
func (l *Logger) LogConfig(action string, data map[string]interface{}) {
	fields := logrus.Fields{
		"action": action,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("config")
}

// LogThrottle logs throttling events
func (l *Logger) LogThrottle(what string, cooldownS, remainingS int) {
	l.logger.WithFields(logrus.Fields{
		"what":          what,
		"cooldown_s":    cooldownS,
		"remaining_s":   remainingS,
	}).Warn("throttle")
}

// LogSwitch logs interface switching events
func (l *Logger) LogSwitch(from, to, reason string, delta float64, data map[string]interface{}) {
	fields := logrus.Fields{
		"from":    from,
		"to":      to,
		"reason":  reason,
		"delta":   delta,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("switch")
}

// LogSample logs metric samples (debug level)
func (l *Logger) LogSample(member string, metrics map[string]interface{}) {
	fields := logrus.Fields{
		"member": member,
	}
	
	for k, v := range metrics {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Debug("sample")
}

// LogProvider logs provider selection and errors
func (l *Logger) LogProvider(member, provider string, data map[string]interface{}) {
	fields := logrus.Fields{
		"member":   member,
		"provider": provider,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("provider")
}

// LogMWAN3 logs mwan3-related events
func (l *Logger) LogMWAN3(action string, data map[string]interface{}) {
	fields := logrus.Fields{
		"action": action,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("mwan3")
}

// LogMemory logs memory usage and pressure events
func (l *Logger) LogMemory(usageMB, maxMB int, action string) {
	l.logger.WithFields(logrus.Fields{
		"usage_mb": usageMB,
		"max_mb":   maxMB,
		"action":   action,
	}).Warn("memory")
}

// LogPerformance logs performance metrics
func (l *Logger) LogPerformance(operation string, duration time.Duration, data map[string]interface{}) {
	fields := logrus.Fields{
		"operation": operation,
		"duration":  duration.String(),
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Debug("performance")
}

// LogStartup logs startup information
func (l *Logger) LogStartup(version string, data map[string]interface{}) {
	fields := logrus.Fields{
		"version": version,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("startup")
}

// LogShutdown logs shutdown information
func (l *Logger) LogShutdown(reason string, data map[string]interface{}) {
	fields := logrus.Fields{
		"reason": reason,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("shutdown")
}

// LogUptime logs uptime and health information
func (l *Logger) LogUptime(uptime time.Duration, data map[string]interface{}) {
	fields := logrus.Fields{
		"uptime": uptime.String(),
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("uptime")
}

// LogValidation logs validation events
func (l *Logger) LogValidation(component string, valid bool, data map[string]interface{}) {
	fields := logrus.Fields{
		"component": component,
		"valid":     valid,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	level := logrus.InfoLevel
	if !valid {
		level = logrus.WarnLevel
	}
	
	l.logger.WithFields(fields).Log(level, "validation")
}

// LogReload logs configuration reload events
func (l *Logger) LogReload(source string, data map[string]interface{}) {
	fields := logrus.Fields{
		"source": source,
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Info("reload")
}

// LogHeartbeat logs periodic heartbeat information
func (l *Logger) LogHeartbeat(interval time.Duration, data map[string]interface{}) {
	fields := logrus.Fields{
		"interval": interval.String(),
	}
	
	for k, v := range data {
		fields[k] = v
	}
	
	l.logger.WithFields(fields).Debug("heartbeat")
}
