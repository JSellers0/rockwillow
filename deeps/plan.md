Perfect! Let's build a clean, production-ready project structure from the ground up for your Raspberry Pi 4 with Podman.

## 📁 **Complete Project Structure**

```
/home/pi/
├── projects/                              # All projects go here
│   ├── gin-api/                          # **Separate repo 1**
│   │   ├── cmd/
│   │   │   └── main.go                   # Gin REST API entry point
│   │   ├── internal/
│   │   │   ├── handlers/
│   │   │   ├── models/
│   │   │   └── database/
│   │   ├── go.mod
│   │   ├── go.sum
│   │   ├── Dockerfile
│   │   └── .env.example
│   │
│   ├── flask-app/                        # **Separate repo 2**
│   │   ├── app/
│   │   │   ├── __init__.py
│   │   │   ├── routes.py
│   │   │   └── models.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   ├── app.py                        # Flask entry point
│   │   └── .env.example
│   │
│   └── pi-deployment/                    # **New: Deployment meta-repo**
│       ├── docker-compose.yml            # Main orchestrator
│       ├── .env                          # Environment variables
│       ├── nginx/
│       │   ├── conf.d/
│       │   │   └── app.conf              # Nginx configuration
│       │   ├── ssl/                      # SSL certificates (optional)
│       │   └── html/                     # Static files (optional)
│       ├── db/
│       │   ├── backups/                  # MariaDB backups
│       │   ├── init.sql                  # Database initialization
│       │   └── data/                     # Persistent data (linked to volume)
│       ├── scripts/
│       │   ├── deploy.sh                 # Deployment script
│       │   ├── backup-db.sh              # Database backup
│       │   ├── update-service.sh         # Update single service
│       │   └── logs.sh                   # View all logs
│       ├── configs/
│       │   ├── podman-containers.conf    # Podman container configs
│       │   └── systemd/
│       │       └── podman-stack.service  # Auto-start service
│       ├── logs/                         # Centralized logs directory
│       └── README.md                     # Deployment documentation
```

## 🐳 **Core Configuration Files**

### **1. `docker-compose.yml`** (in `pi-deployment/`)
```yaml
version: '3.8'

services:
  # Reverse Proxy
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "8080:80"                    # Rootless: use port >1024
      - "8443:443"                   # For SSL if needed
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - gin-api
      - flask-app
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Database
  mariadb:
    image: mariadb:11
    container_name: mariadb-db
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MARIADB_DATABASE: ${DB_NAME}
      MARIADB_USER: ${DB_USER}
      MARIADB_PASSWORD: ${DB_PASSWORD}
      TZ: ${TZ:-UTC}
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      - ./db/backups:/backups
      - ./logs/mariadb:/var/log/mysql
    ports:
      - "3307:3306"                   # External access on 3307
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 40s

  # Go Gin API
  gin-api:
    build:
      context: ../gin-api              # Points to sibling directory
      dockerfile: Dockerfile
    container_name: gin-api
    environment:
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: ${DB_NAME}
      GIN_MODE: release
      API_PORT: 8081
      FLASK_API_URL: http://flask-app:5000/api/data
    volumes:
      - ../gin-api:/app:ro             # Mount code for development
      - ./logs/gin:/app/logs
    depends_on:
      mariadb:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Python Flask App
  flask-app:
    build:
      context: ../flask-app            # Points to sibling directory
      dockerfile: Dockerfile
    container_name: flask-app
    environment:
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: ${DB_NAME}
      GIN_API_URL: http://gin-api:8081/api
      FLASK_ENV: production
      FLASK_APP: app.py
      SECRET_KEY: ${FLASK_SECRET_KEY}
    volumes:
      - ../flask-app:/app:ro           # Mount code for development
      - ./logs/flask:/var/log/flask
    depends_on:
      mariadb:
        condition: service_healthy
      gin-api:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  mariadb_data:
    driver: local
```

### **2. Environment File** (`pi-deployment/.env`)
```env
# Database
DB_ROOT_PASSWORD=ChangeThisStrongPassword123!
DB_NAME=appdb
DB_USER=appuser
DB_PASSWORD=AppUserPassword456!
DB_PORT=3306

# Applications
GIN_API_PORT=8081
FLASK_APP_PORT=5000
FLASK_SECRET_KEY=YourVerySecretKeyHereChangeMe!

# Timezone
TZ=America/New_York

# Networking
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443
MARIADB_EXTERNAL_PORT=3307

# Deployment
PODMAN_USER=pi
PROJECT_ROOT=/home/pi/projects
```

### **3. Nginx Configuration** (`pi-deployment/nginx/conf.d/app.conf`)
```nginx
upstream gin_backend {
    server gin-api:8081;
    keepalive 32;
}

upstream flask_backend {
    server flask-app:5000;
    keepalive 32;
}

server {
    listen 80;
    server_name _;
    access_log /var/log/nginx/app_access.log;
    error_log /var/log/nginx/app_error.log;

    # Gin API - REST endpoints
    location /api/v1/ {
        proxy_pass http://gin_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With";
        
        # Handle preflight
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With";
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type 'text/plain charset=UTF-8';
            add_header Content-Length 0;
            return 204;
        }
    }

    # Flask App - Web interface
    location / {
        proxy_pass http://flask_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Static files (if any)
    location /static/ {
        alias /usr/share/nginx/html/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### **4. Database Initialization** (`pi-deployment/db/init.sql`)
```sql
-- Create databases
CREATE DATABASE IF NOT EXISTS appdb;
CREATE DATABASE IF NOT EXISTS gin_db;
CREATE DATABASE IF NOT EXISTS flask_db;

-- Create application user with limited privileges
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'AppUserPassword456!';

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON appdb.* TO 'appuser'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON gin_db.* TO 'appuser'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON flask_db.* TO 'appuser'@'%';

-- Optional: Create separate users for each service
CREATE USER IF NOT EXISTS 'gin_user'@'%' IDENTIFIED BY 'GinPassword789!';
CREATE USER IF NOT EXISTS 'flask_user'@'%' IDENTIFIED BY 'FlaskPassword012!';

GRANT ALL PRIVILEGES ON gin_db.* TO 'gin_user'@'%';
GRANT ALL PRIVILEGES ON flask_db.* TO 'flask_user'@'%';

-- Create tables for appdb
USE appdb;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email)
);

CREATE TABLE IF NOT EXISTS api_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    service VARCHAR(50) NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status_code INT,
    response_time_ms INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_service (service),
    INDEX idx_created_at (created_at)
);

FLUSH PRIVILEGES;
```

### **5. Deployment Script** (`pi-deployment/scripts/deploy.sh`)
```bash
#!/bin/bash
# deploy.sh - One-command deployment

set -e  # Exit on error

echo "🚀 Starting Raspberry Pi Stack Deployment..."
echo "==========================================="

# Load environment
cd "$(dirname "$0")/.."
source .env 2>/dev/null || echo "⚠ .env file not found, using defaults"

# Update code
echo "📥 Updating code..."
cd ../gin-api && git pull --quiet || echo "⚠ Could not update gin-api"
cd ../flask-app && git pull --quiet || echo "⚠ Could not update flask-app"

# Build containers
echo "🔨 Building containers..."
podman-compose build --pull --no-cache

# Stop existing
echo "🛑 Stopping existing containers..."
podman-compose down --remove-orphans

# Start new
echo "▶ Starting containers..."
podman-compose up -d

# Wait for services
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Verify
echo "✅ Verifying deployment..."
podman-compose ps
echo ""
echo "📊 Service Status:"
echo "Nginx:     http://$(hostname -I | awk '{print $1}'):${NGINX_HTTP_PORT:-8080}"
echo "MariaDB:   localhost:${MARIADB_EXTERNAL_PORT:-3307} (external)"
echo "Gin API:   http://localhost:${GIN_API_PORT:-8081}/health"
echo "Flask App: http://localhost:${FLASK_APP_PORT:-5000}/health"
echo ""
echo "📝 Logs: podman-compose logs -f [service]"
echo "🛠️  Update single service: ./scripts/update-service.sh [service]"
```

## 🔧 **Application Dockerfiles**

### **Gin API Dockerfile** (`projects/gin-api/Dockerfile`)
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /gin-api ./cmd/main.go

# Final stage
FROM alpine:3.18
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /gin-api .
RUN adduser -D -u 1000 ginuser && chown ginuser:ginuser /app/gin-api
USER ginuser
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8081/health || exit 1
CMD ["./gin-api"]
```

### **Flask App Dockerfile** (`projects/flask-app/Dockerfile`)
```dockerfile
FROM python:3.11-slim
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Create non-root user
RUN useradd -m -u 1000 flaskuser && chown -R flaskuser:flaskuser /app
USER flaskuser

EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app", "--workers", "2", "--worker-class", "sync"]
```

## 🚀 **Setup Commands**

```bash
# 1. Create the structure
mkdir -p ~/projects
cd ~/projects

# 2. Clone or create your repos
# git clone your-gin-repo gin-api
# git clone your-flask-repo flask-app

# 3. Create deployment directory
mkdir -p pi-deployment/{nginx/conf.d,db,scripts,logs,configs/systemd}

# 4. Copy the config files above into pi-deployment/

# 5. Make scripts executable
chmod +x ~/projects/pi-deployment/scripts/*.sh

# 6. Set up auto-start
mkdir -p ~/.config/systemd/user/
cp ~/projects/pi-deployment/configs/systemd/podman-stack.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable podman-stack.service

# 7. Enable user lingering
sudo loginctl enable-linger $(whoami)

# 8. Deploy!
cd ~/projects/pi-deployment
./scripts/deploy.sh
```

## 🔗 **Service Communication Flow**

```
Client → Nginx (8080) → Flask App (5000) → Gin API (8081) → MariaDB (3306)
                    ↘→ Gin API (8081) → MariaDB (3306)
```

## 📊 **Key Features of This Structure**

1. **Separation of concerns**: Dev repos separate from deployment
2. **Rootless Podman**: All containers run as non-root users
3. **Health checks**: Each service monitors itself
4. **Centralized logging**: All logs in `pi-deployment/logs/`
5. **Easy updates**: Scripts for updating single services
6. **Auto-restart**: Systemd service for boot resilience
7. **Backup ready**: Database backups directory
8. **Environment config**: Sensitive data in `.env` file

This structure is production-ready while being simple enough for your Raspberry Pi. It balances security (rootless), maintainability (separate repos), and reliability (auto-restart).
