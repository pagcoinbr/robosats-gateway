#!/bin/bash

# RoboSats Gateway - Script Menu
# Shows all available management scripts

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}RoboSats Gateway - Script Collection${NC}"
echo "======================================"
echo ""

echo -e "${GREEN}📦 Installation Scripts:${NC}"
echo "  ./install-robosats-gateway.sh    - Main automated installer"
echo "  ./install-robosats-gateway.sh --help  - Show installer options"
echo "  ./quick-install.sh               - One-command installer"
echo ""

echo -e "${GREEN}🗑️  Removal Scripts:${NC}"
echo "  ./uninstall-robosats-gateway.sh  - Complete uninstaller"
echo "  ./uninstall-robosats-gateway.sh --help  - Show uninstaller options"
echo ""

echo -e "${GREEN}📚 Documentation:${NC}"
echo "  cat README.md                    - View main documentation"
echo "  cat INSTALL.md                   - View installation guide"
echo ""

echo -e "${GREEN}⚡ Quick Start:${NC}"
echo "  1. Run: ./install-robosats-gateway.sh"
echo "  2. Access: http://localhost:80"
echo "  3. Manage: cd robosats-gateway && ./status.sh"
echo ""

echo -e "${GREEN}🛠️  After Installation (in robosats-gateway/ directory):${NC}"
echo "  ./start.sh     - Start the gateway"
echo "  ./stop.sh      - Stop the gateway"
echo "  ./status.sh    - Check status"
echo "  ./logs.sh      - View logs"
echo "  ./update.sh    - Update services"
echo ""

echo -e "${YELLOW}💡 Need Help?${NC}"
echo "  • Read INSTALL.md for detailed instructions"
echo "  • Run scripts with --help for options"
echo "  • Check https://learn.robosats.org for RoboSats documentation"