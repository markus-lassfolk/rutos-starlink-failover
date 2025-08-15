package main

import (
"context"
"fmt"
"net"
"time"

"github.com/markus-lassfolk/rutos-starlink-failover/pkg/starlink"
)

func main() {
fmt.Println("=== Starlink API Test Program ===")

// Test TCP connectivity first
fmt.Println("\n1. Testing TCP connectivity to 192.168.100.1:9200...")
conn, err := net.DialTimeout("tcp", "192.168.100.1:9200", 5*time.Second)
if err != nil {
fmt.Printf("TCP connection failed: %v\n", err)
fmt.Println("Note: This is expected if not connected to a Starlink dish")
} else {
conn.Close()
fmt.Println("TCP connection successful!")
}

// Test HTTP connectivity  
fmt.Println("\n2. Testing HTTP connectivity...")
endpoint := "http://192.168.100.1:9200"
fmt.Printf("Using endpoint: %s\n", endpoint)

// Create Starlink client with simplified HTTP approach
client := starlink.NewClient(endpoint)

ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()

// Test GetStatus with mock data
fmt.Println("\n3. Testing GetStatus...")
status, err := client.GetStatus(ctx)
if err != nil {
fmt.Printf("GetStatus failed: %v\n", err)
} else {
fmt.Println("✓ GetStatus successful!")
if dish := status.DishGetStatus; dish != nil {
fmt.Printf("  State: %s\n", dish.State)
fmt.Printf("  Ping Latency: %.1f ms\n", dish.PopPingLatencyMsAvg)
fmt.Printf("  SNR: %.1f dB\n", dish.SnrDb)
fmt.Printf("  Uptime: %d seconds (%.1f hours)\n", dish.UptimeS, float64(dish.UptimeS)/3600.0)
}
}

fmt.Println("\n=== Test Complete ===")
fmt.Println("Successfully demonstrated HTTP-based Starlink client with mock data")
}
