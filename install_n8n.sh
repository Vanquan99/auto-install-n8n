#!/usr/bin/env bash
set -e
set -o pipefail

# ===============================
# BASIC CHECKS
# ===============================
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this script as root (sudo)"
  exit 1
fi

if ! command -v lsb_release >/dev/null 2>&1; then
  echo "❌ lsb_release not found"
  exit 1
fi

if ! lsb_release -a 2>/dev/null | grep -qi ubuntu; then
  echo "❌ This script supports Ubuntu only"
  exit 1
fi

# ===============================
# VARIABLES
# ===============================
N8N_DIR="/home/n8n"
TIMEZONE="Asia/Ho_Chi_Minh"

# ===============================
# FUNCTIONS
# ===============================
log() {
  echo -e "\n[INFO] $1"
}

success() {
  echo "[OK] $1"
}

get_server_ip() {
  curl -s https://api.ipify.org
}

check_domain() {
  local domain=$1
  local server_ip
  server_ip=$(get_server_ip)
  local domain_ip
  domain_ip=$(dig +short "$domain" | tail -n1)

  [[ "$domain_ip" == "$server_ip" ]]
}

# ===============================
# INPUT DOMAIN
# ===============================
read -rp "Enter your domain or subdomain: " DOMAIN

log "Checking DNS for $DOMAIN"
if check_domain "$DOMAIN"; then
  success "Domain points correctly to this server"
else
  echo "❌ Domain does not point to this server"
  echo "👉 Please point $DOMAIN to IP: $(get_server_ip)"
  exit 1
fi

# ===============================
# CLEAN OLD DOCKER (SAFE)
# ===============================
log "Removing old Docker / containerd if exists"
apt-get remove -y docker docker-engine docker.io docker-ce docker-ce-cli containerd containerd.io runc || true
apt-get purge -y docker docker-engine docker.io docker-ce docker-ce-cli containerd containerd.io runc || true
apt-get autoremove -y
apt-get autoclean
success "Docker cleanup completed"

# ===============================
# INSTALL DOCKER (OFFICIAL)
# ===============================
log "Installing Docker"

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
success "Docker installed"

# ===============================
# PREPARE N8N DIRECTORY
# ===============================
log "Preparing n8n directory"
mkdir -p "$N8N_DIR"

# ===============================
# DOCKER COMPOSE
# ===============================
if [ ! -f "$N8N_DIR/docker-compose.yml" ]; then
  log "Creating docker-compose.yml"

  cat <<EOF > "$N8N_DIR/docker-compose.yml"
version: "3.8"

services:
  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_DIAGNOSTICS_ENABLED=false
    volumes:
      - ${N8N_DIR}:/home/node/.n8n
    networks:
      - n8n_network

  nginx:
    image: nginx:stable
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${N8N_DIR}/nginx.conf:/etc/nginx/conf.d/default.conf
      - ${N8N_DIR}/certbot:/etc/letsencrypt
      - ${N8N_DIR}/certbot-www:/var/www/certbot
    depends_on:
      - n8n
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge
EOF

  success "docker-compose.yml created"
else
  echo "[SKIP] docker-compose.yml already exists"
fi

# ===============================
# NGINX CONFIG
# ===============================
if [ ! -f "$N8N_DIR/nginx.conf" ]; then
  log "Creating nginx config"

  cat <<EOF > "$N8N_DIR/nginx.conf"
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  success "nginx.conf created"
else
  echo "[SKIP] nginx.conf already exists"
fi

# ===============================
# START SERVICES
# ===============================
log "Starting n8n stack"
cd "$N8N_DIR"
docker compose up -d
success "n8n is running"

# ===============================
# DONE
# ===============================
echo ""
echo "================================================="
echo "✅ n8n installation completed"
echo "🌐 URL: https://${DOMAIN}"
echo "📁 Data: ${N8N_DIR}"
echo "================================================="
