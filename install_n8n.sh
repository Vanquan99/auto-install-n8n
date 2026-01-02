#!/usr/bin/env bash
set -e

SCRIPT_VERSION="1.1.1"

# ====== CONFIG ======
N8N_DIR="/opt/n8n"
N8N_VOLUME_NAME="n8n_n8n_data"
N8N_VERSION="${N8N_VERSION:-latest}"
TIMEZONE="Asia/Ho_Chi_Minh"

# ====== CHECK ROOT ======
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

echo "======================================="
echo " n8n Production Installer v${SCRIPT_VERSION}"
echo " n8n version: ${N8N_VERSION}"
echo "======================================="

# ====== ASK DOMAIN ======
read -rp "Enter your domain (e.g. n8n.example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "[ERROR] Domain cannot be empty"
  exit 1
fi

SERVER_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)

if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  echo "[ERROR] Domain does not point to this server"
  echo "Domain IP : $DOMAIN_IP"
  echo "Server IP : $SERVER_IP"
  exit 1
fi

echo "[OK] Domain verified"

# ====== INSTALL DOCKER ======
if ! command -v docker &>/dev/null; then
  echo "[INFO] Installing Docker"
  apt update
  apt install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version &>/dev/null; then
  echo "[INFO] Installing docker-compose plugin"
  apt install -y docker-compose-plugin
fi

echo "[OK] Docker installed"

# ====== PREPARE DIR ======
mkdir -p "$N8N_DIR"
cd "$N8N_DIR"

# ====== CHECK EXISTING VOLUME ======
if docker volume inspect "$N8N_VOLUME_NAME" &>/dev/null; then
  echo "[INFO] Existing n8n data volume detected: $N8N_VOLUME_NAME"
  REUSE_VOLUME=true
else
  echo "[INFO] No existing volume found, will create new one"
  REUSE_VOLUME=false
fi

# ====== WRITE docker-compose.yml ======
cat > docker-compose.yml <<EOF
services:
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - NODE_ENV=production
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}
    volumes:
      - ${N8N_VOLUME_NAME}:/home/node/.n8n

volumes:
  ${N8N_VOLUME_NAME}:
    external: true
EOF

echo "[OK] docker-compose.yml created"

# ====== ENSURE VOLUME EXISTS ======
if [[ "$REUSE_VOLUME" == false ]]; then
  docker volume create "$N8N_VOLUME_NAME"
  echo "[OK] Volume created: $N8N_VOLUME_NAME"
fi

# ====== INSTALL NGINX + CERTBOT ======
if ! command -v nginx &>/dev/null; then
  echo "[INFO] Installing Nginx"
  apt install -y nginx
fi

if ! command -v certbot &>/dev/null; then
  echo "[INFO] Installing Certbot"
  apt install -y certbot python3-certbot-nginx
fi

# ====== NGINX CONFIG ======
NGINX_CONF="/etc/nginx/sites-available/n8n.conf"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/n8n.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

# ====== SSL ======
if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"
fi

# ====== START N8N ======
echo "[INFO] Starting n8n"
docker compose pull
docker compose up -d

echo ""
echo "======================================="
echo " n8n is READY"
echo " URL: https://${DOMAIN}"
echo " Volume: ${N8N_VOLUME_NAME}"
echo "======================================="
