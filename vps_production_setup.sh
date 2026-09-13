#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo ""; echo "ERROR: Installation stopped at line $LINENO."; echo "Check the message above, fix the problem, and run the script again."; exit 1' ERR

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

APP_DIR="/root/evolution"
EVOLUTION_VERSION="v2.3.7"
API_KEY="GodaraByte"
DB_PASSWORD="GodaraByte"

echo "=========================================="
echo " Evolution API VPS Installer"
echo " Evolution API: ${EVOLUTION_VERSION}"
echo "=========================================="
echo ""

echo "[1/8] Updating Ubuntu..."
apt-get update
apt-get upgrade -y

echo "[2/8] Installing required packages..."
apt-get install -y curl ca-certificates ufw

echo "[3/8] Installing/checking Docker..."
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi

systemctl enable --now docker

docker --version
docker compose version

echo "[4/8] Configuring firewall..."
ufw allow OpenSSH
ufw allow 8080/tcp
ufw --force enable
ufw status

echo "[5/8] Creating Evolution API directory..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "[6/8] Creating configuration files..."

cat > .env <<EOF
AUTHENTICATION_API_KEY=${API_KEY}

DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution:${DB_PASSWORD}@postgres:5432/evolution?schema=public

DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=false
DATABASE_SAVE_MESSAGE_UPDATE=false
DATABASE_SAVE_DATA_CONTACTS=false
DATABASE_SAVE_DATA_CHATS=false

CACHE_LOCAL_ENABLED=false
CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://redis:6379/6
CACHE_REDIS_PREFIX_KEY=evolution
EOF

cat > docker-compose.yml <<EOF
services:
  postgres:
    image: postgres:15-alpine
    container_name: evolution_postgres
    restart: always
    environment:
      POSTGRES_USER: evolution
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: evolution
    volumes:
      - evolution_postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    container_name: evolution_redis
    restart: always
    volumes:
      - evolution_redis_data:/data

  evolution-api:
    image: evoapicloud/evolution-api:${EVOLUTION_VERSION}
    container_name: evolution_api
    restart: always
    ports:
      - "8080:8080"
    env_file:
      - .env
    depends_on:
      - postgres
      - redis
    volumes:
      - evolution_instances:/evolution/instances

volumes:
  evolution_postgres_data:
  evolution_redis_data:
  evolution_instances:
EOF

echo "[7/8] Validating and starting Docker containers..."
docker compose config >/dev/null
docker compose pull
docker compose up -d

echo "[8/8] Waiting for Evolution API..."
for i in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8080 >/tmp/evolution_api_response.txt 2>/dev/null; then
        break
    fi

    if [ "$i" -eq 60 ]; then
        echo ""
        echo "Evolution API did not become ready."
        docker compose ps
        docker compose logs --tail=100 evolution-api
        exit 1
    fi

    sleep 2
done

echo ""
echo "=========================================="
echo " Installation completed successfully!"
echo "=========================================="
echo ""
docker compose ps
echo ""
echo "Local API test:"
cat /tmp/evolution_api_response.txt
echo ""
echo "Evolution API:"
echo "http://YOUR_VPS_IPV4:8080"
echo ""
echo "API key:"
echo "${API_KEY}"
echo ""
echo "Installed files:"
echo "${APP_DIR}/.env"
echo "${APP_DIR}/docker-compose.yml"
echo ""
echo "Next: create a WhatsApp instance using the Evolution API endpoint."
