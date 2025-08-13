//go:build !windows
// +build !windows

// Package logx provides structured logging for starfail daemon (Unix/Linux version)
package logx

import (
	"log/syslog"
)

// initSyslog initializes syslog for Unix systems (RutOS/OpenWrt)
func (l *Logger) initSyslog() {
	if syslogger, err := syslog.New(syslog.LOG_DAEMON|syslog.LOG_INFO, "starfaild"); err == nil {
		l.syslogger = syslogger
	}
}

// logToSyslog sends log entry to syslog on Unix systems
func (l *Logger) logToSyslog(level LogLevel, message string) {
	if l.syslogger == nil {
		return
	}

	// Type assert to syslog.Writer
	writer, ok := l.syslogger.(*syslog.Writer)
	if !ok {
		return
	}

	switch level {
	case DebugLevel:
		writer.Debug(message)
	case InfoLevel:
		writer.Info(message)
	case WarnLevel:
		writer.Warning(message)
	case ErrorLevel:
		writer.Err(message)
	}
}
