#!/bin/sh

# === Network Analysis Setup Script ===
# Sets up Python environment and dependencies for network performance analysis

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

printf "%b\n" "${GREEN}Setting up Network Performance Analysis Environment${NC}"

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
echo "Example usage:"
echo "  python analyze-network-performance.py --storage-account mystorageaccount --days 7 --visualizations"
