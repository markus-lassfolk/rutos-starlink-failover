package controller

import (
	"context"
	"testing"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

func TestParseMwan3Config(t *testing.T) {
	sample := "mwan3.wan1.interface='wan'\n" +
		"mwan3.wan2.interface='wan2'\n" +
		"mwan3.wan2.enabled='0'\n"
	c := NewController(Config{UseMwan3: true}, logx.New("debug"))
	members, err := c.parseMwan3Config(sample)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(members) != 2 {
		t.Fatalf("expected 2 members, got %d", len(members))
	}
	found := map[string]bool{}
	for _, m := range members {
		found[m.Name] = true
	}
	if !found["wan1"] || !found["wan2"] {
		t.Fatalf("members not parsed correctly: %v", members)
	}
}

func TestSetPrimaryCooldown(t *testing.T) {
	logger := logx.New("debug")
	c := NewController(Config{UseMwan3: false, DryRun: true, CooldownS: 10}, logger)
	ctx := context.Background()
	m := Member{Name: "wan", Interface: "wan"}
	_ = c.SetPrimary(ctx, m)
	c.lastChange = time.Now()
	if err := c.SetPrimary(ctx, m); err == nil {
		t.Fatalf("expected cooldown error")
	}
}
