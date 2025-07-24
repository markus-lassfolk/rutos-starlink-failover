#!/bin/sh

# === Network Analysis Setup Script ===
# Sets up Python environment and dependencies for network performance analysis

set -e

# Colors for output
# Check if terminal supports colors
# Color definitions for consistent output (compatible with busybox)
# shellcheck disable=SC2034  # Color variables may not all be used in every script

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Fallback to no colors if terminal doesn't support them
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used
    # shellcheck disable=SC2034  # Color variables may not all be used
    RED=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    GREEN=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    YELLOW=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    BLUE=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    CYAN=""
    # shellcheck disable=SC2034  # Color variables may not all be used
    NC=""
fi

printf "%sSetting up Network Performance Analysis Environment%s\n" "$GREEN" "$NC"

# Check if Python 3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required but not installed. Please install Python 3.8 or later."
    exit 1
fi

echo "Python version: $(python3 --version)"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    printf "%b\n" "${YELLOW}Creating Python virtual environment...${NC}"
    python3 -m venv venv
fi

# Activate virtual environment
printf "%b\n" "${YELLOW}Activating virtual environment...${NC}"
# shellcheck disable=SC1091  # Virtual environment path is created dynamically
. venv/bin/activate

# Upgrade pip
printf "%b\n" "${YELLOW}Upgrading pip...${NC}"
pip install --upgrade pip

# Install requirements
printf "%b\n" "${YELLOW}Installing Python packages...${NC}"
pip install -r requirements.txt

printf "%b\n" "${GREEN}Setup complete!${NC}"
echo ""
echo "To use the analysis tool:"
echo "1. Activate the virtual environment: source venv/bin/activate"
echo "2. Run the analysis: python analyze-network-performance.py --storage-account YOUR_ACCOUNT --days 30 --visualizations"
echo ""
echo "setup-analysis-environment.sh v$SCRIPT_VERSION"
echo ""
echo "Example usage:"
echo "  python analyze-network-performance.py --storage-account mystorageaccount --days 7 --visualizations"
