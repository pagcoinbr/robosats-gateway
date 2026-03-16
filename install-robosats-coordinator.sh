#!/bin/bash

# RoboSats Coordinator - Automated Installation Script
# This script sets up a full RoboSats coordinator node that hosts an order book,
# manages escrow via LND hold invoices, and serves traders over Tor + Clearnet.
#
# Requires: Docker, Docker Compose, Tor, Python3, external LND node
# Usage: sudo bash install-robosats-coordinator.sh [OPTIONS]

set -e  # Exit on any error

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Configuration ────────────────────────────────────────────────────────────
INSTALL_DIR="/home/pagcoin/robosats-coordinator"
NGINX_CONF_DIR="/home/pagcoin/robosats-web-host/nginx/conf"
ROBOSATS_IMAGE="recksato/robosats:v0.8.2-alpha"
COMPOSE_PROJECT_NAME="robosats-coordinator"
LND_GRPC_HOST="100.70.4.80:10009"
TLS_CERT_PATH="/home/pagcoin/staking-brln/tls.cert"
MACAROON_PATH="/home/pagcoin/staking-brln/macaroon.hex"
FORCE_INSTALL=false
SKIP_TOR=false
SKIP_SYSTEMD=false
SKIP_SUPERUSER=false

# Credentials (populated at runtime)
DJANGO_SECRET_KEY=""
POSTGRES_PASSWORD=""
LND_CERT_BASE64=""
LND_MACAROON_BASE64=""
ONION_ADDRESS=""

# ─── Docker Compose command detection ─────────────────────────────────────────
DOCKER_COMPOSE=""
detect_compose() {
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif docker compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    else
        print_error "Neither 'docker-compose' nor 'docker compose' plugin found."
        exit 1
    fi
}

# ─── CLI argument parsing ─────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --skip-tor)
                SKIP_TOR=true
                shift
                ;;
            --skip-systemd)
                SKIP_SYSTEMD=true
                shift
                ;;
            --skip-superuser)
                SKIP_SUPERUSER=true
                shift
                ;;
            --lnd-host)
                LND_GRPC_HOST="$2"
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

show_help() {
    echo "RoboSats Coordinator - Auto Installer"
    echo ""
    echo "Usage: sudo bash $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force            Force installation (overwrite existing without backup)"
    echo "  --skip-tor         Skip Tor hidden service setup"
    echo "  --skip-systemd     Skip systemd service creation"
    echo "  --skip-superuser   Skip Django superuser creation"
    echo "  --lnd-host HOST    LND gRPC endpoint (default: $LND_GRPC_HOST)"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo bash $0                         # Full installation"
    echo "  sudo bash $0 --force                 # Reinstall from scratch"
    echo "  sudo bash $0 --skip-tor --skip-systemd  # Minimal install"
}

# ─── Output helpers ───────────────────────────────────────────────────────────
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_phase() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  Phase $1: $2${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
}

# ─── Phase 1: Prerequisites ──────────────────────────────────────────────────
check_requirements() {
    print_phase "1" "Checking Prerequisites"

    # Must run as root (needs torrc, systemd access)
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)."
        print_error "Run: sudo bash $0"
        exit 1
    fi

    # Docker
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed."
        echo "  Install: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    print_success "Docker installed: $(docker --version | head -1)"

    # Docker Compose
    detect_compose
    print_success "Docker Compose available: $DOCKER_COMPOSE"

    # Python3
    if ! command -v python3 &>/dev/null; then
        print_error "Python3 is not installed."
        exit 1
    fi
    print_success "Python3 available"

    # Git
    if ! command -v git &>/dev/null; then
        print_warning "Git not installed (optional, needed for updates)"
    fi

    # Tor
    if ! systemctl is-active --quiet tor 2>/dev/null; then
        print_warning "Tor service is not running."
        if [[ "$SKIP_TOR" != "true" ]]; then
            print_status "Installing and starting Tor..."
            apt-get update -qq && apt-get install -y -qq tor
            systemctl enable tor
            systemctl start tor
            print_success "Tor installed and started"
        fi
    else
        print_success "Tor service is running"
    fi

    # LND connectivity
    local lnd_host="${LND_GRPC_HOST%%:*}"
    local lnd_port="${LND_GRPC_HOST##*:}"
    if timeout 5 bash -c "echo >/dev/tcp/$lnd_host/$lnd_port" 2>/dev/null; then
        print_success "LND reachable at $LND_GRPC_HOST"
    else
        print_error "Cannot reach LND at $LND_GRPC_HOST"
        print_error "Ensure the LND node is running and Tailscale is connected."
        exit 1
    fi

    # Credential files (existence only — never read/display)
    if [[ ! -f "$TLS_CERT_PATH" ]]; then
        print_error "TLS cert not found: $TLS_CERT_PATH"
        exit 1
    fi
    print_success "TLS cert exists: $TLS_CERT_PATH"

    if [[ ! -f "$MACAROON_PATH" ]]; then
        print_error "Macaroon not found: $MACAROON_PATH"
        exit 1
    fi
    print_success "Macaroon exists: $MACAROON_PATH"

    # Port checks
    for port in 8000 9000; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            print_warning "Port $port is already in use"
            ss -tlnp 2>/dev/null | grep ":${port} "
        fi
    done

    # Disk space (need > 5GB)
    local available_gb
    available_gb=$(df -BG --output=avail / | tail -1 | tr -d ' G')
    if [[ "$available_gb" -lt 5 ]]; then
        print_error "Insufficient disk space: ${available_gb}GB available (need 5GB+)"
        exit 1
    fi
    print_success "Disk space: ${available_gb}GB available"

    # RAM check
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [[ "$total_ram_mb" -lt 1024 ]]; then
        print_warning "Low RAM: ${total_ram_mb}MB (recommend 2GB+)"
    else
        print_success "RAM: ${total_ram_mb}MB"
    fi

    print_success "All prerequisites satisfied"
}

# ─── Phase 2: Create directory structure ──────────────────────────────────────
create_directory() {
    print_phase "2" "Creating Directory Structure"

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            print_warning "Force mode: removing existing $INSTALL_DIR"
            # Stop any running containers first
            if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
                cd "$INSTALL_DIR"
                $DOCKER_COMPOSE down 2>/dev/null || true
                cd /
            fi
            rm -rf "$INSTALL_DIR"
        else
            local backup="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            print_warning "Backing up existing directory to $backup"
            # Stop containers before backup
            if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
                cd "$INSTALL_DIR"
                $DOCKER_COMPOSE down 2>/dev/null || true
                cd /
            fi
            mv "$INSTALL_DIR" "$backup"
        fi
    fi

    mkdir -p "$INSTALL_DIR"/{data,static}
    print_success "Created $INSTALL_DIR with data/ and static/ subdirs"
}

# ─── Phase 3: Generate credentials ───────────────────────────────────────────
generate_credentials() {
    print_phase "3" "Generating Credentials"

    # Django SECRET_KEY (50 chars)
    DJANGO_SECRET_KEY=$(python3 -c "
import secrets, string
alphabet = string.ascii_letters + string.digits + '!@#\$%^&*(-_=+)'
print(''.join(secrets.choice(alphabet) for _ in range(50)))
")
    print_success "Django SECRET_KEY generated"

    # PostgreSQL password (32 chars, alphanumeric only for URL safety)
    POSTGRES_PASSWORD=$(python3 -c "
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(32)))
")
    print_success "PostgreSQL password generated"

    # LND TLS cert → base64
    LND_CERT_BASE64=$(base64 -w 0 < "$TLS_CERT_PATH")
    print_success "LND TLS cert encoded to base64"

    # LND macaroon → detect format → base64
    # macaroon.hex could be hex-encoded text or raw binary
    if file "$MACAROON_PATH" | grep -q "text"; then
        # Hex-encoded file: strip whitespace, decode hex, encode base64
        LND_MACAROON_BASE64=$(tr -d '[:space:]' < "$MACAROON_PATH" | xxd -r -p | base64 -w 0)
        print_success "LND macaroon: hex → binary → base64"
    else
        # Raw binary file: encode directly
        LND_MACAROON_BASE64=$(base64 -w 0 < "$MACAROON_PATH")
        print_success "LND macaroon: binary → base64"
    fi
}

# ─── Phase 4: Create environment file ────────────────────────────────────────
create_env_file() {
    print_phase "4" "Creating Environment File"

    cat > "$INSTALL_DIR/robosats.env" << ENVEOF
# ─── RoboSats Coordinator Environment ─────────────────────────────────────────
# Generated by install-robosats-coordinator.sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# WARNING: Contains secrets. Do not commit to version control.

# ─── Coordinator Identity ─────────────────────────────────────────────────────
COORDINATOR_ALIAS=PagCoin Coordinator
LOCAL_ALIAS=PagCoin
# HOST_NAME must be the .onion address for Django ALLOWED_HOSTS
HOST_NAME=localhost
HOST_NAME2=
ONION_LOCATION=
I2P_ALIAS=
I2P_LONG=

# ─── Django Settings ──────────────────────────────────────────────────────────
SECRET_KEY=${DJANGO_SECRET_KEY}
DEBUG=False
ALLOWED_HOSTS=*
CORS_ALLOWED_ORIGINS=*
ESCROW_USERNAME=admin

# ─── Database ─────────────────────────────────────────────────────────────────
POSTGRES_DB=robosats
POSTGRES_USER=robosats
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
DATABASE_URL=postgresql://robosats:${POSTGRES_PASSWORD}@postgres:5432/robosats

# ─── Redis ────────────────────────────────────────────────────────────────────
REDIS_URL=redis://redis:6379/0

# ─── Lightning Network (LND) ─────────────────────────────────────────────────
LNVENDOR=LND
LND_GRPC_HOST=${LND_GRPC_HOST}
LND_CERT_BASE64=${LND_CERT_BASE64}
LND_MACAROON_BASE64=${LND_MACAROON_BASE64}

# ─── Bitcoin Core ─────────────────────────────────────────────────────────────
BITCOIND_RPCUSER=bitcoin
BITCOIND_RPCPASSWORD=bitcoin
BITCOIND_RPCURL=http://host.docker.internal:8332

# ─── Network ──────────────────────────────────────────────────────────────────
NETWORK=mainnet
# NOTE: USE_TOR controls outbound API calls (market prices). Traders still
# access via Tor hidden service regardless. PySocks cannot route through
# host Tor from Docker bridge network, so set False for direct API access.
USE_TOR=False
TOR_PROXY=host.docker.internal:9050

# ─── Fees ─────────────────────────────────────────────────────────────────────
FEE=0.002
MAKER_FEE_SPLIT=0.125
DEVFUND=0.2

# ─── Order Timings (seconds) ─────────────────────────────────────────────────
PENALTY_TIMEOUT=600
EXP_MAKER_BOND_INVOICE=300
EXP_TAKER_BOND_INVOICE=180
RETRY_TIME=600
BLOCK_TIME=600
MAX_MINING_NETWORK_SPEEDUP_EXPECTED=1.5

# ─── Order Limits ────────────────────────────────────────────────────────────
MAX_PUBLIC_ORDERS=500

# ─── Routing Fee Limits ──────────────────────────────────────────────────────
PROPORTIONAL_ROUTING_FEE_LIMIT=0.001
MIN_FLAT_ROUTING_FEE_LIMIT_REWARD=10

# ─── Swap Settings ───────────────────────────────────────────────────────────
SWAP_FEE_SHAPE=linear
MAX_SWAP_FEE=0.02
MIN_POINT=50000
MAX_POINT=500000
SWAP_LAMBDA=5
MIN_SWAP_FEE=0.01

# ─── Market APIs ──────────────────────────────────────────────────────────────
MARKET_PRICE_APIS=https://blockchain.info/ticker,https://api.yadio.io/exrates/BTC

# ─── Node Info ────────────────────────────────────────────────────────────────
NODE_ALIAS=PagCoin RoboSats
NODE_ID=

# ─── Telegram (configure later) ──────────────────────────────────────────────
TELEGRAM_TOKEN=
TELEGRAM_BOT_NAME=
TELEGRAM_COORDINATOR_CHAT_ID=

# ─── Display / Notices ────────────────────────────────────────────────────────
NOTICE_SEVERITY=none
NOTICE_MESSAGE=
ALTERNATIVE_SITE=
ALTERNATIVE_NAME=

# ─── Operational ──────────────────────────────────────────────────────────────
# NOTE: DEVELOPMENT and SKIP_COLLECT_STATIC use shell-style checks in entrypoint.sh
# Any non-empty value (even "False") is truthy in shell. Leave empty to disable.
DEVELOPMENT=
TESTING=False
SKIP_COLLECT_STATIC=1
GEOBLOCKED_COUNTRIES=
CHAT_NOTIFICATION_TIMEGAP=5
ENVEOF

    chmod 600 "$INSTALL_DIR/robosats.env"

    # Create .env symlink so docker-compose auto-loads variables for interpolation
    ln -sf robosats.env "$INSTALL_DIR/.env"
    print_success "Environment file created: $INSTALL_DIR/robosats.env (mode 600)"
    print_success "Symlinked .env -> robosats.env for docker-compose"
}

# ─── Phase 5: Create Docker Compose ──────────────────────────────────────────
create_docker_compose() {
    print_phase "5" "Creating Docker Compose Configuration"

    cat > "$INSTALL_DIR/docker-compose.yml" << COMPOSEEOF
version: '3.8'

networks:
  robosats-net:
    driver: bridge

volumes:
  postgres_data:
  redis_data:

services:
  # ─── PostgreSQL ───────────────────────────────────────────────────────────
  postgres:
    image: postgres:15-alpine
    container_name: robosats-coord-postgres
    restart: always
    networks:
      - robosats-net
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─── Redis ────────────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: robosats-coord-redis
    restart: always
    networks:
      - robosats-net
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─── Coordinator (Gunicorn — HTTP API) ────────────────────────────────────
  coordinator:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coordinator
    restart: always
    networks:
      - robosats-net
    ports:
      - "127.0.0.1:8000:8000"
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
      - ./static:/usr/src/robosats/static
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: ["bash", "-c", "python3 manage.py migrate --noinput && gunicorn robosats.wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 120 --log-level info"]

  # ─── Daphne (ASGI — WebSocket) ───────────────────────────────────────────
  daphne:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coord-daphne
    restart: always
    networks:
      - robosats-net
    ports:
      - "127.0.0.1:9000:9000"
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: >
      daphne -b 0.0.0.0 -p 9000 robosats.asgi:application

  # ─── Celery Worker ───────────────────────────────────────────────────────
  celery-worker:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coord-celery-worker
    restart: always
    networks:
      - robosats-net
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: >
      celery -A robosats worker --loglevel=info --concurrency=4

  # ─── Celery Beat (Scheduled Tasks) ───────────────────────────────────────
  celery-beat:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coord-celery-beat
    restart: always
    networks:
      - robosats-net
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: >
      celery -A robosats beat --loglevel=info --scheduler django_celery_beat.schedulers:DatabaseScheduler

  # ─── Clean Orders ────────────────────────────────────────────────────────
  clean-orders:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coord-clean-orders
    restart: always
    networks:
      - robosats-net
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: >
      python3 manage.py clean_orders

  # ─── Follow Invoices ─────────────────────────────────────────────────────
  follow-invoices:
    image: ${ROBOSATS_IMAGE}
    container_name: robosats-coord-follow-invoices
    restart: always
    networks:
      - robosats-net
    env_file:
      - robosats.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/usr/src/robosats/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: >
      python3 manage.py follow_invoices
COMPOSEEOF

    print_success "Docker Compose file created with 8 services"
    print_status "  postgres, redis, coordinator, daphne,"
    print_status "  celery-worker, celery-beat, clean-orders, follow-invoices"
}

# ─── Phase 6: Tor Hidden Service ─────────────────────────────────────────────
setup_tor_hidden_service() {
    print_phase "6" "Setting Up Tor Hidden Service"

    if [[ "$SKIP_TOR" == "true" ]]; then
        print_warning "Skipping Tor setup (--skip-tor)"
        return
    fi

    local tor_dir="/var/lib/tor/robosats-coordinator"
    local torrc="/etc/tor/torrc"
    local marker="# RoboSats Coordinator Hidden Service"

    # Create hidden service directory
    if [[ ! -d "$tor_dir" ]]; then
        mkdir -p "$tor_dir"
        chown debian-tor:debian-tor "$tor_dir"
        chmod 700 "$tor_dir"
        print_success "Created Tor hidden service directory"
    else
        print_status "Tor hidden service directory already exists"
    fi

    # Append config to torrc (idempotent)
    if ! grep -q "$marker" "$torrc" 2>/dev/null; then
        cat >> "$torrc" << TOREOF

$marker
HiddenServiceDir $tor_dir
HiddenServicePort 80 127.0.0.1:8000
HiddenServicePort 9000 127.0.0.1:9000
TOREOF
        print_success "Hidden service config appended to $torrc"
    else
        print_status "Hidden service config already present in $torrc"
    fi

    # Restart Tor and wait for onion address
    systemctl restart tor
    print_status "Waiting for Tor to generate .onion address..."

    local attempts=0
    while [[ ! -f "$tor_dir/hostname" ]] && [[ $attempts -lt 30 ]]; do
        sleep 2
        ((attempts++))
    done

    if [[ -f "$tor_dir/hostname" ]]; then
        ONION_ADDRESS=$(cat "$tor_dir/hostname")
        print_success "Tor hidden service: $ONION_ADDRESS"

        # Update ONION_LOCATION in env file
        sed -i "s|^ONION_LOCATION=.*|ONION_LOCATION=${ONION_ADDRESS}|" "$INSTALL_DIR/robosats.env"
        # HOST_NAME must include .onion for Django ALLOWED_HOSTS
        sed -i "s|^HOST_NAME=.*|HOST_NAME=${ONION_ADDRESS}|" "$INSTALL_DIR/robosats.env"
        sed -i "s|^HOST_NAME2=.*|HOST_NAME2=localhost|" "$INSTALL_DIR/robosats.env"
        print_success "Updated ONION_LOCATION and HOST_NAME in robosats.env"
    else
        print_warning "Could not obtain .onion address (Tor may still be starting)"
        print_warning "Check manually: cat $tor_dir/hostname"
    fi
}

# ─── Phase 7: Nginx Configuration ────────────────────────────────────────────
update_nginx_config() {
    print_phase "7" "Creating Nginx Configuration"

    # Ensure nginx conf directory exists
    mkdir -p "$NGINX_CONF_DIR"

    cat > "$NGINX_CONF_DIR/coordinator.conf" << 'NGINXEOF'
# ─── RoboSats Coordinator ────────────────────────────────────────────────────
# Generated by install-robosats-coordinator.sh
# API (Gunicorn) on port 8000, WebSocket (Daphne) on port 9000

upstream robosats_api {
    server 127.0.0.1:8000;
}

upstream robosats_ws {
    server 127.0.0.1:9000;
}

# ─── Coordinator via Tor / localhost ──────────────────────────────────────────
# This block serves the coordinator API and WebSocket on port 8001.
# Accessible via Tor .onion or localhost without any domain/SSL requirement.
server {
    listen 8001;
    listen [::]:8001;
    server_name _;

    # Static files
    location /static/ {
        alias /home/pagcoin/robosats-coordinator/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # WebSocket upgrade
    location /ws/ {
        proxy_pass http://robosats_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # API and admin
    location / {
        proxy_pass http://robosats_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# ─── Clearnet HTTPS (uncomment after DNS + SSL setup) ────────────────────────
# 1. Point your domain DNS A record to this server's public IP
# 2. Run: sudo certbot certonly --webroot -w /var/www/certbot -d your-domain.com
# 3. Uncomment the block below and replace your-domain.com
# 4. Reload nginx: docker exec robosats-gateway-nginx-1 nginx -s reload
#
# server {
#     listen 443 ssl http2;
#     listen [::]:443 ssl http2;
#     server_name your-domain.com;
#
#     ssl_certificate /etc/nginx/ssl/live/your-domain.com/fullchain.pem;
#     ssl_certificate_key /etc/nginx/ssl/live/your-domain.com/privkey.pem;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_prefer_server_ciphers on;
#
#     location /static/ {
#         alias /home/pagcoin/robosats-coordinator/static/;
#         expires 30d;
#         add_header Cache-Control "public, immutable";
#     }
#
#     location /ws/ {
#         proxy_pass http://robosats_ws;
#         proxy_http_version 1.1;
#         proxy_set_header Upgrade $http_upgrade;
#         proxy_set_header Connection "upgrade";
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_read_timeout 86400;
#     }
#
#     location / {
#         proxy_pass http://robosats_api;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto https;
#         proxy_http_version 1.1;
#         proxy_set_header Upgrade $http_upgrade;
#         proxy_set_header Connection "upgrade";
#     }
# }
NGINXEOF

    print_success "Nginx config created: $NGINX_CONF_DIR/coordinator.conf"

    # Reload nginx if running
    local nginx_container
    nginx_container=$(docker ps --format '{{.Names}}' | grep -E 'nginx' | head -1)
    if [[ -n "$nginx_container" ]]; then
        docker exec "$nginx_container" nginx -s reload 2>/dev/null && \
            print_success "Nginx reloaded" || \
            print_warning "Could not reload nginx (reload manually)"
    else
        print_warning "No running nginx container found. Reload nginx manually after starting it."
    fi
}

# ─── Phase 8: Start Services ─────────────────────────────────────────────────
start_services() {
    print_phase "8" "Starting Services"

    cd "$INSTALL_DIR"
    export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME"

    # Pull images
    print_status "Pulling Docker images..."
    $DOCKER_COMPOSE pull

    # Start infrastructure first
    print_status "Starting PostgreSQL and Redis..."
    $DOCKER_COMPOSE up -d postgres redis

    print_status "Waiting for database and cache to be healthy..."
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if $DOCKER_COMPOSE ps postgres 2>/dev/null | grep -q "healthy" && \
           $DOCKER_COMPOSE ps redis 2>/dev/null | grep -q "healthy"; then
            break
        fi
        sleep 2
        ((attempts++))
    done

    if [[ $attempts -ge 30 ]]; then
        print_warning "Timed out waiting for healthy status, continuing anyway..."
    else
        print_success "PostgreSQL and Redis are healthy"
    fi

    # Start coordinator (runs migrations + collectstatic)
    print_status "Starting coordinator (migrations + collectstatic)..."
    $DOCKER_COMPOSE up -d coordinator
    sleep 15

    # Check coordinator logs for migration success
    if $DOCKER_COMPOSE logs coordinator 2>&1 | grep -q "Listening at"; then
        print_success "Coordinator is running (Gunicorn started)"
    else
        print_status "Coordinator is starting up (may take a moment)..."
        sleep 10
    fi

    # Start remaining services
    print_status "Starting Daphne, Celery, and management commands..."
    $DOCKER_COMPOSE up -d

    sleep 5
    print_success "All services started"

    # Show container status
    echo ""
    $DOCKER_COMPOSE ps
}

# ─── Phase 9: Create Superuser ───────────────────────────────────────────────
create_superuser() {
    print_phase "9" "Creating Django Superuser"

    if [[ "$SKIP_SUPERUSER" == "true" ]]; then
        print_warning "Skipping superuser creation (--skip-superuser)"
        return
    fi

    cd "$INSTALL_DIR"
    export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME"

    echo ""
    print_status "Creating admin superuser (username must be 'admin' to match ESCROW_USERNAME)."
    print_status "You will be prompted for a password."
    echo ""

    # Create superuser non-interactively, then prompt for password change
    $DOCKER_COMPOSE exec -T coordinator python3 manage.py shell -c "
from django.contrib.auth.models import User
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@localhost', 'changeme')
    print('Superuser admin created with temporary password.')
else:
    print('Superuser admin already exists.')
" || {
        print_warning "Superuser creation failed."
        print_warning "Create manually: cd $INSTALL_DIR && $DOCKER_COMPOSE exec coordinator python3 manage.py createsuperuser"
        return
    }

    print_warning "IMPORTANT: Change the admin password after first login at /admin/"
    print_warning "Or run: cd $INSTALL_DIR && $DOCKER_COMPOSE exec coordinator python3 manage.py changepassword admin"
}

# ─── Phase 10: Systemd Service ───────────────────────────────────────────────
create_systemd_service() {
    print_phase "10" "Creating Systemd Service"

    if [[ "$SKIP_SYSTEMD" == "true" ]]; then
        print_warning "Skipping systemd setup (--skip-systemd)"
        return
    fi

    cat > /etc/systemd/system/robosats-coordinator.service << SYSTEMDEOF
[Unit]
Description=RoboSats Coordinator (Docker Compose)
Requires=docker.service
After=docker.service tor.service
StartLimitIntervalSec=60

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
Environment=COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
ExecStart=$DOCKER_COMPOSE up -d
ExecStop=$DOCKER_COMPOSE down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

    systemctl daemon-reload
    systemctl enable robosats-coordinator.service
    print_success "Systemd service created and enabled"
    print_status "  Start:  systemctl start robosats-coordinator"
    print_status "  Stop:   systemctl stop robosats-coordinator"
    print_status "  Status: systemctl status robosats-coordinator"
}

# ─── Phase 11: Management Scripts ────────────────────────────────────────────
create_management_scripts() {
    print_phase "11" "Creating Management Scripts"

    cd "$INSTALL_DIR"

    # ── start.sh ──
    cat > start.sh << 'STARTEOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Starting RoboSats Coordinator..."
docker-compose up -d 2>/dev/null || docker-compose up -d
echo ""
echo "RoboSats Coordinator started!"
echo "  API:   http://127.0.0.1:8000/api/"
echo "  Admin: http://127.0.0.1:8000/admin/"
echo "  WS:    ws://127.0.0.1:9000/ws/"
echo ""
echo "Use ./status.sh to check services"
STARTEOF

    # ── stop.sh ──
    cat > stop.sh << 'STOPEOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Stopping RoboSats Coordinator..."
docker-compose down 2>/dev/null || docker-compose down
echo "RoboSats Coordinator stopped."
STOPEOF

    # ── status.sh ──
    cat > status.sh << 'STATUSEOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "═══════════════════════════════════════════"
echo "  RoboSats Coordinator Status"
echo "═══════════════════════════════════════════"
echo ""
docker-compose ps 2>/dev/null || docker-compose ps
echo ""
echo "Port Status:"
echo "────────────"
ss -tlnp 2>/dev/null | grep -E ":(8000|8001|9000) " || echo "  No coordinator ports detected"
echo ""
echo "Tor Hidden Service:"
echo "────────────────────"
if [ -f /var/lib/tor/robosats-coordinator/hostname ]; then
    echo "  $(cat /var/lib/tor/robosats-coordinator/hostname)"
else
    echo "  Not configured"
fi
STATUSEOF

    # ── logs.sh ──
    cat > logs.sh << 'LOGSEOF'
#!/bin/bash
cd "$(dirname "$0")"
SERVICE="${1:-}"
FOLLOW="${2:-}"

if [ "$SERVICE" = "-f" ]; then
    echo "Following all logs (Ctrl+C to exit)..."
    docker-compose logs -f 2>/dev/null || docker-compose logs -f
elif [ -n "$SERVICE" ]; then
    if [ "$FOLLOW" = "-f" ]; then
        echo "Following $SERVICE logs (Ctrl+C to exit)..."
        docker-compose logs -f "$SERVICE" 2>/dev/null || docker-compose logs -f "$SERVICE"
    else
        echo "Logs for $SERVICE:"
        docker-compose logs --tail=100 "$SERVICE" 2>/dev/null || docker-compose logs --tail=100 "$SERVICE"
    fi
else
    echo "RoboSats Coordinator Logs (last 50 lines):"
    echo "════════════════════════════════════════════"
    docker-compose logs --tail=50 2>/dev/null || docker-compose logs --tail=50
    echo ""
    echo "Usage: ./logs.sh [-f] [service] [-f]"
    echo "  ./logs.sh              # Last 50 lines, all services"
    echo "  ./logs.sh -f           # Follow all services"
    echo "  ./logs.sh coordinator  # Last 100 lines, coordinator"
    echo "  ./logs.sh coordinator -f  # Follow coordinator"
    echo ""
    echo "Services: postgres, redis, coordinator, daphne,"
    echo "          celery-worker, celery-beat, clean-orders, follow-invoices"
fi
LOGSEOF

    # ── update.sh ──
    cat > update.sh << 'UPDATEEOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Updating RoboSats Coordinator..."
echo ""

# Pull latest images
docker-compose pull 2>/dev/null || docker-compose pull

# Restart with new images
docker-compose up -d 2>/dev/null || docker-compose up -d

echo ""
echo "Update complete! Checking status..."
sleep 5
docker-compose ps 2>/dev/null || docker-compose ps
UPDATEEOF

    # ── backup.sh ──
    cat > backup.sh << 'BACKUPEOF'
#!/bin/bash
cd "$(dirname "$0")"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "═══════════════════════════════════════════"
echo "  RoboSats Coordinator Backup"
echo "═══════════════════════════════════════════"
echo ""

# Backup environment (contains secrets)
cp robosats.env "$BACKUP_DIR/robosats.env"
echo "  [OK] Environment file"

# Backup Docker Compose
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
echo "  [OK] Docker Compose config"

# Backup PostgreSQL database
echo "  [..] Dumping PostgreSQL database..."
docker-compose exec -T postgres pg_dump -U robosats robosats > "$BACKUP_DIR/robosats_db.sql" 2>/dev/null || \
    docker-compose exec -T postgres pg_dump -U robosats robosats > "$BACKUP_DIR/robosats_db.sql" 2>/dev/null

if [ -f "$BACKUP_DIR/robosats_db.sql" ] && [ -s "$BACKUP_DIR/robosats_db.sql" ]; then
    echo "  [OK] Database dump"
else
    echo "  [WARN] Database dump may be empty (are services running?)"
fi

# Set restrictive permissions on backup
chmod -R 600 "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo ""
echo "Backup saved to: $(pwd)/$BACKUP_DIR"
echo "Size: $(du -sh "$BACKUP_DIR" | cut -f1)"
BACKUPEOF

    chmod +x start.sh stop.sh status.sh logs.sh update.sh backup.sh
    print_success "Management scripts created: start, stop, status, logs, update, backup"
}

# ─── Phase 12: Verification ──────────────────────────────────────────────────
test_installation() {
    print_phase "12" "Verifying Installation"

    local pass=0
    local fail=0

    # Test coordinator API
    if curl -sf --max-time 10 http://127.0.0.1:8000/api/ >/dev/null 2>&1; then
        print_success "Coordinator API responding on port 8000"
        ((pass++))
    else
        print_warning "Coordinator API not responding on port 8000 (may still be starting)"
        ((fail++))
    fi

    # Test Daphne
    if curl -sf --max-time 10 http://127.0.0.1:9000/ >/dev/null 2>&1; then
        print_success "Daphne (WebSocket) responding on port 9000"
        ((pass++))
    else
        print_warning "Daphne not responding on port 9000 (may still be starting)"
        ((fail++))
    fi

    # Test Tor access
    if [[ -n "$ONION_ADDRESS" ]] && [[ "$SKIP_TOR" != "true" ]]; then
        if curl -sf --max-time 30 --socks5-hostname 127.0.0.1:9050 "http://${ONION_ADDRESS}/api/" >/dev/null 2>&1; then
            print_success "Tor .onion access works"
            ((pass++))
        else
            print_warning "Tor .onion not reachable yet (can take a few minutes)"
            ((fail++))
        fi
    fi

    # Container status
    cd "$INSTALL_DIR"
    export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME"
    local running
    running=$($DOCKER_COMPOSE ps --format '{{.State}}' 2>/dev/null | grep -c "running" || true)
    print_status "Running containers: $running / 8"

    echo ""
    if [[ $fail -eq 0 ]]; then
        print_success "All verification checks passed"
    else
        print_warning "$pass passed, $fail need attention (services may still be starting)"
        print_status "Check logs: cd $INSTALL_DIR && ./logs.sh"
    fi
}

# ─── Phase 13: Summary ───────────────────────────────────────────────────────
show_summary() {
    print_phase "13" "Installation Complete"

    echo ""
    echo -e "${GREEN}${BOLD}================================================${NC}"
    echo -e "${GREEN}${BOLD}  RoboSats Coordinator is running!${NC}"
    echo -e "${GREEN}${BOLD}================================================${NC}"
    echo ""
    echo -e "${BOLD}Local Access:${NC}"
    echo "  API:       http://127.0.0.1:8000/api/"
    echo "  Admin:     http://127.0.0.1:8000/admin/"
    echo "  WebSocket: ws://127.0.0.1:9000/ws/"
    echo ""

    if [[ -n "$ONION_ADDRESS" ]]; then
        echo -e "${BOLD}Tor Access:${NC}"
        echo "  Onion:     http://${ONION_ADDRESS}"
        echo "  API:       http://${ONION_ADDRESS}/api/"
        echo ""
    fi

    echo -e "${BOLD}Management Commands:${NC}"
    echo "  cd $INSTALL_DIR"
    echo "  ./start.sh     Start all services"
    echo "  ./stop.sh      Stop all services"
    echo "  ./status.sh    Check status"
    echo "  ./logs.sh      View logs"
    echo "  ./update.sh    Update images"
    echo "  ./backup.sh    Backup database + config"
    echo ""
    echo -e "${BOLD}Systemd:${NC}"
    echo "  systemctl status robosats-coordinator"
    echo "  systemctl restart robosats-coordinator"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Test: curl http://127.0.0.1:8000/api/"
    echo "  2. Login to admin: http://127.0.0.1:8000/admin/"
    echo "  3. For clearnet: configure DNS + SSL, uncomment HTTPS block"
    echo "     in $NGINX_CONF_DIR/coordinator.conf"
    echo "  4. Configure Telegram notifications in robosats.env"
    echo "  5. Register as a federation coordinator"
    echo ""
    echo -e "${BOLD}Logs:${NC}"
    echo "  cd $INSTALL_DIR && ./logs.sh coordinator -f"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo ""
    echo -e "${BOLD}================================================${NC}"
    echo -e "${BOLD}  RoboSats Coordinator - Auto Installer${NC}"
    echo -e "${BOLD}================================================${NC}"
    echo ""
    echo "Install directory: $INSTALL_DIR"
    echo "LND endpoint:     $LND_GRPC_HOST"
    echo "Image:            $ROBOSATS_IMAGE"
    echo ""

    check_requirements
    create_directory
    generate_credentials
    create_env_file
    create_docker_compose
    setup_tor_hidden_service
    update_nginx_config
    start_services
    create_superuser
    create_systemd_service
    create_management_scripts
    test_installation
    show_summary
}

main "$@"
