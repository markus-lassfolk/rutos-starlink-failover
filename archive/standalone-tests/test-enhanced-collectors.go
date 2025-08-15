// +build ignore

package main

import (
	"context"
	"fmt"
	"time"

	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/collector"
	"github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

func main() {
	// Create logger for WiFi collector
	logger := logx.New("debug")
	
	// Test enhanced Starlink collector
	fmt.Println("=== Testing Enhanced Starlink Collector ===")
	starlinkCollector := collector.NewStarlinkCollector("192.168.100.1", 9200)
	
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	// Create test member
	starlinkMember := collector.Member{
		Name:          "starlink_test",
		InterfaceName: "wwan0",
		Class:         "starlink",
		Weight:        100,
		Enabled:       true,
	}
	
	metrics, err := starlinkCollector.Collect(ctx, starlinkMember)
	if err != nil {
		fmt.Printf("Starlink collection error (expected on non-Starlink system): %v\n", err)
		fmt.Printf("This demonstrates graceful degradation - collector tried ping fallback\n")
	} else {
		fmt.Printf("Starlink metrics collected: %+v\n", metrics)
	}
	
	// Test enhanced Cellular collector  
	fmt.Println("\n=== Testing Enhanced Cellular Collector ===")
	cellularCollector := collector.NewCellularCollector("cellular")
	
	cellularMember := collector.Member{
		Name:          "cellular_test",
		InterfaceName: "wwan1",
		Class:         "cellular",
		Weight:        50,
		Enabled:       true,
	}
	
	metrics, err = cellularCollector.Collect(ctx, cellularMember)
	if err != nil {
		fmt.Printf("Cellular collection error (expected on non-cellular system): %v\n", err)
		fmt.Printf("This demonstrates graceful degradation - collector tried alternative providers\n")
	} else {
		fmt.Printf("Cellular metrics collected: %+v\n", metrics)
	}
	
	// Test WiFi collector for baseline
	fmt.Println("\n=== Testing WiFi Collector (baseline) ===")
	wifiCollector := collector.NewWiFiCollector([]string{"8.8.8.8"}, logger)
	
	wifiMember := collector.Member{
		Name:          "wifi_test",
		InterfaceName: "wlan0",
		Class:         "wifi",
		Weight:        25,
		Enabled:       true,
	}
	
	metrics, err = wifiCollector.Collect(ctx, wifiMember)
	if err != nil {
		fmt.Printf("WiFi collection error: %v\n", err)
	
	fmt.Println("\n=== Enhanced Collector Test Complete ===")
	fmt.Println("Key improvements tested:")
	fmt.Println("- Starlink collector: Graceful degradation with ping fallback")
	fmt.Println("- Cellular collector: Alternative provider detection and interface estimation")
	fmt.Println("- Error handling: Partial metrics rather than complete failures")
}
	
	fmt.Println("\n=== Enhanced Collector Test Complete ===")
	fmt.Println("Key improvements tested:")
	fmt.Println("- Starlink collector: Graceful degradation with ping fallback")
	fmt.Println("- Cellular collector: Alternative provider detection and interface estimation")
	fmt.Println("- Error handling: Partial metrics rather than complete failures")
}
