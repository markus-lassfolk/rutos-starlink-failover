// Package retry provides command execution with retries and exponential backoff
package retry

import (
	"context"
	"fmt"
	"math"
	"os/exec"
	"time"
)

// Config controls retry behavior
type Config struct {
	MaxAttempts   int           `json:"max_attempts"`
	InitialDelay  time.Duration `json:"initial_delay"`
	MaxDelay      time.Duration `json:"max_delay"`
	BackoffFactor float64       `json:"backoff_factor"`
}

// DefaultConfig returns sensible retry defaults
func DefaultConfig() Config {
	return Config{
		MaxAttempts:   3,
		InitialDelay:  100 * time.Millisecond,
		MaxDelay:      5 * time.Second,
		BackoffFactor: 2.0,
	}
}

// Runner executes commands with retry logic
type Runner struct {
	config Config
}

// NewRunner creates a new retry-enabled command runner
func NewRunner(config Config) *Runner {
	if config.MaxAttempts <= 0 {
		config.MaxAttempts = 1
	}
	if config.InitialDelay <= 0 {
		config.InitialDelay = 100 * time.Millisecond
	}
	if config.MaxDelay <= 0 {
		config.MaxDelay = 5 * time.Second
	}
	if config.BackoffFactor <= 1.0 {
		config.BackoffFactor = 2.0
	}
	return &Runner{config: config}
}

// Output executes a command and returns output with retries on failure
func (r *Runner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
	var lastErr error
	for attempt := 0; attempt < r.config.MaxAttempts; attempt++ {
		if attempt > 0 {
			// Wait with exponential backoff
			delay := r.calculateDelay(attempt)
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(delay):
				// Continue to retry
			}
		}

		output, err := exec.CommandContext(ctx, name, args...).Output()
		if err == nil {
			return output, nil
		}
		lastErr = err
	}
	return nil, fmt.Errorf("command failed after %d attempts: %w", r.config.MaxAttempts, lastErr)
}

// Run executes a command with retries on failure
func (r *Runner) Run(ctx context.Context, name string, args ...string) error {
	var lastErr error
	for attempt := 0; attempt < r.config.MaxAttempts; attempt++ {
		if attempt > 0 {
			// Wait with exponential backoff
			delay := r.calculateDelay(attempt)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(delay):
				// Continue to retry
			}
		}

		err := exec.CommandContext(ctx, name, args...).Run()
		if err == nil {
			return nil
		}
		lastErr = err
	}
	return fmt.Errorf("command failed after %d attempts: %w", r.config.MaxAttempts, lastErr)
}

// calculateDelay computes the delay for the given attempt using exponential backoff
func (r *Runner) calculateDelay(attempt int) time.Duration {
	delay := float64(r.config.InitialDelay) * math.Pow(r.config.BackoffFactor, float64(attempt-1))
	if delay > float64(r.config.MaxDelay) {
		delay = float64(r.config.MaxDelay)
	}
	return time.Duration(delay)
}
