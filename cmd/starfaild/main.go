package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/uci"
)

const (
	version = "1.0.0-dev"
	appName = "starfaild"
)

func main() {
	// Command line flags
	var (
		configFile  = flag.String("config", "/etc/config/starfail", "UCI config file path")
		logLevel    = flag.String("log-level", "info", "Log level (debug|info|warn|error)")
		showVersion = flag.Bool("version", false, "Show version and exit")
		verbose     = flag.Bool("verbose", false, "Enable verbose logging")
		trace       = flag.Bool("trace", false, "Enable trace logging")
	)
	flag.Parse()

	if *showVersion {
		fmt.Printf("%s version %s\n", appName, version)
		os.Exit(0)
	}

	// Setup logging
	effectiveLogLevel := *logLevel
	if *trace {
		effectiveLogLevel = "debug"
	}

	logger := logx.New(effectiveLogLevel)
	if logger == nil {
		fmt.Fprintf(os.Stderr, "Failed to create logger\n")
		os.Exit(1)
	}

	// Basic startup message
	if *verbose || *trace {
		logger.Info("🚀 Starting starfail daemon in MONITORING MODE",
			"version", version,
			"config", *configFile,
			"log_level", effectiveLogLevel,
			"trace", *trace,
			"verbose", *verbose,
		)
	} else {
		logger.Info("starting starfail daemon",
			"version", version,
			"config", *configFile,
			"log_level", effectiveLogLevel,
		)
	}

	// Load UCI configuration
	uciLoader := uci.NewLoader(*configFile)
	config, err := uciLoader.Load()
	if err != nil {
		logger.Error("Failed to load UCI config", "error", err, "config_file", *configFile)
		os.Exit(1)
	}

	logger.Info("Configuration loaded successfully",
		"members", len(config.Members),
		"main_enabled", config.Main.Enable,
	)

	// Setup signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// Main loop - just log that we're running
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	logger.Info("Starfail daemon started successfully")

	for {
		select {
		case <-ctx.Done():
			logger.Info("Context cancelled, shutting down")
			return
		case sig := <-sigCh:
			logger.Info("Received signal, shutting down", "signal", sig)
			cancel()
		case <-ticker.C:
			logger.Debug("Daemon heartbeat", "uptime", time.Since(time.Now()).String())
		}
	}
}
