#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# Simple logging for standalone analysis
log_info() { printf "[INFO] %s\n" "$1"; }
log_step() { printf "[STEP] %s\n" "$1"; }
log_warning() { printf "[WARN] %s\n" "$1"; }
log_error() { printf "[ERROR] %s\n" "$1"; }
log_success() { printf "[SUCCESS] %s\n" "$1"; }

CONFIG_FILE="config/config.unified.template.sh"

log_info "=== Fixing Circular Variable References ==="

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

log_step "1. Identifying circular variable references"

# Find variables that reference themselves with fallback syntax
CIRCULAR_VARS=$(grep -n 'export [A-Z_]*="\${[A-Z_]*:-[^}]*}"' "$CONFIG_FILE" | while read line; do
    var_name=$(echo "$line" | sed 's/.*export \([A-Z_]*\)=.*/\1/')
    reference=$(echo "$line" | sed 's/.*\${\([A-Z_]*\):.*/\1/')
    if [ "$var_name" = "$reference" ]; then
        echo "$var_name"
    fi
done)

if [ -n "$CIRCULAR_VARS" ]; then
    log_warning "Found circular variable references:"
    for var in $CIRCULAR_VARS; do
        line=$(grep -n "export $var=" "$CONFIG_FILE" | head -1 | cut -d: -f1)
        current_def=$(grep "export $var=" "$CONFIG_FILE" | head -1)
        printf "  Line %s: %s\n" "$line" "$current_def"
    done
else
    log_success "No circular variable references found"
    exit 0
fi

log_step "2. Recommendations for fixing circular references"

log_info "The following variables have circular references and should be set to explicit values:"
log_info ""

for var in $CIRCULAR_VARS; do
    current_line=$(grep "export $var=" "$CONFIG_FILE" | head -1)
    fallback_value=$(echo "$current_line" | sed 's/.*:-\([^}]*\)}.*/\1/')

    log_info "Variable: $var"
    log_info "  Current: $current_line"
    log_info "  Should be: export $var=\"$fallback_value\""
    log_info ""
done

log_info "To fix these issues, you should:"
log_info "1. Change 'export VAR=\"\${VAR:-default}\"' to 'export VAR=\"default\"'"
log_info "2. This makes the configuration explicit and clear"
log_info "3. Users can still override by modifying the config file directly"
log_info ""
log_info "Example:"
log_info "  WRONG: export ENABLE_GPS_TRACKING=\"\${ENABLE_GPS_TRACKING:-false}\""
log_info "  RIGHT: export ENABLE_GPS_TRACKING=\"false\""

log_success "Analysis complete"
