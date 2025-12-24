Here's the modified `docker-compose.yml` optimized for Podman (specifically rootless Podman on your Raspberry Pi):

```yaml
version: '3.8'

x-podman-defaults: &podman-defaults
  # Podman-specific settings
  security_opt:
    - no-new-privileges:true
    - label=disable
  # Remove capabilities for security
  cap_drop:
    - ALL
  # Run as non-root inside container
  user: "1000:1000"
  # Podman healthcheck format
  healthcheck:
    interval: 30s
    timeout: 10s
    start_period: 30s
    retries: 3

services:
  # Reverse Proxy - Nginx
  nginx:
    image: nginx:alpine
    container_name: rockwillow-nginx
    ports:
      - "8080:80"                    # Rootless Podman: must use port >1024
      - "8443:443"                   # HTTPS if SSL configured
    volumes:
      # Nginx configuration - use :z for SELinux/mount labeling in Podman
      - ${HOME}/projects/rw_deploy/nginx/conf.d:/etc/nginx/conf.d:z,ro
      - ${HOME}/projects/rw_deploy/nginx/ssl:/etc/nginx/ssl:z,ro
      - ${HOME}/projects/rw_deploy/nginx/html:/usr/share/nginx/html:z,ro
      # Logs to external drive - Podman needs :z for writable mounts
      - ${HOME}/data/logs/nginx:/var/log/nginx:z
    depends_on:
      rw_budget_api:
        condition: service_healthy
      rw_budget:
        condition: service_healthy
    networks:
      - rockwillow-network
    restart: "always"  # Podman uses "always" instead of "unless-stopped"
    <<: *podman-defaults
    # Podman-compatible healthcheck
    healthcheck:
      test: ["CMD-SHELL", "nginx -t || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    # Nginx needs specific capabilities
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
      - NET_BIND_SERVICE
    # Podman: run as nginx user inside container (UID 101 in alpine)
    user: "101:101"

  # Database - MariaDB
  mariadb:
    image: mariadb:11
    container_name: rockwillow-mariadb
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:-ChangeMe123!}
      MARIADB_DATABASE: ${DB_NAME:-rockwillow_budget}
      MARIADB_USER: ${DB_USER:-budget_user}
      MARIADB_PASSWORD: ${DB_PASSWORD:-ChangeMe456!}
      TZ: ${TZ:-America/New_York}
      # Podman: explicitly set user for MariaDB
      MYSQL_USER: mysql
      MYSQL_GROUP: mysql
    volumes:
      # Database data on external drive - :Z for exclusive SELinux labeling
      - ${HOME}/data/mariadb:/var/lib/mysql:Z
      # Schema initialization
      - ${HOME}/projects/rw_deploy/db/init.sql:/docker-entrypoint-initdb.d/init.sql:z,ro
      # Backups directory
      - ${HOME}/data/backups:/backups:z
      # Database logs
      - ${HOME}/data/logs/mariadb:/var/log/mysql:z
    ports:
      - "3307:3306"                   # External access on high port
    networks:
      - rockwillow-network
    restart: "always"
    <<: *podman-defaults
    # MariaDB-specific healthcheck for Podman
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${DB_ROOT_PASSWORD}"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s  # MariaDB needs longer startup time
    # MariaDB needs specific capabilities
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
      - DAC_OVERRIDE
    # Podman: run as mysql user inside container
    user: "999:999"  # mysql user in MariaDB container
    # Podman: add tmpfs for /tmp to reduce writes
    tmpfs:
      - /tmp:size=100M,mode=1777

  # Go Gin REST API
  rw_budget_api:
    build:
      context: ${HOME}/projects/rw_budget_api
      dockerfile: Dockerfile
      # Podman build args
      args:
        - GO_VERSION=1.21
    container_name: rockwillow-budget-api
    environment:
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_USER: ${DB_USER:-budget_user}
      DB_PASSWORD: ${DB_PASSWORD:-ChangeMe456!}
      DB_NAME: ${DB_NAME:-rockwillow_budget}
      GIN_MODE: ${GIN_MODE:-release}
      API_PORT: 8081
      FLASK_APP_URL: http://rw_budget:5000
      # Podman: set user explicitly
      USER: ginuser
      UID: "1000"
      GID: "1000"
    volumes:
      # Mount source code - use :z for shared SELinux context
      - ${HOME}/projects/rw_budget_api:/app:z,ro
      # Application logs
      - ${HOME}/data/logs/rw_budget_api:/app/logs:z
    depends_on:
      mariadb:
        condition: service_healthy
    networks:
      - rockwillow-network
    restart: "always"
    <<: *podman-defaults
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8081/health || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
    # Gin API needs minimal capabilities
    cap_add:
      - CHOWN
    # Expose port for healthcheck (not published to host)
    expose:
      - "8081"

  # Python Flask Web Application
  rw_budget:
    build:
      context: ${HOME}/projects/rw_budget
      dockerfile: Dockerfile
      # Podman build args
      args:
        - PYTHON_VERSION=3.11
    container_name: rockwillow-budget-app
    environment:
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_USER: ${DB_USER:-budget_user}
      DB_PASSWORD: ${DB_PASSWORD:-ChangeMe456!}
      DB_NAME: ${DB_NAME:-rockwillow_budget}
      GIN_API_URL: http://rw_budget_api:8081/api
      FLASK_ENV: ${FLASK_ENV:-production}
      FLASK_APP: app.py
      SECRET_KEY: ${FLASK_SECRET_KEY:-ChangeThisSecretKey!}
      # Podman: set user explicitly
      USER: flaskuser
      UID: "1000"
      GID: "1000"
    volumes:
      # Mount source code
      - ${HOME}/projects/rw_budget:/app:z,ro
      # Application logs
      - ${HOME}/data/logs/rw_budget:/var/log/flask:z
    depends_on:
      mariadb:
        condition: service_healthy
      rw_budget_api:
        condition: service_healthy
    networks:
      - rockwillow-network
    restart: "always"
    <<: *podman-defaults
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
    # Flask needs minimal capabilities
    cap_add:
      - CHOWN
    # Expose port for healthcheck (not published to host)
    expose:
      - "5000"

networks:
  rockwillow-network:
    # Podman: use bridge driver (default) or macvlan for external access
    driver: bridge
    # Podman: enable IPv6 if needed
    enable_ipv6: false
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

## 🔧 **Podman-Specific Configuration Files**

### **1. Podman Storage Configuration** (`~/.config/containers/storage.conf`)
```ini
[storage]
driver = "overlay"
graphroot = "/home/jsellers0/.local/share/containers/storage"
runroot = "/run/user/1000/containers"

[storage.options]
additionalimagestores = []
mount_program = "/usr/bin/fuse-overlayfs"

# For external drive storage (if using your symlink)
# graphroot = "/home/jsellers0/.local/share/containers/storage"
# Which points to: /mnt/rockwillow/containers/storage
```

### **2. Podman Network Configuration** (`~/.config/containers/containers.conf`)
```ini
[containers]
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "FSETID",
    "KILL",
    "NET_BIND_SERVICE",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
    "SYS_CHROOT"
]

netns = "private"
utsns = "private"
ipcns = "private"
cgroupns = "private"
```

## 🚀 **Podman-Specific Deployment Script**

### **`podman-deploy.sh`** (optimized for Podman)
```bash
#!/bin/bash
set -e

echo "🚀 Podman Deployment: Rock Willow Budget System"
echo "==============================================="

cd "$(dirname "$0")/.."

# Check if podman-compose is available
if ! command -v podman-compose &> /dev/null; then
    echo "❌ podman-compose not found. Installing..."
    pip3 install podman-compose
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
```

## ⚠️ **Podman-Specific Notes & Fixes**

### **Volume Labeling (`:z`, `:Z`, `:z,ro`)**
- **`:z`**: Shared SELinux context (multiple containers can read/write)
- **`:Z`**: Private SELinux context (exclusive to one container)
- **`:z,ro`**: Shared read-only (for configuration files)

### **Port Mapping in Rootless Podman**
```yaml
ports:
  - "8080:80"  # OK - port >1024
# ports:
#   - "80:80"   # ❌ Won't work in rootless mode
```

### **User ID Mapping**
```bash
# Check your user's subuid/subgid mapping
cat /etc/subuid
cat /etc/subgid
# Should show: jsellers0:100000:65536

# Fix if missing:
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 jsellers0
```

### **Podman Systemd Service** (`~/.config/systemd/user/podman-stack.service`)
```ini
[Unit]
Description=Rock Willow Podman Stack
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/jsellers0/projects/rw_deploy
ExecStart=/usr/bin/podman-compose up -d
ExecStop=/usr/bin/podman-compose down
TimeoutStartSec=0

[Install]
WantedBy=default.target
```

Enable with:
```bash
systemctl --user daemon-reload
systemctl --user enable podman-stack.service
sudo loginctl enable-linger jsellers0
```

## 🔍 **Troubleshooting Podman Issues**

```bash
# Check Podman version and rootless status
podman info | grep -E "(version|rootless|store)"

# Fix permission issues
podman unshare chown -R $(id -u):$(id -g) ${HOME}/data/mariadb

# Check running containers
podman ps
podman-compose ps

# View detailed container info
podman inspect rockwillow-mariadb | grep -A5 -B5 "Mounts"

# Clean up if needed
podman system prune -a -f
```

This configuration is optimized for **rootless Podman** on Raspberry Pi, with proper security settings, volume labeling, and health checks that work with Podman's architecture.