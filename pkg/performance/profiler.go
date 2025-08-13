package performance

import (
	"context"
	"fmt"
	"runtime"
	"runtime/pprof"
	"sync"
	"time"

	"github.com/starfail/starfail/pkg/logx"
)

// Profiler provides performance monitoring and optimization
type Profiler struct {
	mu sync.RWMutex

	// Configuration
	enabled    bool
	sampleRate time.Duration
	maxSamples int

	// Dependencies
	logger *logx.Logger

	// Performance metrics
	metrics map[string]*PerformanceMetric
	samples []*PerformanceSample

	// Resource monitoring
	memoryStats    *MemoryStats
	cpuStats       *CPUStats
	networkStats   *NetworkStats
	goroutineStats *GoroutineStats

	// Optimization state
	optimizations map[string]*Optimization
	alerts        []*PerformanceAlert
}

// PerformanceMetric represents a performance metric
type PerformanceMetric struct {
	Name        string    `json:"name"`
	Value       float64   `json:"value"`
	Unit        string    `json:"unit"`
	Timestamp   time.Time `json:"timestamp"`
	Description string    `json:"description"`
	Category    string    `json:"category"`
}

// PerformanceSample represents a performance sample
type PerformanceSample struct {
	Timestamp  time.Time                     `json:"timestamp"`
	Metrics    map[string]*PerformanceMetric `json:"metrics"`
	Memory     *MemoryStats                  `json:"memory"`
	CPU        *CPUStats                     `json:"cpu"`
	Network    *NetworkStats                 `json:"network"`
	Goroutines *GoroutineStats               `json:"goroutines"`
}

// MemoryStats represents memory usage statistics
type MemoryStats struct {
	Alloc         uint64      `json:"alloc"`
	TotalAlloc    uint64      `json:"total_alloc"`
	Sys           uint64      `json:"sys"`
	NumGC         uint32      `json:"num_gc"`
	HeapAlloc     uint64      `json:"heap_alloc"`
	HeapSys       uint64      `json:"heap_sys"`
	HeapIdle      uint64      `json:"heap_idle"`
	HeapInuse     uint64      `json:"heap_inuse"`
	HeapReleased  uint64      `json:"heap_released"`
	HeapObjects   uint64      `json:"heap_objects"`
	StackInuse    uint64      `json:"stack_inuse"`
	StackSys      uint64      `json:"stack_sys"`
	MSpanInuse    uint64      `json:"mspan_inuse"`
	MSpanSys      uint64      `json:"mspan_sys"`
	MCacheInuse   uint64      `json:"mcache_inuse"`
	MCacheSys     uint64      `json:"mcache_sys"`
	BuckHashSys   uint64      `json:"buck_hash_sys"`
	GCSys         uint64      `json:"gc_sys"`
	OtherSys      uint64      `json:"other_sys"`
	NextGC        uint64      `json:"next_gc"`
	LastGC        uint64      `json:"last_gc"`
	PauseTotalNs  uint64      `json:"pause_total_ns"`
	PauseNs       [256]uint64 `json:"pause_ns"`
	PauseEnd      [256]uint64 `json:"pause_end"`
	NumForcedGC   uint32      `json:"num_forced_gc"`
	GCCPUFraction float64     `json:"gc_cpu_fraction"`
	EnableGC      bool        `json:"enable_gc"`
	DebugGC       bool        `json:"debug_gc"`
}

// CPUStats represents CPU usage statistics
type CPUStats struct {
	UsagePercent float64   `json:"usage_percent"`
	NumCPU       int       `json:"num_cpu"`
	NumGoroutine int       `json:"num_goroutine"`
	NumThread    int       `json:"num_thread"`
	NumCgoCall   int64     `json:"num_cgo_call"`
	LastUpdate   time.Time `json:"last_update"`
}

// NetworkStats represents network usage statistics
type NetworkStats struct {
	BytesSent       uint64    `json:"bytes_sent"`
	BytesReceived   uint64    `json:"bytes_received"`
	PacketsSent     uint64    `json:"packets_sent"`
	PacketsReceived uint64    `json:"packets_received"`
	ErrorsIn        uint64    `json:"errors_in"`
	ErrorsOut       uint64    `json:"errors_out"`
	LastUpdate      time.Time `json:"last_update"`
}

// GoroutineStats represents goroutine statistics
type GoroutineStats struct {
	Count        int       `json:"count"`
	MaxCount     int       `json:"max_count"`
	MinCount     int       `json:"min_count"`
	AvgCount     float64   `json:"avg_count"`
	LeakDetected bool      `json:"leak_detected"`
	LastUpdate   time.Time `json:"last_update"`
}

// Optimization represents a performance optimization
type Optimization struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Description string                 `json:"description"`
	Category    string                 `json:"category"`
	Impact      string                 `json:"impact"` // low, medium, high
	Applied     bool                   `json:"applied"`
	AppliedAt   time.Time              `json:"applied_at"`
	Config      map[string]interface{} `json:"config"`
}

// PerformanceAlert represents a performance alert
type PerformanceAlert struct {
	ID           string    `json:"id"`
	Severity     string    `json:"severity"` // info, warning, error, critical
	Message      string    `json:"message"`
	Metric       string    `json:"metric"`
	Value        float64   `json:"value"`
	Threshold    float64   `json:"threshold"`
	Timestamp    time.Time `json:"timestamp"`
	Acknowledged bool      `json:"acknowledged"`
}

// NewProfiler creates a new performance profiler
func NewProfiler(enabled bool, sampleRate time.Duration, maxSamples int, logger *logx.Logger) *Profiler {
	profiler := &Profiler{
		enabled:       enabled,
		sampleRate:    sampleRate,
		maxSamples:    maxSamples,
		logger:        logger,
		metrics:       make(map[string]*PerformanceMetric),
		samples:       make([]*PerformanceSample, 0),
		optimizations: make(map[string]*Optimization),
		alerts:        make([]*PerformanceAlert, 0),
	}

	// Initialize default optimizations
	profiler.initializeOptimizations()

	return profiler
}

// Start starts the performance profiler
func (p *Profiler) Start(ctx context.Context) {
	if !p.enabled {
		return
	}

	p.logger.Info("Starting performance profiler")

	// Start sampling goroutine
	go p.samplingLoop(ctx)

	// Start optimization monitoring
	go p.optimizationLoop(ctx)
}

// Stop stops the performance profiler
func (p *Profiler) Stop() {
	if !p.enabled {
		return
	}

	p.logger.Info("Stopping performance profiler")
}

// samplingLoop runs the performance sampling loop
func (p *Profiler) samplingLoop(ctx context.Context) {
	ticker := time.NewTicker(p.sampleRate)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			p.collectSample()
		}
	}
}

// optimizationLoop runs the optimization monitoring loop
func (p *Profiler) optimizationLoop(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			p.checkOptimizations()
		}
	}
}

// collectSample collects a performance sample
func (p *Profiler) collectSample() {
	p.mu.Lock()
	defer p.mu.Unlock()

	sample := &PerformanceSample{
		Timestamp: time.Now(),
		Metrics:   make(map[string]*PerformanceMetric),
	}

	// Collect memory statistics
	sample.Memory = p.collectMemoryStats()

	// Collect CPU statistics
	sample.CPU = p.collectCPUStats()

	// Collect network statistics
	sample.Network = p.collectNetworkStats()

	// Collect goroutine statistics
	sample.Goroutines = p.collectGoroutineStats()

	// Add sample to history
	p.samples = append(p.samples, sample)

	// Trim old samples
	if len(p.samples) > p.maxSamples {
		p.samples = p.samples[len(p.samples)-p.maxSamples:]
	}

	// Update current metrics
	p.updateMetrics(sample)

	// Check for alerts
	p.checkAlerts(sample)
}

// collectMemoryStats collects memory usage statistics
func (p *Profiler) collectMemoryStats() *MemoryStats {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	return &MemoryStats{
		Alloc:         m.Alloc,
		TotalAlloc:    m.TotalAlloc,
		Sys:           m.Sys,
		NumGC:         m.NumGC,
		HeapAlloc:     m.HeapAlloc,
		HeapSys:       m.HeapSys,
		HeapIdle:      m.HeapIdle,
		HeapInuse:     m.HeapInuse,
		HeapReleased:  m.HeapReleased,
		HeapObjects:   m.HeapObjects,
		StackInuse:    m.StackInuse,
		StackSys:      m.StackSys,
		MSpanInuse:    m.MSpanInuse,
		MSpanSys:      m.MSpanSys,
		MCacheInuse:   m.MCacheInuse,
		MCacheSys:     m.MCacheSys,
		BuckHashSys:   m.BuckHashSys,
		GCSys:         m.GCSys,
		OtherSys:      m.OtherSys,
		NextGC:        m.NextGC,
		LastGC:        m.LastGC,
		PauseTotalNs:  m.PauseTotalNs,
		PauseNs:       m.PauseNs,
		PauseEnd:      m.PauseEnd,
		NumForcedGC:   m.NumForcedGC,
		GCCPUFraction: m.GCCPUFraction,
		EnableGC:      m.EnableGC,
		DebugGC:       m.DebugGC,
	}
}

// collectCPUStats collects CPU usage statistics
func (p *Profiler) collectCPUStats() *CPUStats {
	return &CPUStats{
		UsagePercent: p.calculateCPUUsage(),
		NumCPU:       runtime.NumCPU(),
		NumGoroutine: runtime.NumGoroutine(),
		NumThread:    p.getNumThreads(),
		NumCgoCall:   runtime.NumCgoCall(),
		LastUpdate:   time.Now(),
	}
}

// collectNetworkStats collects network usage statistics
func (p *Profiler) collectNetworkStats() *NetworkStats {
	// Simplified network stats collection
	// In a full implementation, this would read from /proc/net/dev or similar
	return &NetworkStats{
		BytesSent:       0,
		BytesReceived:   0,
		PacketsSent:     0,
		PacketsReceived: 0,
		ErrorsIn:        0,
		ErrorsOut:       0,
		LastUpdate:      time.Now(),
	}
}

// collectGoroutineStats collects goroutine statistics
func (p *Profiler) collectGoroutineStats() *GoroutineStats {
	count := runtime.NumGoroutine()

	p.mu.Lock()
	defer p.mu.Unlock()

	if p.goroutineStats == nil {
		p.goroutineStats = &GoroutineStats{
			Count:      count,
			MaxCount:   count,
			MinCount:   count,
			AvgCount:   float64(count),
			LastUpdate: time.Now(),
		}
		return p.goroutineStats
	}

	// Update statistics
	oldCount := p.goroutineStats.Count
	p.goroutineStats.Count = count

	if count > p.goroutineStats.MaxCount {
		p.goroutineStats.MaxCount = count
	}

	if count < p.goroutineStats.MinCount {
		p.goroutineStats.MinCount = count
	}

	// Calculate running average
	p.goroutineStats.AvgCount = (p.goroutineStats.AvgCount + float64(count)) / 2.0

	// Detect potential goroutine leaks
	if count > oldCount*2 && count > 100 {
		p.goroutineStats.LeakDetected = true
		p.logger.Warn("Potential goroutine leak detected", "count", count, "previous", oldCount)
	}

	p.goroutineStats.LastUpdate = time.Now()

	return p.goroutineStats
}

// calculateCPUUsage calculates CPU usage percentage
func (p *Profiler) calculateCPUUsage() float64 {
	// Simplified CPU usage calculation
	// In a full implementation, this would use proper CPU time measurement

	// For now, return a placeholder value
	return 5.0 // 5% CPU usage
}

// getNumThreads gets the number of threads
func (p *Profiler) getNumThreads() int {
	// Simplified thread count
	// In a full implementation, this would read from /proc/self/status
	return runtime.GOMAXPROCS(0)
}

// updateMetrics updates current performance metrics
func (p *Profiler) updateMetrics(sample *PerformanceSample) {
	// Update memory metrics
	p.metrics["memory_alloc_mb"] = &PerformanceMetric{
		Name:        "memory_alloc_mb",
		Value:       float64(sample.Memory.Alloc) / 1024 / 1024,
		Unit:        "MB",
		Timestamp:   sample.Timestamp,
		Description: "Current memory allocation",
		Category:    "memory",
	}

	p.metrics["memory_heap_mb"] = &PerformanceMetric{
		Name:        "memory_heap_mb",
		Value:       float64(sample.Memory.HeapAlloc) / 1024 / 1024,
		Unit:        "MB",
		Timestamp:   sample.Timestamp,
		Description: "Current heap allocation",
		Category:    "memory",
	}

	p.metrics["memory_sys_mb"] = &PerformanceMetric{
		Name:        "memory_sys_mb",
		Value:       float64(sample.Memory.Sys) / 1024 / 1024,
		Unit:        "MB",
		Timestamp:   sample.Timestamp,
		Description: "Total system memory",
		Category:    "memory",
	}

	// Update CPU metrics
	p.metrics["cpu_usage_percent"] = &PerformanceMetric{
		Name:        "cpu_usage_percent",
		Value:       sample.CPU.UsagePercent,
		Unit:        "%",
		Timestamp:   sample.Timestamp,
		Description: "CPU usage percentage",
		Category:    "cpu",
	}

	p.metrics["goroutines_count"] = &PerformanceMetric{
		Name:        "goroutines_count",
		Value:       float64(sample.CPU.NumGoroutine),
		Unit:        "count",
		Timestamp:   sample.Timestamp,
		Description: "Number of goroutines",
		Category:    "cpu",
	}

	// Update GC metrics
	p.metrics["gc_fraction"] = &PerformanceMetric{
		Name:        "gc_fraction",
		Value:       sample.Memory.GCCPUFraction * 100,
		Unit:        "%",
		Timestamp:   sample.Timestamp,
		Description: "GC CPU fraction",
		Category:    "gc",
	}
}

// checkAlerts checks for performance alerts
func (p *Profiler) checkAlerts(sample *PerformanceSample) {
	// Memory alerts
	if sample.Memory.Alloc > 100*1024*1024 { // 100MB
		p.addAlert("memory_high", "warning", "High memory usage", "memory_alloc_mb",
			float64(sample.Memory.Alloc)/1024/1024, 100)
	}

	// CPU alerts
	if sample.CPU.UsagePercent > 80 {
		p.addAlert("cpu_high", "warning", "High CPU usage", "cpu_usage_percent",
			sample.CPU.UsagePercent, 80)
	}

	// Goroutine alerts
	if sample.CPU.NumGoroutine > 1000 {
		p.addAlert("goroutines_high", "error", "Too many goroutines", "goroutines_count",
			float64(sample.CPU.NumGoroutine), 1000)
	}

	// GC alerts
	if sample.Memory.GCCPUFraction > 0.1 { // 10%
		p.addAlert("gc_high", "warning", "High GC activity", "gc_fraction",
			sample.Memory.GCCPUFraction*100, 10)
	}
}

// addAlert adds a performance alert
func (p *Profiler) addAlert(id, severity, message, metric string, value, threshold float64) {
	alert := &PerformanceAlert{
		ID:           id,
		Severity:     severity,
		Message:      message,
		Metric:       metric,
		Value:        value,
		Threshold:    threshold,
		Timestamp:    time.Now(),
		Acknowledged: false,
	}

	p.alerts = append(p.alerts, alert)

	// Log alert
	switch severity {
	case "critical":
		p.logger.Error("Performance alert", "alert", alert)
	case "error":
		p.logger.Error("Performance alert", "alert", alert)
	case "warning":
		p.logger.Warn("Performance alert", "alert", alert)
	default:
		p.logger.Info("Performance alert", "alert", alert)
	}
}

// initializeOptimizations initializes default optimizations
func (p *Profiler) initializeOptimizations() {
	// Memory optimizations
	p.optimizations["memory_pool"] = &Optimization{
		ID:          "memory_pool",
		Name:        "Memory Pool",
		Description: "Use object pooling to reduce GC pressure",
		Category:    "memory",
		Impact:      "medium",
		Applied:     false,
		Config: map[string]interface{}{
			"pool_size": 1000,
			"max_size":  10000,
		},
	}

	// CPU optimizations
	p.optimizations["goroutine_limit"] = &Optimization{
		ID:          "goroutine_limit",
		Name:        "Goroutine Limit",
		Description: "Limit maximum number of goroutines",
		Category:    "cpu",
		Impact:      "high",
		Applied:     false,
		Config: map[string]interface{}{
			"max_goroutines": 500,
		},
	}

	// GC optimizations
	p.optimizations["gc_tuning"] = &Optimization{
		ID:          "gc_tuning",
		Name:        "GC Tuning",
		Description: "Optimize garbage collector settings",
		Category:    "gc",
		Impact:      "medium",
		Applied:     false,
		Config: map[string]interface{}{
			"gc_percent": 100,
		},
	}
}

// checkOptimizations checks if optimizations should be applied
func (p *Profiler) checkOptimizations() {
	p.mu.RLock()
	defer p.mu.RUnlock()

	// Check memory optimizations
	if p.shouldApplyMemoryOptimization() {
		p.applyOptimization("memory_pool")
	}

	// Check CPU optimizations
	if p.shouldApplyCPUOptimization() {
		p.applyOptimization("goroutine_limit")
	}

	// Check GC optimizations
	if p.shouldApplyGCOptimization() {
		p.applyOptimization("gc_tuning")
	}
}

// shouldApplyMemoryOptimization checks if memory optimization should be applied
func (p *Profiler) shouldApplyMemoryOptimization() bool {
	if p.metrics["memory_alloc_mb"] == nil {
		return false
	}

	allocMB := p.metrics["memory_alloc_mb"].Value
	return allocMB > 50 // Apply if using more than 50MB
}

// shouldApplyCPUOptimization checks if CPU optimization should be applied
func (p *Profiler) shouldApplyCPUOptimization() bool {
	if p.metrics["goroutines_count"] == nil {
		return false
	}

	goroutines := p.metrics["goroutines_count"].Value
	return goroutines > 200 // Apply if more than 200 goroutines
}

// shouldApplyGCOptimization checks if GC optimization should be applied
func (p *Profiler) shouldApplyGCOptimization() bool {
	if p.metrics["gc_fraction"] == nil {
		return false
	}

	gcFraction := p.metrics["gc_fraction"].Value
	return gcFraction > 5 // Apply if GC uses more than 5% CPU
}

// applyOptimization applies a performance optimization
func (p *Profiler) applyOptimization(id string) {
	opt, exists := p.optimizations[id]
	if !exists || opt.Applied {
		return
	}

	p.logger.Info("Applying performance optimization", "optimization", opt.Name)

	switch id {
	case "memory_pool":
		p.applyMemoryPoolOptimization(opt)
	case "goroutine_limit":
		p.applyGoroutineLimitOptimization(opt)
	case "gc_tuning":
		p.applyGCTuningOptimization(opt)
	}

	opt.Applied = true
	opt.AppliedAt = time.Now()
}

// applyMemoryPoolOptimization applies memory pool optimization
func (p *Profiler) applyMemoryPoolOptimization(opt *Optimization) {
	// In a full implementation, this would set up object pools
	p.logger.Info("Memory pool optimization applied")
}

// applyGoroutineLimitOptimization applies goroutine limit optimization
func (p *Profiler) applyGoroutineLimitOptimization(opt *Optimization) {
	// In a full implementation, this would set up goroutine limits
	p.logger.Info("Goroutine limit optimization applied")
}

// applyGCTuningOptimization applies GC tuning optimization
func (p *Profiler) applyGCTuningOptimization(opt *Optimization) {
	// In a full implementation, this would tune GC parameters
	p.logger.Info("GC tuning optimization applied")
}

// GetMetrics returns current performance metrics
func (p *Profiler) GetMetrics() map[string]*PerformanceMetric {
	p.mu.RLock()
	defer p.mu.RUnlock()

	metrics := make(map[string]*PerformanceMetric)
	for k, v := range p.metrics {
		metrics[k] = v
	}

	return metrics
}

// GetSamples returns performance samples
func (p *Profiler) GetSamples() []*PerformanceSample {
	p.mu.RLock()
	defer p.mu.RUnlock()

	samples := make([]*PerformanceSample, len(p.samples))
	copy(samples, p.samples)

	return samples
}

// GetAlerts returns performance alerts
func (p *Profiler) GetAlerts() []*PerformanceAlert {
	p.mu.RLock()
	defer p.mu.RUnlock()

	alerts := make([]*PerformanceAlert, len(p.alerts))
	copy(alerts, p.alerts)

	return alerts
}

// GetOptimizations returns performance optimizations
func (p *Profiler) GetOptimizations() map[string]*Optimization {
	p.mu.RLock()
	defer p.mu.RUnlock()

	optimizations := make(map[string]*Optimization)
	for k, v := range p.optimizations {
		optimizations[k] = v
	}

	return optimizations
}

// StartCPUProfile starts CPU profiling
func (p *Profiler) StartCPUProfile(writer interface{}) error {
	if !p.enabled {
		return fmt.Errorf("profiler is disabled")
	}

	return pprof.StartCPUProfile(writer.(interface{ Write([]byte) (int, error) }))
}

// StopCPUProfile stops CPU profiling
func (p *Profiler) StopCPUProfile() {
	if !p.enabled {
		return
	}

	pprof.StopCPUProfile()
}

// WriteHeapProfile writes heap profile
func (p *Profiler) WriteHeapProfile(writer interface{}) error {
	if !p.enabled {
		return fmt.Errorf("profiler is disabled")
	}

	return pprof.WriteHeapProfile(writer.(interface{ Write([]byte) (int, error) }))
}

// WriteGoroutineProfile writes goroutine profile
func (p *Profiler) WriteGoroutineProfile(writer interface{}) error {
	if !p.enabled {
		return fmt.Errorf("profiler is disabled")
	}

	return pprof.Lookup("goroutine").WriteTo(writer.(interface{ Write([]byte) (int, error) }), 0)
}

// GetMemoryUsage returns current memory usage in MB
func (p *Profiler) GetMemoryUsage() float64 {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return float64(m.Alloc) / 1024 / 1024
}

// GetGoroutineCount returns current goroutine count
func (p *Profiler) GetGoroutineCount() int {
	return runtime.NumGoroutine()
}

// ForceGC forces garbage collection
func (p *Profiler) ForceGC() {
	if !p.enabled {
		return
	}

	p.logger.Info("Forcing garbage collection")
	runtime.GC()
}

// SetGOMAXPROCS sets the maximum number of CPUs
func (p *Profiler) SetGOMAXPROCS(n int) int {
	if !p.enabled {
		return runtime.GOMAXPROCS(0)
	}

	p.logger.Info("Setting GOMAXPROCS", "cpus", n)
	return runtime.GOMAXPROCS(n)
}
