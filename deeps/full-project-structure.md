# 📁 **Complete Project Structure Diagram**

```
/home/jsellers0/                                      # User home directory
├── data -> /mnt/rockwillow/data                     # Symlink to external drive data
├── projects -> /mnt/rockwillow/projects             # Symlink to external drive projects
└── rockwillow.code-workspace                        # VS Code workspace file

/mnt/rockwillow/                                     # External drive mount point
├── data/                                            # Application data (NOT in Git)
│   ├── mariadb/                                     # MariaDB database files
│   │   ├── ibdata1                                 # Database tablespace
│   │   ├── ib_logfile0                             # Transaction logs
│   │   ├── mysql/                                  # System tables
│   │   └── appdb/                                  # Application database
│   ├── logs/                                       # Application logs
│   │   ├── nginx/                                  # Nginx access/error logs
│   │   ├── gin-api/                                # Gin API logs
│   │   └── flask-app/                              # Flask app logs
│   ├── backups/                                    # Database backups
│   │   ├── full-20240101.sql                       # Full database dumps
│   │   └── schema-20240101.sql                     # Schema-only backups
│   └── containers/                                 # Podman container storage
│       └── storage/                                # Podman-managed
│           ├── libpod/                             # Podman database
│           ├── overlay-images/                     # Container images
│           ├── overlay-containers/                 # Container metadata
│           └── overlay/                            # Container layers
│
└── projects/                                       # Git repositories (code)
    ├── rw_deploy/                                  # Container deployment config
    │   ├── docker-compose.yml                      # Main orchestration file
    │   ├── .env.example                            # Environment template
    │   ├── .env                                    # Local env (in .gitignore)
    │   ├── nginx/
    │   │   ├── conf.d/
    │   │   │   └── app.conf                        # Nginx configuration
    │   │   ├── ssl/                                # SSL certificates
    │   │   └── html/                               # Static files
    │   ├── db/
    │   │   ├── init.sql                            # Database schema
    │   │   └── seeds/                              # Sample/test data (optional)
    │   ├── scripts/
    │   │   ├── deploy.sh                           # Deployment script
    │   │   ├── backup-db.sh                        # Backup script
    │   │   └── update-service.sh                   # Service updater
    │   ├── configs/
    │   │   └── systemd/
    │   │       └── podman-stack.service            # Auto-start service
    │   ├── LICENSE                                 # MIT License
    │   └── README.md                               # Documentation
    │
    ├── rw_budget_api/                              # Go Gin REST API
    │   ├── cmd/
    │   │   └── main.go                             # Application entry point
    │   ├── internal/
    │   │   ├── handlers/                           # HTTP handlers
    │   │   ├── models/                             # Data models
    │   │   └── database/                           # DB connection logic
    │   ├── go.mod                                  # Go module definition
    │   ├── go.sum                                  # Dependency checksums
    │   ├── Dockerfile                              # Container build file
    │   └── .env.example                            # Environment template
    │
    └── rw_budget/                                  # Python Flask application
        ├── app/
        │   ├── __init__.py                         # Flask app factory
        │   ├── routes.py                           # Route definitions
        │   ├── models.py                           # SQLAlchemy models
        │   └── templates/                          # HTML templates (if any)
        ├── requirements.txt                        # Python dependencies
        ├── Dockerfile                              # Container build file
        ├── app.py                                  # Application entry point
        └── .env.example                            # Environment template
```

# 🔗 **Symlink Relationships**

```bash
# From /home/jsellers0/ directory:
ls -la
# data -> /mnt/rockwillow/data
# projects -> /mnt/rockwillow/projects

# Access paths:
cd ~/projects/rw_deploy                 # Goes to /mnt/rockwillow/projects/rw_deploy
cd ~/data/mariadb                       # Goes to /mnt/rockwillow/data/mariadb
```

# 📊 **Container Volume Mapping**

| Container | Volume Mount | Purpose |
|-----------|--------------|---------|
| **MariaDB** | `~/data/mariadb:/var/lib/mysql:Z` | Database data files |
| **MariaDB** | `~/projects/rw_deploy/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro` | Schema initialization |
| **MariaDB** | `~/data/backups:/backups` | Backup directory |
| **Nginx** | `~/projects/rw_deploy/nginx/conf.d:/etc/nginx/conf.d:ro` | Configuration files |
| **Nginx** | `~/data/logs/nginx:/var/log/nginx` | Access/error logs |
| **Gin API** | `~/projects/rw_budget_api:/app:ro` | Source code (read-only) |
| **Gin API** | `~/data/logs/gin-api:/app/logs` | Application logs |
| **Flask App** | `~/projects/rw_budget:/app:ro` | Source code (read-only) |
| **Flask App** | `~/data/logs/flask-app:/var/log/flask` | Application logs |

# 🐳 **docker-compose.yml Key Paths**

```yaml
services:
  mariadb:
    volumes:
      - /home/jsellers0/data/mariadb:/var/lib/mysql:Z
      - /home/jsellers0/projects/rw_deploy/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
  
  nginx:
    volumes:
      - /home/jsellers0/projects/rw_deploy/nginx/conf.d:/etc/nginx/conf.d:ro
  
  rw_budget_api:
    build:
      context: /home/jsellers0/projects/rw_budget_api
  
  rw_budget:
    build:
      context: /home/jsellers0/projects/rw_budget
```

# 🎯 **Key Principles of This Structure**

1. **Separation of Concerns**
   - **Code**: `~/projects/` (Git repositories)
   - **Data**: `~/data/` (Runtime data, NOT in Git)
   - **Config**: `rw_deploy/` (Deployment configuration)

2. **External Drive Optimization**
   - All write-heavy operations on external drive
   - SD card protected from excessive writes
   - Large data volumes on spacious external storage

3. **Git Hygiene**
   - Only code and config in repositories
   - No database files, logs, or backups in Git
   - Clean `.gitignore` files in each repo

4. **Portability**
   - Symlinks make paths user-relative
   - Easy to move to another system
   - Clear separation for backups

# 📝 **Quick Navigation Commands**

```bash
# Navigate to deployment config
cd ~/projects/rw_deploy

# Navigate to API code
cd ~/projects/rw_budget_api

# Navigate to Flask app
cd ~/projects/rw_budget

# Check database files
ls -lh ~/data/mariadb/

# View logs
ls -lh ~/data/logs/

# Start/stop stack
cd ~/projects/rw_deploy
podman-compose up -d
podman-compose down
```

This structure gives you a clean, scalable, and maintainable setup that follows best practices while being practical for your Raspberry Pi homelab.