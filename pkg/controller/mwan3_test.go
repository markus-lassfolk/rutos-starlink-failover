package controller

import (
    "context"
    "errors"
    "strings"
    "sync"
    "testing"
    "time"

    "github.com/markus-lassfolk/rutos-starlink-failover/pkg/logx"
)

type fakeRunner struct {
    mu     sync.Mutex
    calls  []string
    outMap map[string][]byte
    errMap map[string]error
    onOutput func(name string, args ...string) ([]byte, error)
}

func (f *fakeRunner) key(name string, args ...string) string {
    return name + " " + strings.Join(args, " ")
}

func (f *fakeRunner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
    f.mu.Lock()
    defer f.mu.Unlock()
    k := f.key(name, args...)
    f.calls = append(f.calls, k)
    if f.onOutput != nil {
        if b, err := f.onOutput(name, args...); b != nil || err != nil {
            return b, err
        }
    }
    if err, ok := f.errMap[k]; ok && err != nil {
        return nil, err
    }
    if b, ok := f.outMap[k]; ok {
        return b, nil
    }
    return nil, nil
}

func (f *fakeRunner) Run(ctx context.Context, name string, args ...string) error {
    f.mu.Lock()
    defer f.mu.Unlock()
    k := f.key(name, args...)
    f.calls = append(f.calls, k)
    if err, ok := f.errMap[k]; ok {
        return err
    }
    return nil
}

func TestSetPrimaryIdempotentDryRun(t *testing.T) {
    logger := logxForTest()
    c := NewController(Config{UseMwan3: true, DryRun: true, CooldownS: 0}, logger)
    fr := &fakeRunner{outMap: map[string][]byte{}, errMap: map[string]error{}}
    c.setRunnerForTest(fr)
    c.setSleepForTest(func(d time.Duration) {})

    ctx := context.Background()
    // First call should log and no-op without error
    if err := c.SetPrimary(ctx, Member{Name: "wan", Interface: "wan"}); err != nil {
        t.Fatalf("first SetPrimary failed: %v", err)
    }
    // Second call should be idempotent in dry-run
    if err := c.SetPrimary(ctx, Member{Name: "wan", Interface: "wan"}); err != nil {
        t.Fatalf("second SetPrimary failed: %v", err)
    }
}

func TestNetifdVerifiedApplyBackoff(t *testing.T) {
    logger := logxForTest()
    c := NewController(Config{UseMwan3: false, DryRun: false, CooldownS: 0}, logger)
    fr := &fakeRunner{outMap: map[string][]byte{}, errMap: map[string]error{}}
    c.setRunnerForTest(fr)
    // speed up backoff
    c.setSleepForTest(func(d time.Duration) {})

    // discoverNetifaceMembers: return two interfaces via ubus dump
    fr.outMap["ubus call network.interface dump"] = []byte(`{"interface":[{"interface":"wan","up":true},{"interface":"lte","up":true}]}`)
    // ip route default will fail first 2 times, then succeed on wan
    fail := 0
    fr.outMap["ip -4 route show default"] = []byte("default via 1.1.1.1 dev lte")
    fr.errMap = map[string]error{}

    // Hook Output to simulate changing default route after a couple attempts
    fr.onOutput = func(name string, args ...string) ([]byte, error) {
        if name == "ip" && len(args) >= 4 && args[0] == "-4" && args[1] == "route" {
            if fail < 2 {
                fail++
                return []byte("default via 1.1.1.1 dev lte"), nil
            }
            return []byte("default via 1.1.1.1 dev wan"), nil
        }
        return nil, nil
    }

    if err := c.SetPrimary(context.Background(), Member{Name: "wan", Interface: "wan"}); err != nil {
        t.Fatalf("SetPrimary netifd failed: %v", err)
    }
}

func TestMwan3PrimaryDetectionJSON(t *testing.T) {
    logger := logxForTest()
    c := NewController(Config{UseMwan3: true, DryRun: false, CooldownS: 0}, logger)
    fr := &fakeRunner{outMap: map[string][]byte{}, errMap: map[string]error{}}
    c.setRunnerForTest(fr)

    ctx := context.Background()
    
    // Test JSON parsing with valid mwan3 --json output
    jsonOutput := `{
        "interfaces": {
            "wan1": {
                "status": "online",
                "metric": 10,
                "weight": 1,
                "policy": "wan1_only"
            },
            "lte1": {
                "status": "online", 
                "metric": 1,
                "weight": 1,
                "policy": "lte1_only"
            }
        }
    }`
    fr.outMap["mwan3 status --json"] = []byte(jsonOutput)
    
    member, err := c.GetCurrentPrimary(ctx)
    if err != nil {
        t.Fatalf("GetCurrentPrimary failed: %v", err)
    }
    
    // Should pick lte1 as it has metric=1 (lower = higher priority)
    if member.Name != "lte1" {
        t.Errorf("expected primary=lte1, got %s", member.Name)
    }
    if member.Metric != 1 {
        t.Errorf("expected metric=1, got %d", member.Metric)
    }
}

func TestMwan3PrimaryDetectionTextFallback(t *testing.T) {
    logger := logxForTest()
    c := NewController(Config{UseMwan3: true, DryRun: false, CooldownS: 0}, logger)
    fr := &fakeRunner{outMap: map[string][]byte{}, errMap: map[string]error{}}
    c.setRunnerForTest(fr)

    ctx := context.Background()
    
    // JSON fails, fall back to text parsing
    fr.errMap["mwan3 status --json"] = errors.New("option not supported")
    textOutput := `interface wan1 is online and tracking is active
interface lte1 is offline and tracking is inactive`
    fr.outMap["mwan3 status"] = []byte(textOutput)
    
    member, err := c.GetCurrentPrimary(ctx)
    if err != nil {
        t.Fatalf("GetCurrentPrimary failed: %v", err)
    }
    
    // Should pick wan1 as it's the only online interface
    if member.Name != "wan1" {
        t.Errorf("expected primary=wan1, got %s", member.Name)
    }
}

// TestParseMwan3Config tests the mwan3 config parsing logic
func TestParseMwan3Config(t *testing.T) {
    logger := logxForTest()
    c := NewController(Config{}, logger)

    testCases := []struct {
        name     string
        input    string
        expected []Member
        wantErr  bool
    }{
        {
            name: "valid UCI config",
            input: `mwan3.wan_member=member
mwan3.wan_member.interface='wan'
mwan3.wan_member.metric='1'
mwan3.wan_member.weight='3'
mwan3.lte_member=member  
mwan3.lte_member.interface='lte'
mwan3.lte_member.metric='2'
mwan3.lte_member.weight='1'
mwan3.lte_member.enabled='1'`,
            expected: []Member{
                {Name: "wan_member", Interface: "wan", Metric: 1, Weight: 3, Enabled: true},
                {Name: "lte_member", Interface: "lte", Metric: 2, Weight: 1, Enabled: true},
            },
            wantErr: false,
        },
        {
            name:     "empty config",
            input:    "",
            expected: []Member{},
            wantErr:  false,
        },
        {
            name: "disabled member",
            input: `mwan3.disabled_member=member
mwan3.disabled_member.interface='wan2'
mwan3.disabled_member.metric='3'
mwan3.disabled_member.enabled='0'`,
            expected: []Member{
                {Name: "disabled_member", Interface: "wan2", Metric: 3, Weight: 1, Enabled: false},
            },
            wantErr: false,
        },
    }

    for _, tc := range testCases {
        t.Run(tc.name, func(t *testing.T) {
            members, err := c.parseMwan3Config(tc.input)
            
            if tc.wantErr && err == nil {
                t.Fatalf("expected error but got none")
            }
            if !tc.wantErr && err != nil {
                t.Fatalf("unexpected error: %v", err)
            }

            if len(members) != len(tc.expected) {
                t.Fatalf("expected %d members, got %d", len(tc.expected), len(members))
            }

            for i, expected := range tc.expected {
                if members[i].Name != expected.Name {
                    t.Errorf("member %d: expected name %s, got %s", i, expected.Name, members[i].Name)
                }
                if members[i].Interface != expected.Interface {
                    t.Errorf("member %d: expected interface %s, got %s", i, expected.Interface, members[i].Interface)
                }
                if members[i].Metric != expected.Metric {
                    t.Errorf("member %d: expected metric %d, got %d", i, expected.Metric, members[i].Metric)
                }
                if members[i].Weight != expected.Weight {
                    t.Errorf("member %d: expected weight %d, got %d", i, expected.Weight, members[i].Weight)
                }
                if members[i].Enabled != expected.Enabled {
                    t.Errorf("member %d: expected enabled %v, got %v", i, expected.Enabled, members[i].Enabled)
                }
            }
        })
    }
}

// TestParseDefaultDev tests the default route device parsing
func TestParseDefaultDev(t *testing.T) {
    testCases := []struct {
        name     string
        input    string
        expected string
    }{
        {
            name:     "normal route",
            input:    "default via 192.168.1.1 dev eth0 proto static metric 1",
            expected: "eth0",
        },
        {
            name:     "multiple interfaces",
            input:    "default via 192.168.1.1 dev eth0 proto static\ndefault via 10.0.0.1 dev wlan0 proto dhcp metric 2",
            expected: "eth0",
        },
        {
            name:     "no dev field",
            input:    "default via 192.168.1.1 proto static",
            expected: "",
        },
        {
            name:     "empty input",
            input:    "",
            expected: "",
        },
        {
            name:     "complex interface name",
            input:    "default via 192.168.100.1 dev qmimux0 proto static scope link src 10.51.171.103 metric 3",
            expected: "qmimux0",
        },
        {
            name:     "cellular interface from real RUTOS",
            input:    "default via 10.51.171.1 dev wwan0 proto static scope link src 10.51.171.103 metric 20",
            expected: "wwan0",
        },
    }

    for _, tc := range testCases {
        t.Run(tc.name, func(t *testing.T) {
            result := parseDefaultDev(tc.input)
            if result != tc.expected {
                t.Fatalf("expected %q, got %q", tc.expected, result)
            }
        })
    }
}

// minimal test logger to keep package boundary
func logxForTest() *logx.Logger {
    l := logx.New("error")
    if l == nil {
        panic(errors.New("failed to create logger"))
    }
    return l
}
