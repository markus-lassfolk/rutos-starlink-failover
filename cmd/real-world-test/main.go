package main

import (
	"context"
	"fmt"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/controller"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

// realWorldTest validates our implementation against actual RUTOS hardware
func main() {
	logger := logx.New("INFO")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fmt.Println("=== Real World Validation Test ===")

	// Test 1: Controller Discovery
	fmt.Println("\n1. Testing mwan3 controller discovery...")
	config := controller.Config{
		UseMwan3:  true,
		DryRun:    true,
		CooldownS: 1,
	}
	ctrl := controller.NewController(config, logger)

	members, err := ctrl.DiscoverMembers(ctx)
	if err != nil {
		fmt.Printf("   ❌ Controller discovery failed: %v\n", err)
	} else {
		fmt.Printf("   ✅ Found %d members:\n", len(members))
		for _, member := range members {
			fmt.Printf("      - %s (interface: %s, metric: %d, weight: %d)\n",
				member.Name, member.Interface, member.Metric, member.Weight)
		}
	}

	// Test 2: Cellular Collector
	fmt.Println("\n2. Testing cellular collector...")
	cellular := collector.NewCellularCollector("")

	cellularMember := collector.Member{InterfaceName: "mob1s1a1"}
	cellularMetrics, err := cellular.Collect(ctx, cellularMember)
	if err != nil {
		fmt.Printf("   ❌ Cellular collection failed: %v\n", err)
	} else {
		fmt.Printf("   ✅ Cellular metrics collected:\n")
		if cellularMetrics.RSSI != nil {
			fmt.Printf("      RSSI: %.1f dBm\n", *cellularMetrics.RSSI)
		}
		if cellularMetrics.RSRP != nil {
			fmt.Printf("      RSRP: %.1f dBm\n", *cellularMetrics.RSRP)
		}
		if cellularMetrics.LatencyMs != nil {
			fmt.Printf("      Latency: %.1f ms\n", *cellularMetrics.LatencyMs)
		}
		if cellularMetrics.PacketLossPct != nil {
			fmt.Printf("      Loss: %.2f%%\n", *cellularMetrics.PacketLossPct)
		}
	}

	// Test 3: Ping Collector on WAN interface
	fmt.Println("\n3. Testing ping collector on WAN interface...")
	ping := collector.NewPingCollector([]string{"1.1.1.1", "8.8.8.8"})

	wanMember := collector.Member{InterfaceName: "eth1"}
	pingMetrics, err := ping.Collect(ctx, wanMember)
	if err != nil {
		fmt.Printf("   ❌ Ping collection failed: %v\n", err)
	} else {
		fmt.Printf("   ✅ Ping metrics collected:\n")
		if pingMetrics.LatencyMs != nil {
			fmt.Printf("      Latency: %.1f ms\n", *pingMetrics.LatencyMs)
		}
		if pingMetrics.PacketLossPct != nil {
			fmt.Printf("      Loss: %.2f%%\n", *pingMetrics.PacketLossPct)
		}
		if pingMetrics.JitterMs != nil {
			fmt.Printf("      Jitter: %.1f ms\n", *pingMetrics.JitterMs)
		}
	}

	// Test 4: Starlink Collector
	fmt.Println("\n4. Testing Starlink collector...")
	starlink := collector.NewStarlinkCollector("")

	starlinkMember := collector.Member{InterfaceName: "eth1"}
	starlinkMetrics, err := starlink.Collect(ctx, starlinkMember)
	if err != nil {
		fmt.Printf("   ❌ Starlink collection failed: %v\n", err)
	} else {
		fmt.Printf("   ✅ Starlink metrics collected:\n")
		if starlinkMetrics.SNR != nil {
			fmt.Printf("      SNR: %.1f dB\n", *starlinkMetrics.SNR)
		}
		if starlinkMetrics.PopPingMs != nil {
			fmt.Printf("      Pop Ping: %.1f ms\n", *starlinkMetrics.PopPingMs)
		}
		if starlinkMetrics.ObstructionPct != nil {
			fmt.Printf("      Obstruction: %.2f%%\n", *starlinkMetrics.ObstructionPct)
		}
	}

	fmt.Println("\n=== Test Complete ===")
}
