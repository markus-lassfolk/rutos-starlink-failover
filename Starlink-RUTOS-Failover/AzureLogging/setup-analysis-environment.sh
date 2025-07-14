#!/bin/bash

# === Network Analysis Setup Script ===
# Sets up Python environment and dependencies for network performance analysis

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Network Performance Analysis Environment${NC}"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is required but not installed. Please install Python 3.8 or later."
    exit 1
fi

echo "Python version: $(python3 --version)"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    python3 -m venv venv
fi

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source venv/bin/activate

# Upgrade pip
echo -e "${YELLOW}Upgrading pip...${NC}"
pip install --upgrade pip

# Install requirements
echo -e "${YELLOW}Installing Python packages...${NC}"
pip install -r requirements.txt

echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "To use the analysis tool:"
echo "1. Activate the virtual environment: source venv/bin/activate"
echo "2. Run the analysis: python analyze-network-performance.py --storage-account YOUR_ACCOUNT --days 30 --visualizations"
echo ""
echo "Example usage:"
echo "  python analyze-network-performance.py --storage-account mystorageaccount --days 7 --visualizations"
