package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

var (
	verbose                   = flag.Bool("verbose", false, "Enable verbose logging")
	host                      = flag.String("host", "192.168.80.1", "RutOS host address")
	port                      = flag.String("port", "22", "SSH port")
	user                      = flag.String("user", "root", "SSH username")
	keyFile                   = flag.String("key", "C:\\Users\\markusla\\OneDrive\\IT\\RUTOS Keys\\rusos_private_key_openssh", "SSH private key file")
	timeout                   = flag.Duration("timeout", 30*time.Second, "Command timeout")
	testAll                   = flag.Bool("all", true, "Test all GPS methods")
	testGsmctl                = flag.Bool("gsmctl", false, "Test only gsmctl method")
	testUbus                  = flag.Bool("ubus", false, "Test only ubus method")
	testDevice                = flag.Bool("device", false, "Test only device method")
	analyze                   = flag.Bool("analyze", false, "Perform comprehensive RutOS GPS analysis")
	testGpsctl                = flag.Bool("test-gpsctl", false, "Test gpsctl command approach")
	enhanced                  = flag.Bool("enhanced", false, "Test enhanced GPS data collection with all gpsctl options")
	testGsmGps                = flag.Bool("test-gsm-gps", false, "Test GSM GPS functionality comprehensively")
	testQuectel               = flag.Bool("test-quectel", false, "Test Quectel GSM GPS specifically")
	compareAll                = flag.Bool("compare-all", false, "Compare all three GPS sources")
	testCellular              = flag.Bool("test-cellular", false, "Test cellular network location services")
	testCellTower             = flag.Bool("test-celltower", false, "Test cell tower location databases")
	testCellAccuracy          = flag.Bool("test-cell-accuracy", false, "Comprehensive cell tower location accuracy test")
	testCellLocal             = flag.Bool("test-cell-local", false, "Test cell tower location services locally with hardcoded data")
	debugCellAPIs             = flag.Bool("debug-cell-apis", false, "Debug cell tower APIs with detailed logging")
	testPracticalCell         = flag.Bool("test-practical-cell", false, "Test practical cell tower location using nearby cells")
	testContribute            = flag.Bool("test-contribute", false, "Test contributing data to OpenCellID database")
	showStrategy              = flag.Bool("show-strategy", false, "Show OpenCellID usage strategy and limits")
	testSmartCell             = flag.Bool("test-smart-cell", false, "Test intelligent cell location caching with environment-based triggers")
	testUCIConfig             = flag.Bool("test-uci-config", false, "Test UCI configuration management for cell location services")
	testEnhancedCell          = flag.Bool("test-enhanced-cell", false, "Test enhanced OpenCellID with multiple cells and detailed information")
	testUnwiredLabs           = flag.Bool("test-unwiredlabs", false, "Test UnwiredLabs LocationAPI with cell towers and WiFi access points")
	testUnwiredUCI            = flag.Bool("test-unwired-uci", false, "Test UCI configuration management for UnwiredLabs LocationAPI")
	testGoogleGeo             = flag.Bool("test-google-geo", false, "Test Google Geolocation API with cell towers and WiFi access points")
	testGoogleUCI             = flag.Bool("test-google-uci", false, "Test UCI configuration management for Google Geolocation API")
	debugNeighbors            = flag.Bool("debug-neighbors", false, "Debug neighbor cell parsing to see raw AT command data")
	debug5G                   = flag.Bool("debug-5g", false, "Debug 5G cell data and AT commands to ensure proper 5G support")
	enhanced5G                = flag.Bool("enhanced-5g", false, "Enhanced 5G network analysis with comprehensive NR cell detection")
	testBSSIDOnly             = flag.Bool("test-bssid-only", false, "Test BSSID-only location using WiFi access points (no cellular data)")
	testBSSIDHardcoded        = flag.Bool("test-bssid-hardcoded", false, "Test BSSID location with hardcoded WiFi access points for API verification")
	testCombined              = flag.Bool("test-combined", false, "Test combined cellular + BSSID location for maximum accuracy")
	testEnhancedWiFi          = flag.Bool("test-enhanced-wifi", false, "Test enhanced ubus WiFi scanning with rich data (quality, SNR, channel width)")
	testLocationMgr           = flag.Bool("test-location-manager", false, "Test the intelligent location manager with hierarchy and caching")
	testIntelligentCache      = flag.Bool("test-intelligent-cache", false, "Test intelligent location cache with cell-change invalidation")
	testAdaptiveCache         = flag.Bool("test-adaptive-cache", false, "Test adaptive location cache with movement detection and quality gating")
	testProductionMgr         = flag.Bool("test-production-manager", false, "Test production location manager with non-blocking operations and error fallback")
	testLocationSources       = flag.Bool("test-location-sources", false, "Show comprehensive comparison of all location sources including all Starlink APIs")
	testStarlinkMultiAPI      = flag.Bool("test-starlink-multi-api", false, "Test comprehensive Starlink GPS collection from all three APIs")
	testEnhancedLocation      = flag.Bool("test-enhanced-location", false, "Test enhanced standardized location response with fix types, source details, and altitude compensation")
	testImprovedLocation      = flag.Bool("test-improved-location", false, "Test improved standardized location with integer fix types, m/s speed, altitude verification, and full precision coordinates")
	testGPSTable              = flag.Bool("test-gps-table", false, "Run comprehensive GPS table test showing all sources with unique data in table format")
	testEnhancedGPSTable      = flag.Bool("test-enhanced-gps-table", false, "Run enhanced comprehensive GPS table test with all corrections and proper data interpretation")
	testGPSHealthMonitorFlag  = flag.Bool("test-gps-health", false, "Test GPS health monitoring and reset functionality")
	testSystemMaintenanceFlag = flag.Bool("test-maintenance", false, "Test system maintenance with GPS health monitoring integration")
	testGPSMapsComparisonFlag = flag.Bool("test-gps-maps", false, "Generate Google Maps links with accuracy circles for GPS source comparison")
	testGPSParsingDebugFlag   = flag.Bool("debug-gps-parsing", false, "Debug GPS parsing issues")
	testUnifiedGPSTableFlag   = flag.Bool("test-unified-gps", false, "Test unified GPS table with combined RUTOS GPS data and unique data rows")
	testStandardizedTableFlag = flag.Bool("test-standardized-table", false, "Test standardized output table with corrected formats (m/s speed, decimal accuracy, integer fix type)")
	testStarlinkTimeDebugFlag = flag.Bool("debug-starlink-time", false, "Debug Starlink time/date discrepancy issue")
	testAPIServerFlag         = flag.Bool("start-api-server", false, "Start Starfail GPS API Server (RUTOS-compatible)")
	testAPIResponseFlag       = flag.Bool("test-api-response", false, "Test RUTOS-compatible API response format")
	testAPIEndpointsFlag      = flag.Bool("test-api-endpoints", false, "Test all API endpoints without starting server")
	testUCIAPIConfigFlag      = flag.Bool("test-uci-api-config", false, "Test UCI API configuration management")
)

type GPSTestResult struct {
	Method    string
	Success   bool
	Output    string
	Error     string
	Latitude  float64
	Longitude float64
	Altitude  float64
	Accuracy  float64
	Source    string
	Duration  time.Duration
}

func main() {
	flag.Parse()

	fmt.Println("🛰️  RutOS GPS Testing Tool")
	fmt.Println("=========================")
	fmt.Printf("Target: %s@%s:%s\n", *user, *host, *port)
	fmt.Printf("SSH Key: %s\n", *keyFile)
	fmt.Println()

	// Create SSH client
	client, err := createSSHClient()
	if err != nil {
		log.Fatalf("Failed to create SSH client: %v", err)
	}
	defer client.Close()

	fmt.Println("✅ SSH connection established!")
	fmt.Println()

	// If analysis mode, run comprehensive analysis
	if *analyze {
		analyzeRutOSGPSMethods(client)
		return
	}

	// If gpsctl test mode, test gpsctl approach
	if *testGpsctl {
		testGPSCTL(client)
		return
	}

	// If enhanced mode, test enhanced GPS data collection
	if *enhanced {
		compareGPSSources(client)
		return
	}

	// If GSM GPS test mode, test GSM GPS functionality
	if *testGsmGps {
		testGSMGPS(client)
		return
	}

	// If Quectel test mode, test Quectel GPS specifically
	if *testQuectel {
		_, err := testQuectelGPS(client)
		if err != nil {
			fmt.Printf("❌ Quectel GPS test failed: %v\n", err)
		}
		return
	}

	// If compare all mode, compare all GPS sources
	if *compareAll {
		compareAllGPSSources(client)
		return
	}

	// If cellular test mode, test cellular location services
	if *testCellular {
		testCellularLocation(client)
		return
	}

	// If cell tower test mode, test cell tower location databases
	if *testCellTower {
		intel, err := collectCellularLocationIntelligence(client)
		if err != nil {
			fmt.Printf("❌ Failed to collect cellular data: %v\n", err)
			return
		}
		_, err = getLocationWithCellTowerFallback(intel)
		if err != nil {
			fmt.Printf("❌ Cell tower location failed: %v\n", err)
		}
		return
	}

	// If cell tower accuracy test mode, run comprehensive accuracy test
	if *testCellAccuracy {
		if err := testCellTowerLocationAccuracy(client); err != nil {
			fmt.Printf("❌ Cell tower accuracy test failed: %v\n", err)
		}
		return
	}

	// If local cell tower test mode, run without SSH
	if *testCellLocal {
		if err := runLocalCellTowerTest(); err != nil {
			fmt.Printf("❌ Local cell tower test failed: %v\n", err)
		}
		return
	}

	// If debug cell APIs mode, run debug tests
	if *debugCellAPIs {
		if err := debugCellTowerAPIs(); err != nil {
			fmt.Printf("❌ Debug cell APIs failed: %v\n", err)
		}
		return
	}

	// If practical cell test mode, test using nearby cells
	if *testPracticalCell {
		if err := testPracticalCellLocation(); err != nil {
			fmt.Printf("❌ Practical cell location test failed: %v\n", err)
		}
		return
	}

	// If contribute test mode, test contributing to OpenCellID
	if *testContribute {
		if err := testContributionToOpenCellID(client); err != nil {
			fmt.Printf("❌ OpenCellID contribution test failed: %v\n", err)
		}
		return
	}

	// If show strategy mode, display usage strategy
	if *showStrategy {
		displayUsageStrategy()
		testUsageStrategy()
		return
	}

	// If smart cell test mode, test intelligent cell location caching
	if *testSmartCell {
		if err := runSmartCellLocationTest(); err != nil {
			fmt.Printf("❌ Smart cell location test failed: %v\n", err)
		}
		return
	}

	// If UCI config test mode, test UCI configuration management
	if *testUCIConfig {
		if err := testUCICellConfig(); err != nil {
			fmt.Printf("❌ UCI configuration test failed: %v\n", err)
		}
		return
	}

	// If enhanced cell test mode, test enhanced OpenCellID with multiple cells
	if *testEnhancedCell {
		if err := testEnhancedOpenCellID(); err != nil {
			fmt.Printf("❌ Enhanced OpenCellID test failed: %v\n", err)
		}
		return
	}

	// If UnwiredLabs test mode, test UnwiredLabs LocationAPI
	if *testUnwiredLabs {
		// Use live data from RutOS
		response, err := GetLocationWithUnwiredLabs(client, "eu1")
		if err != nil {
			fmt.Printf("❌ UnwiredLabs LocationAPI test failed: %v\n", err)
		} else {
			fmt.Printf("✅ UnwiredLabs test successful: %.6f°, %.6f° (±%dm)\n",
				response.Lat, response.Lon, response.Accuracy)
		}
		return
	}

	// If UnwiredLabs UCI config test mode, test UCI configuration management
	if *testUnwiredUCI {
		if err := testUCIUnwiredLabsConfig(); err != nil {
			fmt.Printf("❌ UnwiredLabs UCI configuration test failed: %v\n", err)
		}
		return
	}

	// If Google Geolocation test mode, test Google Geolocation API
	if *testGoogleGeo {
		// Use live data from RutOS
		response, err := GetLocationWithGoogleComplete(client, true)
		if err != nil {
			fmt.Printf("❌ Google Geolocation API test failed: %v\n", err)
		} else {
			fmt.Printf("✅ Google Geolocation test successful: %.6f°, %.6f° (±%.0fm)\n",
				response.Location.Lat, response.Location.Lng, response.Accuracy)

			// Compare with GPS if available
			fmt.Println("\n🎯 Comparing with GPS reference...")
			response.CompareWithGPS(59.48007, 18.27985) // Known GPS coordinates
		}
		return
	}

	// If Google UCI config test mode, test UCI configuration management
	if *testGoogleUCI {
		if err := testUCIGoogleConfig(); err != nil {
			fmt.Printf("❌ Google Geolocation UCI configuration test failed: %v\n", err)
		}
		return
	}

	// If debug neighbors mode, analyze neighbor cell parsing
	if *debugNeighbors {
		if err := testDebugNeighborCells(); err != nil {
			fmt.Printf("❌ Debug neighbor cells failed: %v\n", err)
		}
		return
	}

	// If debug 5G mode, analyze 5G cell data and AT commands
	if *debug5G {
		if err := test5GCellDebug(); err != nil {
			fmt.Printf("❌ Debug 5G cells failed: %v\n", err)
		}
		return
	}

	// If enhanced 5G mode, run comprehensive 5G network analysis
	if *enhanced5G {
		if err := test5GEnhancedCollection(); err != nil {
			fmt.Printf("❌ Enhanced 5G analysis failed: %v\n", err)
		}
		return
	}

	// If BSSID-only test mode, test WiFi access point location
	if *testBSSIDOnly {
		if err := testBSSIDOnlyLocation(); err != nil {
			fmt.Printf("❌ BSSID-only location test failed: %v\n", err)
		}
		return
	}

	// If BSSID hardcoded test mode, test with hardcoded WiFi access points
	if *testBSSIDHardcoded {
		if err := testBSSIDHardcodedLocation(); err != nil {
			fmt.Printf("❌ BSSID hardcoded test failed: %v\n", err)
		}
		return
	}

	// If combined test mode, test cellular + BSSID location
	if *testCombined {
		if err := testCombinedLocation(); err != nil {
			fmt.Printf("❌ Combined location test failed: %v\n", err)
		}
		return
	}

	// If enhanced WiFi test mode, test ubus WiFi scanning
	if *testEnhancedWiFi {
		testEnhancedUbusWiFiScan()
		return
	}

	// If location manager test mode, test intelligent hierarchy
	if *testLocationMgr {
		testLocationManager()
		return
	}

	// If intelligent cache test mode, test smart invalidation
	if *testIntelligentCache {
		testIntelligentLocationCache()
		return
	}

	// If adaptive cache test mode, test movement detection and quality gating
	if *testAdaptiveCache {
		testAdaptiveLocationCache()
		return
	}

	// If production manager test mode, test non-blocking operations
	if *testProductionMgr {
		testProductionLocationManager()
		return
	}

	// If location sources comparison test mode
	if *testLocationSources {
		testLocationSourceComparison()
		return
	}

	// If Starlink multi-API test mode
	if *testStarlinkMultiAPI {
		testComprehensiveStarlinkGPS()
		return
	}

	// If enhanced location test mode
	if *testEnhancedLocation {
		testEnhancedStandardizedLocation()
		return
	}

	// If improved location test mode
	if *testImprovedLocation {
		testImprovedStandardizedLocation()
		return
	}

	// If GPS table test mode
	if *testGPSTable {
		testComprehensiveGPSTable()
		return
	}

	// If enhanced GPS table test mode
	if *testEnhancedGPSTable {
		testEnhancedComprehensiveGPSTable()
		return
	}

	// If GPS health monitor test mode
	if *testGPSHealthMonitorFlag {
		testGPSHealthMonitor()
		return
	}

	// If system maintenance test mode
	if *testSystemMaintenanceFlag {
		testSystemMaintenance()
		return
	}

	// If GPS maps comparison test mode
	if *testGPSMapsComparisonFlag {
		testGPSMapsComparison()
		return
	}

	// If GPS parsing debug test mode
	if *testGPSParsingDebugFlag {
		testGPSParsingDebug()
		return
	}

	// If unified GPS table test mode
	if *testUnifiedGPSTableFlag {
		testUnifiedGPSTable()
		return
	}

	// If standardized table test mode
	if *testStandardizedTableFlag {
		testStandardizedOutputTable()
		return
	}

	// If Starlink time debug test mode
	if *testStarlinkTimeDebugFlag {
		testStarlinkTimeDebug()
		return
	}

	// If API server mode
	if *testAPIServerFlag {
		testStarfailAPIServer()
		return
	}

	// If API response test mode
	if *testAPIResponseFlag {
		testAPIResponse()
		return
	}

	// If API endpoints test mode
	if *testAPIEndpointsFlag {
		testAPIEndpoints()
		return
	}

	// If UCI API config test mode
	if *testUCIAPIConfigFlag {
		testUCIAPIConfig()
		return
	}

	// Test GPS methods
	var results []GPSTestResult

	if *testAll || *testGsmctl {
		fmt.Println("🔍 Testing Method 1: gsmctl GPS (AT+CGPSINFO)")
		fmt.Println("=" + strings.Repeat("=", 50))
		result := testGsmctlGPS(client)
		results = append(results, result)
		displayResult(result)
		fmt.Println()
	}

	if *testAll || *testUbus {
		fmt.Println("🔍 Testing Method 2: ubus GPS service")
		fmt.Println("=" + strings.Repeat("=", 40))
		result := testUbusGPS(client)
		results = append(results, result)
		displayResult(result)
		fmt.Println()
	}

	if *testAll || *testDevice {
		fmt.Println("🔍 Testing Method 3: Direct GPS device access")
		fmt.Println("=" + strings.Repeat("=", 45))
		result := testDirectGPS(client)
		results = append(results, result)
		displayResult(result)
		fmt.Println()
	}

	// Enhanced GPS tests
	if *testAll {
		fmt.Println("🔍 Enhanced GPS Tests")
		fmt.Println("=" + strings.Repeat("=", 20))

		// Test gpsd daemon
		fmt.Println("📡 Testing gpsd daemon:")
		gpsResult := testGPSDaemon(client)
		results = append(results, gpsResult)
		displayResult(gpsResult)
		fmt.Println()

		// Test NMEA direct reading
		fmt.Println("📡 Testing NMEA direct reading:")
		nmeaResults := testNMEADirect(client)
		for _, result := range nmeaResults {
			results = append(results, result)
			displayResult(result)
		}
		fmt.Println()

		// Test AT commands
		fmt.Println("📡 Testing AT commands:")
		atResults := testATCommands(client)
		for _, result := range atResults {
			results = append(results, result)
			displayResult(result)
		}
		fmt.Println()
	}

	// Additional system info
	fmt.Println("🔧 System Information")
	fmt.Println("=" + strings.Repeat("=", 20))
	getSystemInfo(client)
	fmt.Println()

	// Get actual GPS coordinates if we found working sources
	hasWorkingGPS := false
	for _, result := range results {
		if result.Success && (strings.Contains(result.Source, "nmea") || strings.Contains(result.Source, "gpsd")) {
			hasWorkingGPS = true
			break
		}
	}

	if hasWorkingGPS {
		fmt.Println()
		getGPSCoordinates(client)
		fmt.Println()
	}

	// Summary
	fmt.Println("📊 GPS Test Summary")
	fmt.Println("=" + strings.Repeat("=", 18))
	displaySummary(results)
}

func createSSHClient() (*ssh.Client, error) {
	// Read private key
	key, err := os.ReadFile(*keyFile)
	if err != nil {
		return nil, fmt.Errorf("unable to read private key: %v", err)
	}

	// Create the Signer for this private key
	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("unable to parse private key: %v", err)
	}

	// SSH client config
	config := &ssh.ClientConfig{
		User: *user,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // Note: In production, use proper host key verification
		Timeout:         *timeout,
	}

	// Connect to SSH server
	client, err := ssh.Dial("tcp", *host+":"+*port, config)
	if err != nil {
		return nil, fmt.Errorf("failed to dial: %v", err)
	}

	return client, nil
}

func executeCommand(client *ssh.Client, command string) (string, error) {
	session, err := client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create session: %v", err)
	}
	defer session.Close()

	if *verbose {
		fmt.Printf("  Executing: %s\n", command)
	}

	output, err := session.CombinedOutput(command)
	return string(output), err
}

func testGsmctlGPS(client *ssh.Client) GPSTestResult {
	start := time.Now()
	result := GPSTestResult{
		Method: "gsmctl (AT+CGPSINFO)",
	}

	// Test if gsmctl is available
	output, err := executeCommand(client, "which gsmctl")
	if err != nil {
		result.Error = "gsmctl command not found"
		result.Duration = time.Since(start)
		return result
	}

	// Execute GPS command
	output, err = executeCommand(client, "gsmctl -A 'AT+CGPSINFO'")
	result.Output = output
	result.Duration = time.Since(start)

	if err != nil {
		result.Error = fmt.Sprintf("gsmctl command failed: %v", err)
		return result
	}

	// Parse output for GPS data
	if strings.Contains(output, "+CGPSINFO:") {
		result.Success = true
		// TODO: Parse actual coordinates from output
		result.Source = "cellular_modem"
	} else {
		result.Error = "No GPS data in gsmctl output"
	}

	return result
}

func testUbusGPS(client *ssh.Client) GPSTestResult {
	start := time.Now()
	result := GPSTestResult{
		Method: "ubus GPS service",
	}

	// Test if ubus is available
	output, err := executeCommand(client, "which ubus")
	if err != nil {
		result.Error = "ubus command not found"
		result.Duration = time.Since(start)
		return result
	}

	// Execute GPS command
	output, err = executeCommand(client, "ubus call gps info")
	result.Output = output
	result.Duration = time.Since(start)

	if err != nil {
		result.Error = fmt.Sprintf("ubus GPS call failed: %v", err)
		return result
	}

	// Check if GPS service is available
	if strings.Contains(output, "latitude") && strings.Contains(output, "longitude") {
		result.Success = true
		result.Source = "rutos_gps_service"
		// TODO: Parse actual coordinates from JSON output
	} else if strings.Contains(output, "Command failed") {
		result.Error = "GPS service not available or not configured"
	} else {
		result.Error = "Unexpected ubus GPS response format"
	}

	return result
}

func testDirectGPS(client *ssh.Client) GPSTestResult {
	start := time.Now()
	result := GPSTestResult{
		Method: "Direct GPS device",
	}

	// Check for GPS devices
	devices := []string{"/dev/ttyUSB1", "/dev/ttyUSB2", "/dev/ttyACM0", "/dev/ttyUSB0"}

	var foundDevices []string
	for _, device := range devices {
		output, err := executeCommand(client, fmt.Sprintf("ls -la %s", device))
		if err == nil && !strings.Contains(output, "No such file") {
			foundDevices = append(foundDevices, device)
		}
	}

	result.Duration = time.Since(start)

	if len(foundDevices) == 0 {
		result.Error = "No GPS devices found"
		return result
	}

	result.Output = fmt.Sprintf("Found GPS devices: %s", strings.Join(foundDevices, ", "))
	result.Success = true
	result.Source = "direct_device"

	// Note: Reading from GPS device would require NMEA parsing
	// For now, just report that devices are available

	return result
}

func getSystemInfo(client *ssh.Client) {
	commands := map[string]string{
		"RutOS Version":  "cat /etc/version",
		"Uptime":         "uptime",
		"USB Devices":    "lsusb",
		"TTY Devices":    "ls -la /dev/tty*",
		"Modem Status":   "gsmctl -S",
		"Network Status": "ip route show",
		"GPS Processes":  "ps | grep -i gps",
	}

	for name, cmd := range commands {
		fmt.Printf("  %s:\n", name)
		output, err := executeCommand(client, cmd)
		if err != nil {
			fmt.Printf("    Error: %v\n", err)
		} else {
			lines := strings.Split(strings.TrimSpace(output), "\n")
			for _, line := range lines {
				if strings.TrimSpace(line) != "" {
					fmt.Printf("    %s\n", line)
				}
			}
		}
		fmt.Println()
	}
}

func displayResult(result GPSTestResult) {
	if result.Success {
		fmt.Printf("  ✅ SUCCESS - %s\n", result.Method)
		fmt.Printf("     Source: %s\n", result.Source)
		fmt.Printf("     Duration: %v\n", result.Duration)
		if result.Latitude != 0 && result.Longitude != 0 {
			fmt.Printf("     Coordinates: %.6f, %.6f\n", result.Latitude, result.Longitude)
			if result.Altitude != 0 {
				fmt.Printf("     Altitude: %.2f m\n", result.Altitude)
			}
		}
	} else {
		fmt.Printf("  ❌ FAILED - %s\n", result.Method)
		fmt.Printf("     Error: %s\n", result.Error)
		fmt.Printf("     Duration: %v\n", result.Duration)
	}

	if *verbose && result.Output != "" {
		fmt.Printf("     Raw Output:\n")
		lines := strings.Split(result.Output, "\n")
		for _, line := range lines {
			if strings.TrimSpace(line) != "" {
				fmt.Printf("       %s\n", line)
			}
		}
	}
}

func displaySummary(results []GPSTestResult) {
	successful := 0
	for _, result := range results {
		if result.Success {
			successful++
		}
	}

	fmt.Printf("  Total methods tested: %d\n", len(results))
	fmt.Printf("  Successful methods: %d\n", successful)
	fmt.Printf("  Failed methods: %d\n", len(results)-successful)
	fmt.Println()

	if successful > 0 {
		fmt.Println("  ✅ Working GPS sources:")
		for _, result := range results {
			if result.Success {
				fmt.Printf("    - %s (%s)\n", result.Method, result.Source)
			}
		}
	} else {
		fmt.Println("  ❌ No working GPS sources found")
		fmt.Println("     Possible issues:")
		fmt.Println("     - GPS hardware not connected")
		fmt.Println("     - GPS services not configured")
		fmt.Println("     - Cellular modem without GPS capability")
		fmt.Println("     - GPS antenna not connected")
	}
}
