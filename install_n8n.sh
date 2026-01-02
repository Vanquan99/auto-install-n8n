#!/usr/bin/env bash
set -e

### ===== CONFIG =====
N8N_DIR="/opt/n8n"
COMPOSE_FILE="$N8N_DIR/docker-compose.yml"
NGINX_SITE="/etc/nginx/sites-available/n8n"
TIMEZONE="Asia/Ho_Chi_Minh"
### ==================

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $1"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

### ===== ROOT CHECK =====
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root (sudo)"
fi

### ===== DOMAIN INPUT =====
read -rp "Enter your domain or subdomain: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  error "Domain cannot be empty"
fi

SERVER_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)

if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  error "Domain $DOMAIN does not point to this server ($SERVER_IP)"
fi

log "Domain verified: $DOMAIN → $SERVER_IP"

### ===== INSTALL DOCKER (SAFE) =====
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker (official repo)"

  apt update
  apt install -y ca-certificates curl gnupg lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
else
  log "Docker already installed"
fi

### ===== INSTALL NGINX =====
if ! command -v nginx >/dev/null 2>&1; then
  log "Installing Nginx"
  apt install -y nginx
  systemctl enable nginx
  systemctl start nginx
else
  log "Nginx already installed"
fi

### ===== INSTALL CERTBOT =====
if ! command -v certbot >/dev/null 2>&1; then
  log "Installing Certbot"
  apt install -y certbot python3-certbot-nginx
else
  log "Certbot already installed"
fi

### ===== PREPARE N8N DIR =====
log "Preparing n8n directory"
mkdir -p "$N8N_DIR"

### ===== DOCKER COMPOSE =====
if [[ ! -f "$COMPOSE_FILE" ]]; then
  log "Creating docker-compose.yml"

  cat > "$COMPOSE_FILE" <<EOF
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - NODE_ENV=production
      - GENERIC_TIMEZONE=$TIMEZONE
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF
else
  warn "docker-compose.yml already exists"
fi

### ===== START N8N =====
log "Starting n8n stack"
cd "$N8N_DIR"
docker compose up -d

### ===== NGINX CONFIG =====
if [[ ! -f "$NGINX_SITE" ]]; then
  log "Creating nginx config"

  cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -s "$NGINX_SITE" /etc/nginx/sites-enabled/n8n
else
  warn "nginx config already exists"
fi

nginx -t
systemctl reload nginx

### ===== SSL =====
if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
  log "Issuing SSL certificate"
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN --redirect
else
  log "SSL certificate already exists"
fi

### ===== DONE =====
echo ""
echo "========================================"
echo " n8n installed successfully (v1.1.0)"
echo "----------------------------------------"
echo " URL: https://$DOMAIN"
echo " Data: Docker volume n8n_data"
echo "========================================"
