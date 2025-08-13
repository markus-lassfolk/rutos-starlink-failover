// Package collector provides metric collection for different interface types
package collector

import (
	"context"
	"time"
)

// Metrics represents collected metrics for an interface
type Metrics struct {
	Timestamp      time.Time `json:"timestamp"`
	InterfaceName  string    `json:"interface"`
	Class          string    `json:"class"`
	
	// Common metrics (all classes)
	LatencyMs      *float64 `json:"latency_ms,omitempty"`
	PacketLossPct  *float64 `json:"packet_loss_pct,omitempty"`
	JitterMs       *float64 `json:"jitter_ms,omitempty"`
	
	// Starlink specific
	ObstructionPct *float64 `json:"obstruction_pct,omitempty"`
	SNR           *float64 `json:"snr,omitempty"`
	Outages       *int     `json:"outages,omitempty"`
	PopPingMs     *float64 `json:"pop_ping_ms,omitempty"`
	
	// Cellular specific
	RSSI          *float64 `json:"rssi,omitempty"`
	RSRP          *float64 `json:"rsrp,omitempty"`
	RSRQ          *float64 `json:"rsrq,omitempty"`
	SINR          *float64 `json:"sinr,omitempty"`
	NetworkType   *string  `json:"network_type,omitempty"`
	Roaming       *bool    `json:"roaming,omitempty"`
	
	// WiFi specific
	Signal        *float64 `json:"signal,omitempty"`
	Noise         *float64 `json:"noise,omitempty"`
	Bitrate       *float64 `json:"bitrate,omitempty"`
}

// Member represents a network interface member
type Member struct {
	Name          string `json:"name"`
	InterfaceName string `json:"interface"`
	Class         string `json:"class"`
	Weight        int    `json:"weight"`
	Enabled       bool   `json:"enabled"`
}

// Collector interface for metric collection
type Collector interface {
	// Collect gathers metrics for the given member
	Collect(ctx context.Context, member Member) (Metrics, error)
	
	// Class returns the interface class this collector handles
	Class() string
	
	// SupportsInterface checks if this collector can handle the given interface
	SupportsInterface(interfaceName string) bool
}

// Registry manages collector instances
type Registry struct {
	collectors map[string]Collector
}

// NewRegistry creates a new collector registry
func NewRegistry() *Registry {
	return &Registry{
		collectors: make(map[string]Collector),
	}
}

// Register adds a collector for a specific class
func (r *Registry) Register(class string, collector Collector) {
	r.collectors[class] = collector
}

// Get returns the collector for a given class
func (r *Registry) Get(class string) (Collector, bool) {
	collector, exists := r.collectors[class]
	return collector, exists
}

// TODO: Implement specific collectors:
// - StarlinkCollector (gRPC/JSON API to 192.168.100.1)
// - CellularCollector (ubus mobiled/gsm providers)
// - WiFiCollector (ubus iwinfo or /proc/net/wireless)
// - LANCollector (generic ping-based)
// - GenericCollector (fallback ping-based)
