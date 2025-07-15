#!/bin/sh

# Quick test to fix and verify the IP validation function

# Improved IP validation function
validate_ip() {
    ip="$1"

    # Check basic format using case/esac pattern matching
    case "$ip" in
        *[!0-9.]*) return 1 ;;  # Contains non-digit, non-dot characters
        *..*) return 1 ;;       # Contains consecutive dots
        .*|*.) return 1 ;;      # Starts or ends with dot
    esac

    # Check each octet is <= 255
    IFS='.' 
    set -- "$ip"
    for octet in "$@"; do
        case "$octet" in
            ''|*[!0-9]*) return 1 ;;  # Empty or contains non-digits
        esac
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

validate_url() {
    url="$1"
    case "$url" in
        http://*|https://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

echo "Testing improved IP validation..."

# Test cases
test_ips="192.168.1.1
10.0.0.1
172.16.0.1
999.999.999.999
192.168.1
not.an.ip
0.0.0.0
255.255.255.255"

echo "$test_ips" | while read -r ip; do
    if validate_ip "$ip"; then
        echo "✓ Valid: $ip"
    else
        echo "✗ Invalid: $ip"
    fi
done

echo
echo "Testing URL validation..."

test_urls="https://example.com http://test.com ftp://test.com not-a-url https://subdomain.domain.com/path?query=value"

for url in $test_urls; do
    if validate_url "$url"; then
        echo "✓ Valid URL: $url"
    else
        echo "✗ Invalid URL: $url"
    fi
done
