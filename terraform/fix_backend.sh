#!/bin/bash
# Fix script - run on backend EC2 to complete the failed bootstrap
set -euo pipefail
exec > >(tee /var/log/cacms-backend-fix.log | logger -t cacms-fix) 2>&1

echo "=== Fix started at $(date) ==="

# Install missing packages (python3 is already available on Ubuntu 22.04)
apt-get install -y python3 python3-venv python3-dev python3-pip build-essential libpq-dev

APP_DIR="/home/ubuntu/cacms"

# Clone repo if not already done
if [ ! -d "$APP_DIR" ]; then
  git clone --branch main https://github.com/rounakshankar/appointment-manangement.git "$APP_DIR"
  chown -R ubuntu:ubuntu "$APP_DIR"
fi

# Create venv and install dependencies
cd "$APP_DIR"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e ".[dev]"
.venv/bin/pip install "aiosmtplib>=3.0.0"

# Write .env.production if not already written
if [ ! -f "$APP_DIR/.env.production" ]; then
  echo "ERROR: .env.production not found - run write_env.sh first"
  exit 1
fi

# Run migrations
sudo -u ubuntu bash -c "cd $APP_DIR && .venv/bin/alembic upgrade head"
echo "Migrations complete"

# Create systemd service
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

echo "Waiting for API..."
for i in $(seq 1 20); do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "API is healthy!"
    break
  fi
  echo "Attempt $i/20..."
  sleep 5
done

echo "=== Fix complete at $(date) ==="
