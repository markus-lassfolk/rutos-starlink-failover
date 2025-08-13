package pkg

import (
	"context"
	"time"
)

// Member represents a network interface member that can be monitored and controlled
type Member struct {
	Name      string            `json:"name"`
	Class     string            `json:"class"`
	Iface     string            `json:"iface"`
	Policy    string            `json:"policy,omitempty"`
	Weight    int               `json:"weight"`
	Eligible  bool              `json:"eligible"`
	Detect    string            `json:"detect"` // auto|disable|force
	Config    map[string]string `json:"config,omitempty"`
	LastSeen  time.Time         `json:"last_seen"`
	CreatedAt time.Time         `json:"created_at"`
}

// Metrics represents the health metrics for a member
type Metrics struct {
	Timestamp       time.Time `json:"timestamp"`
	LatencyMS       float64   `json:"lat_ms"`
	LossPercent     float64   `json:"loss_pct"`
	JitterMS        float64   `json:"jitter_ms"`
	ObstructionPct  *float64  `json:"obstruction_pct,omitempty"` // Starlink only
	Outages         *int      `json:"outages,omitempty"`         // Starlink only
	RSRP            *int      `json:"rsrp,omitempty"`            // Cellular only
	RSRQ            *int      `json:"rsrq,omitempty"`            // Cellular only
	SINR            *int      `json:"sinr,omitempty"`            // Cellular only
	SignalStrength  *int      `json:"signal,omitempty"`          // WiFi only
	NoiseLevel      *int      `json:"noise,omitempty"`           // WiFi only
	SNR             *int      `json:"snr,omitempty"`             // WiFi only
	Bitrate         *int      `json:"bitrate,omitempty"`         // WiFi only
	NetworkType     *string   `json:"network_type,omitempty"`    // Cellular only
	Roaming         *bool     `json:"roaming,omitempty"`         // Cellular only
	Operator        *string   `json:"operator,omitempty"`        // Cellular only
	Band            *string   `json:"band,omitempty"`            // Cellular only
	CellID          *string   `json:"cell_id,omitempty"`         // Cellular only
}

// Score represents the health scoring for a member
type Score struct {
	Instant   float64 `json:"instant"`
	EWMA      float64 `json:"ewma"`
	Final     float64 `json:"final"`
	UpdatedAt time.Time `json:"updated_at"`
}

// MemberState represents the current state of a member
type MemberState struct {
	Member  *Member  `json:"member"`
	Metrics *Metrics `json:"metrics,omitempty"`
	Score   *Score   `json:"score,omitempty"`
	Status  string   `json:"status"` // eligible|cooldown|warmup|failed
}

// Event represents a system event
type Event struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"`
	Timestamp time.Time              `json:"timestamp"`
	Member    string                 `json:"member,omitempty"`
	From      string                 `json:"from,omitempty"`
	To        string                 `json:"to,omitempty"`
	Reason    string                 `json:"reason,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

// Collector interface for collecting metrics from different member types
type Collector interface {
	Collect(ctx context.Context, member *Member) (*Metrics, error)
	Validate(member *Member) error
}

// Controller interface for controlling network interfaces
type Controller interface {
	Switch(from, to *Member) error
	GetCurrentMember() (*Member, error)
	Validate(member *Member) error
}

// Member classes
const (
	ClassStarlink = "starlink"
	ClassCellular = "cellular"
	ClassWiFi     = "wifi"
	ClassLAN      = "lan"
	ClassOther    = "other"
)

// Event types
const (
	EventMemberDiscovered = "member_discovered"
	EventMemberLost       = "member_lost"
	EventFailover         = "failover"
	EventFailback         = "failback"
	EventPredictive       = "predictive"
	EventCooldown         = "cooldown"
	EventWarmup           = "warmup"
	EventError            = "error"
	EventConfigReload     = "config_reload"
)

// Member statuses
const (
	StatusEligible = "eligible"
	StatusCooldown = "cooldown"
	StatusWarmup   = "warmup"
	StatusFailed   = "failed"
)

// Detection modes
const (
	DetectAuto    = "auto"
	DetectDisable = "disable"
	DetectForce   = "force"
)
