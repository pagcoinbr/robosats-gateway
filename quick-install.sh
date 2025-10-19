#!/bin/bash

# RoboSats Gateway - Quick Installer
# Downloads and runs the full installation script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}RoboSats Gateway - Quick Installer${NC}"
echo "==================================="
echo ""

# Check if we're in a git repository
if [[ -d ".git" ]]; then
    echo -e "${GREEN}Running from existing repository...${NC}"
    if [[ -f "install-robosats-gateway.sh" ]]; then
        ./install-robosats-gateway.sh
    else
        echo "Error: install-robosats-gateway.sh not found in current directory"
        exit 1
    fi
else
    # Download the repository or script
    echo -e "${GREEN}Setting up RoboSats Gateway...${NC}"
    
    # Check if curl is available
    if command -v curl &> /dev/null; then
        # If this script exists online, we could download it
        echo "Please clone the repository and run the installer:"
        echo ""
        echo "git clone https://github.com/pagcoinbr/robosats-gateway.git"
        echo "cd robosats-gateway"
        echo "./install-robosats-gateway.sh"
    else
        echo "Error: curl not found. Please install curl or clone the repository manually."
        exit 1
    fi
fi