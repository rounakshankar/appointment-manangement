#!/bin/bash
# CACMS Frontend EC2 bootstrap
# Builds Flutter Web and serves it via Nginx
# Nginx also proxies /api/* to the backend EC2
set -euo pipefail
exec > >(tee /var/log/cacms-frontend-bootstrap.log | logger -t cacms-frontend) 2>&1

echo "=== CACMS Frontend Bootstrap started at $(date) ==="

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git ca-certificates unzip nginx

# ---------------------------------------------------------------------------
# 2. Install Flutter
# ---------------------------------------------------------------------------
FLUTTER_VERSION="3.22.0"
cd /opt
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
tar xf flutter.tar.xz
rm flutter.tar.xz
chown -R ubuntu:ubuntu /opt/flutter
export PATH="$PATH:/opt/flutter/bin"
echo 'export PATH="$PATH:/opt/flutter/bin"' >> /home/ubuntu/.bashrc

# Flutter pre-cache web artifacts
sudo -u ubuntu /opt/flutter/bin/flutter precache --web
sudo -u ubuntu /opt/flutter/bin/flutter config --enable-web

# ---------------------------------------------------------------------------
# 3. Clone the repository
# ---------------------------------------------------------------------------
APP_DIR="/home/ubuntu/cacms"
git clone --branch ${git_branch} ${git_repo_url} "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

# ---------------------------------------------------------------------------
# 4. Build Flutter Web
# ---------------------------------------------------------------------------
cd "$APP_DIR/cacms_flutter"
sudo -u ubuntu /opt/flutter/bin/flutter pub get
sudo -u ubuntu /opt/flutter/bin/flutter build web \
  --dart-define=BACKEND_URL=http://${backend_private_ip}:8000 \
  --release

echo "Flutter Web build complete"

# ---------------------------------------------------------------------------
# 5. Deploy built files to Nginx web root
# ---------------------------------------------------------------------------
mkdir -p /var/www/cacms
cp -r "$APP_DIR/cacms_flutter/build/web/." /var/www/cacms/
chown -R www-data:www-data /var/www/cacms

# ---------------------------------------------------------------------------
# 6. Configure Nginx
# ---------------------------------------------------------------------------
cat > /etc/nginx/sites-available/cacms << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    root /var/www/cacms;
    index index.html;

    # Flutter Web - serve index.html for all routes (SPA routing)
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API calls to backend EC2
    # Frontend calls /api/v1/... -> backend:8000/v1/...
    location /api/ {
        rewrite ^/api/(.*) /$1 break;
        proxy_pass http://${backend_private_ip}:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection '';
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }

    # SSE endpoints need buffering disabled
    location /api/v1/events/ {
        rewrite ^/api/(.*) /$1 break;
        proxy_pass http://${backend_private_ip}:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        chunked_transfer_encoding on;
    }

    location /api/v1/public/events/ {
        rewrite ^/api/(.*) /$1 break;
        proxy_pass http://${backend_private_ip}:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        chunked_transfer_encoding on;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/cacms /etc/nginx/sites-enabled/cacms
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "=== CACMS Frontend Bootstrap completed at $(date) ==="
echo "Frontend: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
