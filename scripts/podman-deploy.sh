#!/bin/bash
set -e

echo "🚀 Podman Deployment: Rock Willow Budget System"
echo "==============================================="

cd "$(dirname "$0")/.."

# Check if podman-compose is available
echo "❌ podman-compose not found. Installing via apt..."
    
if ! command -v podman-compose &> /dev/null; then
    echo "❌ podman-compose not found. Installing via apt..."
    
    # Try apt first
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y podman-compose
    else
        echo "❌ Could not install podman-compose. Please install manually:"
        echo "   sudo apt install podman-compose"
        exit 1
    fi
fi

# Load environment
if [ -f .env ]; then
    source .env
    echo "✅ Loaded environment variables"
else
    echo "⚠️  No .env file found, using defaults"
    # Set defaults for Podman
    export DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-ChangeMe123!}
fi

# Podman: Check if user has enough subuids/subgids
echo "🔍 Checking Podman configuration..."
if ! grep -q "^$(whoami):" /etc/subuid 2>/dev/null; then
    echo "⚠️  Podman subuids not configured. Run:"
    echo "   sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami)"
fi

# Create necessary directories with Podman permissions
echo "📁 Setting up directories..."
mkdir -p ${HOME}/data/{mariadb,logs/{nginx,mariadb,rw_budget_api,rw_budget},backups}
# Podman needs correct permissions for rootless containers
podman unshare chown -R 999:999 ${HOME}/data/mariadb 2>/dev/null || true
podman unshare chown -R 101:101 ${HOME}/data/logs/nginx 2>/dev/null || true

# Build and start with Podman
echo "🔨 Building containers with Podman..."
podman-compose build --pull --no-cache

echo "🛑 Stopping existing containers..."
podman-compose down --remove-orphans

echo "▶️  Starting Podman containers..."
podman-compose up -d

# Podman-specific: wait for containers to start
echo "⏳ Waiting for Podman containers to start..."
for i in {1..30}; do
    if podman-compose ps | grep -q "Up"; then
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

echo "✅ Podman deployment complete!"
echo ""
echo "📊 Service Status:"
podman-compose ps
echo ""
echo "🌐 Access points:"
echo "   Nginx Proxy:    http://$(hostname -I | awk '{print $1}'):8080"
echo "   MariaDB:        mysql://localhost:3307 (external)"
echo "   Gin API:        http://localhost:8081/health"
echo "   Flask App:      http://localhost:5000/health"
echo ""
echo "🔍 Podman commands:"
echo "   View logs:      podman-compose logs -f"
echo "   Shell access:   podman exec -it rockwillow-mariadb bash"
echo "   Stop all:       podman-compose down"