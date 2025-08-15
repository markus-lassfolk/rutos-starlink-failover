// Package recovery provides automated backup and recovery functionality
package recovery

import (
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/uci"
)

// Manager handles backup and recovery operations
type Manager struct {
	config    Config
	logger    logx.Logger
	backupDir string
	versions  []ConfigVersion
}

// Config holds recovery configuration
type Config struct {
	Enable             bool   `uci:"enable" default:"true"`
	BackupDir          string `uci:"backup_dir" default:"/etc/starfail/backup"`
	MaxVersions        int    `uci:"max_versions" default:"10"`
	AutoBackupOnChange bool   `uci:"auto_backup_on_change" default:"true"`
	BackupInterval     int    `uci:"backup_interval_hours" default:"24"`
	CompressBackups    bool   `uci:"compress_backups" default:"true"`
}

// ConfigVersion represents a configuration backup version
type ConfigVersion struct {
	Version     int                    `json:"version"`
	Timestamp   time.Time              `json:"timestamp"`
	Config      map[string]interface{} `json:"config"`
	Hash        string                 `json:"hash"`
	Size        int64                  `json:"size"`
	Compressed  bool                   `json:"compressed"`
	Description string                 `json:"description"`
	FilePath    string                 `json:"file_path"`
}

// RecoveryState represents current recovery status
type RecoveryState struct {
	LastBackup                 time.Time `json:"last_backup"`
	LastRecovery               time.Time `json:"last_recovery"`
	ConfigIntact               bool      `json:"config_intact"`
	SystemIntact               bool      `json:"system_intact"`
	RecoveryInProgress         bool      `json:"recovery_in_progress"`
	RequiresManualIntervention bool      `json:"requires_manual_intervention"`
}

// BackupResult represents the result of a backup operation
type BackupResult struct {
	Success  bool          `json:"success"`
	Version  int           `json:"version"`
	Hash     string        `json:"hash"`
	Size     int64         `json:"size"`
	Duration time.Duration `json:"duration"`
	FilePath string        `json:"file_path"`
	Error    error         `json:"error,omitempty"`
}

// RecoveryResult represents the result of a recovery operation
type RecoveryResult struct {
	Success           bool          `json:"success"`
	RestoredVersion   int           `json:"restored_version"`
	ConfigRestored    bool          `json:"config_restored"`
	ServicesRestarted []string      `json:"services_restarted"`
	Duration          time.Duration `json:"duration"`
	Error             error         `json:"error,omitempty"`
	RequiredActions   []string      `json:"required_actions,omitempty"`
}

// NewManager creates a new recovery manager
func NewManager(config Config, logger logx.Logger) (*Manager, error) {
	if !config.Enable {
		return nil, fmt.Errorf("recovery is disabled")
	}

	// Ensure backup directory exists
	if err := os.MkdirAll(config.BackupDir, 0750); err != nil {
		return nil, fmt.Errorf("failed to create backup directory: %w", err)
	}

	manager := &Manager{
		config:    config,
		logger:    logger,
		backupDir: config.BackupDir,
	}

	// Load existing versions
	if err := manager.loadVersions(); err != nil {
		logger.Warn("failed to load existing backup versions", "error", err)
	}

	return manager, nil
}

// BackupConfig creates a backup of the current configuration
func (m *Manager) BackupConfig(ctx context.Context, description string) (*BackupResult, error) {
	start := time.Now()

	result := &BackupResult{
		Version: m.getNextVersion(),
	}

	// Load current configuration
	uciLoader := uci.NewLoader("/etc/config/starfail")
	config, err := uciLoader.Load()
	if err != nil {
		result.Error = fmt.Errorf("failed to load current config: %w", err)
		return result, result.Error
	}

	// Convert to map for JSON serialization
	configMap, err := m.configToMap(config)
	if err != nil {
		result.Error = fmt.Errorf("failed to convert config: %w", err)
		return result, result.Error
	}

	// Calculate hash
	configData, err := json.Marshal(configMap)
	if err != nil {
		result.Error = fmt.Errorf("failed to marshal config: %w", err)
		return result, result.Error
	}

	hash := sha256.Sum256(configData)
	result.Hash = hex.EncodeToString(hash[:])

	// Create version record
	version := ConfigVersion{
		Version:     result.Version,
		Timestamp:   time.Now(),
		Config:      configMap,
		Hash:        result.Hash,
		Compressed:  m.config.CompressBackups,
		Description: description,
	}

	// Write backup file
	fileName := fmt.Sprintf("starfail-config-v%d-%s.json",
		result.Version, version.Timestamp.Format("20060102-150405"))

	if m.config.CompressBackups {
		fileName += ".gz"
	}

	filePath := filepath.Join(m.backupDir, fileName)
	version.FilePath = filePath
	result.FilePath = filePath

	if err := m.writeBackupFile(filePath, configData); err != nil {
		result.Error = fmt.Errorf("failed to write backup file: %w", err)
		return result, result.Error
	}

	// Get file size
	if stat, err := os.Stat(filePath); err == nil {
		result.Size = stat.Size()
		version.Size = stat.Size()
	}

	// Add to versions list
	m.versions = append(m.versions, version)

	// Clean up old versions
	if err := m.cleanupOldVersions(); err != nil {
		m.logger.Warn("failed to cleanup old versions", "error", err)
	}

	// Save versions metadata
	if err := m.saveVersions(); err != nil {
		m.logger.Warn("failed to save versions metadata", "error", err)
	}

	result.Success = true
	result.Duration = time.Since(start)

	m.logger.Info("configuration backup created",
		"version", result.Version,
		"hash", result.Hash[:12],
		"size", result.Size,
		"file", fileName,
	)

	return result, nil
}

// RestoreConfig restores configuration from a specific version
func (m *Manager) RestoreConfig(ctx context.Context, version int) (*RecoveryResult, error) {
	start := time.Now()

	result := &RecoveryResult{
		RestoredVersion: version,
	}

	// Find the version
	var targetVersion *ConfigVersion
	for _, v := range m.versions {
		if v.Version == version {
			targetVersion = &v
			break
		}
	}

	if targetVersion == nil {
		result.Error = fmt.Errorf("version %d not found", version)
		return result, result.Error
	}

	// Read backup file
	configData, err := m.readBackupFile(targetVersion.FilePath)
	if err != nil {
		result.Error = fmt.Errorf("failed to read backup file: %w", err)
		return result, result.Error
	}

	// Verify hash
	hash := sha256.Sum256(configData)
	if hex.EncodeToString(hash[:]) != targetVersion.Hash {
		result.Error = fmt.Errorf("backup file integrity check failed")
		return result, result.Error
	}

	// Parse configuration
	var configMap map[string]interface{}
	if err := json.Unmarshal(configData, &configMap); err != nil {
		result.Error = fmt.Errorf("failed to parse backup config: %w", err)
		return result, result.Error
	}

	// Create backup of current config before restore
	if _, err := m.BackupConfig(ctx, "pre-restore-backup"); err != nil {
		m.logger.Warn("failed to create pre-restore backup", "error", err)
	}

	// Write restored configuration
	if err := m.writeConfigToUCI(configMap); err != nil {
		result.Error = fmt.Errorf("failed to write restored config: %w", err)
		return result, result.Error
	}

	result.ConfigRestored = true

	// Restart services
	services := []string{"starfail", "mwan3", "network"}
	for _, service := range services {
		if err := m.restartService(service); err != nil {
			m.logger.Warn("failed to restart service", "service", service, "error", err)
		} else {
			result.ServicesRestarted = append(result.ServicesRestarted, service)
		}
	}

	result.Success = true
	result.Duration = time.Since(start)

	m.logger.Info("configuration restored",
		"version", version,
		"hash", targetVersion.Hash[:12],
		"services_restarted", len(result.ServicesRestarted),
	)

	return result, nil
}

// DetectSystemRecovery detects if system recovery is needed
func (m *Manager) DetectSystemRecovery(ctx context.Context) (*RecoveryState, error) {
	state := &RecoveryState{}

	// Check if configuration exists and is valid
	uciLoader := uci.NewLoader("/etc/config/starfail")
	if _, err := uciLoader.Load(); err != nil {
		state.ConfigIntact = false
		m.logger.Warn("configuration appears corrupted", "error", err)
	} else {
		state.ConfigIntact = true
	}

	// Check if starfail daemon is running
	if err := m.checkServiceRunning("starfail"); err != nil {
		state.SystemIntact = false
		m.logger.Warn("starfail daemon not running", "error", err)
	} else {
		state.SystemIntact = true
	}

	// Determine if manual intervention is needed
	if !state.ConfigIntact && len(m.versions) == 0 {
		state.RequiresManualIntervention = true
	}

	// Get last backup time
	if len(m.versions) > 0 {
		sort.Slice(m.versions, func(i, j int) bool {
			return m.versions[i].Timestamp.After(m.versions[j].Timestamp)
		})
		state.LastBackup = m.versions[0].Timestamp
	}

	return state, nil
}

// AutoRecover attempts automatic system recovery
func (m *Manager) AutoRecover(ctx context.Context) (*RecoveryResult, error) {
	m.logger.Info("attempting automatic system recovery")

	state, err := m.DetectSystemRecovery(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to detect system state: %w", err)
	}

	if state.RequiresManualIntervention {
		return nil, fmt.Errorf("manual intervention required - no backup available")
	}

	// If config is broken but we have backups, restore latest
	if !state.ConfigIntact && len(m.versions) > 0 {
		latestVersion := m.versions[0].Version
		return m.RestoreConfig(ctx, latestVersion)
	}

	// If system is broken but config is intact, restart services
	if !state.SystemIntact && state.ConfigIntact {
		result := &RecoveryResult{Success: true}
		services := []string{"starfail", "mwan3"}
		for _, service := range services {
			if err := m.restartService(service); err == nil {
				result.ServicesRestarted = append(result.ServicesRestarted, service)
			}
		}
		return result, nil
	}

	return &RecoveryResult{Success: true}, nil
}

// GetVersions returns list of available backup versions
func (m *Manager) GetVersions() []ConfigVersion {
	// Return a copy to prevent external modification
	versions := make([]ConfigVersion, len(m.versions))
	copy(versions, m.versions)
	return versions
}

// Helper methods

func (m *Manager) getNextVersion() int {
	maxVersion := 0
	for _, v := range m.versions {
		if v.Version > maxVersion {
			maxVersion = v.Version
		}
	}
	return maxVersion + 1
}

func (m *Manager) configToMap(config *uci.Config) (map[string]interface{}, error) {
	// This is a simplified conversion - in practice would need full UCI structure
	data, err := json.Marshal(config)
	if err != nil {
		return nil, err
	}

	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	return result, nil
}

func (m *Manager) writeBackupFile(filePath string, data []byte) error {
	if m.config.CompressBackups {
		return m.writeCompressedFile(filePath, data)
	}
	return os.WriteFile(filePath, data, 0600)
}

func (m *Manager) writeCompressedFile(filePath string, data []byte) error {
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := gzip.NewWriter(file)
	defer writer.Close()

	_, err = writer.Write(data)
	return err
}

func (m *Manager) readBackupFile(filePath string) ([]byte, error) {
	if m.config.CompressBackups && filepath.Ext(filePath) == ".gz" {
		return m.readCompressedFile(filePath)
	}
	return os.ReadFile(filePath)
}

func (m *Manager) readCompressedFile(filePath string) ([]byte, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	reader, err := gzip.NewReader(file)
	if err != nil {
		return nil, err
	}
	defer reader.Close()

	return io.ReadAll(reader)
}

func (m *Manager) writeConfigToUCI(configMap map[string]interface{}) error {
	// Create UCI loader for configuration operations
	uciLoader := uci.NewLoader("/etc/config/starfail")

	// Load current configuration
	config, err := uciLoader.Load()
	if err != nil {
		return fmt.Errorf("failed to load current UCI config: %w", err)
	}

	// Apply changes from the configMap
	// Note: This is a simplified implementation that handles basic config restoration
	// A full implementation would need to map the configMap structure to the UCI config fields
	for key, value := range configMap {
		m.logger.Debug("restoring config value", "key", key, "value", value)
		// For now, we'll restore the main fields that are commonly backed up
		switch key {
		case "main.enable":
			if v, ok := value.(bool); ok {
				config.Main.Enable = v
			}
		case "main.poll_interval_ms":
			if v, ok := value.(float64); ok {
				config.Main.PollIntervalMs = int(v)
			}
		case "main.dry_run":
			if v, ok := value.(bool); ok {
				config.Main.DryRun = v
			}
		default:
			m.logger.Debug("skipping unsupported config key during restoration", "key", key)
		}
	}

	// Save and commit the configuration
	if err := uciLoader.Save(config); err != nil {
		return fmt.Errorf("failed to save UCI config: %w", err)
	}

	m.logger.Info("configuration written to UCI", "keys", len(configMap))
	return nil
}

func (m *Manager) restartService(service string) error {
	m.logger.Info("restarting service", "service", service)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Use procd service management for RutOS/OpenWrt
	if err := m.execCommand(ctx, "/etc/init.d/"+service, "restart"); err != nil {
		return fmt.Errorf("failed to restart service %s: %w", service, err)
	}

	// Wait a moment for service to stabilize
	time.Sleep(2 * time.Second)

	// Verify service is running
	if err := m.checkServiceRunning(service); err != nil {
		return fmt.Errorf("service %s failed to start after restart: %w", service, err)
	}

	m.logger.Info("service restarted successfully", "service", service)
	return nil
}

func (m *Manager) checkServiceRunning(service string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Check service status using procd
	if err := m.execCommand(ctx, "/etc/init.d/"+service, "status"); err != nil {
		return fmt.Errorf("service %s is not running: %w", service, err)
	}

	return nil
}

// execCommand executes a system command with the given arguments
func (m *Manager) execCommand(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		m.logger.Debug("command execution failed",
			"command", name,
			"args", args,
			"output", string(output),
			"error", err)
		return err
	}
	return nil
}

func (m *Manager) cleanupOldVersions() error {
	if len(m.versions) <= m.config.MaxVersions {
		return nil
	}

	// Sort by timestamp, oldest first
	sort.Slice(m.versions, func(i, j int) bool {
		return m.versions[i].Timestamp.Before(m.versions[j].Timestamp)
	})

	// Remove excess versions
	toRemove := len(m.versions) - m.config.MaxVersions
	for i := 0; i < toRemove; i++ {
		version := m.versions[i]
		if err := os.Remove(version.FilePath); err != nil {
			m.logger.Warn("failed to remove old backup file",
				"file", version.FilePath, "error", err)
		}
	}

	// Keep only the latest versions
	m.versions = m.versions[toRemove:]
	return nil
}

func (m *Manager) loadVersions() error {
	versionsFile := filepath.Join(m.backupDir, "versions.json")
	data, err := os.ReadFile(versionsFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No versions file yet
		}
		return err
	}

	return json.Unmarshal(data, &m.versions)
}

func (m *Manager) saveVersions() error {
	versionsFile := filepath.Join(m.backupDir, "versions.json")
	data, err := json.MarshalIndent(m.versions, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(versionsFile, data, 0600)
}
