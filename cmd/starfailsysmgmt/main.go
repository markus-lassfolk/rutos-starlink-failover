package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/sysmgmt"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

var (
	configFile = flag.String("config", "/etc/config/starfail", "Configuration file path")
	logLevel   = flag.String("log-level", "info", "Log level (debug|info|warn|error|trace)")
	dryRun     = flag.Bool("dry-run", false, "Dry run mode - don't make changes")
	checkOnly  = flag.Bool("check", false, "Check mode only - don't fix issues")
	interval   = flag.Duration("interval", 5*time.Minute, "Check interval when running as daemon")
	monitor    = flag.Bool("monitor", false, "Run in monitoring mode with verbose output")
	verbose    = flag.Bool("verbose", false, "Enable verbose logging (equivalent to trace level)")
	foreground = flag.Bool("foreground", false, "Run in foreground mode (don't daemonize)")
)

func main() {
	flag.Parse()

	// Determine log level
	effectiveLogLevel := *logLevel
	if *verbose || *monitor {
		effectiveLogLevel = "trace"
	}

	// Initialize logger
	logger := logx.NewLogger(effectiveLogLevel, "starfailsysmgmt")
	logger.Info("Starting Starfail System Management", "version", "1.0.0")
	
	// Log monitoring mode status
	if *monitor {
		logger.Info("Running in monitoring mode", "verbose_logging", true, "foreground", *foreground)
		logger.LogVerbose("monitoring_mode_enabled", map[string]interface{}{
			"log_level": effectiveLogLevel,
			"dry_run":   *dryRun,
			"check_only": *checkOnly,
			"verbose":   *verbose,
		})
	}

	// Load configuration
	config, err := sysmgmt.LoadConfig(*configFile)
	if err != nil {
		logger.Error("Failed to load configuration", "error", err)
		os.Exit(1)
	}

	// Create system manager
	manager := sysmgmt.NewManager(config, logger, *dryRun)

	// Handle signals for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Run in daemon mode or single check mode
	if !*checkOnly {
		logger.Info("Running in daemon mode", "interval", *interval)
		go func() {
			ticker := time.NewTicker(*interval)
			defer ticker.Stop()

			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					if err := manager.RunHealthCheck(ctx); err != nil {
						logger.Error("Health check failed", "error", err)
					}
				}
			}
		}()

		// Wait for shutdown signal
		<-sigChan
		logger.Info("Shutting down system manager")
	} else {
		// Single check mode
		logger.Info("Running single health check")
		if err := manager.RunHealthCheck(ctx); err != nil {
			logger.Error("Health check failed", "error", err)
			os.Exit(1)
		}
		logger.Info("Health check completed successfully")
	}
}
