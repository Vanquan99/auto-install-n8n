#!/usr/bin/env bash
set -e

SCRIPT_VERSION="1.0.0"
N8N_DIR="/opt/n8n"
N8N_VOLUME="n8n_n8n_data"
BACKUP_DIR="/opt/n8n/backups"
N8N_VERSION="${N8N_VERSION:-latest}"

echo "======================================="
echo " n8n UPDATE SCRIPT v${SCRIPT_VERSION}"
echo " Target n8n version: ${N8N_VERSION}"
echo "======================================="

# ===== CHECK ROOT =====
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

# ===== CHECK DIR =====
if [[ ! -f "${N8N_DIR}/docker-compose.yml" ]]; then
  echo "[ERROR] docker-compose.yml not found in ${N8N_DIR}"
  exit 1
fi

cd "$N8N_DIR"

# ===== CHECK VOLUME =====
if ! docker volume inspect "$N8N_VOLUME" &>/dev/null; then
  echo "[ERROR] n8n data volume not found: ${N8N_VOLUME}"
  exit 1
fi

echo "[OK] Data volume detected: ${N8N_VOLUME}"

# ===== BACKUP =====
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/n8n_backup_$(date +%F_%H-%M-%S).tar.gz"

echo "[INFO] Creating backup: ${BACKUP_FILE}"

docker run --rm \
  -v ${N8N_VOLUME}:/data \
  -v ${BACKUP_DIR}:/backup \
  busybox \
  tar czf "/backup/$(basename "$BACKUP_FILE")" /data

echo "[OK] Backup completed"

# ===== UPDATE IMAGE =====
echo "[INFO] Updating n8n image"

docker compose pull

# ===== APPLY VERSION (IF SPECIFIED) =====
if [[ "$N8N_VERSION" != "latest" ]]; then
  echo "[INFO] Forcing n8n version: ${N8N_VERSION}"
  sed -i "s|image: n8nio/n8n.*|image: n8nio/n8n:${N8N_VERSION}|g" docker-compose.yml
fi

# ===== RESTART =====
echo "[INFO] Restarting n8n"

docker compose up -d

# ===== VERIFY =====
sleep 5

if docker ps | grep -q n8n; then
  echo "[OK] n8n container is running"
else
  echo "[ERROR] n8n failed to start"
  echo "You can rollback using previous image"
  exit 1
fi

echo "======================================="
echo " n8n UPDATE SUCCESSFUL"
echo " Backup saved at:"
echo " ${BACKUP_FILE}"
echo "======================================="
