#!/bin/bash
# CACMS EC2 bootstrap script
# Runs once on first boot via cloud-init (user_data)
# Logs to /var/log/cacms-bootstrap.log

set -euo pipefail
exec > >(tee /var/log/cacms-bootstrap.log | logger -t cacms-bootstrap) 2>&1

echo "=== CACMS Bootstrap started at $(date) ==="

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git ca-certificates gnupg postgresql-client-14

# ---------------------------------------------------------------------------
# 2. Install Docker
# ---------------------------------------------------------------------------
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Enable Docker on boot
systemctl enable docker
systemctl start docker

echo "Docker installed: $(docker --version)"

# ---------------------------------------------------------------------------
# 3. Clone the CACMS repository
# ---------------------------------------------------------------------------
APP_DIR="/home/ubuntu/cacms"

if [ -d "$APP_DIR" ]; then
  echo "Repo already exists, pulling latest..."
  cd "$APP_DIR"
  git fetch origin
  git checkout ${git_branch}
  git pull origin ${git_branch}
else
  echo "Cloning repo..."
  git clone --branch ${git_branch} ${git_repo_url} "$APP_DIR"
fi

chown -R ubuntu:ubuntu "$APP_DIR"

# ---------------------------------------------------------------------------
# 4. Write .env.production
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env.production" << 'ENVEOF'
ENVIRONMENT=${environment}

# Database (RDS)
DATABASE_URL=${database_url}

# Auth
JWT_SECRET=${jwt_secret}
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60

# CORS — updated by Terraform null_resource after EIP is assigned
CORS_ORIGINS=${cors_origins_placeholder}

# OTP
OTP_TTL_SECONDS=300

# Rate limiting
AUTH_RATE_LIMIT=10/minute

# Backups
BACKUP_ENCRYPTION_KEY=${backup_encryption_key}
BACKUP_DIR=/var/backups/cacms

# Redis (sidecar — do not change)
REDIS_URL=redis://redis:6379/0

# Monitoring
SENTRY_DSN=${sentry_dsn}
SENTRY_TRACES_SAMPLE_RATE=0.1
ENVEOF

chmod 600 "$APP_DIR/.env.production"
chown ubuntu:ubuntu "$APP_DIR/.env.production"

echo ".env.production written"

# ---------------------------------------------------------------------------
# 5. Create backup directory
# ---------------------------------------------------------------------------
mkdir -p /var/backups/cacms
chown ubuntu:ubuntu /var/backups/cacms

# ---------------------------------------------------------------------------
# 6. Install and configure Nginx
# ---------------------------------------------------------------------------
apt-get install -y nginx

# Copy CACMS Nginx config
cp "$APP_DIR/nginx/cacms.conf" /etc/nginx/sites-available/cacms
ln -sf /etc/nginx/sites-available/cacms /etc/nginx/sites-enabled/cacms
rm -f /etc/nginx/sites-enabled/default

# Test config syntax (will fail gracefully if cert not yet present)
nginx -t 2>/dev/null || echo "Nginx config test skipped (TLS cert not yet provisioned)"

systemctl enable nginx
systemctl start nginx || true

echo "Nginx installed and enabled"

# ---------------------------------------------------------------------------
# 7. Install Certbot (Let's Encrypt)
# ---------------------------------------------------------------------------
apt-get install -y certbot python3-certbot-nginx

echo "Certbot installed — run 'certbot --nginx -d yourdomain.com' after DNS is configured"

# ---------------------------------------------------------------------------
# 8. Build and start the application
# ---------------------------------------------------------------------------
cd "$APP_DIR"

# Run as ubuntu user (docker group)
sudo -u ubuntu docker compose -f docker-compose.aws.yml --env-file .env.production build --no-cache
sudo -u ubuntu docker compose -f docker-compose.aws.yml --env-file .env.production up -d

echo "Docker containers started"

# ---------------------------------------------------------------------------
# 9. Wait for API to be healthy, then run migrations
# ---------------------------------------------------------------------------
echo "Waiting for API to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "API is healthy after $i attempts"
    break
  fi
  echo "Attempt $i/30 — waiting 10s..."
  sleep 10
done

# Migrations are run automatically by the Dockerfile CMD (alembic upgrade head)
# This is just a verification step
echo "Checking migration status..."
sudo -u ubuntu docker compose -f docker-compose.aws.yml --env-file .env.production \
  exec -T api alembic current || echo "Migration check skipped (API may still be starting)"

# ---------------------------------------------------------------------------
# 10. Set up daily backup cron job
# ---------------------------------------------------------------------------
CRON_JOB="0 2 * * * cd $APP_DIR && docker compose -f docker-compose.aws.yml --env-file .env.production exec -T api python scripts/backup_postgres.py >> /var/log/cacms-backup.log 2>&1"

(crontab -u ubuntu -l 2>/dev/null; echo "$CRON_JOB") | crontab -u ubuntu -

echo "Daily backup cron job set (runs at 2:00 AM UTC)"

# ---------------------------------------------------------------------------
# 11. Done
# ---------------------------------------------------------------------------
echo "=== CACMS Bootstrap completed at $(date) ==="
echo "API should be available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000/health"
