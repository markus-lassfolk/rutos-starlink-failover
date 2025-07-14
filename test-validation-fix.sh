#!/bin/bash

# Quick test to fix and verify the IP validation function

# Improved IP validation function
validate_ip() {
    local ip="$1"
    
    # Check basic format
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Check each octet is <= 255
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [[ $i -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

validate_url() {
    local url="$1"
    if [[ $url =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

echo "Testing improved IP validation..."

# Test cases
test_ips=("192.168.1.1" "10.0.0.1" "172.16.0.1" "999.999.999.999" "192.168.1" "not.an.ip" "0.0.0.0" "255.255.255.255")

for ip in "${test_ips[@]}"; do
    if validate_ip "$ip"; then
        echo "✓ Valid: $ip"
    else
        echo "✗ Invalid: $ip"
    fi
done

echo
echo "Testing URL validation..."

test_urls=("https://example.com" "http://test.com" "ftp://test.com" "not-a-url" "https://subdomain.domain.com/path?query=value")

for url in "${test_urls[@]}"; do
    if validate_url "$url"; then
        echo "✓ Valid URL: $url"
    else
        echo "✗ Invalid URL: $url"
    fi
done
