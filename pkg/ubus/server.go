// Package ubus provides ubus API server for external communication
package ubus

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/controller"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/uci"
)

// Server provides ubus API endpoints for starfail daemon
type Server struct {
	logger      *logx.Logger
	store       *telem.Store
	controller  *controller.Controller
	registry    *collector.Registry
	uciLoader   *uci.Loader
	serviceName string
	startTime   time.Time
}

// Config for ubus server
type Config struct {
	ServiceName string `uci:"service_name"`
	Enable      bool   `uci:"enable"`
}

// NewServer creates a new ubus API server
func NewServer(config Config, logger *logx.Logger, store *telem.Store,
	ctrl *controller.Controller, registry *collector.Registry, uciLoader *uci.Loader) *Server {

	if config.ServiceName == "" {
		config.ServiceName = "starfail"
	}

	return &Server{
		logger:      logger,
		store:       store,
		controller:  ctrl,
		registry:    registry,
		uciLoader:   uciLoader,
		serviceName: config.ServiceName,
	}
}

// Start registers the ubus service and starts listening
func (s *Server) Start(ctx context.Context) error {
	s.logger.WithFields(logx.Fields{
		"component":    "ubus",
		"service_name": s.serviceName,
	}).Info("starting ubus API server")

	// In a real implementation, we would use libubus bindings
	// For now, we'll implement a basic command handler approach
	s.startTime = time.Now()
	return s.registerMethods(ctx)
}

// Stop unregisters the ubus service
func (s *Server) Stop(ctx context.Context) error {
	s.logger.WithFields(logx.Fields{
		"component":    "ubus",
		"service_name": s.serviceName,
	}).Info("stopping ubus API server")

	// Unregister ubus service
	cmd := exec.CommandContext(ctx, "ubus", "remove", s.serviceName)
	return cmd.Run()
}

// registerMethods registers all ubus API methods
func (s *Server) registerMethods(ctx context.Context) error {
	if _, err := exec.LookPath("ubus"); err != nil {
		s.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Warn("ubus command not found, skipping registration")
		return nil
	}

	// Define the methods exposed over ubus
	methods := map[string]map[string]interface{}{
		"status":     {},
		"members":    {},
		"metrics":    {"member": "str", "limit": "int"},
		"action":     {"action": "str", "member": "str", "force": "bool"},
		"events":     {"limit": "int"},
		"config.get": {},
		"config.set": {"changes": "object"},
	}

	spec, err := json.Marshal(methods)
	if err != nil {
		return fmt.Errorf("failed to marshal method spec: %w", err)
	}

	// Register the service with ubus
	cmd := exec.CommandContext(ctx, "ubus", "add", s.serviceName, string(spec))
	if output, err := cmd.CombinedOutput(); err != nil {
		s.logger.WithFields(logx.Fields{
			"error":  err.Error(),
			"output": string(output),
		}).Error("failed to register ubus service")
		return err
	}

	// Start the handler loop to process ubus calls
	go s.handleCalls(ctx)

	s.logger.WithFields(logx.Fields{
		"methods": []string{"status", "members", "metrics", "action", "events", "config.get", "config.set"},
	}).Info("registered ubus methods")

	return nil
}

// handleCalls listens for ubus method invocations and dispatches them
func (s *Server) handleCalls(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "ubus", "listen", s.serviceName)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		s.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Error("failed to get ubus listen stdout")
		return
	}
	if err := cmd.Start(); err != nil {
		s.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Error("failed to start ubus listen")
		return
	}

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		line := scanner.Bytes()
		var req struct {
			ID     uint32                 `json:"id"`
			Method string                 `json:"method"`
			Params map[string]interface{} `json:"params"`
		}
		if err := json.Unmarshal(line, &req); err != nil {
			continue
		}

		var (
			result  interface{}
			callErr error
		)

		switch req.Method {
		case "status":
			result, callErr = s.HandleStatus(ctx)
		case "members":
			result, callErr = s.HandleMembers(ctx)
		case "metrics":
			member, _ := req.Params["member"].(string)
			limit := 0
			if v, ok := req.Params["limit"].(float64); ok {
				limit = int(v)
			}
			result, callErr = s.HandleMetrics(ctx, member, limit)
		case "action":
			var ar ActionRequest
			b, _ := json.Marshal(req.Params)
			_ = json.Unmarshal(b, &ar)
			result, callErr = s.HandleAction(ctx, ar)
		case "events":
			limit := 0
			if v, ok := req.Params["limit"].(float64); ok {
				limit = int(v)
			}
			result, callErr = s.HandleEvents(ctx, limit)
		case "config.get":
			result, callErr = s.HandleConfigGet(ctx)
		case "config.set":
			var payload map[string]interface{}
			if req.Params != nil {
				payload = req.Params
			}
			result, callErr = s.HandleConfigSet(ctx, payload)
		default:
			callErr = fmt.Errorf("unknown method: %s", req.Method)
		}

		reply := map[string]interface{}{}
		if callErr != nil {
			reply["error"] = callErr.Error()
		} else {
			reply["result"] = result
		}
		resp, _ := json.Marshal(reply)
		exec.CommandContext(ctx, "ubus", "reply", fmt.Sprintf("%d", req.ID), string(resp)).Run()
	}

	if err := scanner.Err(); err != nil {
		s.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Warn("ubus listen scanner error")
	}

	_ = cmd.Wait()
}

// StatusResponse represents the response for the status method
type StatusResponse struct {
	Status        string                 `json:"status"`
	Uptime        int64                  `json:"uptime_seconds"`
	Version       string                 `json:"version"`
	CurrentMember *controller.Member     `json:"current_member,omitempty"`
	LastChange    int64                  `json:"last_change_seconds,omitempty"`
	Stats         map[string]interface{} `json:"stats"`
}

// MembersResponse represents the response for the members method
type MembersResponse struct {
	Members []MemberInfo `json:"members"`
	Count   int          `json:"count"`
}

// MemberInfo represents detailed member information
type MemberInfo struct {
	Member      controller.Member  `json:"member"`
	LastMetrics *collector.Metrics `json:"last_metrics,omitempty"`
	LastScore   *float64           `json:"last_score,omitempty"`
	Status      string             `json:"status"`
	LastUpdate  int64              `json:"last_update_seconds,omitempty"`
}

// MetricsResponse represents the response for the metrics method
type MetricsResponse struct {
	Member    string         `json:"member"`
	Samples   []telem.Sample `json:"samples"`
	Count     int            `json:"count"`
	TimeRange string         `json:"time_range"`
}

// ActionRequest represents a request to execute an action
type ActionRequest struct {
	Action string `json:"action"`
	Member string `json:"member,omitempty"`
	Force  bool   `json:"force,omitempty"`
}

// ActionResponse represents the response for an action
type ActionResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Action  string `json:"action"`
	Member  string `json:"member,omitempty"`
}

// EventsResponse represents the response for the events method
type EventsResponse struct {
	Events []telem.Event `json:"events"`
	Count  int           `json:"count"`
}

// HandleStatus handles the status ubus method
func (s *Server) HandleStatus(ctx context.Context) (*StatusResponse, error) {
	s.logger.WithFields(logx.Fields{
		"method": "status",
	}).Debug("handling status request")

	// Get current primary member
	currentMember, err := s.controller.GetCurrentPrimary(ctx)
	if err != nil {
		s.logger.WithFields(logx.Fields{
			"error": err.Error(),
		}).Warn("failed to get current primary member")
	}

	// Get store stats
	stats := s.store.GetStats()

	response := &StatusResponse{
		Status:        "running",
		Uptime:        int64(time.Since(s.startTime).Seconds()),
		Version:       "1.0.0-dev",
		CurrentMember: currentMember,
		Stats:         stats,
	}

	return response, nil
}

// HandleMembers handles the members ubus method
func (s *Server) HandleMembers(ctx context.Context) (*MembersResponse, error) {
	s.logger.WithFields(logx.Fields{
		"method": "members",
	}).Debug("handling members request")

	// Discover members
	members, err := s.controller.DiscoverMembers(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to discover members: %w", err)
	}

	var memberInfos []MemberInfo
	for _, member := range members {
		// Get latest sample for this member
		samples := s.store.GetSamples(member.Name, 1)

		memberInfo := MemberInfo{
			Member: member,
			Status: "unknown",
		}

		if len(samples) > 0 {
			sample := samples[0]
			memberInfo.LastMetrics = &sample.Metrics
			memberInfo.LastScore = &sample.FinalScore
			memberInfo.LastUpdate = sample.Timestamp.Unix()
			memberInfo.Status = "active"
		}

		memberInfos = append(memberInfos, memberInfo)
	}

	response := &MembersResponse{
		Members: memberInfos,
		Count:   len(memberInfos),
	}

	return response, nil
}

// HandleMetrics handles the metrics ubus method
func (s *Server) HandleMetrics(ctx context.Context, member string, limit int) (*MetricsResponse, error) {
	s.logger.WithFields(logx.Fields{
		"method": "metrics",
		"member": member,
		"limit":  limit,
	}).Debug("handling metrics request")

	if member == "" {
		return nil, fmt.Errorf("member parameter required")
	}
	// Clamp limit
	if limit <= 0 {
		limit = 100
	} else if limit > 2000 {
		limit = 2000
	}
	// Validate member exists (discover current members)
	if members, err := s.controller.DiscoverMembers(ctx); err == nil {
		found := false
		for _, m := range members {
			if m.Name == member {
				found = true
				break
			}
		}
		if !found {
			return nil, fmt.Errorf("member '%s' not found", member)
		}
	}

	samples := s.store.GetSamples(member, limit)

	var timeRange string
	if len(samples) > 0 {
		oldest := samples[0].Timestamp
		newest := samples[len(samples)-1].Timestamp
		timeRange = fmt.Sprintf("%s to %s", oldest.Format(time.RFC3339), newest.Format(time.RFC3339))
	}

	response := &MetricsResponse{
		Member:    member,
		Samples:   samples,
		Count:     len(samples),
		TimeRange: timeRange,
	}

	return response, nil
}

// HandleAction handles the action ubus method
func (s *Server) HandleAction(ctx context.Context, request ActionRequest) (*ActionResponse, error) {
	s.logger.WithFields(logx.Fields{
		"method": "action",
		"action": request.Action,
		"member": request.Member,
		"force":  request.Force,
	}).Info("handling action request")

	response := &ActionResponse{
		Success: false,
		Action:  request.Action,
		Member:  request.Member,
	}

	switch request.Action {
	case "failover":
		if request.Member == "" {
			response.Message = "member parameter required for failover action"
			return response, nil
		}

		// Discover members to validate the requested member
		members, err := s.controller.DiscoverMembers(ctx)
		if err != nil {
			response.Message = fmt.Sprintf("failed to discover members: %v", err)
			return response, nil
		}

		var targetMember *controller.Member
		for _, member := range members {
			if member.Name == request.Member {
				targetMember = &member
				break
			}
		}

		if targetMember == nil {
			response.Message = fmt.Sprintf("member '%s' not found", request.Member)
			return response, nil
		}

		// Execute failover
		if err := s.controller.SetPrimary(ctx, *targetMember); err != nil {
			response.Message = fmt.Sprintf("failover failed: %v", err)
			return response, nil
		}

		response.Success = true
		response.Message = fmt.Sprintf("successfully failed over to member '%s'", request.Member)

	case "refresh":
		response.Success = true
		response.Message = "configuration refreshed"

	case "status":
		// Return current status
		currentMember, err := s.controller.GetCurrentPrimary(ctx)
		if err != nil {
			response.Message = fmt.Sprintf("failed to get current status: %v", err)
			return response, nil
		}

		response.Success = true
		if currentMember != nil {
			response.Message = fmt.Sprintf("current primary: %s", currentMember.Name)
		} else {
			response.Message = "no primary member active"
		}

	default:
		response.Message = fmt.Sprintf("unknown action: %s", request.Action)
	}

	return response, nil
}

// HandleEvents handles the events ubus method
func (s *Server) HandleEvents(ctx context.Context, limit int) (*EventsResponse, error) {
	s.logger.WithFields(logx.Fields{
		"method": "events",
		"limit":  limit,
	}).Debug("handling events request")

	if limit <= 0 {
		limit = 50 // Default limit
	}

	events := s.store.GetEvents(limit)

	response := &EventsResponse{
		Events: events,
		Count:  len(events),
	}

	return response, nil
}

// ExecuteUbusCall simulates executing a ubus call (for testing/development)
func (s *Server) ExecuteUbusCall(ctx context.Context, method string, params map[string]interface{}) (interface{}, error) {
	s.logger.WithFields(logx.Fields{
		"method": method,
		"params": params,
	}).Debug("executing ubus call")

	switch method {
	case "status":
		return s.HandleStatus(ctx)

	case "members":
		return s.HandleMembers(ctx)

	case "metrics":
		member, _ := params["member"].(string)
		limit, _ := params["limit"].(int)
		return s.HandleMetrics(ctx, member, limit)

	case "action":
		// Parse action request from params
		actionData, _ := json.Marshal(params)
		var request ActionRequest
		if err := json.Unmarshal(actionData, &request); err != nil {
			return nil, fmt.Errorf("invalid action request: %w", err)
		}
		return s.HandleAction(ctx, request)

	case "events":
		limit, _ := params["limit"].(int)
		return s.HandleEvents(ctx, limit)
	case "config.get":
		return s.HandleConfigGet(ctx)
	case "config.set":
		return s.HandleConfigSet(ctx, params)

	default:
		return nil, fmt.Errorf("unknown method: %s", method)
	}
}

// GetServiceInfo returns information about the ubus service
func (s *Server) GetServiceInfo() map[string]interface{} {
	return map[string]interface{}{
		"service_name": s.serviceName,
		"methods":      []string{"status", "members", "metrics", "action", "events", "config.get", "config.set"},
		"description":  "Starfail multi-interface failover daemon API",
		"version":      "1.0.0",
	}
}

// HandleConfigGet returns an effective configuration snapshot relevant to runtime
func (s *Server) HandleConfigGet(ctx context.Context) (map[string]interface{}, error) {
	stats := s.store.GetStats()
	// We don't have a live Config object here; expose runtime-relevant bits we own
	// plus controller/registry context summaries.
	members, _ := s.controller.DiscoverMembers(ctx)
	return map[string]interface{}{
		"service":   s.serviceName,
		"telemetry": stats,
		"members":   members,
	}, nil
}

// HandleConfigSet validates an incoming change-set and applies when supported.
// Enhanced to support more configuration options with UCI write-back.
func (s *Server) HandleConfigSet(ctx context.Context, changes map[string]interface{}) (map[string]interface{}, error) {
	if len(changes) == 0 {
		return nil, fmt.Errorf("changes object required")
	}

	var applied = map[string]interface{}{}
	var needsUCICommit = false

	// Support telemetry.max_ram_mb live update
	if telemIface, ok := changes["telemetry"]; ok {
		if telemMap, ok := telemIface.(map[string]interface{}); ok {
			if v, ok := telemMap["max_ram_mb"]; ok {
				switch t := v.(type) {
				case float64:
					mb := int(t)
					if mb < 4 || mb > 128 {
						return nil, fmt.Errorf("telemetry.max_ram_mb out of range 4-128")
					}
					// Apply to runtime store
					if err := s.store.SetMaxRAMMB(mb); err != nil {
						return nil, err
					}
					applied["telemetry.max_ram_mb"] = mb
				default:
					return nil, fmt.Errorf("telemetry.max_ram_mb must be number")
				}
			}
		} else {
			return nil, fmt.Errorf("telemetry must be object")
		}
	}

	// Support main configuration updates
	if mainIface, ok := changes["main"]; ok {
		if mainMap, ok := mainIface.(map[string]interface{}); ok {
			if err := s.applyMainConfigChanges(ctx, mainMap, applied); err != nil {
				return nil, fmt.Errorf("failed to apply main config changes: %w", err)
			}
			needsUCICommit = true
		} else {
			return nil, fmt.Errorf("main must be object")
		}
	}

	// Support scoring configuration updates
	if scoringIface, ok := changes["scoring"]; ok {
		if scoringMap, ok := scoringIface.(map[string]interface{}); ok {
			if err := s.applyScoringConfigChanges(ctx, scoringMap, applied); err != nil {
				return nil, fmt.Errorf("failed to apply scoring config changes: %w", err)
			}
			needsUCICommit = true
		} else {
			return nil, fmt.Errorf("scoring must be object")
		}
	}

	// Support starlink configuration updates
	if starlinkIface, ok := changes["starlink"]; ok {
		if starlinkMap, ok := starlinkIface.(map[string]interface{}); ok {
			if err := s.applyStarlinkConfigChanges(ctx, starlinkMap, applied); err != nil {
				return nil, fmt.Errorf("failed to apply starlink config changes: %w", err)
			}
			needsUCICommit = true
		} else {
			return nil, fmt.Errorf("starlink must be object")
		}
	}

	// If UCI changes were made, reload and commit
	if needsUCICommit {
		if err := s.commitUCIChanges(ctx, applied); err != nil {
			return nil, fmt.Errorf("failed to commit UCI changes: %w", err)
		}
	}

	if len(applied) == 0 {
		return nil, fmt.Errorf("no supported changes applied")
	}

	return map[string]interface{}{
		"applied":    applied,
		"uci_commit": needsUCICommit,
	}, nil
}

// ubusCall executes a ubus command (helper function)
func ubusCall(ctx context.Context, service, method string, params map[string]interface{}) ([]byte, error) {
	// Build ubus call command
	args := []string{"call", service, method}

	if len(params) > 0 {
		paramJSON, err := json.Marshal(params)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal params: %w", err)
		}
		args = append(args, string(paramJSON))
	}

	cmd := exec.CommandContext(ctx, "ubus", args...)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ubus call failed: %w", err)
	}

	return output, nil
}

// ListServices returns available ubus services
func ListServices(ctx context.Context) ([]string, error) {
	cmd := exec.CommandContext(ctx, "ubus", "list")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list ubus services: %w", err)
	}

	services := strings.Split(strings.TrimSpace(string(output)), "\n")
	return services, nil
}

// applyMainConfigChanges applies supported main configuration changes
func (s *Server) applyMainConfigChanges(ctx context.Context, changes map[string]interface{}, applied map[string]interface{}) error {
	// Support commonly modified main config options
	if v, ok := changes["poll_interval_ms"]; ok {
		if interval, ok := v.(float64); ok {
			if interval < 100 || interval > 10000 {
				return fmt.Errorf("poll_interval_ms must be between 100-10000")
			}
			applied["main.poll_interval_ms"] = int(interval)
		} else {
			return fmt.Errorf("poll_interval_ms must be number")
		}
	}

	if v, ok := changes["dry_run"]; ok {
		if dryRun, ok := v.(bool); ok {
			applied["main.dry_run"] = dryRun
		} else {
			return fmt.Errorf("dry_run must be boolean")
		}
	}

	if v, ok := changes["enable"]; ok {
		if enable, ok := v.(bool); ok {
			applied["main.enable"] = enable
		} else {
			return fmt.Errorf("enable must be boolean")
		}
	}

	return nil
}

// applyScoringConfigChanges applies supported scoring configuration changes
func (s *Server) applyScoringConfigChanges(ctx context.Context, changes map[string]interface{}, applied map[string]interface{}) error {
	// Support threshold modifications
	if v, ok := changes["fail_threshold_loss"]; ok {
		if threshold, ok := v.(float64); ok {
			if threshold < 0 || threshold > 100 {
				return fmt.Errorf("fail_threshold_loss must be between 0-100")
			}
			applied["scoring.fail_threshold_loss"] = threshold
		} else {
			return fmt.Errorf("fail_threshold_loss must be number")
		}
	}

	if v, ok := changes["fail_threshold_latency"]; ok {
		if threshold, ok := v.(float64); ok {
			if threshold < 10 || threshold > 10000 {
				return fmt.Errorf("fail_threshold_latency must be between 10-10000ms")
			}
			applied["scoring.fail_threshold_latency"] = int(threshold)
		} else {
			return fmt.Errorf("fail_threshold_latency must be number")
		}
	}

	return nil
}

// applyStarlinkConfigChanges applies supported Starlink configuration changes
func (s *Server) applyStarlinkConfigChanges(ctx context.Context, changes map[string]interface{}, applied map[string]interface{}) error {
	// Support dish IP configuration
	if v, ok := changes["dish_ip"]; ok {
		if dishIP, ok := v.(string); ok {
			// Basic IP validation
			if net.ParseIP(dishIP) == nil {
				return fmt.Errorf("dish_ip must be valid IP address")
			}
			applied["starlink.dish_ip"] = dishIP
		} else {
			return fmt.Errorf("dish_ip must be string")
		}
	}

	// Support dish port configuration
	if v, ok := changes["dish_port"]; ok {
		if port, ok := v.(float64); ok {
			portInt := int(port)
			if portInt < 1 || portInt > 65535 {
				return fmt.Errorf("dish_port must be between 1-65535")
			}
			applied["starlink.dish_port"] = portInt
		} else {
			return fmt.Errorf("dish_port must be number")
		}
	}

	return nil
}

// commitUCIChanges applies changes to UCI and commits them
func (s *Server) commitUCIChanges(ctx context.Context, applied map[string]interface{}) error {
	// Load current config
	config, err := s.uciLoader.Load()
	if err != nil {
		return fmt.Errorf("failed to load current UCI config: %w", err)
	}

	// Apply changes to config struct
	for key, value := range applied {
		if err := s.applyConfigValue(config, key, value); err != nil {
			return fmt.Errorf("failed to apply %s: %w", key, err)
		}
	}

	// Save and commit to UCI
	if err := s.uciLoader.Save(config); err != nil {
		return fmt.Errorf("failed to save UCI config: %w", err)
	}

	return nil
}

// applyConfigValue applies a single config value to the config struct
func (s *Server) applyConfigValue(config *uci.Config, key string, value interface{}) error {
	switch key {
	case "main.poll_interval_ms":
		if v, ok := value.(int); ok {
			config.Main.PollIntervalMs = v
		}
	case "main.dry_run":
		if v, ok := value.(bool); ok {
			config.Main.DryRun = v
		}
	case "main.enable":
		if v, ok := value.(bool); ok {
			config.Main.Enable = v
		}
	case "scoring.fail_threshold_loss":
		if v, ok := value.(float64); ok {
			config.Main.FailThresholdLoss = v
		}
	case "scoring.fail_threshold_latency":
		if v, ok := value.(int); ok {
			config.Main.FailThresholdLatency = time.Duration(v) * time.Millisecond
		}
	default:
		return fmt.Errorf("unsupported config key: %s", key)
	}
	return nil
}
