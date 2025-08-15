package uci

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadDefaultsWhenUCINotPresent(t *testing.T) {
	t.Setenv("PATH", "")
	loader := NewLoader("/etc/config/starfail")
	cfg, err := loader.Load()
	if err != nil {
		t.Fatalf("load failed: %v", err)
	}
	if !cfg.Main.Enable || cfg.Main.PollIntervalMs != 1500 {
		t.Fatalf("unexpected defaults: %+v", cfg.Main)
	}
}

func TestLoadMainAndMembersFromUCI(t *testing.T) {
	dir := t.TempDir()
	// Create platform-specific mock for `uci`
	script := filepath.Join(dir, "uci")
	if os.PathSeparator == '\\' { // Windows
		// Create a .cmd shim
		script += ".cmd"
		content := "@echo off\r\n" +
			"if \"%1\"==\"show\" if \"%2\"==\"starfail.main\" (\r\n" +
			"  echo starfail.main.enable='0'\r\n" +
			"  echo starfail.main.use_mwan3='0'\r\n" +
			"  echo starfail.main.poll_interval_ms='2000'\r\n" +
			") else if \"%1\"==\"show\" if \"%2\"==\"starfail\" (\r\n" +
			"  echo starfail.@member[0].class='cellular'\r\n" +
			"  echo starfail.@member[0].weight='60'\r\n" +
			"  echo starfail.@member[1].class='wifi'\r\n" +
			")\r\n"
		if err := os.WriteFile(script, []byte(content), 0644); err != nil {
			t.Fatalf("write windows script: %v", err)
		}
	} else {
		content := `#!/bin/sh
if [ "$1" = show ] && [ "$2" = starfail.main ]; then
  echo "starfail.main.enable='0'"
  echo "starfail.main.use_mwan3='0'"
  echo "starfail.main.poll_interval_ms='2000'"
elif [ "$1" = show ] && [ "$2" = starfail ]; then
  echo "starfail.@member[0].class='cellular'"
  echo "starfail.@member[0].weight='60'"
  echo "starfail.@member[1].class='wifi'"
fi
`
		if err := os.WriteFile(script, []byte(content), 0755); err != nil {
			t.Fatalf("write script: %v", err)
		}
	}
	t.Setenv("PATH", dir)

	loader := NewLoader("/etc/config/starfail")
	cfg, err := loader.Load()
	if err != nil {
		t.Fatalf("load failed: %v", err)
	}
	if cfg.Main.Enable || cfg.Main.UseMwan3 || cfg.Main.PollIntervalMs != 2000 {
		t.Fatalf("uci overrides not applied: %+v", cfg.Main)
	}
	if len(cfg.Members) != 2 || cfg.Members[0].Class != "cellular" || cfg.Members[0].Weight != 60 {
		t.Fatalf("member parsing failed: %+v", cfg.Members)
	}
}

func TestValidateMainInvalidPollInterval(t *testing.T) {
	loader := NewLoader("/etc/config/starfail")
	cfg := loader.getDefaultConfig()
	cfg.Main.PollIntervalMs = 100
	if err := loader.Validate(cfg); err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestSaveConfig(t *testing.T) {
	dir := t.TempDir()

	// Create platform-specific mock for `uci` that logs set commands
	script := filepath.Join(dir, "uci")
	logFile := filepath.Join(dir, "uci_commands.log")

	if os.PathSeparator == '\\' { // Windows
		script += ".cmd"
		content := "@echo off\r\n" +
			"echo %* >> " + logFile + "\r\n" +
			"if \"%1\"==\"show\" (\r\n" +
			"  rem Return empty for show commands\r\n" +
			")\r\n"
		if err := os.WriteFile(script, []byte(content), 0644); err != nil {
			t.Fatalf("write windows script: %v", err)
		}
	} else {
		content := `#!/bin/sh
echo "$@" >> ` + logFile + `
if [ "$1" = "show" ]; then
  # Return empty for show commands
  true
fi
`
		if err := os.WriteFile(script, []byte(content), 0755); err != nil {
			t.Fatalf("write script: %v", err)
		}
	}
	t.Setenv("PATH", dir)

	// Create a simple config to save
	loader := NewLoader("/etc/config/starfail")
	cfg := &Config{
		Main: MainConfig{
			Enable:         true,
			UseMwan3:       false,
			PollIntervalMs: 2000,
		},
		Members: []MemberConfig{
			{
				Name:   "cellular1",
				Class:  "cellular",
				Detect: "auto",
				Weight: 80,
			},
		},
	}

	// Test save operation
	err := loader.Save(cfg)
	if err != nil {
		t.Fatalf("save failed: %v", err)
	}

	// Verify commands were written to log
	logData, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatalf("failed to read log: %v", err)
	}

	logContent := string(logData)

	// Should contain set commands for main config
	if !containsString(logContent, "set starfail.main.enable=1") {
		t.Errorf("missing main enable set command in log: %s", logContent)
	}

	// Should contain commit command
	if !containsString(logContent, "commit starfail") {
		t.Errorf("missing commit command in log: %s", logContent)
	}
}

func containsString(haystack, needle string) bool {
	return strings.Contains(haystack, needle)
}
