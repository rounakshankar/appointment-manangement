#!/bin/bash
# CACMS Backend EC2 bootstrap
# Installs Python 3.12, Redis, FastAPI via systemd — no Docker
set -euo pipefail
exec > >(tee /var/log/cacms-backend-bootstrap.log | logger -t cacms-backend) 2>&1

echo "=== CACMS Backend Bootstrap started at $(date) ==="

# ---------------------------------------------------------------------------
# 1. System update and dependencies
# ---------------------------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  curl git ca-certificates gnupg \
  python3 python3-venv python3-dev \
  python3-pip build-essential libpq-dev \
  redis-server postgresql-client-14

# ---------------------------------------------------------------------------
# 2. Configure and start Redis
# ---------------------------------------------------------------------------
# Bind Redis to localhost only (not exposed externally)
sed -i 's/^bind 127.0.0.1 -::1/bind 127.0.0.1/' /etc/redis/redis.conf
systemctl enable redis-server
systemctl start redis-server
echo "Redis started: $(redis-cli ping)"

# ---------------------------------------------------------------------------
# 3. Clone the repository
# ---------------------------------------------------------------------------
APP_DIR="/home/ubuntu/cacms"
git clone --branch ${git_branch} ${git_repo_url} "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

# ---------------------------------------------------------------------------
# 4. Create Python virtual environment and install dependencies
# ---------------------------------------------------------------------------
cd "$APP_DIR"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e ".[dev]"
# Install aiosmtplib explicitly (added in Phase 1 SaaS)
.venv/bin/pip install aiosmtplib>=3.0.0

# ---------------------------------------------------------------------------
# 5. Write .env.production
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env.production" << 'ENVEOF'
ENVIRONMENT=production
DATABASE_URL=postgresql+asyncpg://${rds_username}:${rds_password}@${rds_endpoint}:5432/${rds_db_name}
JWT_SECRET=${jwt_secret}
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60
CORS_ORIGINS=${cors_origins}
OTP_TTL_SECONDS=300
AUTH_RATE_LIMIT=10/minute
BACKUP_ENCRYPTION_KEY=${backup_encryption_key}
BACKUP_DIR=/var/backups/cacms
REDIS_URL=redis://127.0.0.1:6379/0
SENTRY_DSN=${sentry_dsn}
SENTRY_TRACES_SAMPLE_RATE=0.1
SUPERADMIN_TOKEN=${superadmin_token}
ENVEOF

chmod 600 "$APP_DIR/.env.production"
chown ubuntu:ubuntu "$APP_DIR/.env.production"

# ---------------------------------------------------------------------------
# 6. Create backup directory
# ---------------------------------------------------------------------------
mkdir -p /var/backups/cacms
chown ubuntu:ubuntu /var/backups/cacms

# ---------------------------------------------------------------------------
# 7. Run Alembic migrations
# ---------------------------------------------------------------------------
cd "$APP_DIR"
sudo -u ubuntu bash -c "cd $APP_DIR && .venv/bin/alembic upgrade head"
echo "Migrations complete"

# ---------------------------------------------------------------------------
# 8. Create systemd service for FastAPI
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/cacms-api.service << 'SVCEOF'
[Unit]
Description=CACMS FastAPI Backend
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cacms
EnvironmentFile=/home/ubuntu/cacms/.env.production
ExecStart=/home/ubuntu/cacms/.venv/bin/uvicorn cacms.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cacms-api

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable cacms-api
systemctl start cacms-api

# ---------------------------------------------------------------------------
# 9. Wait for API to be healthy
# ---------------------------------------------------------------------------
echo "Waiting for API to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "API is healthy after $i attempts"
    break
  fi
  echo "Attempt $i/30 - waiting 10s..."
  sleep 10
done

echo "=== CACMS Backend Bootstrap completed at $(date) ==="
echo "API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000/health"
