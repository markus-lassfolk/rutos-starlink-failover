package ubus

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg/logx"
)

// Client represents a ubus client connection
type Client struct {
	conn     net.Conn
	logger   *logx.Logger
	mu       sync.RWMutex
	nextID   uint32
	handlers map[string]MethodHandler
}

// MethodHandler represents a ubus method handler
type MethodHandler func(ctx context.Context, params map[string]interface{}) (interface{}, error)

// Message represents a ubus message
type Message struct {
	ID      uint32                 `json:"id"`
	Type    string                 `json:"type"`
	Object  string                 `json:"object,omitempty"`
	Method  string                 `json:"method,omitempty"`
	Data    map[string]interface{} `json:"data,omitempty"`
	Error   string                 `json:"error,omitempty"`
	Result  interface{}            `json:"result,omitempty"`
}

// NewClient creates a new ubus client
func NewClient(logger *logx.Logger) *Client {
	return &Client{
		logger:   logger,
		handlers: make(map[string]MethodHandler),
		nextID:   1,
	}
}

// Connect connects to the ubus daemon
func (c *Client) Connect(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Try different ubus socket locations
	socketPaths := []string{
		"/var/run/ubus.sock",
		"/tmp/ubus.sock",
	}

	var conn net.Conn
	var err error

	for _, path := range socketPaths {
		if _, err := os.Stat(path); err == nil {
			conn, err = net.Dial("unix", path)
			if err == nil {
				c.conn = conn
				c.logger.Info("Connected to ubus daemon", "socket", path)
				return nil
			}
		}
	}

	return fmt.Errorf("failed to connect to ubus daemon: no socket found")
}

// Disconnect disconnects from the ubus daemon
func (c *Client) Disconnect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn != nil {
		err := c.conn.Close()
		c.conn = nil
		return err
	}
	return nil
}

// RegisterObject registers an object with methods
func (c *Client) RegisterObject(ctx context.Context, object string, methods map[string]MethodHandler) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Store handlers
	for method, handler := range methods {
		key := fmt.Sprintf("%s.%s", object, method)
		c.handlers[key] = handler
	}

	// Send registration message
	msg := Message{
		ID:     c.nextID,
		Type:   "add",
		Object: object,
		Data:   map[string]interface{}{"methods": getMethodSignatures(methods)},
	}

	c.nextID++

	return c.sendMessage(msg)
}

// UnregisterObject unregisters an object
func (c *Client) UnregisterObject(ctx context.Context, object string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Remove handlers
	for key := range c.handlers {
		if key[:len(object)] == object {
			delete(c.handlers, key)
		}
	}

	// Send unregistration message
	msg := Message{
		ID:     c.nextID,
		Type:   "remove",
		Object: object,
	}

	c.nextID++

	return c.sendMessage(msg)
}

// Listen starts listening for ubus messages
func (c *Client) Listen(ctx context.Context) error {
	c.logger.Info("Starting ubus message listener")

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			msg, err := c.receiveMessage()
			if err != nil {
				c.logger.Error("Failed to receive ubus message", "error", err)
				continue
			}

			go c.handleMessage(ctx, msg)
		}
	}
}

// handleMessage handles incoming ubus messages
func (c *Client) handleMessage(ctx context.Context, msg Message) {
	c.mu.RLock()
	handler, exists := c.handlers[fmt.Sprintf("%s.%s", msg.Object, msg.Method)]
	c.mu.RUnlock()

	if !exists {
		c.sendError(msg.ID, "Method not found")
		return
	}

	// Execute handler
	result, err := handler(ctx, msg.Data)
	if err != nil {
		c.sendError(msg.ID, err.Error())
		return
	}

	// Send success response
	response := Message{
		ID:     msg.ID,
		Type:   "return",
		Result: result,
	}

	c.sendMessage(response)
}

// sendMessage sends a message to the ubus daemon
func (c *Client) sendMessage(msg Message) error {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if c.conn == nil {
		return fmt.Errorf("not connected to ubus daemon")
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	// Add length prefix (ubus protocol requirement)
	length := uint32(len(data))
	header := []byte{
		byte(length & 0xFF),
		byte((length >> 8) & 0xFF),
		byte((length >> 16) & 0xFF),
		byte((length >> 24) & 0xFF),
	}

	_, err = c.conn.Write(append(header, data...))
	if err != nil {
		return fmt.Errorf("failed to send message: %w", err)
	}

	return nil
}

// sendError sends an error response
func (c *Client) sendError(id uint32, errorMsg string) {
	response := Message{
		ID:    id,
		Type:  "return",
		Error: errorMsg,
	}

	c.sendMessage(response)
}

// receiveMessage receives a message from the ubus daemon
func (c *Client) receiveMessage() (Message, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if c.conn == nil {
		return Message{}, fmt.Errorf("not connected to ubus daemon")
	}

	// Read length prefix
	header := make([]byte, 4)
	_, err := c.conn.Read(header)
	if err != nil {
		return Message{}, fmt.Errorf("failed to read message header: %w", err)
	}

	length := uint32(header[0]) | uint32(header[1])<<8 | uint32(header[2])<<16 | uint32(header[3])<<24

	// Read message data
	data := make([]byte, length)
	_, err = c.conn.Read(data)
	if err != nil {
		return Message{}, fmt.Errorf("failed to read message data: %w", err)
	}

	// Parse message
	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil {
		return Message{}, fmt.Errorf("failed to parse message: %w", err)
	}

	return msg, nil
}

// getMethodSignatures returns method signatures for registration
func getMethodSignatures(methods map[string]MethodHandler) map[string]interface{} {
	signatures := make(map[string]interface{})
	for method := range methods {
		signatures[method] = map[string]interface{}{
			"description": fmt.Sprintf("Starfail %s method", method),
		}
	}
	return signatures
}

// Call makes a ubus call to another object
func (c *Client) Call(ctx context.Context, object, method string, params map[string]interface{}) (interface{}, error) {
	msg := Message{
		ID:     c.nextID,
		Type:   "call",
		Object: object,
		Method: method,
		Data:   params,
	}

	c.nextID++

	// Send call
	if err := c.sendMessage(msg); err != nil {
		return nil, err
	}

	// Wait for response with timeout
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
			response, err := c.receiveMessage()
			if err != nil {
				return nil, err
			}

			if response.ID == msg.ID {
				if response.Error != "" {
					return nil, fmt.Errorf("ubus call failed: %s", response.Error)
				}
				return response.Result, nil
			}
		}
	}
}
