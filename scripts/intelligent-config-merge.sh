#!/bin/sh
# ==============================================================================
# Unified Template Config Merge Logic for install-rutos.sh
# This implements intelligent merging for the unified configuration template
# shellcheck disable=SC2001  # Complex sed patterns needed for config variable extraction
# ==============================================================================

# Function to perform intelligent config merge using unified template approach

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Use version for logging
echo "intelligent-config-merge.sh v$SCRIPT_VERSION (unified template support) started" >/dev/null 2>&1 || true
intelligent_config_merge() {
    template_file="$1"
    current_config="$2"
    output_config="$3"

    config_debug "=== INTELLIGENT CONFIG MERGE START ==="
    config_debug "Template: $template_file"
    config_debug "Current config: $current_config"
    config_debug "Output: $output_config"

    # Step 1: Create temporary working files
    temp_template_vars="/tmp/template_vars.$$"
    temp_current_vars="/tmp/current_vars.$$"
    temp_merged_config="/tmp/merged_config.$$"
    temp_extra_vars="/tmp/extra_vars.$$"

    config_debug "=== STEP 1: EXTRACT VARIABLES FROM TEMPLATE ==="
    # Extract all variable assignments from template (both export and standard)
    grep -E "^(export )?[A-Za-z_][A-Za-z0-9_]*=" "$template_file" 2>/dev/null >"$temp_template_vars" || touch "$temp_template_vars"
    template_count=$(wc -l <"$temp_template_vars" 2>/dev/null || echo 0)
    config_debug "Found $template_count variables in template"

    if [ "${CONFIG_DEBUG:-0}" = "1" ] && [ "$template_count" -gt 0 ]; then
        config_debug "Template variables:"
        head -10 "$temp_template_vars" | while IFS= read -r line; do
            config_debug "  $line"
        done
        if [ "$template_count" -gt 10 ]; then
            config_debug "  ... and $((template_count - 10)) more"
        fi
    fi

    config_debug "=== STEP 2: EXTRACT VARIABLES FROM CURRENT CONFIG ==="
    # Extract all variable assignments from current config
    if [ -f "$current_config" ]; then
        grep -E "^(export )?[A-Za-z_][A-Za-z0-9_]*=" "$current_config" 2>/dev/null >"$temp_current_vars" || touch "$temp_current_vars"
        current_count=$(wc -l <"$temp_current_vars" 2>/dev/null || echo 0)
        config_debug "Found $current_count variables in current config"

        if [ "${CONFIG_DEBUG:-0}" = "1" ] && [ "$current_count" -gt 0 ]; then
            config_debug "Current config variables (first 10):"
            head -10 "$temp_current_vars" | while IFS= read -r line; do
                case "$line" in
                    *TOKEN* | *PASSWORD* | *USER*)
                        config_debug "  ${line%=*}=***"
                        ;;
                    *)
                        config_debug "  $line"
                        ;;
                esac
            done
            if [ "$current_count" -gt 10 ]; then
                config_debug "  ... and $((current_count - 10)) more"
            fi
        fi
    else
        touch "$temp_current_vars"
        current_count=0
        config_debug "Current config file not found, treating as new installation"
    fi

    config_debug "=== STEP 3: START WITH TEMPLATE AS BASE ==="
    # Start with the complete template (preserves structure, comments, formatting)
    cp "$template_file" "$temp_merged_config"
    config_debug "Template copied as base for merged config"

    config_debug "=== STEP 4: PROCESS TEMPLATE VARIABLES ==="
    # Process each variable in the template
    preserved_count=0
    kept_default_count=0

    while IFS= read -r template_line; do
        if [ -z "$template_line" ]; then
            continue
        fi

        # Extract variable name from template line
        var_name=""
        if echo "$template_line" | grep -q "^export "; then
            var_name=$(echo "$template_line" | sed 's/^export \([^=]*\)=.*/\1/')
        else
            var_name=$(echo "$template_line" | sed 's/^\([^=]*\)=.*/\1/')
        fi

        if [ -n "$var_name" ]; then
            config_debug "--- Processing template variable: $var_name ---"

            # Look for this variable in current config (both formats)
            current_value=""
            if grep -q "^export ${var_name}=" "$current_config" 2>/dev/null; then
                current_line=$(grep "^export ${var_name}=" "$current_config" | head -1)
                current_value=$(echo "$current_line" | sed 's/^export [^=]*=//; s/^"//; s/"$//')
                config_debug "Found current value (export): $var_name = $current_value"
            elif grep -q "^${var_name}=" "$current_config" 2>/dev/null; then
                current_line=$(grep "^${var_name}=" "$current_config" | head -1)
                current_value=$(echo "$current_line" | sed 's/^[^=]*=//; s/^"//; s/"$//')
                config_debug "Found current value (standard): $var_name = $current_value"
            else
                config_debug "Variable not found in current config: $var_name"
            fi

            # Decide whether to use current value or keep template default
            if [ -n "$current_value" ] && ! echo "$current_value" | grep -qE "(YOUR_|CHANGE_ME|PLACEHOLDER|EXAMPLE|TEST_)" 2>/dev/null; then
                # Use current value (preserve user setting)
                config_debug "Preserving user value: $var_name = $current_value"

                # Replace in merged config (preserve template format)
                if echo "$template_line" | grep -q "^export "; then
                    replacement="export ${var_name}=\"${current_value}\""
                else
                    replacement="${var_name}=\"${current_value}\""
                fi

                # Replace the line in merged config
                if sed -i "s|^export ${var_name}=.*|$replacement|" "$temp_merged_config" 2>/dev/null ||
                    sed -i "s|^${var_name}=.*|$replacement|" "$temp_merged_config" 2>/dev/null; then
                    preserved_count=$((preserved_count + 1))
                    config_debug "✓ Successfully preserved: $var_name"
                else
                    config_debug "✗ Failed to replace: $var_name"
                fi
            else
                # Keep template default
                kept_default_count=$((kept_default_count + 1))
                config_debug "Keeping template default: $var_name"
            fi
        fi
    done <"$temp_template_vars"

    config_debug "=== STEP 5: FIND EXTRA USER SETTINGS ==="
    # Find settings in current config that are NOT in template
    true >"$temp_extra_vars" # Clear file
    extra_count=0

    if [ -f "$current_config" ] && [ "$current_count" -gt 0 ]; then
        while IFS= read -r current_line; do
            if [ -z "$current_line" ]; then
                continue
            fi

            # Extract variable name from current config line
            var_name=""
            if echo "$current_line" | grep -q "^export "; then
                var_name=$(echo "$current_line" | sed 's/^export \([^=]*\)=.*/\1/')
            else
                var_name=$(echo "$current_line" | sed 's/^\([^=]*\)=.*/\1/')
            fi

            if [ -n "$var_name" ]; then
                # Check if this variable exists in template
                if ! grep -q "^export ${var_name}=" "$temp_template_vars" 2>/dev/null &&
                    ! grep -q "^${var_name}=" "$temp_template_vars" 2>/dev/null; then
                    # This is an extra setting not in template
                    config_debug "Found extra user setting: $var_name"
                    echo "$current_line" >>"$temp_extra_vars"
                    extra_count=$((extra_count + 1))
                fi
            fi
        done <"$temp_current_vars"
    fi

    config_debug "Found $extra_count extra user settings not in template"

    config_debug "=== STEP 6: ADD EXTRA SETTINGS TO MERGED CONFIG ==="
    if [ "$extra_count" -gt 0 ]; then
        config_debug "Adding extra user settings to merged config"

        # Add a section header for extra settings
        cat >>"$temp_merged_config" <<EOF

# ==============================================================================
# Additional User Settings (not in template)
# These settings were found in your existing config but are not part of the
# standard template. They are preserved here to maintain your customizations.
# ==============================================================================
EOF

        # Add each extra setting with some context
        while IFS= read -r extra_line; do
            if [ -n "$extra_line" ]; then
                # Extract variable name for comment
                var_name=""
                if echo "$extra_line" | grep -q "^export "; then
                    var_name=$(echo "$extra_line" | sed 's/^export \([^=]*\)=.*/\1/')
                else
                    var_name=$(echo "$extra_line" | sed 's/^\([^=]*\)=.*/\1/')
                fi

                {
                    echo "# Custom setting: $var_name (preserved from existing config)"
                    echo "$extra_line"
                    echo ""
                } >>"$temp_merged_config"

                config_debug "Added extra setting: $var_name"
            fi
        done <"$temp_extra_vars"
    fi

    config_debug "=== STEP 7: FINALIZE MERGE ==="
    # Copy merged config to final destination
    if cp "$temp_merged_config" "$output_config" 2>/dev/null; then
        config_debug "✓ Merged config successfully written to: $output_config"

        # Generate summary
        total_template_vars=$template_count
        total_preserved=$preserved_count
        total_defaults=$kept_default_count
        total_extra=$extra_count

        config_debug "=== MERGE SUMMARY ==="
        config_debug "Template variables: $total_template_vars"
        config_debug "User values preserved: $total_preserved"
        config_debug "Template defaults kept: $total_defaults"
        config_debug "Extra user settings: $total_extra"
        config_debug "Final config size: $(wc -c <"$output_config" 2>/dev/null || echo 'unknown') bytes"

        # Show notification settings specifically
        config_debug "=== NOTIFICATION SETTINGS VERIFICATION ==="
        for notify_setting in "NOTIFY_ON_CRITICAL" "NOTIFY_ON_HARD_FAIL" "NOTIFY_ON_RECOVERY" "NOTIFY_ON_SOFT_FAIL" "NOTIFY_ON_INFO"; do
            if grep -q "^export ${notify_setting}=" "$output_config" 2>/dev/null; then
                notify_value=$(grep "^export ${notify_setting}=" "$output_config" | head -1)
                config_debug "✓ $notify_value"
            elif grep -q "^${notify_setting}=" "$output_config" 2>/dev/null; then
                notify_value=$(grep "^${notify_setting}=" "$output_config" | head -1)
                config_debug "✓ $notify_value"
            else
                config_debug "✗ MISSING: $notify_setting"
            fi
        done

        cleanup_result=0
    else
        config_debug "✗ FAILED to write merged config to: $output_config"
        cleanup_result=1
    fi

    # Cleanup temporary files
    rm -f "$temp_template_vars" "$temp_current_vars" "$temp_merged_config" "$temp_extra_vars" 2>/dev/null

    if [ "$cleanup_result" = 0 ]; then
        config_debug "=== INTELLIGENT CONFIG MERGE COMPLETE ==="
        return 0
    else
        config_debug "=== INTELLIGENT CONFIG MERGE FAILED ==="
        return 1
    fi
}
