# RoboSats Gateway - Automated Installation

🔒 **Self-hosted RoboSats client gateway for private Bitcoin trading**

A complete automated installation system for setting up your own RoboSats federation gateway. Connect to the RoboSats network through your own private, Tor-enabled gateway without needing to run a Lightning node.

## 🚀 Quick Start

```bash
# Clone and install
git clone https://github.com/pagcoin/robosats-gateway.git
cd robosats-gateway
./install-robosats-gateway.sh
```

**That's it!** Your RoboSats gateway will be running on `http://localhost:80`

## ✨ Features

- 🔒 **Privacy via Tor** - All coordinator connections through Tor
- 🌐 **Federation Access** - Connect to multiple RoboSats coordinators  
- 🏠 **Self-hosted** - Your own private entrance to RoboSats
- ⚡ **No Lightning Node Required** - Uses existing coordinators
- 🐳 **Docker-based** - Easy deployment and management
- 🛠️ **Management Scripts** - Simple commands for all operations
- 📚 **Complete Documentation** - Detailed guides and troubleshooting

## 🎯 What This Provides

Instead of using public RoboSats instances, you get:
- Your own private gateway to the RoboSats federation
- Enhanced privacy through your own Tor routing
- Full control over your trading interface
- No dependence on third-party hosted instances
- Direct connection to multiple coordinators

## 📋 Requirements

- Linux system (Ubuntu/Debian recommended)
- Docker and Docker Compose
- 2GB RAM minimum
- Internet connection
- Ports 80, 12596 available

## 🛠️ Installation Options

### Standard Installation
```bash
./install-robosats-gateway.sh
```

### Advanced Options
```bash
# Force reinstall (overwrites existing)
./install-robosats-gateway.sh --force

# Clean existing containers first
./install-robosats-gateway.sh --cleanup

# Install to custom directory
./install-robosats-gateway.sh --dir my-custom-gateway

# View all options
./install-robosats-gateway.sh --help
```

## 🎮 Management

After installation, manage your gateway:

```bash
cd robosats-gateway

./start.sh    # Start the gateway
./stop.sh     # Stop the gateway  
./status.sh   # Check status
./logs.sh     # View logs
./logs.sh -f  # Follow logs live
./update.sh   # Update to latest
```

## 🌐 Access Points

- **Direct Access**: `http://localhost:12596`
- **Nginx Proxy**: `http://localhost:80`
- **Network Access**: `http://[your-ip]:80`

## 🏗️ Architecture

```
User ←→ Nginx (Port 80) ←→ RoboSats Client (Port 12596) ←→ Tor ←→ Federation Coordinators
```

Your gateway acts as a private bridge to the RoboSats federation:
- **Nginx**: Reverse proxy for clean URLs and SSL termination
- **RoboSats Client**: Federation client connecting to multiple coordinators
- **Tor Integration**: All coordinator traffic routed through Tor for privacy
- **Docker Orchestration**: Containerized services for easy management

## 📁 Generated Structure

The installer creates a complete, self-contained gateway:

```
robosats-gateway/
├── docker-compose.yml         # Service orchestration
├── Dockerfile                # Nginx container
├── nginx/conf/nginx.conf      # Reverse proxy config
├── robosats-client-data/      # Persistent data
├── start.sh                  # Start services
├── stop.sh                   # Stop services
├── status.sh                 # Health checks
├── logs.sh                   # Log viewer
├── update.sh                 # Update services
└── README.md                 # Detailed documentation
```

## 🔧 Customization

### SSL/HTTPS Setup
The installation includes certbot for SSL certificates:

1. Update `nginx/conf/nginx.conf` with your domain
2. Run certbot to obtain certificates  
3. Enable HTTPS in nginx configuration

### Environment Variables
Customize the RoboSats client by editing environment variables in `docker-compose.yml`.

### Custom Coordinators
The client automatically discovers and connects to federation coordinators. No manual configuration needed.

## 🛟 Troubleshooting

### Services Won't Start
```bash
# Check requirements
docker --version
docker-compose --version

# Check port usage
sudo netstat -tlnp | grep -E ":(80|12596)"

# View detailed logs
cd robosats-gateway && ./logs.sh
```

### Tor Connection Issues
```bash
# Check Tor service
sudo systemctl status tor

# Restart Tor
sudo systemctl restart tor

# Check Tor ports
netstat -tlnp | grep 9050
```

### Container Issues
```bash
# Clean restart
cd robosats-gateway
./stop.sh
docker system prune -f
./start.sh
```

## 🗑️ Uninstallation

Complete removal with one command:
```bash
./uninstall-robosats-gateway.sh
```

Or force removal:
```bash
./uninstall-robosats-gateway.sh --force
```

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the installation process
5. Submit a pull request

## 📖 Documentation

- **[Installation Guide](INSTALL.md)** - Detailed setup instructions
- **[Scripts Overview](scripts-menu.sh)** - All available commands
- **[RoboSats Learn](https://learn.robosats.org)** - Official RoboSats documentation

## 🔐 Security

- All coordinator communications via Tor
- Self-hosted eliminates third-party dependencies  
- Regular security updates recommended
- Keep Docker and system packages updated

## 📞 Support

- **Issues**: [GitHub Issues](../../issues)
- **RoboSats Community**: [Telegram](https://t.me/robosats)
- **Documentation**: [learn.robosats.org](https://learn.robosats.org)

## 📄 License

This project is licensed under the same terms as RoboSats - check the [LICENSE](LICENSE) file for details.

## ⚡ Quick Commands Reference

```bash
# Installation
git clone https://github.com/pagcoin/robosats-gateway.git
cd robosats-gateway
./install-robosats-gateway.sh

# Management  
cd robosats-gateway
./start.sh && ./status.sh

# Monitoring
./logs.sh -f

# Updates
./update.sh

# Removal
./uninstall-robosats-gateway.sh
```

---

**Ready to start private Bitcoin trading with your own RoboSats gateway? Clone and run the installer now!**
