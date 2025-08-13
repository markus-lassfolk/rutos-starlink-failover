package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"starfail/pkg/audit"
	"starfail/pkg/collector"
	"starfail/pkg/controller"
	"starfail/pkg/decision"
	"starfail/pkg/gps"
	"starfail/pkg/logx"
	"starfail/pkg/notification"
	"starfail/pkg/obstruction"
	"starfail/pkg/recovery"
	"starfail/pkg/sampling"
	"starfail/pkg/sysmgmt"
	"starfail/pkg/telem"
	"starfail/pkg/ubus"
	"starfail/pkg/uci"
)

const (
	version = "1.0.0-dev"
	appName = "starfaild"
)

var (
	configFile     = flag.String("config", "/etc/config/starfail", "UCI config file path")
	logLevel       = flag.String("log-level", "info", "Log level (debug|info|warn|error|trace)")
	logFile        = flag.String("log-file", "", "Log file path (empty for stdout/syslog only)")
	monitor        = flag.Bool("monitor", false, "Run in monitoring mode with real-time output")
	verbose        = flag.Bool("verbose", false, "Enable verbose logging (equivalent to debug level)")
	trace          = flag.Bool("trace", false, "Enable trace logging (most detailed)")
	noColor        = flag.Bool("no-color", false, "Disable colored output in monitoring mode")
	jsonLogs       = flag.Bool("json", true, "Output logs in JSON format")
	version_       = flag.Bool("version", false, "Show version and exit")
	help           = flag.Bool("help", false, "Show help message with examples")
)

func main() {
	flag.Parse()

	if *help {
		showHelp()
		os.Exit(0)
	}

	if *version_ {
		fmt.Printf("%s %s\n", appName, version)
		os.Exit(0)
	}

	// Determine effective log level
	effectiveLogLevel := *logLevel
	if *trace {
		effectiveLogLevel = "trace"
	} else if *verbose {
		effectiveLogLevel = "debug"
	}

	// Initialize structured logger with enhanced options
	loggerConfig := logx.Config{
		Level:       effectiveLogLevel,
		Format:      getLogFormat(),
		Output:      getLogOutput(),
		Monitor:     *monitor,
		NoColor:     *noColor,
		FilePath:    *logFile,
	}
	
	logger := logx.NewWithConfig(loggerConfig)
	logger = logger.WithFields(map[string]interface{}{
		"daemon": "starfaild",
		"version": version,
		"pid": os.Getpid(),
	})

	if *monitor {
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
		"config", *configFile,
	)

	// Load UCI configuration
	uciLoader := uci.NewLoader(*configFile)
	config, err := uciLoader.Load()
	if err != nil {
		logger.Error("failed to load configuration", "error", err)
		os.Exit(1)
	}
	
	// Use config values for logger and daemon
	logger.SetLevel(config.Main.LogLevel)
	logger = logger.WithFields(map[string]interface{}{
		"daemon": "starfaild",
		"version": version,
	})
	
	logger.Info("configuration loaded successfully",
		"poll_interval_ms", config.Main.PollIntervalMs,
		"use_mwan3", config.Main.UseMwan3,
		"members_count", len(config.Members),
	)

	// Setup signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)

	// Initialize enhanced components
	
	// Initialize system management for health monitoring and auto-recovery
	sysMgmt, err := sysmgmt.NewManager(config.SysMgmt, logger)
	if err != nil {
		logger.Error("failed to initialize system management", "error", err)
		os.Exit(1)
	}
	
	// Initialize backup and recovery system
	var recoveryMgr *recovery.Manager
	if config.Recovery.Enable {
		var err error
		recoveryMgr, err = recovery.NewManager(config.Recovery, logger)
		if err != nil {
			logger.Warn("backup/recovery system disabled", "error", err)
		}
	}
	
	// Initialize notification system
	var notificationMgr *notification.Manager
	if config.Notifications.Enable {
		var err error
		notificationMgr, err = notification.NewManager(config.Notifications, logger)
		if err != nil {
			logger.Warn("notification system disabled", "error", err)
		}
	}
	
	// Initialize adaptive sampling system
	var samplingMgr *sampling.Manager
	if config.Sampling.Enable {
		var err error
		samplingMgr, err = sampling.NewManager(config.Sampling, logger)
		if err != nil {
			logger.Warn("adaptive sampling disabled", "error", err)
		}
	}
	
	// Initialize audit logger for comprehensive decision tracking
	auditLogger, err := audit.NewAuditLogger("/var/log/starfail")
	if err != nil {
		logger.Error("failed to initialize audit logger", "error", err)
		os.Exit(1)
	}
	defer auditLogger.Close()
	
	// Initialize GPS manager for location-aware intelligence
	gpsManager := gps.NewGPSManager()
	
	// Initialize obstruction predictor for Starlink optimization
	obstructionManager := obstruction.NewObstructionManager()

	// Initialize telemetry store
	store := telem.NewStore(telem.Config{
		MaxSamplesPerMember: config.Main.MaxSamplesPerMember,
		MaxEvents:          config.Main.MaxEvents,
		RetentionHours:     config.Main.RetentionHours,
		MaxRAMMB:           config.Main.MaxRAMMB,
	})

	// Initialize collector registry
	registry := collector.NewRegistry()
	
	// Register enhanced collectors
	starlinkCollector := collector.NewStarlinkCollector(config.Main.StarlinkDishIP)
	cellularCollector := collector.NewCellularCollector(logger)
	wifiCollector := collector.NewWiFiCollector(logger)
	pingCollector := collector.NewPingCollector(logger)
	
	registry.Register("starlink", starlinkCollector)
	registry.Register("cellular", cellularCollector)
	registry.Register("wifi", wifiCollector)
	registry.Register("lan", pingCollector)
	registry.Register("generic", pingCollector)

	// Initialize mwan3 controller
	controllerConfig := controller.Config{
		UseMwan3:  config.Main.UseMwan3,
		DryRun:    config.Main.DryRun,
		CooldownS: config.Main.CooldownS,
	}
	ctrl := controller.NewController(controllerConfig, logger)

	// Initialize enhanced decision engine with audit logging
	decisionConfig := decision.Config{
		SwitchMargin:         config.Main.SwitchMargin,
		FailMinDurationS:     config.Main.FailMinDurationS,
		RestoreMinDurationS:  config.Main.RestoreMinDurationS,
		HistoryWindowS:       config.Main.HistoryWindowS,
		EWMAAlpha:           config.Main.EWMAAlpha,
		WeightLatency:       config.Scoring.WeightLatency,
		WeightLoss:          config.Scoring.WeightLoss,
		WeightJitter:        config.Scoring.WeightJitter,
		WeightObstruction:   config.Scoring.WeightObstruction,
		LatencyOkMs:         config.Scoring.LatencyOkMs,
		LatencyBadMs:        config.Scoring.LatencyBadMs,
		LossOkPct:           config.Scoring.LossOkPct,
		LossBadPct:          config.Scoring.LossBadPct,
		JitterOkMs:          config.Scoring.JitterOkMs,
		JitterBadMs:         config.Scoring.JitterBadMs,
		ObstructionOkPct:    config.Scoring.ObstructionOkPct,
		ObstructionBadPct:   config.Scoring.ObstructionBadPct,
	}
	engine := decision.NewEngine(decisionConfig, logger, store, auditLogger, gpsManager, obstructionManager)

	// Initialize ubus API server
	ubusConfig := ubus.Config{
		ServiceName: "starfail",
		Enable:      config.Main.EnableUbus,
	}
	ubusServer := ubus.NewServer(ubusConfig, logger, store, ctrl, registry)

	// Start ubus server if enabled
	if config.Main.EnableUbus {
		go func() {
			if err := ubusServer.Start(ctx); err != nil {
				logger.Error("failed to start ubus server", "error", err)
			}
		}()
	}

	// Validate controller configuration
	if err := ctrl.ValidateConfig(ctx); err != nil {
		logger.Error("controller validation failed", "error", err)
		os.Exit(1)
	}

	// Discover initial members
	members, err := ctrl.DiscoverMembers(ctx)
	if err != nil {
		logger.Error("failed to discover members", "error", err)
		os.Exit(1)
	}

	logger.Info("discovered members", "count", len(members))
	for _, member := range members {
		logger.Info("member discovered", 
			"name", member.Name,
			"interface", member.Interface,
			"enabled", member.Enabled,
			"weight", member.Weight,
		)
	}

	// Log startup in audit trail
	auditLogger.LogRecovery(ctx, "startup", fmt.Sprintf("starfail daemon started with %d members", len(members)))

	// Send startup notification
	if notificationMgr != nil {
		notificationMgr.Send(ctx, notification.Alert{
			Priority: notification.PriorityLow,
			Title:    "Starfail Daemon Started",
			Message:  fmt.Sprintf("System started with %d members", len(members)),
			Source:   "daemon",
			Context: map[string]interface{}{
				"version":       version,
				"members_count": len(members),
			},
		})
	}

	// Add startup event
	store.AddEvent(telem.Event{
		Timestamp: time.Now(),
		Level:     "info",
		Type:      "startup",
		Message:   "starfail daemon started",
		Data: map[string]interface{}{
			"version":         version,
			"members_count":   len(members),
			"config_file":     *configFile,
			"enhanced_features": []string{
				"system_health_monitoring",
				"enhanced_starlink_diagnostics", 
				"location_aware_intelligence",
				"comprehensive_audit_trail",
				"advanced_notification_systems",
				"predictive_obstruction_management",
				"adaptive_sampling",
				"backup_and_recovery",
			},
		},
	})

	// Start background GPS monitoring
	go func() {
		gpsTicker := time.NewTicker(30 * time.Second) // Update GPS every 30s
		defer gpsTicker.Stop()
		
		for {
			select {
			case <-ctx.Done():
				return
			case <-gpsTicker.C:
				if pos, err := gpsManager.GetCurrentPosition(ctx); err == nil {
					logger.Debug("GPS position updated",
						"lat", pos.Latitude,
						"lon", pos.Longitude,
						"accuracy", pos.Accuracy,
						"source", pos.Source,
					)
				}
			}
		}
	}()

	// Start background obstruction monitoring for Starlink members
	go func() {
		obstructionTicker := time.NewTicker(60 * time.Second) // Check obstructions every minute
		defer obstructionTicker.Stop()
		
		for {
			select {
			case <-ctx.Done():
				return
			case <-obstructionTicker.C:
				// Get location context for obstruction analysis
				if locationCtx, err := gpsManager.GetLocationContext(ctx); err == nil && locationCtx.CurrentPosition != nil {
					// Analyze obstruction patterns
					if analysis, err := obstructionManager.AnalyzeObstruction(ctx, 
						locationCtx.CurrentPosition.Latitude, 
						locationCtx.CurrentPosition.Longitude); err == nil {
						
						logger.Debug("obstruction analysis completed",
							"current_obstruction", analysis.CurrentState.Current,
							"trend", analysis.CurrentState.Trend,
							"confidence", analysis.Confidence,
						)
						
						// Log significant obstruction events
						if analysis.CurrentState.Severity == "high" || analysis.CurrentState.Severity == "critical" {
							auditLogger.LogError(ctx, "obstruction", "analysis", 
								fmt.Sprintf("High obstruction detected: %.1f%%", analysis.CurrentState.Current),
								map[string]interface{}{
									"analysis": analysis,
								})
						}
					}
				}
			}
		}
	}()

	// Main daemon loop with enhanced monitoring
	ticker := time.NewTicker(time.Duration(config.Main.PollIntervalMs) * time.Millisecond)
	defer ticker.Stop()

	logger.Info("daemon started successfully")

	for {
		select {
		case sig := <-sigChan:
			switch sig {
			case syscall.SIGHUP:
				logger.Info("received SIGHUP, reloading configuration")
				// Reload config
				newConfig, err := uciLoader.Load()
				if err != nil {
					logger.Error("failed to reload configuration", "error", err)
				} else {
					config = newConfig
					logger.SetLevel(config.Main.LogLevel)
					ticker.Reset(time.Duration(config.Main.PollIntervalMs) * time.Millisecond)
					logger.Info("configuration reloaded successfully")
				}
			case syscall.SIGINT, syscall.SIGTERM:
				logger.Info("received shutdown signal", "signal", sig.String())
				cancel()
				return
			}

		case <-ticker.C:
			// Adaptive sampling: adjust interval based on connection characteristics
			if samplingMgr != nil {
				if newInterval := samplingMgr.GetCurrentInterval(); newInterval != time.Duration(config.Main.PollIntervalMs)*time.Millisecond {
					ticker.Reset(newInterval)
					logger.Debug("adjusted sampling interval", "new_interval_ms", newInterval.Milliseconds())
				}
			}
			
			// System health check every 10th cycle
			if time.Now().Unix()%600 == 0 && sysMgmt != nil { // Every 10 minutes
				if healthOk := sysMgmt.QuickHealthCheck(ctx); !healthOk {
					logger.Warn("system health check failed, scheduling maintenance")
					go func() {
						if err := sysMgmt.FullMaintenance(ctx); err != nil {
							logger.Error("system maintenance failed", "error", err)
							if notificationMgr != nil {
								notificationMgr.Send(ctx, notification.Alert{
									Priority: notification.PriorityHigh,
									Title:    "System Maintenance Failed",
									Message:  fmt.Sprintf("Maintenance error: %v", err),
									Source:   "sysmgmt",
								})
							}
						}
					}()
				}
			}
			
			// Main tick logic
			logger.Debug("starting collection cycle")
			
			// 1. Discover/refresh members (periodically)
			if time.Now().Unix()%60 == 0 { // Refresh every minute
				freshMembers, err := ctrl.DiscoverMembers(ctx)
				if err != nil {
					logger.Error("failed to refresh members", "error", err)
				} else {
					members = freshMembers
					logger.Debug("refreshed members", "count", len(members))
				}
			}

			// 2. Collect metrics per member
			var samples []telem.Sample
			for _, member := range members {
				if !member.Enabled {
					continue
				}

				// Get appropriate collector
				collectorInstance, exists := registry.Get(determineClass(member.Interface))
				if !exists {
					// Fall back to generic ping collector
					collectorInstance, _ = registry.Get("generic")
				}

				// Collect metrics
				metrics, err := collectorInstance.Collect(ctx, collector.Member{
					Name:          member.Name,
					InterfaceName: member.Interface,
					Class:         determineClass(member.Interface),
					Weight:        member.Weight,
					Enabled:       member.Enabled,
				})

				if err != nil {
					logger.Error("failed to collect metrics", 
						"member", member.Name, 
						"error", err)
					continue
				}

				// 3. Update scores using decision engine
				scores := engine.CalculateScores(metrics)
				
				sample := telem.Sample{
					Timestamp:    time.Now(),
					Member:       member.Name,
					Metrics:      metrics,
					InstantScore: scores.Instant,
					EWMAScore:    scores.EWMA,
					FinalScore:   scores.Final,
				}

				samples = append(samples, sample)
				store.AddSample(sample)

				logger.Debug("collected sample",
					"member", member.Name,
					"class", metrics.Class,
					"instant_score", scores.Instant,
					"ewma_score", scores.EWMA,
					"final_score", scores.Final,
				)
			}

			// 4. Update adaptive sampling with current performance
			if samplingMgr != nil && len(samples) > 0 {
				for _, sample := range samples {
					performance := sampling.Performance{
						Latency:      sample.Metrics.Latency,
						PacketLoss:   sample.Metrics.Loss,
						ConnectionOk: sample.FinalScore > 50.0,
					}
					samplingMgr.UpdatePerformance(sample.Member, performance)
				}
			}
			
			// 5. Evaluate switch conditions
			if len(samples) > 0 {
				// Get current primary
				currentPrimary, err := ctrl.GetCurrentPrimary(ctx)
				if err != nil {
					logger.Error("failed to get current primary", "error", err)
				} else {
					// Evaluate if we need to switch
					switchDecision := engine.EvaluateSwitch(samples, currentPrimary)
					if switchDecision != nil {
						logger.Info("switch decision made",
							"from", switchDecision.From,
							"to", switchDecision.To,
							"reason", switchDecision.Reason,
							"score_delta", switchDecision.ScoreDelta,
						)

						// Send switch notification
						if notificationMgr != nil {
							priority := notification.PriorityMedium
							if switchDecision.Confidence > 0.8 {
								priority = notification.PriorityHigh
							}
							
							notificationMgr.Send(ctx, notification.Alert{
								Priority: priority,
								Title:    "Failover Event",
								Message:  fmt.Sprintf("Switching from %s to %s", switchDecision.From, switchDecision.To),
								Source:   "decision_engine",
								Context: map[string]interface{}{
									"decision": switchDecision,
								},
							})
						}

						// 6. Apply decision via controller
						targetMember := findMemberByName(members, switchDecision.To)
						if targetMember != nil {
							if err := ctrl.SetPrimary(ctx, *targetMember); err != nil {
								logger.Error("failed to execute switch", 
									"target", switchDecision.To,
									"error", err)
								
								store.AddEvent(telem.Event{
									Timestamp: time.Now(),
									Level:     "error",
									Type:      "switch_failed",
									Member:    switchDecision.To,
									Message:   fmt.Sprintf("failed to switch to %s: %v", switchDecision.To, err),
									Data:      switchDecision,
								})
								
								// Send failure notification
								if notificationMgr != nil {
									notificationMgr.Send(ctx, notification.Alert{
										Priority: notification.PriorityHigh,
										Title:    "Failover Failed",
										Message:  fmt.Sprintf("Failed to switch to %s: %v", switchDecision.To, err),
										Source:   "controller",
									})
								}
							} else {
								logger.Info("switch executed successfully", 
									"target", switchDecision.To)
								
								store.AddEvent(telem.Event{
									Timestamp: time.Now(),
									Level:     "info",
									Type:      "switch_success",
									Member:    switchDecision.To,
									Message:   fmt.Sprintf("successfully switched to %s", switchDecision.To),
									Data:      switchDecision,
								})
								
								// Create automatic backup after successful switch
								if recoveryMgr != nil {
									go func() {
										if _, err := recoveryMgr.BackupConfig(ctx, 
											fmt.Sprintf("post-switch-to-%s", switchDecision.To)); err != nil {
											logger.Warn("failed to create post-switch backup", "error", err)
										}
									}()
								}
							}
						}
					}
				}
			}

			// 7. Cleanup old telemetry data periodically
			if time.Now().Unix()%300 == 0 { // Every 5 minutes
				store.Cleanup()
				logger.Debug("cleaned up old telemetry data")
			}

		case <-ctx.Done():
			logger.Info("daemon shutting down")
			
			// Send shutdown notification
			if notificationMgr != nil {
				notificationMgr.Send(ctx, notification.Alert{
					Priority: notification.PriorityLow,
					Title:    "Starfail Daemon Stopped",
					Message:  "System is shutting down",
					Source:   "daemon",
				})
			}
			
			// Create shutdown backup
			if recoveryMgr != nil {
				if _, err := recoveryMgr.BackupConfig(ctx, "shutdown-backup"); err != nil {
					logger.Warn("failed to create shutdown backup", "error", err)
				}
			}
			
			// Stop ubus server
			if config.Main.EnableUbus {
				if err := ubusServer.Stop(ctx); err != nil {
					logger.Error("failed to stop ubus server", "error", err)
				}
			}

			// Add shutdown event
			store.AddEvent(telem.Event{
				Timestamp: time.Now(),
				Level:     "info",
				Type:      "shutdown",
				Message:   "starfail daemon shutting down",
			})

			return
		}
	}
}

// determineClass determines the interface class based on interface name and configuration
func determineClass(interfaceName string) string {
	// Simple heuristic-based classification
	// In practice, this would be more sophisticated and configurable
	
	switch {
	case interfaceName == "starlink" || interfaceName == "wan_starlink":
		return "starlink"
	case interfaceName == "wwan" || interfaceName == "wan_cell" || 
		 interfaceName == "cellular" || interfaceName == "modem":
		return "cellular"
	case interfaceName == "wlan" || interfaceName == "wifi" || 
		 interfaceName == "wireless":
		return "wifi"
	case interfaceName == "wan" || interfaceName == "eth1":
		return "lan"
	default:
		return "generic"
	}
}

// findMemberByName finds a member by name in the members slice
func findMemberByName(members []controller.Member, name string) *controller.Member {
	for _, member := range members {
		if member.Name == name {
			return &member
		}
	}
	return nil
}

// getLogFormat determines the log format based on flags
func getLogFormat() string {
	if *monitor && !*jsonLogs {
		return "console"
	}
	return "json"
}

// getLogOutput determines the log output destination
func getLogOutput() string {
	if *logFile != "" {
		return *logFile
	}
	if *monitor {
		return "stdout"
	}
	return "syslog"
}

// showHelp displays comprehensive help information with examples
func showHelp() {
	fmt.Printf(`%s %s - Intelligent Multi-Interface Failover Daemon for RutOS/OpenWrt

USAGE:
    %s [OPTIONS]

DESCRIPTION:
    starfaild is a production-ready Go daemon for intelligent multi-interface failover on
    RutOS/OpenWrt routers. It monitors Starlink, cellular, and other WAN interfaces using
    real-time metrics and provides seamless failover with comprehensive telemetry.

    The daemon uses a collector → decision → controller pipeline to gather interface
    metrics, calculate health scores, and automatically switch between WAN connections
    based on configurable policies.

OPTIONS:
    --config PATH           UCI configuration file path
                           (default: /etc/config/starfail)
    
    --log-level LEVEL      Set logging level
                           Options: trace, debug, info, warn, error
                           (default: info)
    
    --log-file PATH        Log file path (empty for stdout/syslog only)
                           (default: stdout in monitor mode, syslog otherwise)
    
    --monitor              Enable real-time monitoring mode
                           Shows live console output with color coding
    
    --verbose              Enable verbose logging (debug level)
                           Equivalent to --log-level debug
    
    --trace                Enable trace logging (most detailed)
                           Shows internal operations and API calls
    
    --no-color             Disable colored output in monitoring mode
                           Useful for log files or non-TTY environments
    
    --json                 Output logs in JSON format
                           (default: true, false in monitor mode)
    
    --version              Show version information and exit
    
    --help                 Show this help message

EXAMPLES:
    # Basic daemon operation (production mode)
    %s --config /etc/config/starfail

    # Development/troubleshooting with full visibility
    %s --monitor --trace --verbose

    # Real-time monitoring with clean console output
    %s --monitor --no-color --verbose

    # Debug specific configuration issues
    %s --monitor --debug --config ./configs/starfail.example

    # JSON structured logs for analysis
    %s --json --verbose --log-file /var/log/starfail.log

    # Test configuration without making changes
    %s --monitor --trace --config /tmp/test-config

MONITORING MODE:
    When --monitor is enabled, the daemon outputs real-time logs to the console
    with color-coded log levels for easy visual scanning:
    
    [15:04:05.123] INFO  Starting starfail daemon
    [15:04:05.456] DEBUG Loading UCI configuration members=3
    [15:04:05.789] TRACE Starlink API request endpoint=192.168.100.1
    [15:04:06.012] WARN  Interface score below threshold score=65.2
    [15:04:06.345] INFO  Failover triggered from=starlink to=cellular

LOG LEVELS:
    TRACE    Most detailed logging, shows internal operations
    DEBUG    Development debugging information  
    INFO     General operational information
    WARN     Warning conditions that don't stop operation
    ERROR    Error conditions that may affect functionality

CONFIGURATION:
    The daemon uses UCI configuration format compatible with OpenWrt:
    
    config starfail 'main'
        option enable '1'
        option use_mwan3 '1'
        option poll_interval_ms '1500'
        
    config member 'starlink_any'
        option detect 'auto'
        option class 'starlink'
        
    config member 'cellular_wan'
        option interface 'cellular_wan'
        option class 'cellular'

SIGNALS:
    SIGTERM/SIGINT    Graceful shutdown with cleanup
    SIGHUP            Reload configuration (if supported)

FILES:
    /etc/config/starfail       Default UCI configuration
    /var/run/starfail.pid      Process ID file
    /var/log/messages          Syslog output (production mode)

AUTHOR:
    RutOS Starlink Failover Project
    https://github.com/markus-lassfolk/rutos-starlink-failover

`, appName, version, appName, appName, appName, appName, appName, appName, appName)
}
