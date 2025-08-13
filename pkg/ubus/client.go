package ubus

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg/logx"
)

// Client represents a ubus client
type Client struct {
	logger    *logx.Logger
	conn      net.Conn
	connected bool
	mu        sync.RWMutex
	callID    uint32
	callMu    sync.Mutex
}

// Message represents a ubus message
type Message struct {
	Type    string          `json:"type"`
	Method  string          `json:"method,omitempty"`
	Path    string          `json:"path,omitempty"`
	Data    json.RawMessage `json:"data,omitempty"`
	ID      uint32          `json:"id,omitempty"`
	Code    int             `json:"code,omitempty"`
	Message string          `json:"message,omitempty"`
}

// MethodHandler represents a ubus method handler
type MethodHandler func(ctx context.Context, data json.RawMessage) (interface{}, error)

// NewClient creates a new ubus client
func NewClient(logger *logx.Logger) *Client {
	return &Client{
		logger: logger,
	}
}

// Connect connects to the ubus daemon
func (c *Client) Connect(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.connected {
		return nil
	}

	// Try to connect to ubus socket
	conn, err := net.Dial("unix", "/var/run/ubus.sock")
	if err != nil {
		return fmt.Errorf("failed to connect to ubus socket: %w", err)
	}

	c.conn = conn
	c.connected = true

	if c.logger != nil {
		c.logger.Info("Connected to ubus daemon")
	}

	return nil
}

// Disconnect disconnects from the ubus daemon
func (c *Client) Disconnect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.connected {
		return nil
	}

	if c.conn != nil {
		c.conn.Close()
	}

	c.connected = false

	if c.logger != nil {
		c.logger.Info("Disconnected from ubus daemon")
	}

	return nil
}

// Call makes a ubus call
func (c *Client) Call(ctx context.Context, object, method string, data interface{}) (json.RawMessage, error) {
	c.mu.RLock()
	if !c.connected {
		c.mu.RUnlock()
		return nil, fmt.Errorf("not connected to ubus")
	}
	c.mu.RUnlock()

	// Use ubus CLI as fallback for now
	return c.callViaCLI(ctx, object, method, data)
}

// callViaCLI makes a ubus call using the CLI
func (c *Client) callViaCLI(ctx context.Context, object, method string, data interface{}) (json.RawMessage, error) {
	args := []string{"call", object, method}

	if data != nil {
		dataJSON, err := json.Marshal(data)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal data: %w", err)
		}
		args = append(args, string(dataJSON))
	}

	cmd := exec.CommandContext(ctx, "ubus", args...)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ubus call failed: %w", err)
	}

	return output, nil
}

// RegisterObject registers an object with the ubus daemon
func (c *Client) RegisterObject(ctx context.Context, name string, methods map[string]MethodHandler) error {
	// For now, we'll use a simplified approach
	// In a full implementation, this would register the object with the ubus daemon
	if c.logger != nil {
		c.logger.Info("Registering ubus object", "name", name, "methods", len(methods))
	}
	return nil
}

// UnregisterObject unregisters an object from the ubus daemon
func (c *Client) UnregisterObject(ctx context.Context, name string) error {
	if c.logger != nil {
		c.logger.Info("Unregistering ubus object", "name", name)
	}
	return nil
}

// Listen listens for ubus messages
func (c *Client) Listen(ctx context.Context) error {
	// For now, we'll use a simplified approach
	// In a full implementation, this would listen for ubus messages
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			// Check for messages (simplified)
			continue
		}
	}
}

// ListObjects lists available ubus objects
func (c *Client) ListObjects(ctx context.Context) ([]string, error) {
	cmd := exec.CommandContext(ctx, "ubus", "list")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list ubus objects: %w", err)
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	var objects []string
	for _, line := range lines {
		if line != "" {
			objects = append(objects, strings.TrimSpace(line))
		}
	}

	return objects, nil
}

// ListMethods lists methods for a specific object
func (c *Client) ListMethods(ctx context.Context, object string) (map[string]interface{}, error) {
	cmd := exec.CommandContext(ctx, "ubus", "list", object)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list methods for object %s: %w", object, err)
	}

	var methods map[string]interface{}
	if err := json.Unmarshal(output, &methods); err != nil {
		return nil, fmt.Errorf("failed to parse methods: %w", err)
	}

	return methods, nil
}

// ValidateUbus checks if ubus is available and working
func (c *Client) ValidateUbus(ctx context.Context) error {
	_, err := exec.CommandContext(ctx, "ubus", "version").Output()
	if err != nil {
		return fmt.Errorf("ubus is not available: %w", err)
	}
	return nil
}

// GetSystemInfo gets system information via ubus
func (c *Client) GetSystemInfo(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "system", "info", nil)
	if err != nil {
		return nil, err
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse system info: %w", err)
	}

	return info, nil
}

// GetNetworkInfo gets network information via ubus
func (c *Client) GetNetworkInfo(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "network.device", "status", nil)
	if err != nil {
		return nil, err
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse network info: %w", err)
	}

	return info, nil
}

// GetInterfaceStatus gets the status of a specific interface
func (c *Client) GetInterfaceStatus(ctx context.Context, iface string) (map[string]interface{}, error) {
	data := map[string]interface{}{
		"name": iface,
	}

	output, err := c.Call(ctx, "network.device", "status", data)
	if err != nil {
		return nil, err
	}

	var status map[string]interface{}
	if err := json.Unmarshal(output, &status); err != nil {
		return nil, fmt.Errorf("failed to parse interface status: %w", err)
	}

	return status, nil
}

// GetMWAN3Status gets mwan3 status via ubus
func (c *Client) GetMWAN3Status(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "mwan3", "status", nil)
	if err != nil {
		return nil, err
	}

	var status map[string]interface{}
	if err := json.Unmarshal(output, &status); err != nil {
		return nil, fmt.Errorf("failed to parse mwan3 status: %w", err)
	}

	return status, nil
}

// GetMWAN3Interfaces gets mwan3 interfaces via ubus
func (c *Client) GetMWAN3Interfaces(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "mwan3", "interfaces", nil)
	if err != nil {
		return nil, err
	}

	var interfaces map[string]interface{}
	if err := json.Unmarshal(output, &interfaces); err != nil {
		return nil, fmt.Errorf("failed to parse mwan3 interfaces: %w", err)
	}

	return interfaces, nil
}

// GetMWAN3Members gets mwan3 members via ubus
func (c *Client) GetMWAN3Members(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "mwan3", "members", nil)
	if err != nil {
		return nil, err
	}

	var members map[string]interface{}
	if err := json.Unmarshal(output, &members); err != nil {
		return nil, fmt.Errorf("failed to parse mwan3 members: %w", err)
	}

	return members, nil
}

// GetMWAN3Policies gets mwan3 policies via ubus
func (c *Client) GetMWAN3Policies(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "mwan3", "policies", nil)
	if err != nil {
		return nil, err
	}

	var policies map[string]interface{}
	if err := json.Unmarshal(output, &policies); err != nil {
		return nil, fmt.Errorf("failed to parse mwan3 policies: %w", err)
	}

	return policies, nil
}

// GetCellularInfo gets cellular information via ubus (RutOS specific)
func (c *Client) GetCellularInfo(ctx context.Context) (map[string]interface{}, error) {
	// Try different cellular ubus objects
	objects := []string{"mobiled", "gsm", "cellular"}

	for _, object := range objects {
		output, err := c.Call(ctx, object, "status", nil)
		if err == nil {
			var info map[string]interface{}
			if err := json.Unmarshal(output, &info); err == nil {
				return info, nil
			}
		}
	}

	return nil, fmt.Errorf("no cellular ubus object found")
}

// GetWiFiInfo gets WiFi information via ubus
func (c *Client) GetWiFiInfo(ctx context.Context) (map[string]interface{}, error) {
	output, err := c.Call(ctx, "iwinfo", "info", nil)
	if err != nil {
		return nil, err
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse WiFi info: %w", err)
	}

	return info, nil
}

// GetWiFiDevices gets WiFi devices via ubus
func (c *Client) GetWiFiDevices(ctx context.Context) ([]string, error) {
	output, err := c.Call(ctx, "iwinfo", "devices", nil)
	if err != nil {
		return nil, err
	}

	var devices []string
	if err := json.Unmarshal(output, &devices); err != nil {
		return nil, fmt.Errorf("failed to parse WiFi devices: %w", err)
	}

	return devices, nil
}

// GetWiFiDeviceInfo gets information for a specific WiFi device
func (c *Client) GetWiFiDeviceInfo(ctx context.Context, device string) (map[string]interface{}, error) {
	data := map[string]interface{}{
		"device": device,
	}

	output, err := c.Call(ctx, "iwinfo", "info", data)
	if err != nil {
		return nil, err
	}

	var info map[string]interface{}
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse WiFi device info: %w", err)
	}

	return info, nil
}

// IsConnected returns whether the client is connected to ubus
func (c *Client) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.connected
}

// GetNextCallID returns the next call ID
func (c *Client) GetNextCallID() uint32 {
	c.callMu.Lock()
	defer c.callMu.Unlock()
	c.callID++
	return c.callID
}
