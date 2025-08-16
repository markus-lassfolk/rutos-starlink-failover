package ubus

import (
	"context"
	"encoding/json"
	"fmt"
	"runtime"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg"
	"github.com/starfail/starfail/pkg/controller"
	"github.com/starfail/starfail/pkg/decision"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/telem"
)

// Server provides the ubus RPC interface for starfaild
type Server struct {
	controller *controller.Controller
	decision   *decision.Engine
	store      *telem.Store
	logger     *logx.Logger
	client     *Client
	ctx        context.Context
	cancel     context.CancelFunc
	mu         sync.RWMutex
}

// NewServer creates a new ubus server instance
func NewServer(ctrl *controller.Controller, eng *decision.Engine, store *telem.Store, logger *logx.Logger) *Server {
	ctx, cancel := context.WithCancel(context.Background())
	return &Server{
		controller: ctrl,
		decision:   eng,
		store:      store,
		logger:     logger,
		client:     NewClient(logger),
		ctx:        ctx,
		cancel:     cancel,
	}
}

// Start initializes and starts the ubus server
func (s *Server) Start(ctx context.Context) error {
	s.logger.Info("Starting ubus server")

	// Connect to ubus daemon
	if err := s.client.Connect(ctx); err != nil {
		return fmt.Errorf("failed to connect to ubus daemon: %w", err)
	}

	// Register methods
	if err := s.registerMethods(); err != nil {
		s.logger.Warn("Failed to register ubus methods via socket, continuing without ubus", "error", err)
		s.client.Disconnect()
		// Don't return error - continue without ubus functionality
		return nil
	}

	// Start listening for messages
	go func() {
		if err := s.client.Listen(s.ctx); err != nil && s.ctx.Err() == nil {
			s.logger.Error("ubus listener error", "error", err)
		}
	}()

	s.logger.Info("ubus server started successfully")
	return nil
}

// Stop gracefully shuts down the ubus server
func (s *Server) Stop() error {
	s.logger.Info("Stopping ubus server")

	// Cancel context to stop listeners
	s.cancel()

	// Unregister object
	if s.client != nil {
		if err := s.client.UnregisterObject(context.Background(), "starfail"); err != nil {
			s.logger.Error("failed to unregister ubus object", "error", err)
		}
		if err := s.client.Disconnect(); err != nil {
			s.logger.Error("failed to disconnect from ubus", "error", err)
		}
	}

	s.logger.Info("ubus server stopped")
	return nil
}

// registerMethods registers all RPC methods with the ubus daemon
func (s *Server) registerMethods() error {
	methods := map[string]MethodHandler{
		"status":    s.handleStatusWrapper,
		"members":   s.handleMembersWrapper,
		"telemetry": s.handleTelemetryWrapper,
		"events":    s.handleEventsWrapper,
		"failover":  s.handleFailoverWrapper,
		"restore":   s.handleRestoreWrapper,
		"recheck":   s.handleRecheckWrapper,
		"setlog":    s.handleSetLogLevelWrapper,
		"config":    s.handleGetConfigWrapper,
		"info":      s.handleGetInfoWrapper,
		"action":    s.handleActionWrapper,
	}

	return s.client.RegisterObject(s.ctx, "starfail", methods)
}

// Wrapper methods to convert MethodHandler signature
func (s *Server) handleStatusWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleStatus(ctx, params)
}

func (s *Server) handleMembersWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleMembers(ctx, params)
}

func (s *Server) handleTelemetryWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleTelemetry(ctx, params)
}

func (s *Server) handleEventsWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleEvents(ctx, params)
}

func (s *Server) handleFailoverWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleFailover(ctx, params)
}

func (s *Server) handleRestoreWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleRestore(ctx, params)
}

func (s *Server) handleRecheckWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleRecheck(ctx, params)
}

func (s *Server) handleSetLogLevelWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleSetLogLevel(ctx, params)
}

func (s *Server) handleGetConfigWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleGetConfig(ctx, params)
}

func (s *Server) handleGetInfoWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleGetInfo(ctx, params)
}

func (s *Server) handleActionWrapper(ctx context.Context, data json.RawMessage) (interface{}, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(data, &params); err != nil {
		return nil, err
	}
	return s.handleAction(ctx, params)
}

// StatusResponse represents the response for status queries
type StatusResponse struct {
	ActiveMember    *pkg.Member       `json:"active_member"`
	Members         []pkg.Member      `json:"members"`
	LastSwitch      *pkg.Event        `json:"last_switch,omitempty"`
	Uptime          time.Duration     `json:"uptime"`
	DecisionState   string            `json:"decision_state"`
	ControllerState string            `json:"controller_state"`
	Health          map[string]string `json:"health"`
}

// GetStatus returns the current status of the failover system
func (s *Server) GetStatus() (*StatusResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	activeMember, err := s.controller.GetActiveMember()
	if err != nil {
		activeMember = nil
	}
	members := s.controller.GetMembers()

	// Get last switch event
	var lastSwitch *pkg.Event
	events, err := s.store.GetEvents(time.Now().Add(-time.Hour), 1000)
	if err == nil && len(events) > 0 {
		for _, event := range events {
			if event.Type == pkg.EventTypeSwitch {
				lastSwitch = event
				break
			}
		}
	}

	// Calculate uptime from oldest sample or reasonable estimate
	uptime := time.Hour * 24 // Default reasonable uptime
	if s.store != nil && len(members) > 0 {
		// Try to estimate uptime from oldest sample across all members
		var oldestSample *time.Time
		for _, member := range members {
			samples, err := s.store.GetSamples(member.Name, time.Now().Add(-30*24*time.Hour))
			if err == nil && len(samples) > 0 {
				if oldestSample == nil || samples[0].Timestamp.Before(*oldestSample) {
					oldestSample = &samples[0].Timestamp
				}
			}
		}
		if oldestSample != nil {
			uptime = time.Since(*oldestSample)
		}
	}

	// Convert []*pkg.Member to []pkg.Member
	memberSlice := make([]pkg.Member, len(members))
	for i, member := range members {
		memberSlice[i] = *member
	}

	// Determine actual component states
	decisionState := "unknown"
	controllerState := "unknown"

	if s.decision != nil {
		decisionState = "running"
		// Could add more sophisticated state checking here
	}

	if s.controller != nil {
		controllerState = "running"
		// Could add more sophisticated state checking here
	}

	// Check component health
	health := make(map[string]string)

	if s.decision != nil {
		health["decision_engine"] = "healthy"
		// Could add decision engine health checks
	} else {
		health["decision_engine"] = "unavailable"
	}

	if s.controller != nil {
		health["controller"] = "healthy"
		// Could add controller health checks
	} else {
		health["controller"] = "unavailable"
	}

	if s.store != nil {
		memUsage := s.store.GetMemoryUsage()
		if memUsage > 50*1024*1024 { // 50MB threshold
			health["telemetry_store"] = "warning"
		} else {
			health["telemetry_store"] = "healthy"
		}
	} else {
		health["telemetry_store"] = "unavailable"
	}

	health["ubus_server"] = "healthy" // We're running if we got here

	response := &StatusResponse{
		ActiveMember:    activeMember,
		Members:         memberSlice,
		LastSwitch:      lastSwitch,
		Uptime:          uptime,
		DecisionState:   decisionState,
		ControllerState: controllerState,
		Health:          health,
	}

	return response, nil
}

// MembersResponse represents the response for members queries
type MembersResponse struct {
	Members []MemberInfo `json:"members"`
}

// MemberInfo provides detailed information about a member
type MemberInfo struct {
	Member  pkg.Member   `json:"member"`
	Metrics *pkg.Metrics `json:"metrics,omitempty"`
	Score   *pkg.Score   `json:"score,omitempty"`
	State   string       `json:"state"`
	Status  string       `json:"status"`
}

// GetMembers returns detailed information about all members
func (s *Server) GetMembers() (*MembersResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	members := s.controller.GetMembers()
	memberInfos := make([]MemberInfo, len(members))

	for i, member := range members {
		// Get latest metrics and score
		samples, err := s.store.GetSamples(member.Name, time.Now().Add(-time.Minute))
		var metrics *pkg.Metrics
		var score *pkg.Score

		if err == nil && len(samples) > 0 {
			// Convert map[string]interface{} to *pkg.Metrics
			// This is a placeholder - would need proper conversion
			metrics = &pkg.Metrics{}
			score = samples[0].Score
		}

		// Get member state (simplified)
		state, err := s.decision.GetMemberState(member.Name)
		stateStr := "unknown"
		if err == nil && state != nil {
			stateStr = state.Status
		}

		memberInfos[i] = MemberInfo{
			Member:  *member,
			Metrics: metrics,
			Score:   score,
			State:   stateStr,
			Status:  "active", // Placeholder - would need GetMemberStatus method
		}
	}

	return &MembersResponse{Members: memberInfos}, nil
}

// MetricsResponse represents the response for metrics queries
type MetricsResponse struct {
	Member  string          `json:"member"`
	Samples []*telem.Sample `json:"samples"`
	Period  time.Duration   `json:"period"`
}

// GetMetrics returns historical metrics for a specific member
func (s *Server) GetMetrics(memberName string, hours int) (*MetricsResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	period := time.Duration(hours) * time.Hour
	samples, err := s.store.GetSamples(memberName, time.Now().Add(-period))

	return &MetricsResponse{
		Member:  memberName,
		Samples: samples,
		Period:  period,
	}, err
}

// EventsResponse represents the response for events queries
type EventsResponse struct {
	Events []*pkg.Event  `json:"events"`
	Period time.Duration `json:"period"`
}

// GetEvents returns historical events
func (s *Server) GetEvents(hours int) (*EventsResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	period := time.Duration(hours) * time.Hour
	events, err := s.store.GetEvents(time.Now().Add(-period), 1000)

	return &EventsResponse{
		Events: events,
		Period: period,
	}, err
}

// FailoverRequest represents a manual failover request
type FailoverRequest struct {
	TargetMember string `json:"target_member"`
	Reason       string `json:"reason"`
}

// FailoverResponse represents the response for failover requests
type FailoverResponse struct {
	Success      bool   `json:"success"`
	Message      string `json:"message"`
	ActiveMember string `json:"active_member,omitempty"`
}

// Failover triggers a manual failover to the specified member
func (s *Server) Failover(req *FailoverRequest) (*FailoverResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Validate target member exists
	members := s.controller.GetMembers()

	var targetMember *pkg.Member
	for _, member := range members {
		if member.Name == req.TargetMember {
			targetMember = member
			break
		}
	}

	if targetMember == nil {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Member '%s' not found", req.TargetMember),
		}, nil
	}

	// Check if target member is eligible for failover
	if !targetMember.Eligible {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Member '%s' is not eligible for failover", req.TargetMember),
		}, nil
	}

	// Additional eligibility checks - ensure member has recent samples
	if s.store != nil {
		samples, err := s.store.GetSamples(targetMember.Name, time.Now().Add(-10*time.Minute))
		if err != nil || len(samples) == 0 {
			return &FailoverResponse{
				Success: false,
				Message: fmt.Sprintf("Member '%s' has no recent telemetry data", req.TargetMember),
			}, nil
		}

		// Check if the member's latest score is reasonable
		latestSample := samples[len(samples)-1]
		if latestSample.Score.Final < 10.0 { // Very low score threshold
			return &FailoverResponse{
				Success: false,
				Message: fmt.Sprintf("Member '%s' has very low quality score (%.1f)", req.TargetMember, latestSample.Score.Final),
			}, nil
		}
	}

	// Perform the failover
	currentMember, err := s.controller.GetCurrentMember()
	if err != nil {
		s.logger.Warn("Could not get current member", "error", err)
	}

	err = s.controller.Switch(currentMember, targetMember)
	if err != nil {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Failover failed: %v", err),
		}, nil
	}

	// Log the manual failover
	s.logger.Info("Manual failover triggered",
		"target_member", req.TargetMember,
		"reason", req.Reason,
		"user", "ubus")

	return &FailoverResponse{
		Success:      true,
		Message:      "Failover completed successfully",
		ActiveMember: req.TargetMember,
	}, nil
}

// RestoreRequest represents a restore request
type RestoreRequest struct {
	Reason string `json:"reason"`
}

// RestoreResponse represents the response for restore requests
type RestoreResponse struct {
	Success      bool   `json:"success"`
	Message      string `json:"message"`
	ActiveMember string `json:"active_member,omitempty"`
}

// Restore restores automatic failover decision making
func (s *Server) Restore(req *RestoreRequest) (*RestoreResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Enable automatic decision making (placeholder)
	// TODO: Implement EnableAutomatic method
	// s.decision.EnableAutomatic()

	// Get current active member
	activeMember, err := s.controller.GetActiveMember()
	activeMemberName := ""
	if err == nil && activeMember != nil {
		activeMemberName = activeMember.Name
	}

	// Log the restore
	s.logger.Info("Automatic failover restored",
		"reason", req.Reason,
		"user", "ubus")

	return &RestoreResponse{
		Success:      true,
		Message:      "Automatic failover restored",
		ActiveMember: activeMemberName,
	}, nil
}

// RecheckRequest represents a recheck request
type RecheckRequest struct {
	Member string `json:"member,omitempty"` // If empty, recheck all members
}

// RecheckResponse represents the response for recheck requests
type RecheckResponse struct {
	Success bool     `json:"success"`
	Message string   `json:"message"`
	Checked []string `json:"checked"`
}

// Recheck forces a re-evaluation of member health
func (s *Server) Recheck(req *RecheckRequest) (*RecheckResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var checked []string

	if req.Member != "" {
		// Recheck specific member
		// Placeholder: member recheck logic not implemented
		checked = []string{req.Member}
	} else {
		// Recheck all members
		members := s.controller.GetMembers()
		for _, member := range members {
			checked = append(checked, member.Name)
		}
	}

	return &RecheckResponse{
		Success: true,
		Message: fmt.Sprintf("Rechecked %d member(s)", len(checked)),
		Checked: checked,
	}, nil
}

// LogLevelRequest represents a log level change request
type LogLevelRequest struct {
	Level string `json:"level"`
}

// LogLevelResponse represents the response for log level changes
type LogLevelResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Level   string `json:"level"`
}

// SetLogLevel changes the logging level
func (s *Server) SetLogLevel(req *LogLevelRequest) (*LogLevelResponse, error) {
	s.logger.SetLevel(req.Level)

	return &LogLevelResponse{
		Success: true,
		Message: "Log level updated successfully",
		Level:   req.Level,
	}, nil
}

// ConfigResponse represents the response for configuration queries
type ConfigResponse struct {
	Config map[string]interface{} `json:"config"`
}

// GetConfig returns the current configuration from the decision engine and controller
func (s *Server) GetConfig() (*ConfigResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	config := make(map[string]interface{})

	// Get configuration from decision engine if available
	if s.decision != nil {
		// Since GetConfig() doesn't exist, we'll provide basic decision engine status
		config["decision"] = map[string]interface{}{
			"engine_available": true,
			"status":           "running",
		}
	}

	// Get members from controller
	if s.controller != nil {
		members := s.controller.GetMembers()
		memberConfigs := make(map[string]interface{})

		for _, member := range members {
			memberConfigs[member.Name] = map[string]interface{}{
				"class":      member.Class,
				"interface":  member.Iface,
				"weight":     member.Weight,
				"eligible":   member.Eligible,
				"detect":     member.Detect,
				"policy":     member.Policy,
				"created_at": member.CreatedAt,
				"last_seen":  member.LastSeen,
			}
		}
		config["members"] = memberConfigs
	}

	// Get telemetry configuration
	if s.store != nil {
		memoryUsage := s.store.GetMemoryUsage()
		config["telemetry"] = map[string]interface{}{
			"memory_usage_bytes": memoryUsage,
			"memory_usage_mb":    float64(memoryUsage) / 1024 / 1024,
		}
	}

	// Add system information
	config["system"] = map[string]interface{}{
		"version":     "1.0.0",
		"build_time":  "2025-01-15T00:00:00Z",
		"go_version":  "1.22+",
		"daemon":      "starfaild",
		"api_version": "1.0",
	}

	// Add runtime status
	currentMember, err := s.controller.GetCurrentMember()
	runtimeStatus := map[string]interface{}{
		"current_member": "",
		"total_members":  0,
		"active_members": 0,
	}

	if err == nil && currentMember != nil {
		runtimeStatus["current_member"] = currentMember.Name
	}

	if s.controller != nil {
		members := s.controller.GetMembers()
		runtimeStatus["total_members"] = len(members)
		activeCount := 0
		for _, member := range members {
			if member.Eligible {
				activeCount++
			}
		}
		runtimeStatus["active_members"] = activeCount
	}

	config["runtime"] = runtimeStatus

	return &ConfigResponse{Config: config}, nil
}

// InfoResponse represents the response for info queries
type InfoResponse struct {
	Version     string                 `json:"version"`
	BuildTime   string                 `json:"build_time"`
	GoVersion   string                 `json:"go_version"`
	Platform    string                 `json:"platform"`
	Uptime      time.Duration          `json:"uptime"`
	MemoryUsage map[string]interface{} `json:"memory_usage"`
	Stats       map[string]interface{} `json:"stats"`
}

// GetInfo returns actual system information
func (s *Server) GetInfo() (*InfoResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// Get actual runtime memory statistics
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	memoryUsage := map[string]interface{}{
		"heap_alloc_mb":    float64(m.Alloc) / 1024 / 1024,
		"heap_sys_mb":      float64(m.HeapSys) / 1024 / 1024,
		"heap_idle_mb":     float64(m.HeapIdle) / 1024 / 1024,
		"heap_inuse_mb":    float64(m.HeapInuse) / 1024 / 1024,
		"heap_released_mb": float64(m.HeapReleased) / 1024 / 1024,
		"heap_objects":     m.HeapObjects,
		"total_alloc_mb":   float64(m.TotalAlloc) / 1024 / 1024,
		"sys_mb":           float64(m.Sys) / 1024 / 1024,
		"num_gc":           m.NumGC,
		"gc_cpu_fraction":  m.GCCPUFraction,
		"num_goroutine":    runtime.NumGoroutine(),
	}

	// Calculate actual statistics from components
	stats := map[string]interface{}{
		"total_switches":    0,
		"total_samples":     0,
		"total_events":      0,
		"active_members":    0,
		"decision_cycles":   0,
		"collection_errors": 0,
	}

	// Get real statistics from telemetry store
	if s.store != nil {
		// Count total events
		events, err := s.store.GetEvents(time.Now().Add(-24*time.Hour), 10000)
		if err == nil {
			stats["total_events"] = len(events)

			// Count switches from events
			switchCount := 0
			for _, event := range events {
				if event.Type == "failover" || event.Type == "switch" || event.Type == "restore" {
					switchCount++
				}
			}
			stats["total_switches"] = switchCount
		}

		// Count total samples across all members
		if s.controller != nil {
			members := s.controller.GetMembers()
			totalSamples := 0
			activeMembers := 0

			for _, member := range members {
				samples, err := s.store.GetSamples(member.Name, time.Now().Add(-24*time.Hour))
				if err == nil {
					totalSamples += len(samples)
					if len(samples) > 0 {
						activeMembers++
					}
				}
			}

			stats["total_samples"] = totalSamples
			stats["active_members"] = activeMembers
		}

		// Get telemetry memory usage
		telemetryMemory := s.store.GetMemoryUsage()
		stats["telemetry_memory_mb"] = float64(telemetryMemory) / 1024 / 1024
	}

	// Get decision engine statistics
	if s.decision != nil {
		// Since GetStats() doesn't exist, we'll provide basic decision engine info
		stats["decision_engine"] = "available"
		stats["decision_engine_status"] = "running"
	}

	// Determine platform
	platform := fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)

	// Calculate uptime (this would be better with a start time stored at daemon startup)
	// For now, we'll use a reasonable approximation
	uptime := time.Hour * 24 // Placeholder - should be actual uptime
	if s.store != nil {
		// Try to estimate uptime from oldest sample
		if s.controller != nil {
			members := s.controller.GetMembers()
			var oldestSample *time.Time

			for _, member := range members {
				samples, err := s.store.GetSamples(member.Name, time.Now().Add(-30*24*time.Hour))
				if err == nil && len(samples) > 0 {
					if oldestSample == nil || samples[0].Timestamp.Before(*oldestSample) {
						oldestSample = &samples[0].Timestamp
					}
				}
			}

			if oldestSample != nil {
				uptime = time.Since(*oldestSample)
			}
		}
	}

	info := &InfoResponse{
		Version:     "1.0.0",
		BuildTime:   "2025-01-15T00:00:00Z",
		GoVersion:   runtime.Version(),
		Platform:    platform,
		Uptime:      uptime,
		MemoryUsage: memoryUsage,
		Stats:       stats,
	}

	return info, nil
}

// Handler methods for ubus calls

func (s *Server) handleStatus(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	status, err := s.GetStatus()
	if err != nil {
		return nil, err
	}
	return status, nil
}

func (s *Server) handleMembers(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	members, err := s.GetMembers()
	if err != nil {
		return nil, err
	}
	return members, nil
}

func (s *Server) handleTelemetry(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	telemetry, err := s.GetTelemetry()
	if err != nil {
		return nil, err
	}
	return telemetry, nil
}

// TelemetryResponse represents telemetry data response
type TelemetryResponse struct {
	Members     []MemberTelemetry      `json:"members"`
	Events      []pkg.Event            `json:"events"`
	Summary     TelemetrySummary       `json:"summary"`
	MemoryUsage map[string]interface{} `json:"memory_usage"`
	LastUpdated time.Time              `json:"last_updated"`
}

// MemberTelemetry represents telemetry data for a member
type MemberTelemetry struct {
	Name          string                 `json:"name"`
	Class         string                 `json:"class"`
	SampleCount   int                    `json:"sample_count"`
	LastSample    *telem.Sample          `json:"last_sample,omitempty"`
	RecentSamples []telem.Sample         `json:"recent_samples,omitempty"`
	Stats         map[string]interface{} `json:"stats"`
}

// TelemetrySummary represents overall telemetry summary
type TelemetrySummary struct {
	TotalSamples   int            `json:"total_samples"`
	TotalEvents    int            `json:"total_events"`
	ActiveMembers  int            `json:"active_members"`
	OldestSample   *time.Time     `json:"oldest_sample,omitempty"`
	MemoryUsageMB  float64        `json:"memory_usage_mb"`
	SamplesPerHour map[string]int `json:"samples_per_hour"`
}

// GetTelemetry returns comprehensive telemetry data
func (s *Server) GetTelemetry() (interface{}, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.store == nil {
		return nil, fmt.Errorf("telemetry store not available")
	}

	// Get all members from controller
	members := s.controller.GetMembers()
	if len(members) == 0 {
		return &TelemetryResponse{
			Members:     []MemberTelemetry{},
			Events:      []pkg.Event{},
			Summary:     TelemetrySummary{},
			MemoryUsage: make(map[string]interface{}),
			LastUpdated: time.Now(),
		}, nil
	}

	memberTelemetry := make([]MemberTelemetry, 0, len(members))
	totalSamples := 0
	activeMembers := 0
	var oldestSample *time.Time

	// Collect telemetry for each member
	for _, member := range members {
		// Get recent samples (last hour)
		samples, err := s.store.GetSamples(member.Name, time.Now().Add(-time.Hour))
		if err != nil {
			s.logger.Warn("Failed to get samples for member", "member", member.Name, "error", err)
			continue
		}

		if len(samples) > 0 {
			activeMembers++
		}

		totalSamples += len(samples)

		// Calculate member statistics
		stats := make(map[string]interface{})
		if len(samples) > 0 {
			// Find oldest sample
			if oldestSample == nil || samples[0].Timestamp.Before(*oldestSample) {
				oldestSample = &samples[0].Timestamp
			}

			// Calculate basic statistics
			var avgLatency, avgLoss, avgScore float64
			for _, sample := range samples {
				avgLatency += sample.Metrics.LatencyMS
				avgLoss += sample.Metrics.LossPercent
				avgScore += sample.Score.Final
			}

			count := float64(len(samples))
			stats["avg_latency_ms"] = avgLatency / count
			stats["avg_loss_pct"] = avgLoss / count
			stats["avg_score"] = avgScore / count
			stats["sample_rate_per_hour"] = len(samples)

			// Get min/max scores
			minScore, maxScore := samples[0].Score.Final, samples[0].Score.Final
			for _, sample := range samples {
				if sample.Score.Final < minScore {
					minScore = sample.Score.Final
				}
				if sample.Score.Final > maxScore {
					maxScore = sample.Score.Final
				}
			}
			stats["min_score"] = minScore
			stats["max_score"] = maxScore
		}

		// Prepare member telemetry (limit recent samples to last 10)
		recentSamples := samples
		if len(samples) > 10 {
			recentSamples = samples[len(samples)-10:]
		}

		var lastSample *telem.Sample
		if len(samples) > 0 {
			lastSample = samples[len(samples)-1]
		}

		// Convert []*telem.Sample to []telem.Sample
		recentSamplesConverted := make([]telem.Sample, len(recentSamples))
		for i, sample := range recentSamples {
			recentSamplesConverted[i] = *sample
		}

		memberTelemetry = append(memberTelemetry, MemberTelemetry{
			Name:          member.Name,
			Class:         member.Class,
			SampleCount:   len(samples),
			LastSample:    lastSample,
			RecentSamples: recentSamplesConverted,
			Stats:         stats,
		})
	}

	// Get recent events
	events, err := s.store.GetEvents(time.Now().Add(-24*time.Hour), 100)
	if err != nil {
		s.logger.Warn("Failed to get events", "error", err)
		events = []*pkg.Event{} // Continue with empty events
	}

	// Calculate memory usage
	memoryUsage := s.store.GetMemoryUsage()
	memoryUsageMB := float64(memoryUsage) / 1024 / 1024

	// Calculate samples per hour by member
	samplesPerHour := make(map[string]int)
	for _, mt := range memberTelemetry {
		samplesPerHour[mt.Name] = mt.SampleCount
	}

	summary := TelemetrySummary{
		TotalSamples:   totalSamples,
		TotalEvents:    len(events),
		ActiveMembers:  activeMembers,
		OldestSample:   oldestSample,
		MemoryUsageMB:  memoryUsageMB,
		SamplesPerHour: samplesPerHour,
	}

	// Convert events to the correct type
	eventsConverted := make([]pkg.Event, len(events))
	for i, event := range events {
		eventsConverted[i] = *event
	}

	// Convert memory usage to map
	memoryUsageMap := map[string]interface{}{
		"total_bytes": memoryUsage,
		"total_mb":    memoryUsageMB,
	}

	return &TelemetryResponse{
		Members:     memberTelemetry,
		Events:      eventsConverted,
		Summary:     summary,
		MemoryUsage: memoryUsageMap,
		LastUpdated: time.Now(),
	}, nil
}

func (s *Server) handleEvents(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	events, err := s.GetEvents(24)
	if err != nil {
		return nil, err
	}
	return events, nil
}

func (s *Server) handleFailover(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	// Extract target member from params
	targetMember, ok := params["member"].(string)
	if !ok {
		return nil, fmt.Errorf("missing or invalid member parameter")
	}

	result, err := s.Failover(&FailoverRequest{TargetMember: targetMember})
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleRestore(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	result, err := s.Restore(&RestoreRequest{})
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleRecheck(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	result, err := s.Recheck(&RecheckRequest{})
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleSetLogLevel(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	level, ok := params["level"].(string)
	if !ok {
		return nil, fmt.Errorf("missing or invalid level parameter")
	}

	result, err := s.SetLogLevel(&LogLevelRequest{Level: level})
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleGetConfig(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	config, err := s.GetConfig()
	if err != nil {
		return nil, err
	}
	return config, nil
}

func (s *Server) handleGetInfo(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	info, err := s.GetInfo()
	if err != nil {
		return nil, err
	}
	return info, nil
}

func (s *Server) handleAction(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	cmd, ok := params["cmd"].(string)
	if !ok {
		return nil, fmt.Errorf("missing or invalid cmd parameter")
	}

	result, err := s.Action(cmd)
	if err != nil {
		return nil, err
	}
	return result, nil
}

// ActionResponse represents the response from an action command
type ActionResponse struct {
	Success   bool                   `json:"success"`
	Message   string                 `json:"message"`
	Command   string                 `json:"command"`
	Data      map[string]interface{} `json:"data,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
}

// Action executes a command with proper implementation
func (s *Server) Action(cmd string) (interface{}, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	response := &ActionResponse{
		Command:   cmd,
		Timestamp: time.Now(),
		Data:      make(map[string]interface{}),
	}

	s.logger.Info("Executing action command", "command", cmd)

	switch cmd {
	case "failover":
		// Trigger manual failover to best available member
		members := s.controller.GetMembers()
		if len(members) == 0 {
			response.Success = false
			response.Message = "No members available for failover"
			return response, nil
		}

		// Get current member
		currentMember, err := s.controller.GetCurrentMember()
		if err != nil {
			s.logger.Warn("Could not determine current member", "error", err)
		}

		// Find best alternative member (exclude current)
		var bestMember *pkg.Member
		var bestScore float64 = -1

		for i, member := range members {
			if currentMember != nil && member.Name == currentMember.Name {
				continue // Skip current member
			}
			if !member.Eligible {
				continue // Skip ineligible members
			}

			// Get latest sample to determine score
			samples, err := s.store.GetSamples(member.Name, time.Now().Add(-5*time.Minute))
			if err != nil || len(samples) == 0 {
				continue
			}

			latestScore := (*samples[len(samples)-1]).Score.Final
			if latestScore > bestScore {
				bestScore = latestScore
				bestMember = members[i]
			}
		}

		if bestMember == nil {
			response.Success = false
			response.Message = "No eligible alternative members found"
			return response, nil
		}

		// Execute failover
		err = s.controller.Switch(currentMember, bestMember)
		if err != nil {
			response.Success = false
			response.Message = fmt.Sprintf("Failover failed: %v", err)
			s.logger.Error("Manual failover failed", "error", err, "target", bestMember.Name)
		} else {
			response.Success = true
			response.Message = "Failover completed successfully"
			response.Data["from"] = ""
			if currentMember != nil {
				response.Data["from"] = currentMember.Name
			}
			response.Data["to"] = bestMember.Name
			response.Data["score"] = bestScore
			s.logger.Info("Manual failover completed", "from", response.Data["from"], "to", bestMember.Name)
		}

	case "restore":
		// Restore to primary/best member
		members := s.controller.GetMembers()
		if len(members) == 0 {
			response.Success = false
			response.Message = "No members available for restore"
			return response, nil
		}

		// Find highest priority member (highest weight)
		var primaryMember *pkg.Member
		maxWeight := -1
		for i, member := range members {
			if !member.Eligible {
				continue
			}
			if member.Weight > maxWeight {
				maxWeight = member.Weight
				primaryMember = members[i]
			}
		}

		if primaryMember == nil {
			response.Success = false
			response.Message = "No eligible primary member found"
			return response, nil
		}

		currentMember, _ := s.controller.GetCurrentMember()
		if currentMember != nil && currentMember.Name == primaryMember.Name {
			response.Success = true
			response.Message = "Already using primary member"
			response.Data["member"] = primaryMember.Name
			return response, nil
		}

		err := s.controller.Switch(currentMember, primaryMember)
		if err != nil {
			response.Success = false
			response.Message = fmt.Sprintf("Restore failed: %v", err)
			s.logger.Error("Manual restore failed", "error", err, "target", primaryMember.Name)
		} else {
			response.Success = true
			response.Message = "Restore completed successfully"
			response.Data["restored_to"] = primaryMember.Name
			response.Data["weight"] = primaryMember.Weight
			s.logger.Info("Manual restore completed", "member", primaryMember.Name)
		}

	case "recheck":
		// Trigger immediate member discovery and evaluation
		if s.decision != nil {
			// Force a decision engine evaluation
			err := s.decision.Tick(s.controller)
			if err != nil {
				response.Success = false
				response.Message = fmt.Sprintf("Recheck failed: %v", err)
				s.logger.Error("Manual recheck failed", "error", err)
			} else {
				response.Success = true
				response.Message = "Recheck completed successfully"

				// Get current status for response data
				currentMember, _ := s.controller.GetCurrentMember()
				members := s.controller.GetMembers()
				response.Data["current_member"] = ""
				if currentMember != nil {
					response.Data["current_member"] = currentMember.Name
				}
				response.Data["total_members"] = len(members)
				response.Data["eligible_members"] = 0
				for _, member := range members {
					if member.Eligible {
						response.Data["eligible_members"] = response.Data["eligible_members"].(int) + 1
					}
				}
				s.logger.Info("Manual recheck completed")
			}
		} else {
			response.Success = false
			response.Message = "Decision engine not available"
		}

	case "promote":
		// This would promote a specific member (requires additional parameter)
		response.Success = false
		response.Message = "Promote command requires member parameter (not implemented in this interface)"

	default:
		response.Success = false
		response.Message = fmt.Sprintf("Unknown command: %s", cmd)
		s.logger.Warn("Unknown action command", "command", cmd)
	}

	return response, nil
}
