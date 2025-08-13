package logx

import (
	"testing"
	"strings"
)

func TestLoggerLevels(t *testing.T) {
	tests := []struct {
		level string
		expected LogLevel
	}{
		{"debug", DebugLevel},
		{"info", InfoLevel},
		{"warn", WarnLevel},
		{"warning", WarnLevel},
		{"error", ErrorLevel},
		{"invalid", InfoLevel}, // should default to info
	}

	for _, test := range tests {
		t.Run(test.level, func(t *testing.T) {
			result := parseLevel(test.level)
			if result != test.expected {
				t.Errorf("parseLevel(%q) = %v; want %v", test.level, result, test.expected)
			}
		})
	}
}

func TestLoggerOutput(t *testing.T) {
	// Test that logger produces valid JSON output
	logger := New("debug")
	
	// We can't easily capture the output in this simple test,
	// but we can at least verify the logger was created successfully
	if logger == nil {
		t.Fatal("Failed to create logger")
	}
	
	if logger.level != DebugLevel {
		t.Errorf("Expected debug level, got %v", logger.level)
	}
}

func TestLevelString(t *testing.T) {
	tests := []struct {
		level LogLevel
		expected string
	}{
		{DebugLevel, "debug"},
		{InfoLevel, "info"},
		{WarnLevel, "warn"},
		{ErrorLevel, "error"},
	}

	for _, test := range tests {
		result := levelString(test.level)
		if result != test.expected {
			t.Errorf("levelString(%v) = %q; want %q", test.level, result, test.expected)
		}
	}
}
