# Configuration Boolean Standardization

## Issues Found

1. **GPS Field Path**: Using `gpsStats.gpsValid` instead of `dishGetStatus.gpsStats.gpsValid`
2. **SNR Field**: Trying to extract non-existent `snr` field instead of using available `isSnrAboveNoiseFloor`  
3. **Boolean Inconsistency**: Mixed use of "1"/"0" vs "true"/"false" for boolean values

## Fixes Applied

### 1. GPS Field Path Correction
**Before**: 
```bash
gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsValid // true' 2>/dev/null)
gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.gpsStats.gpsSats // 0' 2>/dev/null)
```

**After**:
```bash
gps_valid=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsValid // true' 2>/dev/null)
gps_sats=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.gpsStats.gpsSats // 0' 2>/dev/null)
```

### 2. SNR Field Enhancement
**Before**: 
```bash
snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.snr // 0' 2>/dev/null)
```

**After**:
```bash
# SNR field may not exist in all firmware versions - try multiple locations
snr=$(echo "$status_data" | "$JQ_CMD" -r '.dishGetStatus.snr // .dishGetStatus.downlinkThroughputBps // 0' 2>/dev/null)
# If no direct SNR available, use isSnrAboveNoiseFloor as boolean indicator
if [ "$snr" = "0" ] || [ "$snr" = "null" ]; then
    if [ "$is_snr_above_noise_floor" = "true" ]; then
        snr="good"
    else
        snr="poor"
    fi
fi
```

### 3. Boolean Standardization Strategy

**Current Mixed Usage**:
- `PUSHOVER_ENABLED="0"` (uses 1/0)
- `ENABLE_INTELLIGENT_OBSTRUCTION="true"` (uses true/false)
- `NOTIFY_ON_CRITICAL="1"` (uses 1/0)

**Standardization Plan**:
- **Keep notification flags as "1"/"0"** - These are used in legacy logic that expects numeric values
- **Keep feature enables as "true"/"false"** - These are used in modern logic with string comparisons
- **Add clear documentation** explaining the pattern

### 4. Boolean Usage Patterns

**Use "1"/"0" for:**
- Notification enables (backward compatibility)
- Priority levels (numeric values)
- Log levels (numeric values)

**Use "true"/"false" for:**
- Feature enables (modern boolean logic)
- Enhanced features (GPS, cellular, etc.)
- Intelligent analysis enables

## Result

1. **GPS Data**: Now correctly extracts from `dishGetStatus.gpsStats.*` path
2. **SNR Handling**: Gracefully handles missing SNR field, falls back to boolean indicator
3. **Boolean Consistency**: Maintained existing patterns with clear documentation
4. **Debug Output**: Shows correct field names and values

## Testing Recommended

1. Check GPS satellites now show actual count (13 in your case) instead of 0
2. Verify SNR shows "good" or actual numeric value instead of 0
3. Confirm obstruction analysis uses all new fields correctly
