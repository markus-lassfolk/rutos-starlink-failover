# Network Analysis Setup Script for Windows
# Sets up Python environment and dependencies for network performance analysis

Write-Host "Setting up Network Performance Analysis Environment" -ForegroundColor Green

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python version: $pythonVersion"
} catch {
    Write-Host "Python is required but not installed. Please install Python 3.8 or later from python.org" -ForegroundColor Red
    exit 1
}

# Create virtual environment if it doesn't exist
if (!(Test-Path "venv")) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
    python -m venv venv
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& "venv\Scripts\Activate.ps1"

# Upgrade pip
Write-Host "Upgrading pip..." -ForegroundColor Yellow
python -m pip install --upgrade pip

# Install requirements
Write-Host "Installing Python packages..." -ForegroundColor Yellow
pip install -r requirements.txt

Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To use the analysis tool:"
Write-Host "1. Activate the virtual environment: venv\Scripts\Activate.ps1"
Write-Host "2. Run the analysis: python analyze-network-performance.py --storage-account YOUR_ACCOUNT --days 30 --visualizations"
Write-Host ""
Write-Host "Example usage:"
Write-Host "  python analyze-network-performance.py --storage-account mystorageaccount --days 7 --visualizations"
