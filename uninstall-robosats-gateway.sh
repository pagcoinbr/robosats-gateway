#!/bin/bash

# RoboSats Gateway Uninstaller
# Removes the RoboSats Gateway installation completely

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
INSTALL_DIR="robosats-gateway"
FORCE_REMOVE=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_REMOVE=true
                shift
                ;;
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    echo "RoboSats Gateway Uninstaller"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force      Skip confirmation prompts"
    echo "  --dir DIR    Uninstall from custom directory (default: robosats-gateway)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Normal uninstallation with prompts"
    echo "  $0 --force           # Force uninstall without prompts"
    echo "  $0 --dir my-gateway  # Uninstall from custom directory"
}

# Confirm uninstallation
confirm_removal() {
    if [[ "$FORCE_REMOVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "This will completely remove your RoboSats Gateway installation:"
    echo ""
    echo "  • Stop all running containers"
    echo "  • Remove Docker containers and images"
    echo "  • Delete the $INSTALL_DIR directory"
    echo "  • Remove all configuration and data"
    echo ""
    print_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " response
    
    case $response in
        [Yy][Ee][Ss]|[Yy])
            return 0
            ;;
        *)
            print_status "Uninstallation cancelled."
            exit 0
            ;;
    esac
}

# Stop and remove containers
stop_containers() {
    print_status "Stopping RoboSats Gateway containers..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR"
        
        # Stop containers using docker-compose if available
        if [[ -f "docker-compose.yml" ]]; then
            docker-compose down 2>/dev/null || true
        fi
        
        cd ..
    fi
    
    # Stop individual containers
    docker stop robosats-client 2>/dev/null || true
    docker stop robosats-gateway_nginx_1 2>/dev/null || true
    docker stop robosats-gateway_certbot_1 2>/dev/null || true
    
    print_success "Containers stopped"
}

# Remove containers and images
remove_containers() {
    print_status "Removing RoboSats Gateway containers and images..."
    
    # Remove containers
    docker rm robosats-client 2>/dev/null || true
    docker rm robosats-gateway_nginx_1 2>/dev/null || true
    docker rm robosats-gateway_certbot_1 2>/dev/null || true
    
    # Remove images
    docker rmi robosats-gateway_nginx 2>/dev/null || true
    docker rmi recksato/robosats-client:v0.8.2-alpha 2>/dev/null || true
    docker rmi certbot/certbot:latest 2>/dev/null || true
    docker rmi nginx:stable-alpine 2>/dev/null || true
    
    # Remove unused volumes
    docker volume prune -f 2>/dev/null || true
    
    print_success "Containers and images removed"
}

# Remove installation directory
remove_directory() {
    print_status "Removing installation directory: $INSTALL_DIR"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        print_success "Directory $INSTALL_DIR removed"
    else
        print_warning "Directory $INSTALL_DIR not found"
    fi
}

# Clean up Docker networks
cleanup_networks() {
    print_status "Cleaning up Docker networks..."
    
    # Remove the default network if it exists
    docker network rm robosats-gateway_default 2>/dev/null || true
    
    # Prune unused networks
    docker network prune -f 2>/dev/null || true
    
    print_success "Networks cleaned up"
}

# Show final status
show_final_status() {
    echo ""
    echo "================================================"
    print_success "RoboSats Gateway Uninstallation Complete!"
    echo "================================================"
    echo ""
    echo "✅ All containers stopped and removed"
    echo "✅ Docker images cleaned up"
    echo "✅ Installation directory removed"
    echo "✅ Networks cleaned up"
    echo ""
    echo "Your system has been restored to its previous state."
    echo ""
    print_status "Note: System packages (Docker, Tor) were not removed."
    print_status "To reinstall, run the installation script again."
}

# Main uninstallation function
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    echo "================================================"
    echo "  RoboSats Gateway - Uninstaller"
    echo "================================================"
    
    confirm_removal
    stop_containers
    remove_containers
    remove_directory
    cleanup_networks
    show_final_status
}

# Run main function
main "$@"