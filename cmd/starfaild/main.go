package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/collector"
	"github.com/starfail/starfail/pkg/controller"
	"github.com/starfail/starfail/pkg/decision"
	"github.com/starfail/starfail/pkg/discovery"
	"github.com/starfail/starfail/pkg/health"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/metrics"
	"github.com/starfail/starfail/pkg/mqtt"
	"github.com/starfail/starfail/pkg/performance"
	"github.com/starfail/starfail/pkg/security"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/ubus"
	"github.com/starfail/starfail/pkg/uci"
)

var (
	configPath = flag.String("config", "/etc/config/starfail", "Path to UCI configuration file")
	logLevel   = flag.String("log-level", "", "Override log level (debug|info|warn|error|trace)")
	version    = flag.Bool("version", false, "Show version information")
	profile    = flag.Bool("profile", false, "Enable performance profiling")
	audit      = flag.Bool("audit", false, "Enable security auditing")
	monitor    = flag.Bool("monitor", false, "Run in monitoring mode with verbose output")
	verbose    = flag.Bool("verbose", false, "Enable verbose logging (equivalent to trace level)")
	foreground = flag.Bool("foreground", false, "Run in foreground mode (don't daemonize)")
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

	// Determine log level
	effectiveLogLevel := "info"
	if *logLevel != "" {
		effectiveLogLevel = *logLevel
	}
	if *verbose || *monitor {
		effectiveLogLevel = "trace"
	}

	// Initialize logger with component name
	logger := logx.NewLogger(effectiveLogLevel, "starfaild")

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

	// Log monitoring mode status
	if *monitor {
		logger.Info("Running in monitoring mode", "verbose_logging", true, "foreground", *foreground)
		logger.LogVerbose("monitoring_mode_enabled", map[string]interface{}{
			"log_level": effectiveLogLevel,
			"profile":   *profile,
			"audit":     *audit,
			"verbose":   *verbose,
		})
	}

	// Initialize telemetry store
	telemetry, err := telem.NewStore(cfg.RetentionHours, cfg.MaxRAMMB)
	if err != nil {
		logger.Error("Failed to initialize telemetry store", "error", err)
		os.Exit(1)
	}
	defer telemetry.Close()

	// Initialize performance profiler
	var profiler *performance.Profiler
	if *profile || cfg.PerformanceProfiling {
		profiler = performance.NewProfiler(true, 30*time.Second, 1000, logger)
		profiler.Start(context.Background())
		defer profiler.Stop()
		logger.Info("Performance profiler enabled")
	}

	// Initialize security auditor
	var auditor *security.Auditor
	if *audit || cfg.SecurityAuditing {
		auditConfig := &security.AuditConfig{
			Enabled:           true,
			LogLevel:          cfg.LogLevel,
			MaxEvents:         1000,
			RetentionDays:     30,
			FileIntegrity:     true,
			NetworkSecurity:   true,
			AccessControl:     true,
			ThreatDetection:   true,
			CriticalFiles:     []string{"/etc/config/starfail", "/usr/sbin/starfaild"},
			AllowedIPs:        cfg.AllowedIPs,
			BlockedIPs:        cfg.BlockedIPs,
			AllowedPorts:      []int{8080, 9090},
			BlockedPorts:      []int{22, 23, 25},
			MaxFailedAttempts: 5,
			BlockDuration:     24,
		}
		auditor = security.NewAuditor(auditConfig, logger)
		auditor.Start(context.Background())
		defer auditor.Stop()
		logger.Info("Security auditor enabled")
	}

	// Predictive configuration is handled internally by the decision engine

	// Initialize decision engine with predictive capabilities
	decisionEngine := decision.NewEngine(cfg, logger, telemetry)
	if cfg.Predictive {
		logger.Info("Predictive failover engine enabled via configuration")
	}

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
	if err := ctrl.SetMembers(members); err != nil {
		logger.Error("Failed to set members", "error", err)
		os.Exit(1)
	}

	// Initialize collector factory with UCI configuration
	collectorConfig := map[string]interface{}{
		"timeout":              time.Duration(cfg.StarlinkTimeout) * time.Second,
		"targets":              []string{"8.8.8.8", "1.1.1.1", "1.0.0.1"},
		"ubus_path":            "ubus",
		"starlink_api_host":    cfg.StarlinkAPIHost,
		"starlink_api_port":    cfg.StarlinkAPIPort,
		"starlink_timeout_s":   cfg.StarlinkTimeout,
		"starlink_grpc_first":  cfg.StarlinkGRPCFirst,
		"starlink_http_first":  cfg.StarlinkHTTPFirst,
	}
	collectorFactory := collector.NewCollectorFactory(collectorConfig)

	// Add discovered members to decision engine
	for _, member := range members {
		decisionEngine.AddMember(member)
		logger.Info("Added member to decision engine", "member", member.Name, "class", member.Class)
	}

	// Initialize ubus server
	ubusServer := ubus.NewServer(ctrl, decisionEngine, telemetry, logger)

	// Start ubus server
	if err := ubusServer.Start(context.Background()); err != nil {
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
		// Convert UCI MQTT config to MQTT client config
		mqttConfig := &mqtt.Config{
			Broker:      cfg.MQTT.Broker,
			Port:        cfg.MQTT.Port,
			ClientID:    cfg.MQTT.ClientID,
			Username:    cfg.MQTT.Username,
			Password:    cfg.MQTT.Password,
			TopicPrefix: cfg.MQTT.TopicPrefix,
			QoS:         cfg.MQTT.QoS,
			Retain:      cfg.MQTT.Retain,
			Enabled:     cfg.MQTT.Enabled,
		}
		mqttClient = mqtt.NewClient(mqttConfig, logger)
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
	go runMainLoop(ctx, cfg, decisionEngine, ctrl, logger, telemetry, discoverer, collectorFactory, metricsServer, healthServer, mqttClient, profiler, auditor)

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

func runMainLoop(ctx context.Context, cfg *uci.Config, engine *decision.Engine, ctrl *controller.Controller, logger *logx.Logger, telemetry *telem.Store, discoverer *discovery.Discoverer, collectorFactory *collector.CollectorFactory, metricsServer *metrics.Server, healthServer *health.Server, mqttClient *mqtt.Client, profiler *performance.Profiler, auditor *security.Auditor) {
	// Set up event publishing callback if MQTT is enabled
	if mqttClient != nil && cfg.MQTT.Enabled {
		// Create a callback function for real-time event publishing
		eventPublisher := func(event *pkg.Event) {
			eventData := map[string]interface{}{
				"timestamp": event.Timestamp.Unix(),
				"type":      event.Type,
				"reason":    event.Reason,
				"member":    event.Member,
				"from":      event.From,
				"to":        event.To,
				"data":      event.Data,
			}

			if err := mqttClient.PublishEvent(eventData); err != nil {
				logger.Warn("Failed to publish real-time event to MQTT", "event_type", event.Type, "error", err)
			} else {
				logger.Debug("Published real-time event to MQTT", "event_type", event.Type)
			}
		}

		// Add the callback to telemetry store for immediate publishing
		telemetry.SetEventCallback(eventPublisher)
	}
	// Create tickers for different intervals
	decisionTicker := time.NewTicker(time.Duration(cfg.DecisionIntervalMS) * time.Millisecond)
	discoveryTicker := time.NewTicker(time.Duration(cfg.DiscoveryIntervalMS) * time.Millisecond)
	cleanupTicker := time.NewTicker(time.Duration(cfg.CleanupIntervalMS) * time.Millisecond)
	securityTicker := time.NewTicker(2 * time.Minute)
	performanceTicker := time.NewTicker(1 * time.Minute)
	mqttTicker := time.NewTicker(30 * time.Second) // Publish telemetry every 30 seconds

	defer decisionTicker.Stop()
	defer discoveryTicker.Stop()
	defer cleanupTicker.Stop()
	defer securityTicker.Stop()
	defer performanceTicker.Stop()
	defer mqttTicker.Stop()

	logger.Info("Starting main loop", map[string]interface{}{
		"decision_interval_ms":  cfg.DecisionIntervalMS,
		"discovery_interval_ms": cfg.DiscoveryIntervalMS,
		"cleanup_interval_ms":   cfg.CleanupIntervalMS,
		"predictive":            cfg.Predictive,
		"profiling":             profiler != nil,
		"auditing":              auditor != nil,
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
				if err := ctrl.SetMembers(newMembers); err != nil {
					logger.Error("Failed to set members", map[string]interface{}{"error": err.Error()})
				} else {
					// Update decision engine with new members
					for _, member := range newMembers {
						engine.AddMember(member)
					}

					logger.Debug("Member discovery refreshed", map[string]interface{}{
						"member_count": len(newMembers),
					})
				}
			}

		case <-cleanupTicker.C:
			// Perform periodic cleanup
			telemetry.Cleanup()
			logger.Debug("Telemetry cleanup completed")

		case <-securityTicker.C:
			// Perform security checks
			if auditor != nil {
				// Check file integrity
				for _, filePath := range []string{"/etc/config/starfail", "/usr/sbin/starfaild"} {
					if _, err := auditor.ValidateFileIntegrity(filePath); err != nil {
						logger.Error("File integrity check failed", "file", filePath, "error", err)
					}
				}

				// Check network security
				for _, port := range []int{8080, 9090} {
					if _, err := auditor.CheckNetworkSecurity(port, "tcp"); err != nil {
						logger.Error("Network security check failed", "port", port, "error", err)
					}
				}
			}

		case <-performanceTicker.C:
			// Perform performance monitoring
			if profiler != nil {
				// Check memory usage
				memoryUsage := profiler.GetMemoryUsage()
				if memoryUsage > 100 { // 100MB threshold
					logger.Warn("High memory usage detected", "usage_mb", memoryUsage)
				}

				// Check goroutine count
				goroutineCount := profiler.GetGoroutineCount()
				if goroutineCount > 500 {
					logger.Warn("High goroutine count detected", "count", goroutineCount)
				}

				// Force GC if memory usage is high
				if memoryUsage > 200 { // 200MB threshold
					logger.Info("Forcing garbage collection due to high memory usage")
					profiler.ForceGC()
				}
			}

		case <-mqttTicker.C:
			// Publish telemetry data via MQTT
			if mqttClient != nil && cfg.MQTT.Enabled {
				publishTelemetryToMQTT(mqttClient, ctrl, telemetry, engine, logger)
			}
		}
	}
}

// publishTelemetryToMQTT publishes comprehensive telemetry data to MQTT
func publishTelemetryToMQTT(mqttClient *mqtt.Client, ctrl *controller.Controller, telemetry *telem.Store, engine *decision.Engine, logger *logx.Logger) {
	// Get current system status
	members := ctrl.GetMembers()
	currentMember, _ := ctrl.GetCurrentMember()

	// Create status payload
	status := map[string]interface{}{
		"timestamp":      time.Now().Unix(),
		"current_member": "",
		"total_members":  len(members),
		"active_members": 0,
		"daemon_uptime":  time.Since(time.Now().Add(-24 * time.Hour)).Seconds(), // Approximate
	}

	if currentMember != nil {
		status["current_member"] = currentMember.Name
	}

	// Count active members
	activeCount := 0
	for _, member := range members {
		if member.Eligible {
			activeCount++
		}
	}
	status["active_members"] = activeCount

	// Publish system status
	if err := mqttClient.PublishStatus(status); err != nil {
		logger.Warn("Failed to publish status to MQTT", "error", err)
	}

	// Publish member list
	memberData := make([]map[string]interface{}, len(members))
	for i, member := range members {
		memberData[i] = map[string]interface{}{
			"name":      member.Name,
			"class":     member.Class,
			"interface": member.Iface,
			"weight":    member.Weight,
			"eligible":  member.Eligible,
			"active":    currentMember != nil && currentMember.Name == member.Name,
		}
	}

	if err := mqttClient.PublishMemberList(memberData); err != nil {
		logger.Warn("Failed to publish member list to MQTT", "error", err)
	}

	// Publish recent samples for each member
	for _, member := range members {
		samples, err := telemetry.GetSamples(member.Name, time.Now().Add(-5*time.Minute))
		if err != nil || len(samples) == 0 {
			continue
		}

		// Get the latest sample
		latestSample := samples[len(samples)-1]
		sampleData := map[string]interface{}{
			"member":     member.Name,
			"timestamp":  latestSample.Timestamp.Unix(),
			"latency_ms": latestSample.Metrics.LatencyMS,
			"loss_pct":   latestSample.Metrics.LossPercent,
			"score":      latestSample.Score.Final,
		}

		// Add class-specific metrics
		if latestSample.Metrics.ObstructionPct != nil {
			sampleData["obstruction_pct"] = *latestSample.Metrics.ObstructionPct
		}
		if latestSample.Metrics.SignalStrength != nil {
			sampleData["signal_strength"] = *latestSample.Metrics.SignalStrength
		}

		if err := mqttClient.PublishSample(sampleData); err != nil {
			logger.Warn("Failed to publish sample to MQTT", "member", member.Name, "error", err)
		}
	}

	// Publish recent events
	events, err := telemetry.GetEvents(time.Now().Add(-10*time.Minute), 10)
	if err == nil && len(events) > 0 {
		for _, event := range events {
			eventData := map[string]interface{}{
				"timestamp": event.Timestamp.Unix(),
				"type":      event.Type,
				"reason":    event.Reason,
				"member":    event.Member,
				"from":      event.From,
				"to":        event.To,
				"data":      event.Data,
			}

			if err := mqttClient.PublishEvent(eventData); err != nil {
				logger.Warn("Failed to publish event to MQTT", "event_type", event.Type, "error", err)
			}
		}
	}

	// Publish health information
	healthData := map[string]interface{}{
		"timestamp":       time.Now().Unix(),
		"telemetry_usage": telemetry.GetMemoryUsage(),
		"components": map[string]string{
			"controller":      "healthy",
			"decision_engine": "healthy",
			"telemetry_store": "healthy",
		},
	}

	if err := mqttClient.PublishHealth(healthData); err != nil {
		logger.Warn("Failed to publish health to MQTT", "error", err)
	}

	logger.Debug("Successfully published telemetry to MQTT")
}
