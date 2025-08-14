package uci

import (
	"os"
	"path/filepath"
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
