#!/bin/bash

set -e

# ===============================
# CHECK ROOT
# ===============================
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# ===============================
# FUNCTIONS
# ===============================
get_public_ip() {
  curl -s https://api.ipify.org
}

check_domain() {
  local domain=$1
  local server_ip=$(get_public_ip)
  local domain_ip=$(dig +short "$domain" | tail -n1)

  [[ "$domain_ip" == "$server_ip" ]]
}

# ===============================
# INPUT DOMAIN
# ===============================
read -p "Enter your domain or subdomain (e.g. n8n.example.com): " DOMAIN

if ! check_domain "$DOMAIN"; then
  echo "❌ Domain $DOMAIN is not pointing to this server."
  echo "👉 Please point it to $(get_public_ip) and rerun the script."
  exit 1
fi

echo "✅ Domain verified. Continue installation..."

# ===============================
# VARIABLES
# ===============================
N8N_DIR="/opt/n8n"
TIMEZONE="Asia/Ho_Chi_Minh"

# ===============================
# INSTALL PACKAGES
# ===============================
apt update
apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common \
  nginx \
  certbot \
  python3-certbot-nginx \
  docker.io \
  docker-compose

systemctl enable docker
systemctl start docker
systemctl enable nginx
systemctl start nginx

# ===============================
# CREATE N8N DIRECTORY
# ===============================
mkdir -p "$N8N_DIR"
cd "$N8N_DIR"

# ===============================
# DOCKER COMPOSE
# ===============================
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}/
      - NODE_ENV=production
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_DIAGNOSTICS_ENABLED=false
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF

# ===============================
# START N8N
# ===============================
docker-compose up -d

# ===============================
# NGINX CONFIG
# ===============================
cat > /etc/nginx/sites-available/n8n <<EOF
server {
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
nginx -t
systemctl reload nginx

# ===============================
# SSL CERTIFICATE
# ===============================
certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m admin@${DOMAIN} --redirect

# ===============================
# FIREWALL (OPTIONAL SAFE DEFAULT)
# ===============================
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ===============================
# DONE
# ===============================
echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             ║"
echo "║  ✅ N8N INSTALLED SUCCESSFULLY (NGINX PRODUCTION MODE)      ║"
echo "║                                                             ║"
echo "║  🌐 URL: https://${DOMAIN}                                  ║"
echo "║                                                             ║"
echo "║  🔁 Auto-restart enabled (Docker + Nginx)                  ║"
echo "║                                                             ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""
