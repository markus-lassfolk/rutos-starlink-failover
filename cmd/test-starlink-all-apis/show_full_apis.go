package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/starfail/starfail/pkg/collector"
)

func main() {
	fmt.Println("🛰️  Starlink API Full Output Display - ALL METHODS")
	fmt.Println("===================================================")

	// Create a Starlink collector with default settings
	config := map[string]interface{}{
		"starlink_api_host":   "192.168.100.1",
		"starlink_api_port":   9200,
		"starlink_timeout_s":  20,
		"starlink_grpc_first": true,
		"starlink_http_first": false,
	}

	collector, err := collector.NewStarlinkCollector(config)
	if err != nil {
		log.Fatalf("Failed to create Starlink collector: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// List of all Starlink API methods to test
	apiMethods := []struct {
		name        string
		description string
	}{
		{"get_status", "Device status, performance metrics, obstruction data"},
		{"get_location", "GPS coordinates and location information"},
		{"get_history", "Historical performance data and statistics"},
		{"get_device_info", "Hardware and software information"},
		{"get_diagnostics", "Detailed diagnostic information and alerts"},
	}

	// Call each API method and display full output
	for i, method := range apiMethods {
		fmt.Printf("\n🔍 STARLINK %s API - FULL OUTPUT:\n", strings.ToUpper(method.name))
		fmt.Printf("Description: %s\n", method.description)
		fmt.Println(strings.Repeat("=", 60))
		
		response, err := collector.TestStarlinkMethod(ctx, method.name)
		if err != nil {
			fmt.Printf("❌ %s failed: %v\n", method.name, err)
		} else {
			fmt.Printf("✅ %s succeeded! (%d bytes)\n\n", method.name, len(response))
			fmt.Println(response)
		}

		// Add separator between methods (except for the last one)
		if i < len(apiMethods)-1 {
			fmt.Println("\n" + strings.Repeat("=", 80))
		}
	}

	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Println("🎯 Full API output display completed for all methods!")
}
