package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/controller"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/decision"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
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
	// Initialize core components
	registry := collector.NewRegistry()
	registry.Register("starlink", collector.NewStarlinkCollector(""))
	registry.Register("cellular", collector.NewCellularCollector(""))
	registry.Register("wifi", collector.NewWiFiCollector(nil))
	registry.Register("generic", collector.NewPingCollector(nil))

	storeCfg := telem.Config{
		MaxSamplesPerMember: config.Main.MaxSamplesPerMember,
		MaxEvents:           config.Main.MaxEvents,
		RetentionHours:      config.Main.RetentionHours,
		MaxRAMMB:            config.Main.MaxRAMMB,
	}
	store := telem.NewStore(storeCfg)

	decisionCfg := decision.Config{
		SwitchMargin:     config.Main.SwitchMargin,
		MinUptimeS:       config.Main.MinUptimeS,
		CooldownS:        time.Duration(config.Main.CooldownS) * time.Second,
		HistoryWindowS:   config.Main.HistoryWindowS,
		EnablePredictive: config.Main.Predictive,
	}
	engine := decision.NewEngine(decisionCfg, *logger, store, nil, nil, nil)

	controllerCfg := controller.Config{
		UseMwan3:  config.Main.UseMwan3,
		DryRun:    config.Main.DryRun,
		CooldownS: config.Main.CooldownS,
	}
	ctrl := controller.NewController(controllerCfg, logger)

	// Setup signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	pollInterval := time.Duration(config.Main.PollIntervalMs) * time.Millisecond
	ticker := time.NewTicker(pollInterval)
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
			// Discover members via controller
			members, err := ctrl.DiscoverMembers(ctx)
			if err != nil {
				logger.Error("Failed to discover members", "error", err)
				continue
			}

			controllerMembers := make(map[string]controller.Member)
			var colMembers []collector.Member
			for _, m := range members {
				controllerMembers[m.Name] = m

				cm := collector.Member{
					Name:          m.Name,
					InterfaceName: m.Interface,
					Weight:        m.Weight,
					Enabled:       m.Enabled,
				}

				for _, cfgMember := range config.Members {
					if cfgMember.Name == m.Name {
						if cfgMember.Class != "" {
							cm.Class = cfgMember.Class
						}
						if cfgMember.Weight != 0 {
							cm.Weight = cfgMember.Weight
						}
						if cfgMember.Detect == "disable" {
							cm.Enabled = false
						}
					}
				}

				if cm.Class == "" {
					cm.Class = "generic"
				}
				colMembers = append(colMembers, cm)
			}

			// Collect metrics and update decision engine
			for _, member := range colMembers {
				if !member.Enabled {
					continue
				}

				coll, ok := registry.Get(member.Class)
				if !ok {
					coll, ok = registry.Get("generic")
					if !ok {
						logger.Error("no collector available", "class", member.Class, "member", member.Name)
						continue
					}
				}

				metrics, err := coll.Collect(ctx, member)
				if err != nil {
					logger.Error("metric collection failed", "member", member.Name, "error", err)
					store.AddEvent(telem.Event{Timestamp: time.Now(), Level: "error", Type: "collect", Member: member.Name, Message: err.Error()})
					continue
				}

				engine.UpdateMember(member, metrics)
				state := engine.GetMemberStates()[member.Name]
				store.AddSample(telem.Sample{
					Timestamp:    metrics.Timestamp,
					Member:       member.Name,
					Metrics:      metrics,
					InstantScore: state.Score.Instant,
					EWMAScore:    state.Score.EWMA,
					FinalScore:   state.Score.Final,
				})
			}

			// Evaluate decision and act via controller
			if event := engine.EvaluateSwitch(); event != nil {
				target, ok := controllerMembers[event.To]
				if ok {
					if err := ctrl.SetPrimary(ctx, target); err != nil {
						logger.Error("controller set primary failed", "error", err)
					} else {
						store.AddEvent(telem.Event{
							Timestamp: event.Timestamp,
							Level:     "info",
							Type:      event.Type,
							Member:    event.To,
							Message:   event.Reason,
							Data: map[string]interface{}{
								"from":  event.From,
								"delta": event.ScoreDelta,
							},
						})
					}
				} else {
					logger.Warn("switch target not found", "member", event.To)
				}
			}
		}
	}
}
