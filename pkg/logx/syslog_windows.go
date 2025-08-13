//go:build windows
// +build windows

// Package logx provides structured logging for starfail daemon (Windows version)
package logx

// initSyslog is a no-op on Windows
func (l *Logger) initSyslog() {
	// Syslog not available on Windows - no-op
}

// logToSyslog is a no-op on Windows
func (l *Logger) logToSyslog(level LogLevel, message string) {
	// Syslog not available on Windows - no-op
}
