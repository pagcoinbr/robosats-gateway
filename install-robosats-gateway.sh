#!/bin/bash

# RoboSats Client Gateway - Automated Installation Script
# This script sets up a self-hosted RoboSats client that connects to the federation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="robosats-gateway"
COMPOSE_PROJECT_NAME="robosats-gateway"
FORCE_INSTALL=false
CLEANUP_EXISTING=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --cleanup)
                CLEANUP_EXISTING=true
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
    echo "RoboSats Gateway Auto Installer"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force      Force installation even if directory exists"
    echo "  --cleanup    Remove existing Docker containers before installing"
    echo "  --dir DIR    Install to custom directory (default: robosats-gateway)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Normal installation"
    echo "  $0 --force           # Force reinstall"
    echo "  $0 --cleanup         # Clean existing containers first"
    echo "  $0 --dir my-gateway  # Install to custom directory"
}

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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        echo "Run: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if user is in docker group
    if ! groups $USER | grep -q '\bdocker\b'; then
        print_warning "User $USER is not in the docker group. You might need to use sudo for docker commands."
        print_warning "To fix this, run: sudo usermod -aG docker $USER && newgrp docker"
    fi
    
    # Check for port conflicts
    if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
        print_warning "Port 80 is already in use. The installation will continue, but you may need to stop the existing service."
        netstat -tlnp 2>/dev/null | grep ":80 "
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":12596 "; then
        print_warning "Port 12596 is already in use. The installation will continue, but you may need to stop the existing service."
        netstat -tlnp 2>/dev/null | grep ":12596 "
    fi
    
    # Check if Tor is running (we'll use system Tor)
    if systemctl is-active --quiet tor 2>/dev/null || pgrep -f "tor" > /dev/null; then
        print_success "Tor service is running - will use system Tor"
    else
        print_warning "Tor is not running. Installing and starting Tor service..."
        sudo apt update
        sudo apt install -y tor
        sudo systemctl enable tor
        sudo systemctl start tor
        print_success "Tor service installed and started"
    fi
    
    print_success "All requirements satisfied"
}

# Create installation directory
create_directory() {
    print_status "Creating installation directory: $INSTALL_DIR"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            print_warning "Force mode: Removing existing directory $INSTALL_DIR"
            rm -rf "$INSTALL_DIR"
        else
            print_warning "Directory $INSTALL_DIR already exists. Backing up existing installation..."
            mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Create subdirectories
    mkdir -p nginx/conf
    mkdir -p robosats-client-data
    
    print_success "Directory structure created"
}

# Create Docker Compose file
create_docker_compose() {
    print_status "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  nginx:
    build:
      context: .
      dockerfile: Dockerfile
    restart: always
    volumes:
      - ./nginx/conf/:/etc/nginx/conf.d/:ro
      - /var/www/certbot:/var/www/certbot/:ro
      - /etc/letsencrypt/:/etc/nginx/ssl/:ro
    network_mode: host
    depends_on:
      - robosats-client

  # RoboSats Client App (connects to federation coordinators)
  robosats-client:
    image: recksato/robosats-client:v0.8.2-alpha
    container_name: robosats-client
    restart: always
    environment:
      - TOR_PROXY_IP=127.0.0.1
      - TOR_PROXY_PORT=9050
    volumes:
      - ./robosats-client-data:/usr/src/robosats/data
    network_mode: host

  certbot:
    image: certbot/certbot:latest
    restart: always
    volumes:
      - /var/www/certbot/:/var/www/certbot/:rw
      - /etc/letsencrypt/:/etc/letsencrypt/:rw
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
EOF

    print_success "Docker Compose file created"
}

# Create Nginx Dockerfile
create_nginx_dockerfile() {
    print_status "Creating Nginx Dockerfile..."
    
    cat > Dockerfile << 'EOF'
FROM nginx:stable-alpine
EXPOSE 80
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]
EOF

    print_success "Nginx Dockerfile created"
}

# Create Nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    cat > nginx/conf/nginx.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;

    location /.well-known/acme-challenge {
        root /var/www/certbot;
    }
    
    location / {
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   Host $host;
        proxy_pass         http://127.0.0.1:12596;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
EOF

    print_success "Nginx configuration created"
}

# Create management scripts
create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Start script
    cat > start.sh << 'EOF'
#!/bin/bash
echo "Starting RoboSats Gateway..."
docker-compose up -d
echo "RoboSats Gateway started!"
echo "Access URLs:"
echo "  - Direct: http://localhost:12596"
echo "  - Via Nginx: http://localhost:80"
echo ""
echo "To check status: ./status.sh"
echo "To view logs: ./logs.sh"
echo "To stop: ./stop.sh"
EOF

    # Stop script
    cat > stop.sh << 'EOF'
#!/bin/bash
echo "Stopping RoboSats Gateway..."
docker-compose down
echo "RoboSats Gateway stopped!"
EOF

    # Status script
    cat > status.sh << 'EOF'
#!/bin/bash
echo "RoboSats Gateway Status:"
echo "========================"
docker-compose ps
echo ""
echo "Port Status:"
echo "============"
netstat -tlnp 2>/dev/null | grep -E ":(80|12596|9050)" || echo "No relevant ports found"
EOF

    # Logs script
    cat > logs.sh << 'EOF'
#!/bin/bash
if [ "$1" = "-f" ]; then
    echo "Following RoboSats Gateway logs (Ctrl+C to exit)..."
    docker-compose logs -f
else
    echo "RoboSats Gateway Logs:"
    echo "======================"
    docker-compose logs --tail=50
    echo ""
    echo "To follow logs in real-time: ./logs.sh -f"
fi
EOF

    # Update script
    cat > update.sh << 'EOF'
#!/bin/bash
echo "Updating RoboSats Gateway..."
docker-compose pull
docker-compose up -d
echo "RoboSats Gateway updated!"
EOF

    # Make scripts executable
    chmod +x start.sh stop.sh status.sh logs.sh update.sh
    
    print_success "Management scripts created"
}

# Create README
create_readme() {
    print_status "Creating README documentation..."
    
    cat > README.md << 'EOF'
# RoboSats Client Gateway

A self-hosted RoboSats client that connects to the RoboSats federation network, allowing you to trade Bitcoin privately through your own gateway.

## What This Provides

- 🔒 **Privacy via Tor** - All coordinator connections go through Tor
- 🌐 **Federation Access** - Connect to multiple RoboSats coordinators  
- 🏠 **Self-hosted** - Your own private entrance to RoboSats
- ⚡ **No Lightning Node Required** - Uses existing coordinators' infrastructure
- 🔧 **Easy Management** - Simple scripts for all operations

## Quick Start

```bash
# Start the gateway
./start.sh

# Check status
./status.sh

# View logs
./logs.sh

# Stop the gateway
./stop.sh
```

## Access URLs

- **Direct Access**: http://localhost:12596
- **Via Nginx**: http://localhost:80
- **Tailnet Access**: http://[your-tailnet-ip]:80

## Management Commands

- `./start.sh` - Start all services
- `./stop.sh` - Stop all services  
- `./status.sh` - Check service status
- `./logs.sh` - View recent logs
- `./logs.sh -f` - Follow logs in real-time
- `./update.sh` - Update to latest versions

## Architecture

```
Internet ←→ Nginx (Port 80) ←→ RoboSats Client (Port 12596) ←→ Tor ←→ Federation Coordinators
```

## Troubleshooting

### Services Won't Start
```bash
# Check Docker status
docker --version
docker-compose --version

# Check if ports are in use
netstat -tlnp | grep -E ":(80|12596)"
```

### Tor Connection Issues
```bash
# Check Tor service
sudo systemctl status tor

# Restart Tor if needed
sudo systemctl restart tor
```

### View Detailed Logs
```bash
# All services
./logs.sh

# Specific service
docker-compose logs robosats-client
docker-compose logs nginx
```

## Security Notes

- This setup routes all coordinator traffic through Tor for privacy
- No personal Lightning node required - uses federation coordinators
- Keep your installation directory secure
- Consider setting up SSL certificates for HTTPS access

## Support

- RoboSats Documentation: https://learn.robosats.org
- RoboSats GitHub: https://github.com/RoboSats/robosats
- Community Support: https://t.me/robosats
EOF

    print_success "README documentation created"
}

# Start services
start_services() {
    print_status "Starting RoboSats Gateway services..."
    
    # Cleanup existing containers if requested
    if [[ "$CLEANUP_EXISTING" == "true" ]]; then
        print_status "Cleaning up existing containers..."
        docker stop robosats-client 2>/dev/null || true
        docker rm robosats-client 2>/dev/null || true
        docker stop robosats-gateway_nginx_1 2>/dev/null || true
        docker rm robosats-gateway_nginx_1 2>/dev/null || true
        docker stop robosats-gateway_certbot_1 2>/dev/null || true
        docker rm robosats-gateway_certbot_1 2>/dev/null || true
    fi
    
    # Check for existing containers with same names
    if docker ps -a --format "table {{.Names}}" | grep -q "robosats-client"; then
        print_warning "Found existing robosats-client container. Removing it..."
        docker stop robosats-client 2>/dev/null || true
        docker rm robosats-client 2>/dev/null || true
    fi
    
    # Pull latest images
    docker-compose pull
    
    # Start services
    docker-compose up -d
    
    # Wait for services to start
    sleep 10
    
    print_success "Services started"
}

# Test installation
test_installation() {
    print_status "Testing installation..."
    
    # Test RoboSats client direct access
    if curl -s --max-time 10 http://localhost:12596 > /dev/null; then
        print_success "RoboSats client is accessible on port 12596"
    else
        print_warning "RoboSats client test failed on port 12596"
    fi
    
    # Test Nginx proxy
    if curl -s --max-time 10 http://localhost:80 > /dev/null; then
        print_success "Nginx proxy is working on port 80"
    else
        print_warning "Nginx proxy test failed on port 80"
    fi
    
    # Check Tor
    if netstat -tlnp 2>/dev/null | grep -q ":9050"; then
        print_success "Tor proxy is running on port 9050"
    else
        print_warning "Tor proxy not detected on port 9050"
    fi
}

# Main installation function
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    echo "================================================"
    echo "  RoboSats Client Gateway - Auto Installer"
    echo "================================================"
    echo ""
    
    check_root
    check_requirements
    create_directory
    create_docker_compose
    create_nginx_dockerfile
    create_nginx_config
    create_management_scripts
    create_readme
    start_services
    test_installation
    
    echo ""
    echo "================================================"
    print_success "RoboSats Gateway Installation Complete!"
    echo "================================================"
    echo ""
    echo "🎉 Your RoboSats Gateway is now running!"
    echo ""
    echo "📍 Access URLs:"
    echo "   • Direct: http://localhost:12596"
    echo "   • Nginx:  http://localhost:80"
    echo ""
    echo "🛠️  Management:"
    echo "   • Start:  ./start.sh"
    echo "   • Stop:   ./stop.sh" 
    echo "   • Status: ./status.sh"
    echo "   • Logs:   ./logs.sh"
    echo ""
    echo "📚 Read README.md for detailed documentation"
    echo ""
    echo "🔒 Your gateway is now connected to the RoboSats federation"
    echo "   and ready for private Bitcoin trading!"
}

# Run main function
main "$@"