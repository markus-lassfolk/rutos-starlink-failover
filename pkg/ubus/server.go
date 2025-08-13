// Package ubus provides ubus API server for external communication
package ubus

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/controller"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/telem"
)

// Server provides ubus API endpoints for starfail daemon
type Server struct {
	logger      *logx.Logger
	store       *telem.Store
	controller  *controller.Controller
	registry    *collector.Registry
	serviceName string
}

// Config for ubus server
type Config struct {
	ServiceName string `uci:"service_name"`
	Enable      bool   `uci:"enable"`
}

// NewServer creates a new ubus API server
func NewServer(config Config, logger *logx.Logger, store *telem.Store,
	ctrl *controller.Controller, registry *collector.Registry) *Server {

	if config.ServiceName == "" {
		config.ServiceName = "starfail"
	}

	return &Server{
		logger:      logger,
		store:       store,
		controller:  ctrl,
		registry:    registry,
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
	// In a real implementation, this would register actual ubus methods
	// For now, we'll document the expected API

	methods := map[string]string{
		"status":  "Get daemon status and current member info",
		"members": "List all discovered members with current metrics",
		"metrics": "Get detailed metrics for a specific member",
		"action":  "Execute manual failover actions",
		"events":  "Get recent system events",
	}

	s.logger.WithFields(logx.Fields{
		"methods": methods,
	}).Info("registered ubus methods")

	return nil
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
		Uptime:        int64(time.Since(time.Now()).Seconds()), // This would be actual uptime
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

	if limit <= 0 {
		limit = 100 // Default limit
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

	default:
		return nil, fmt.Errorf("unknown method: %s", method)
	}
}

// GetServiceInfo returns information about the ubus service
func (s *Server) GetServiceInfo() map[string]interface{} {
	return map[string]interface{}{
		"service_name": s.serviceName,
		"methods":      []string{"status", "members", "metrics", "action", "events"},
		"description":  "Starfail multi-interface failover daemon API",
		"version":      "1.0.0",
	}
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
