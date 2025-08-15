package retry

import (
	"context"
	"runtime"
	"strings"
	"testing"
	"time"
)

func getTestCommand() (success []string, failure []string) {
	if runtime.GOOS == "windows" {
		return []string{"cmd", "/c", "echo", "test"}, []string{"cmd", "/c", "exit", "1"}
	}
	return []string{"echo", "test"}, []string{"false"}
}

func TestRunnerSuccessFirstAttempt(t *testing.T) {
	runner := NewRunner(DefaultConfig())

	// Should succeed immediately with a simple command
	success, _ := getTestCommand()
	err := runner.Run(context.Background(), success[0], success[1:]...)
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}
}

func TestRunnerRetryOnFailure(t *testing.T) {
	config := Config{
		MaxAttempts:   3,
		InitialDelay:  10 * time.Millisecond,
		MaxDelay:      100 * time.Millisecond,
		BackoffFactor: 2.0,
	}
	runner := NewRunner(config)

	start := time.Now()
	// This command should fail all attempts
	_, failure := getTestCommand()
	err := runner.Run(context.Background(), failure[0], failure[1:]...)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("expected error from failure command")
	}

	// Should have taken at least some time for retries
	minExpected := 10*time.Millisecond + 20*time.Millisecond // first retry + second retry
	if elapsed < minExpected {
		t.Errorf("expected at least %v for retries, got %v", minExpected, elapsed)
	}
}

func TestRunnerOutputSuccess(t *testing.T) {
	runner := NewRunner(DefaultConfig())

	success, _ := getTestCommand()
	output, err := runner.Output(context.Background(), success[0], success[1:]...)
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}

	expected := "test"
	outputStr := string(output)
	// Trim whitespace since Windows/Unix might differ in newline format
	outputStr = strings.TrimSpace(outputStr)
	if outputStr != expected {
		t.Errorf("expected %q, got %q", expected, outputStr)
	}
}

func TestRunnerContextCancellation(t *testing.T) {
	config := Config{
		MaxAttempts:   5,
		InitialDelay:  100 * time.Millisecond,
		MaxDelay:      1 * time.Second,
		BackoffFactor: 2.0,
	}
	runner := NewRunner(config)

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	start := time.Now()
	err := runner.Run(ctx, "false") // This will fail and retry
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("expected context cancellation error")
	}

	// Should respect context timeout
	if elapsed > 200*time.Millisecond {
		t.Errorf("took too long: %v", elapsed)
	}
}

func TestDefaultConfig(t *testing.T) {
	config := DefaultConfig()

	if config.MaxAttempts != 3 {
		t.Errorf("expected MaxAttempts=3, got %d", config.MaxAttempts)
	}
	if config.InitialDelay != 100*time.Millisecond {
		t.Errorf("expected InitialDelay=100ms, got %v", config.InitialDelay)
	}
}
