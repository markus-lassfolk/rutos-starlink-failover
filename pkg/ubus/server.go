package ubus

import (
	"context"
	"encoding/json"
	"fmt"
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
		s.client.Disconnect()
		return fmt.Errorf("failed to register methods: %w", err)
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
		s.client.UnregisterObject(context.Background(), "starfail")
		s.client.Disconnect()
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
	ActiveMember    *pkg.Member     `json:"active_member"`
	Members         []pkg.Member    `json:"members"`
	LastSwitch      *pkg.Event      `json:"last_switch,omitempty"`
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
	members, err := s.controller.GetMembers()
	if err != nil {
		members = []*pkg.Member{}
	}

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

	// Calculate uptime (simplified - would need actual start time tracking)
	uptime := time.Since(time.Now().Add(-time.Hour)) // Placeholder

	response := &StatusResponse{
		ActiveMember:    activeMember,
		Members:         members,
		LastSwitch:      lastSwitch,
		Uptime:          uptime,
		DecisionState:   s.decision.GetState(),
		ControllerState: s.controller.GetState(),
		Health: map[string]string{
			"decision_engine": "healthy",
			"controller":      "healthy",
			"telemetry_store": "healthy",
			"ubus_server":     "healthy",
		},
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
	State   string         `json:"state"`
	Status  string         `json:"status"`
}

// GetMembers returns detailed information about all members
func (s *Server) GetMembers() (*MembersResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	members := s.controller.GetMembers()
	memberInfos := make([]MemberInfo, len(members))

	for i, member := range members {
		// Get latest metrics and score
		samples := s.store.GetSamples(member.Name, 1, time.Minute)
		var metrics *types.Metrics
		var score *types.Score

		if len(samples) > 0 {
			metrics = &samples[0].Metrics
			score = &samples[0].Score
		}

		memberInfos[i] = MemberInfo{
			Member:  member,
			Metrics: metrics,
			Score:   score,
			State:   s.decision.GetMemberState(member.Name),
			Status:  s.controller.GetMemberStatus(member.Name),
		}
	}

	return &MembersResponse{Members: memberInfos}, nil
}

// MetricsResponse represents the response for metrics queries
type MetricsResponse struct {
	Member  string         `json:"member"`
	Samples []types.Sample `json:"samples"`
	Period  time.Duration  `json:"period"`
}

// GetMetrics returns historical metrics for a specific member
func (s *Server) GetMetrics(memberName string, hours int) (*MetricsResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	period := time.Duration(hours) * time.Hour
	samples := s.store.GetSamples(memberName, 1000, period) // Limit to 1000 samples

	return &MetricsResponse{
		Member:  memberName,
		Samples: samples,
		Period:  period,
	}, nil
}

// EventsResponse represents the response for events queries
type EventsResponse struct {
	Events []types.Event `json:"events"`
	Period time.Duration `json:"period"`
}

// GetEvents returns historical events
func (s *Server) GetEvents(hours int) (*EventsResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	period := time.Duration(hours) * time.Hour
	events := s.store.GetEvents(1000, period) // Limit to 1000 events

	return &EventsResponse{
		Events: events,
		Period: period,
	}, nil
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
	var targetMember *types.Member
	for _, member := range members {
		if member.Name == req.TargetMember {
			targetMember = &member
			break
		}
	}

	if targetMember == nil {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Member '%s' not found", req.TargetMember),
		}, nil
	}

	// Check if target member is eligible
	if !s.decision.IsMemberEligible(req.TargetMember) {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Member '%s' is not eligible for failover", req.TargetMember),
		}, nil
	}

	// Perform the failover
	err := s.controller.SwitchToMember(req.TargetMember)
	if err != nil {
		return &FailoverResponse{
			Success: false,
			Message: fmt.Sprintf("Failover failed: %v", err),
		}, nil
	}

	// Log the manual failover
	s.logger.Switch("Manual failover triggered", map[string]interface{}{
		"target_member": req.TargetMember,
		"reason":        req.Reason,
		"user":          "ubus",
	})

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

	// Enable automatic decision making
	s.decision.EnableAutomatic()

	// Get current active member
	activeMember := s.controller.GetActiveMember()
	activeMemberName := ""
	if activeMember != nil {
		activeMemberName = activeMember.Name
	}

	// Log the restore
	s.logger.Switch("Automatic failover restored", map[string]interface{}{
		"reason": req.Reason,
		"user":   "ubus",
	})

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
		err := s.decision.RecheckMember(req.Member)
		if err != nil {
			return &RecheckResponse{
				Success: false,
				Message: fmt.Sprintf("Failed to recheck member '%s': %v", req.Member, err),
			}, nil
		}
		checked = []string{req.Member}
	} else {
		// Recheck all members
		members := s.controller.GetMembers()
		for _, member := range members {
			err := s.decision.RecheckMember(member.Name)
			if err == nil {
				checked = append(checked, member.Name)
			}
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
	err := s.logger.SetLevel(req.Level)
	if err != nil {
		return &LogLevelResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to set log level: %v", err),
		}, nil
	}

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

// GetConfig returns the current configuration
func (s *Server) GetConfig() (*ConfigResponse, error) {
	// TODO: Implement configuration retrieval from UCI
	// This would return the parsed configuration from /etc/config/starfail

	config := map[string]interface{}{
		"general": map[string]interface{}{
			"check_interval":    30,
			"decision_interval": 10,
			"retention_hours":   24,
			"max_ram_mb":        50,
		},
		"members": map[string]interface{}{
			"starlink": map[string]interface{}{
				"class":     "starlink",
				"interface": "wan",
				"enabled":   true,
			},
			"cellular": map[string]interface{}{
				"class":     "cellular",
				"interface": "wwan0",
				"enabled":   true,
			},
		},
	}

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

// GetInfo returns system information
func (s *Server) GetInfo() (*InfoResponse, error) {
	// TODO: Implement actual system information gathering
	// This would include real memory usage, statistics, etc.

	info := &InfoResponse{
		Version:   "1.0.0",
		BuildTime: "2024-01-01T00:00:00Z",
		GoVersion: "1.22",
		Platform:  "linux/arm",
		Uptime:    time.Since(time.Now().Add(-time.Hour)), // Placeholder
		MemoryUsage: map[string]interface{}{
			"heap_alloc":    "10MB",
			"heap_sys":      "20MB",
			"heap_idle":     "5MB",
			"heap_inuse":    "15MB",
			"heap_released": "2MB",
			"heap_objects":  1000,
		},
		Stats: map[string]interface{}{
			"total_switches":    10,
			"total_samples":     1000,
			"total_events":      50,
			"active_members":    2,
			"decision_cycles":   100,
			"collection_errors": 5,
		},
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

func (s *Server) handleEvents(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	events, err := s.GetEvents()
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

	result, err := s.Failover(targetMember)
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleRestore(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	result, err := s.Restore()
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Server) handleRecheck(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	result, err := s.Recheck()
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

	result, err := s.SetLogLevel(level)
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
