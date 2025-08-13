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
	
	switch level {
	case DebugLevel:
		l.syslogger.Debug(message)
	case InfoLevel:
		l.syslogger.Info(message)
	case WarnLevel:
		l.syslogger.Warning(message)
	case ErrorLevel:
		l.syslogger.Err(message)
	}
}
