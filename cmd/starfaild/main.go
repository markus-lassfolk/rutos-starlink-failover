package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/starfail/starfail/pkg/controller"
	"github.com/starfail/starfail/pkg/decision"
	"github.com/starfail/starfail/pkg/discovery"
	"github.com/starfail/starfail/pkg/health"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/metrics"
	"github.com/starfail/starfail/pkg/mqtt"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/ubus"
	"github.com/starfail/starfail/pkg/uci"
)

var (
	configPath = flag.String("config", "/etc/config/starfail", "Path to UCI configuration file")
	logLevel   = flag.String("log-level", "", "Override log level (debug|info|warn|error)")
	version    = flag.Bool("version", false, "Show version information")
)

const (
	AppName    = "starfaild"
	AppVersion = "1.0.0"
)

func main() {
	flag.Parse()

	if *version {
		fmt.Printf("%s version %s\n", AppName, AppVersion)
		os.Exit(0)
	}

	// Initialize logger
	logger := logx.NewLogger()
	if *logLevel != "" {
		logger.SetLevel(*logLevel)
	}

	logger.Info("Starting starfail daemon", "version", AppVersion)

	// Load configuration
	cfg, err := uci.LoadConfig(*configPath)
	if err != nil {
		logger.Error("Failed to load configuration", "error", err, "path", *configPath)
		os.Exit(1)
	}

	// Apply log level override if specified
	if *logLevel != "" {
		cfg.LogLevel = *logLevel
		logger.SetLevel(cfg.LogLevel)
	}

	logger.Info("Configuration loaded", "predictive", cfg.Predictive, "use_mwan3", cfg.UseMWAN3)

	// Initialize telemetry store
	telemetry, err := telem.NewStore(cfg.RetentionHours, cfg.MaxRAMMB)
	if err != nil {
		logger.Error("Failed to initialize telemetry store", "error", err)
		os.Exit(1)
	}
	defer telemetry.Close()

	// Initialize decision engine
	decisionEngine := decision.NewEngine(cfg, logger, telemetry)

	// Initialize discovery system
	discoverer := discovery.NewDiscoverer(logger)

	// Discover initial members
	members, err := discoverer.DiscoverMembers()
	if err != nil {
		logger.Error("Failed to discover members", "error", err)
		os.Exit(1)
	}

	logger.Info("Initial member discovery completed", "count", len(members))

	// Initialize controller with discovered members
	ctrl, err := controller.NewController(cfg, logger)
	if err != nil {
		logger.Error("Failed to initialize controller", "error", err)
		os.Exit(1)
	}

	// Set discovered members in controller
	ctrl.SetMembers(members)

	// Initialize ubus server
	ubusServer := ubus.NewServer(ctrl, decisionEngine, telemetry, logger)

	// Start ubus server
	if err := ubusServer.Start(); err != nil {
		logger.Error("Failed to start ubus server", "error", err)
		os.Exit(1)
	}
	defer ubusServer.Stop()

	// Initialize and start metrics server if enabled
	var metricsServer *metrics.Server
	if cfg.MetricsListener {
		metricsServer = metrics.NewServer(ctrl, decisionEngine, telemetry, logger)
		if err := metricsServer.Start(cfg.MetricsPort); err != nil {
			logger.Error("Failed to start metrics server", "error", err)
			os.Exit(1)
		}
		defer metricsServer.Stop()
	}

	// Initialize and start health server if enabled
	var healthServer *health.Server
	if cfg.HealthListener {
		healthServer = health.NewServer(ctrl, decisionEngine, telemetry, logger)
		if err := healthServer.Start(cfg.HealthPort); err != nil {
			logger.Error("Failed to start health server", "error", err)
			os.Exit(1)
		}
		defer healthServer.Stop()
	}

	// Initialize MQTT client if enabled
	var mqttClient *mqtt.Client
	if cfg.MQTT.Enabled {
		mqttClient = mqtt.NewClient(&cfg.MQTT, logger)
		if err := mqttClient.Connect(); err != nil {
			logger.Error("Failed to connect to MQTT broker", "error", err)
			// Don't exit, MQTT is optional
		} else {
			defer mqttClient.Disconnect()
		}
	}

	// Setup signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)

	// Start main loop
	go runMainLoop(ctx, cfg, decisionEngine, ctrl, logger, telemetry, discoverer, metricsServer, healthServer, mqttClient)

	// Wait for shutdown signal
	sig := <-sigChan
	logger.Info("Received shutdown signal", "signal", sig)

	// Graceful shutdown
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	// Stop the main loop
	cancel()

	// Wait for shutdown or timeout
	select {
	case <-shutdownCtx.Done():
		logger.Warn("Shutdown timeout exceeded")
	case <-time.After(5 * time.Second):
		logger.Info("Graceful shutdown completed")
	}
}

func runMainLoop(ctx context.Context, cfg *uci.Config, engine *decision.Engine, ctrl *controller.Controller, logger *logx.Logger, telemetry *telem.Store, discoverer *discovery.Discoverer, metricsServer *metrics.Server, healthServer *health.Server, mqttClient *mqtt.Client) {
	// Create tickers for different intervals
	decisionTicker := time.NewTicker(time.Duration(cfg.DecisionIntervalMS) * time.Millisecond)
	discoveryTicker := time.NewTicker(time.Duration(cfg.DiscoveryIntervalMS) * time.Millisecond)
	cleanupTicker := time.NewTicker(time.Duration(cfg.CleanupIntervalMS) * time.Millisecond)
	
	defer decisionTicker.Stop()
	defer discoveryTicker.Stop()
	defer cleanupTicker.Stop()

	logger.Info("Starting main loop", map[string]interface{}{
		"decision_interval_ms":  cfg.DecisionIntervalMS,
		"discovery_interval_ms": cfg.DiscoveryIntervalMS,
		"cleanup_interval_ms":   cfg.CleanupIntervalMS,
	})

	for {
		select {
		case <-ctx.Done():
			logger.Info("Main loop stopped")
			return
			
		case <-decisionTicker.C:
			// Run decision engine tick
			if err := engine.Tick(ctrl); err != nil {
				logger.Error("Error in decision engine tick", map[string]interface{}{
					"error": err.Error(),
				})
			}
			
			// Update metrics if server is running
			if metricsServer != nil {
				metricsServer.UpdateMetrics()
			}
			
		case <-discoveryTicker.C:
			// Refresh member discovery
			currentMembers := ctrl.GetMembers()
			newMembers, err := discoverer.RefreshMembers(currentMembers)
			if err != nil {
				logger.Error("Error refreshing members", map[string]interface{}{
					"error": err.Error(),
				})
			} else {
				// Update controller with new members
				ctrl.SetMembers(newMembers)
				logger.Debug("Member discovery refreshed", map[string]interface{}{
					"member_count": len(newMembers),
				})
			}
			
		case <-cleanupTicker.C:
			// Perform periodic cleanup
			if err := telemetry.Cleanup(); err != nil {
				logger.Error("Error during telemetry cleanup", map[string]interface{}{
					"error": err.Error(),
				})
			}
		}
	}
}

// These functions are no longer needed as the servers are now properly integrated
