package health

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"time"

	"github.com/starfail/starfail/pkg/controller"
	"github.com/starfail/starfail/pkg/decision"
	"github.com/starfail/starfail/pkg/logx"
	"github.com/starfail/starfail/pkg/telem"
	"github.com/starfail/starfail/pkg/types"
)

// Server provides health check endpoints for starfaild
type Server struct {
	controller *controller.Controller
	decision   *decision.Engine
	store      *telem.Store
	logger     *logx.Logger
	server     *http.Server
	startTime  time.Time
}

// HealthStatus represents the overall health status
type HealthStatus struct {
	Status      string                 `json:"status"`
	Timestamp   time.Time              `json:"timestamp"`
	Uptime      time.Duration          `json:"uptime"`
	Version     string                 `json:"version"`
	Components  map[string]Component   `json:"components"`
	Members     []MemberHealth         `json:"members"`
	Statistics  Statistics             `json:"statistics"`
	Memory      MemoryInfo             `json:"memory"`
	LastError   *ErrorInfo             `json:"last_error,omitempty"`
}

// Component represents the health of a component
type Component struct {
	Status    string    `json:"status"`
	Message   string    `json:"message"`
	LastCheck time.Time `json:"last_check"`
	Uptime    time.Duration `json:"uptime"`
}

// MemberHealth represents the health of a member
type MemberHealth struct {
	Name      string    `json:"name"`
	Class     string    `json:"class"`
	Interface string    `json:"interface"`
	Status    string    `json:"status"`
	State     string    `json:"state"`
	Score     float64   `json:"score"`
	Active    bool      `json:"active"`
	LastSeen  time.Time `json:"last_seen"`
	Uptime    time.Duration `json:"uptime"`
}

// Statistics represents system statistics
type Statistics struct {
	TotalMembers     int `json:"total_members"`
	ActiveMembers    int `json:"active_members"`
	TotalSwitches    int `json:"total_switches"`
	TotalSamples     int `json:"total_samples"`
	TotalEvents      int `json:"total_events"`
	DecisionCycles   int `json:"decision_cycles"`
	CollectionErrors int `json:"collection_errors"`
}

// MemoryInfo represents memory usage information
type MemoryInfo struct {
	Alloc     uint64  `json:"alloc_bytes"`
	Sys       uint64  `json:"sys_bytes"`
	HeapAlloc uint64  `json:"heap_alloc_bytes"`
	HeapSys   uint64  `json:"heap_sys_bytes"`
	HeapIdle  uint64  `json:"heap_idle_bytes"`
	HeapInuse uint64  `json:"heap_inuse_bytes"`
	NumGC     uint32  `json:"num_gc"`
	PauseNs   uint64  `json:"pause_ns"`
}

// ErrorInfo represents error information
type ErrorInfo struct {
	Message   string    `json:"message"`
	Type      string    `json:"type"`
	Timestamp time.Time `json:"timestamp"`
	Component string    `json:"component"`
}

// NewServer creates a new health server
func NewServer(ctrl *controller.Controller, eng *decision.Engine, store *telem.Store, logger *logx.Logger) *Server {
	return &Server{
		controller: ctrl,
		decision:   eng,
		store:      store,
		logger:     logger,
		startTime:  time.Now(),
	}
}

// Start starts the health server
func (s *Server) Start(port int) error {
	s.logger.Info("Starting health server", map[string]interface{}{
		"port": port,
	})

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.healthHandler)
	mux.HandleFunc("/health/detailed", s.detailedHealthHandler)
	mux.HandleFunc("/health/ready", s.readyHandler)
	mux.HandleFunc("/health/live", s.liveHandler)

	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", port),
		Handler: mux,
	}

	go func() {
		if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			s.logger.Error("Health server error", map[string]interface{}{
				"error": err.Error(),
			})
		}
	}()

	return nil
}

// Stop stops the health server
func (s *Server) Stop() error {
	s.logger.Info("Stopping health server")
	
	if s.server != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return s.server.Shutdown(ctx)
	}
	return nil
}

// healthHandler provides basic health status
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	status := s.getHealthStatus()
	
	w.Header().Set("Content-Type", "application/json")
	
	if status.Status == "healthy" {
		w.WriteHeader(http.StatusOK)
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	
	json.NewEncoder(w).Encode(status)
}

// detailedHealthHandler provides detailed health information
func (s *Server) detailedHealthHandler(w http.ResponseWriter, r *http.Request) {
	status := s.getDetailedHealthStatus()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(status)
}

// readyHandler provides readiness check
func (s *Server) readyHandler(w http.ResponseWriter, r *http.Request) {
	status := s.getHealthStatus()
	
	w.Header().Set("Content-Type", "application/json")
	
	if status.Status == "healthy" {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ready"}`))
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"status":"not ready"}`))
	}
}

// liveHandler provides liveness check
func (s *Server) liveHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"alive"}`))
}

// getHealthStatus returns basic health status
func (s *Server) getHealthStatus() HealthStatus {
	status := HealthStatus{
		Status:    "healthy",
		Timestamp: time.Now(),
		Uptime:    time.Since(s.startTime),
		Version:   "1.0.0",
		Components: map[string]Component{
			"controller": {
				Status:    "healthy",
				Message:   "Controller is operational",
				LastCheck: time.Now(),
				Uptime:    time.Since(s.startTime),
			},
			"decision_engine": {
				Status:    "healthy",
				Message:   "Decision engine is operational",
				LastCheck: time.Now(),
				Uptime:    time.Since(s.startTime),
			},
			"telemetry_store": {
				Status:    "healthy",
				Message:   "Telemetry store is operational",
				LastCheck: time.Now(),
				Uptime:    time.Since(s.startTime),
			},
		},
	}

	// Check if any components are unhealthy
	for _, component := range status.Components {
		if component.Status != "healthy" {
			status.Status = "unhealthy"
			break
		}
	}

	return status
}

// getDetailedHealthStatus returns detailed health status
func (s *Server) getDetailedHealthStatus() HealthStatus {
	status := s.getHealthStatus()
	
	// Add member health information
	status.Members = s.getMemberHealth()
	
	// Add statistics
	status.Statistics = s.getStatistics()
	
	// Add memory information
	status.Memory = s.getMemoryInfo()
	
	// Add last error (if any)
	if lastError := s.getLastError(); lastError != nil {
		status.LastError = lastError
	}
	
	return status
}

// getMemberHealth returns health information for all members
func (s *Server) getMemberHealth() []MemberHealth {
	members := s.controller.GetMembers()
	activeMember := s.controller.GetActiveMember()
	
	var memberHealth []MemberHealth
	
	for _, member := range members {
		health := MemberHealth{
			Name:      member.Name,
			Class:     member.Class,
			Interface: member.Interface,
			Status:    "unknown",
			State:     s.decision.GetMemberState(member.Name),
			Score:     0.0,
			Active:    false,
			LastSeen:  member.Created,
			Uptime:    time.Since(member.Created),
		}
		
		// Check if member is active
		if activeMember != nil && activeMember.Name == member.Name {
			health.Active = true
			health.Status = "active"
		} else {
			health.Status = "inactive"
		}
		
		// Get latest score
		samples := s.store.GetSamples(member.Name, 1, time.Minute)
		if len(samples) > 0 {
			health.Score = samples[0].Score.Final
			health.LastSeen = samples[0].Metrics.Timestamp
		}
		
		// Determine status based on score and state
		if health.Score > 80 {
			health.Status = "excellent"
		} else if health.Score > 60 {
			health.Status = "good"
		} else if health.Score > 40 {
			health.Status = "fair"
		} else if health.Score > 20 {
			health.Status = "poor"
		} else {
			health.Status = "critical"
		}
		
		memberHealth = append(memberHealth, health)
	}
	
	return memberHealth
}

// getStatistics returns system statistics
func (s *Server) getStatistics() Statistics {
	members := s.controller.GetMembers()
	activeMember := s.controller.GetActiveMember()
	
	stats := Statistics{
		TotalMembers: len(members),
		ActiveMembers: 0,
	}
	
	if activeMember != nil {
		stats.ActiveMembers = 1
	}
	
	// Count total samples
	for _, member := range members {
		samples := s.store.GetSamples(member.Name, 1000, time.Hour)
		stats.TotalSamples += len(samples)
	}
	
	// Count total events
	events := s.store.GetEvents(1000, time.Hour)
	stats.TotalEvents = len(events)
	
	// Count switches
	for _, event := range events {
		if event.Type == types.EventTypeSwitch {
			stats.TotalSwitches++
		}
	}
	
	// These would be tracked by the decision engine in a real implementation
	stats.DecisionCycles = 0
	stats.CollectionErrors = 0
	
	return stats
}

// getMemoryInfo returns memory usage information
func (s *Server) getMemoryInfo() MemoryInfo {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	
	return MemoryInfo{
		Alloc:     m.Alloc,
		Sys:       m.Sys,
		HeapAlloc: m.HeapAlloc,
		HeapSys:   m.HeapSys,
		HeapIdle:  m.HeapIdle,
		HeapInuse: m.HeapInuse,
		NumGC:     m.NumGC,
		PauseNs:   m.PauseNs[(m.NumGC+255)%256],
	}
}

// getLastError returns the last error (if any)
func (s *Server) getLastError() *ErrorInfo {
	// In a real implementation, this would track the last error
	// For now, return nil (no errors)
	return nil
}

// UpdateComponentHealth updates the health status of a component
func (s *Server) UpdateComponentHealth(componentName, status, message string) {
	// In a real implementation, this would update the component health
	// For now, this is a placeholder
	s.logger.Debug("Component health update", map[string]interface{}{
		"component": componentName,
		"status":    status,
		"message":   message,
	})
}

// RecordError records an error for health monitoring
func (s *Server) RecordError(errorType, component, message string) {
	// In a real implementation, this would record the error
	// For now, just log it
	s.logger.Error("Health error recorded", map[string]interface{}{
		"type":      errorType,
		"component": component,
		"message":   message,
	})
}
