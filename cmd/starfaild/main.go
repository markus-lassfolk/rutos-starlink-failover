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

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

const (
	version = "1.0.0-dev"
	appName = "starfaild"
)

var (
	configFile = flag.String("config", "/etc/config/starfail", "UCI config file path")
	logLevel   = flag.String("log-level", "info", "Log level (debug|info|warn|error)")
	version_   = flag.Bool("version", false, "Show version and exit")
)

func main() {
	flag.Parse()

	if *version_ {
		fmt.Printf("%s %s\n", appName, version)
		os.Exit(0)
	}

	// Initialize structured logger
	logger := logx.New(*logLevel)
	logger.Info("starting starfail daemon", 
		"version", version,
		"config", *configFile,
	)

	// Setup signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)

	// TODO: Initialize components
	// - UCI config loader
	// - Member discovery
	// - Metric collectors
	// - Decision engine
	// - Controllers (mwan3/netifd)
	// - ubus API server
	// - Telemetry store

	// Main daemon loop
	ticker := time.NewTicker(1500 * time.Millisecond) // 1.5s default tick
	defer ticker.Stop()

	logger.Info("daemon started successfully")

	for {
		select {
		case sig := <-sigChan:
			switch sig {
			case syscall.SIGHUP:
				logger.Info("received SIGHUP, reloading configuration")
				// TODO: Reload config
			case syscall.SIGINT, syscall.SIGTERM:
				logger.Info("received shutdown signal", "signal", sig.String())
				cancel()
				return
			}

		case <-ticker.C:
			// TODO: Main tick logic
			// 1. Discover/refresh members
			// 2. Collect metrics per member
			// 3. Update scores
			// 4. Evaluate switch conditions
			// 5. Apply decisions
			// 6. Update telemetry
			logger.Debug("tick")

		case <-ctx.Done():
			logger.Info("daemon shutting down")
			return
		}
	}
}
