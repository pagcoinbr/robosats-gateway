# RoboSats Gateway - Automated Installation

This repository contains scripts to automatically install and configure a RoboSats client gateway, giving you a self-hosted entrance to the RoboSats federation network for private Bitcoin trading.

## What You Get

🔒 **Private Bitcoin Trading** - Connect to RoboSats federation through your own gateway  
🌐 **Tor Privacy** - All coordinator connections routed through Tor  
🏠 **Self-Hosted** - Complete control over your trading gateway  
⚡ **No Lightning Node Required** - Uses existing coordinators' infrastructure  
🐳 **Docker-Based** - Easy deployment and management  
🔧 **Management Scripts** - Simple commands for all operations

## Quick Installation

### Option 1: One-Command Install (if you have this repo)

```bash
./install-robosats-gateway.sh
```

### Option 2: Manual Clone and Install

```bash
git clone <this-repository>
cd robosats-web-host
./install-robosats-gateway.sh
```

### Option 3: Fresh System Install

```bash
# Install Docker (if not already installed)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Clone and install
git clone <this-repository>
cd robosats-web-host
./install-robosats-gateway.sh
```

## What the Script Does

The automated installer will:

1. ✅ **Check Requirements** - Verify Docker, Docker Compose, and Tor
2. ✅ **Install Dependencies** - Install Tor if not present
3. ✅ **Create Directory Structure** - Set up organized file structure
4. ✅ **Generate Configuration** - Create Docker Compose and Nginx configs
5. ✅ **Create Management Scripts** - Generate helper scripts for operations
6. ✅ **Start Services** - Launch RoboSats client and Nginx proxy
7. ✅ **Test Installation** - Verify everything is working
8. ✅ **Create Documentation** - Generate README and usage guides

## Post-Installation

After installation, you'll have a new `robosats-gateway` directory with:

```
robosats-gateway/
├── docker-compose.yml      # Service definitions
├── Dockerfile             # Nginx container config
├── nginx/conf/nginx.conf   # Proxy configuration
├── start.sh               # Start services
├── stop.sh                # Stop services  
├── status.sh              # Check status
├── logs.sh                # View logs
├── update.sh              # Update services
└── README.md              # Detailed documentation
```

## Access Your Gateway

- **Direct Access**: http://localhost:12596
- **Via Nginx Proxy**: http://localhost:80
- **Tailnet Access**: http://[your-tailnet-ip]:80

## Management Commands

```bash
cd robosats-gateway

# Start the gateway
./start.sh

# Check if everything is running
./status.sh

# View logs
./logs.sh

# Follow logs in real-time
./logs.sh -f

# Stop the gateway
./stop.sh

# Update to latest versions
./update.sh
```

## Architecture

```
User ←→ Nginx (Port 80) ←→ RoboSats Client (Port 12596) ←→ Tor ←→ Federation Coordinators
```

## System Requirements

- **OS**: Linux (Ubuntu/Debian recommended)
- **Docker**: Latest version
- **Docker Compose**: Latest version  
- **Tor**: Installed and running
- **Ports**: 80, 12596 (and 9050 for Tor)
- **Network**: Internet access for Docker images and Tor

## Troubleshooting

### Installation Fails

```bash
# Check Docker installation
docker --version
docker-compose --version

# Check user permissions
groups $USER | grep docker

# If not in docker group:
sudo usermod -aG docker $USER
newgrp docker
```

### Services Won't Start

```bash
# Check what's using the ports
sudo netstat -tlnp | grep -E ":(80|12596)"

# Check Tor status
sudo systemctl status tor

# Restart if needed
sudo systemctl restart tor
```

### Connection Issues

```bash
# Check all services are running
cd robosats-gateway
./status.sh

# Check detailed logs
./logs.sh

# Test connectivity
curl http://localhost:12596
curl http://localhost:80
```

## Security Notes

- All coordinator traffic is routed through Tor for privacy
- No personal Lightning node required - uses federation coordinators  
- Keep your installation directory secure with appropriate permissions
- Consider setting up SSL certificates for HTTPS access
- Regular updates recommended for security patches

## Uninstallation

```bash
cd robosats-gateway
./stop.sh
cd ..
rm -rf robosats-gateway
```

## Support Resources

- **RoboSats Learn**: https://learn.robosats.org
- **GitHub**: https://github.com/RoboSats/robosats  
- **Telegram**: https://t.me/robosats
- **Matrix**: #robosats:matrix.org

## Advanced Configuration

### Custom Nginx Configuration

Edit `nginx/conf/nginx.conf` and restart:
```bash
./stop.sh
./start.sh
```

### SSL/HTTPS Setup

The installer includes certbot for SSL certificates. To enable HTTPS:

1. Get your domain/IP ready
2. Update nginx config with your domain
3. Run certbot to get certificates
4. Update nginx config to use SSL

### Environment Variables

You can customize the RoboSats client by editing the `docker-compose.yml` environment section.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this automated installer.