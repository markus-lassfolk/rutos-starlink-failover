#!/bin/sh

# Test script to verify extract_variable function works correctly

# Function to extract variable value from config file
# PowerShell-style approach: cleaner, more reliable
extract_variable() {
    file="$1"
    var_name="$2"

    if [ -f "$file" ]; then
        # Find the line with the variable
        line=$(grep "^[[:space:]]*export[[:space:]]*${var_name}=" "$file" | head -n 1)
        
        if [ -n "$line" ]; then
            # Remove the "export VAR_NAME=" part
            value=$(echo "$line" | sed "s/^[[:space:]]*export[[:space:]]*${var_name}=//")
            
            # Remove leading/trailing quotes
            value=$(echo "$value" | sed 's/^[\"'\'']//' | sed 's/[\"'\''][[:space:]]*#.*$//' | sed 's/[\"'\''][[:space:]]*$//')
            
            # Handle case where there's no quote but there's a comment
            value=$(echo "$value" | sed 's/[[:space:]]*#.*$//')
            
            # Clean up trailing whitespace
            value=$(echo "$value" | sed 's/[[:space:]]*$//')
            
            echo "$value"
        fi
    fi
}

# Create a test config file
cat > test_config.sh << 'EOF'
export CHECK_INTERVAL="30"
export FAILOVER_THRESHOLD="3"  
export ENABLE_PUSHOVER="true" # Enable Pushover notifications
export PUSHOVER_USER_TOKEN="your_user_token_here"
export PUSHOVER_APP_TOKEN="your_app_token_here" # App token
export LOG_LEVEL='debug'
export SOME_VAR=value_without_quotes
export QUOTED_WITH_COMMENT="value here" # This is a comment
EOF

echo "Testing extract_variable function:"
echo ""

# Test cases
test_vars="CHECK_INTERVAL FAILOVER_THRESHOLD ENABLE_PUSHOVER PUSHOVER_USER_TOKEN PUSHOVER_APP_TOKEN LOG_LEVEL SOME_VAR QUOTED_WITH_COMMENT"

for var in $test_vars; do
    result=$(extract_variable "test_config.sh" "$var")
    printf "%-25s = '%s'\n" "$var" "$result"
done

# Clean up
rm -f test_config.sh
