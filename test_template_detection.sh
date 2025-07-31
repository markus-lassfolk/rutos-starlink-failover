#!/bin/sh

# Quick test of template detection logic

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION
echo "=== Template Detection Test ==="

config_file="./test_config.sh"
config_dir="$(dirname "$config_file")"

# Find templates
basic_template=""
advanced_template=""

if [ -f "$config_dir/config/config.template.sh" ]; then
    basic_template="$config_dir/config/config.template.sh"
fi

if [ -f "$config_dir/config/config.advanced.template.sh" ]; then
    advanced_template="$config_dir/config/config.advanced.template.sh"
fi

echo "Config file: $config_file"
echo "Config dir: $config_dir"
echo "Basic template: $basic_template"
echo "Advanced template: $advanced_template"

# Count variables in config
config_var_count=$(grep -c "^export [A-Z_]*=" "$config_file" 2>/dev/null || echo 0)
config_var_count_alt=$(grep -c "^[A-Z_]*=" "$config_file" 2>/dev/null || echo 0)
if [ "$config_var_count_alt" -gt "$config_var_count" ]; then
    config_var_count="$config_var_count_alt"
fi
echo "Config variables: $config_var_count"

# Check for advanced template indicators
has_advanced_vars=0
if grep -q "^export ENABLE_AZURE_LOGGING=" "$config_file" 2>/dev/null ||
    grep -q "^export AZURE_WORKSPACE_ID=" "$config_file" 2>/dev/null ||
    grep -q "^export GPS_DEVICE=" "$config_file" 2>/dev/null ||
    grep -q "^export ADVANCED_MONITORING=" "$config_file" 2>/dev/null ||
    grep -q "^ENABLE_AZURE_LOGGING=" "$config_file" 2>/dev/null ||
    grep -q "^AZURE_WORKSPACE_ID=" "$config_file" 2>/dev/null ||
    grep -q "^GPS_DEVICE=" "$config_file" 2>/dev/null ||
    grep -q "^ADVANCED_MONITORING=" "$config_file" 2>/dev/null ||
    [ "$config_var_count" -gt 25 ]; then
    has_advanced_vars=1
fi

echo "Has advanced variables: $has_advanced_vars"

# Select appropriate template
if [ "$has_advanced_vars" -eq 1 ] && [ -n "$advanced_template" ]; then
    template_file="$advanced_template"
    echo "Selected: Advanced template"
elif [ -n "$basic_template" ]; then
    template_file="$basic_template"
    echo "Selected: Basic template"
elif [ -n "$advanced_template" ]; then
    template_file="$advanced_template"
    echo "Selected: Advanced template (fallback)"
else
    echo "Selected: None found"
    exit 1
fi

echo "Template file: $template_file"

# Check what variables are in each
echo ""
echo "=== Variable Comparison ==="
echo "Config variables:"
grep "^export [A-Z_]*=" "$config_file" | cut -d'=' -f1 | sed 's/^export //' | sort

echo ""
echo "Template variables:"
{
    grep -E '^[A-Z_]+=.*' "$template_file" | cut -d'=' -f1
    grep -E '^export [A-Z_]+=.*' "$template_file" | sed 's/^export //' | cut -d'=' -f1
} | sort -u

echo ""
echo "Variables in config but not in template:"
config_vars=$(grep "^export [A-Z_]*=" "$config_file" | cut -d'=' -f1 | sed 's/^export //' | sort)
template_vars=$({
    grep -E '^[A-Z_]+=.*' "$template_file" | cut -d'=' -f1
    grep -E '^export [A-Z_]+=.*' "$template_file" | sed 's/^export //' | cut -d'=' -f1
} | sort -u)

for var in $config_vars; do
    if ! echo "$template_vars" | grep -q "^$var$"; then
        echo "  $var"
    fi
    # Debug version display
    if [ "$DEBUG" = "1" ]; then
        printf "Script version: %s\n" "$SCRIPT_VERSION"
    fi

done
