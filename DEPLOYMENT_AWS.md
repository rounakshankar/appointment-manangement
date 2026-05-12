# CACMS — AWS Free Tier Deployment Guide

## Architecture

```
Internet
    │
    ▼
EC2 t2.micro (Ubuntu 22.04)
├── Docker: cacms-api (port 8000)
├── Docker: redis:7-alpine (internal only)
└── Nginx (optional, for HTTPS — recommended)
    │
    ▼ (private VPC subnet, port 5432)
RDS db.t3.micro (PostgreSQL 16)
```

**Free tier limits:**
- EC2 t2.micro: 750 hours/month free for 12 months
- RDS db.t3.micro: 750 hours/month + 20 GB storage free for 12 months
- Data transfer: 100 GB/month outbound free

---

## Step 1 — AWS RDS Setup

### Create RDS PostgreSQL instance

1. Go to AWS Console → RDS → Create database
2. Settings:
   - Engine: **PostgreSQL 16**
   - Template: **Free tier**
   - DB instance identifier: `cacms-db`
   - Master username: `cacms_user`
   - Master password: generate a strong password (save it)
   - Instance class: `db.t3.micro`
   - Storage: 20 GB gp2 (free tier max)
   - **Public access: NO** (EC2 only)
   - VPC: same VPC as your EC2 instance
3. Create a security group for RDS:
   - Inbound: TCP 5432 — source = EC2 security group (not 0.0.0.0/0)
4. Note the **RDS endpoint** after creation (looks like `cacms-db.xxxx.us-east-1.rds.amazonaws.com`)

### Create the database

After RDS is running, connect from EC2:
```bash
psql -h YOUR_RDS_ENDPOINT -U cacms_user -d postgres
CREATE DATABASE cacms;
\q
```

---

## Step 2 — EC2 Setup

### Launch EC2 instance

1. Go to AWS Console → EC2 → Launch instance
2. Settings:
   - AMI: **Ubuntu Server 22.04 LTS** (free tier eligible)
   - Instance type: **t2.micro**
   - Key pair: create or use existing (save the .pem file)
   - Security group inbound rules:
     - TCP 22 — your IP only (SSH)
     - TCP 8000 — 0.0.0.0/0 (API access; restrict later with Nginx + HTTPS)
3. Launch and note the **Public IPv4 address**

### Install Docker on EC2

```bash
ssh -i your-key.pem ubuntu@YOUR_EC2_IP

# Update and install Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add ubuntu user to docker group (no sudo needed)
sudo usermod -aG docker ubuntu
newgrp docker

# Verify
docker --version
docker compose version
```

---

## Step 3 — Deploy CACMS

### Copy files to EC2

From your local machine:
```bash
# Copy the repo (or just the needed files)
scp -i your-key.pem -r . ubuntu@YOUR_EC2_IP:~/cacms/

# Or use git on EC2
ssh -i your-key.pem ubuntu@YOUR_EC2_IP
git clone https://github.com/YOUR_REPO/cacms.git
cd cacms
```

### Create production .env file on EC2

```bash
cd ~/cacms
cp .env.example .env.production
nano .env.production
```

Fill in these values:
```dotenv
ENVIRONMENT=production

# RDS connection (replace with your actual RDS endpoint and password)
DATABASE_URL=postgresql+asyncpg://cacms_user:YOUR_RDS_PASSWORD@YOUR_RDS_ENDPOINT:5432/cacms

# Generate with: python3 -c "import secrets; print(secrets.token_hex(32))"
JWT_SECRET=GENERATE_A_STRONG_SECRET_HERE

# Your EC2 public IP or domain (Flutter app will connect to this)
# If using IP directly:
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP:8000
# If you have a domain with HTTPS:
# CORS_ORIGINS=https://yourdomain.com

# Backup encryption key (generate with: python3 -c "import secrets; print(secrets.token_hex(32))")
BACKUP_ENCRYPTION_KEY=GENERATE_A_STRONG_KEY_HERE
BACKUP_DIR=/var/backups/cacms

AUTH_RATE_LIMIT=10/minute
OTP_TTL_SECONDS=300
JWT_EXPIRE_MINUTES=60

# Optional: Sentry for error tracking
SENTRY_DSN=
SENTRY_TRACES_SAMPLE_RATE=0.1
```

### Build and start

```bash
cd ~/cacms

# Build the image
docker compose -f docker-compose.aws.yml --env-file .env.production build

# Start (detached)
docker compose -f docker-compose.aws.yml --env-file .env.production up -d

# Check logs
docker compose -f docker-compose.aws.yml logs -f api

# Verify health
curl http://localhost:8000/health
```

### Create the first owner account

```bash
# Run the seed script inside the running container
docker compose -f docker-compose.aws.yml --env-file .env.production exec api \
  python scripts/create_owner.py \
  --username owner \
  --password "YourStrongPassword123!" \
  --clinic-name "Your Clinic Name"
```

---

## Step 4 — Flutter App Build for AWS

Build the Flutter APK pointing to your EC2 instance:

```bash
# From your local machine (not EC2)
cd cacms_flutter

# Android APK
flutter build apk --dart-define=BACKEND_URL=http://YOUR_EC2_PUBLIC_IP:8000

# APK location: build/app/outputs/flutter-apk/app-release.apk
```

Distribute the APK to clinic staff. They install it and it connects directly to your EC2 backend.

---

## Step 5 — Verify Connection

Test from your phone/browser:
```
http://YOUR_EC2_PUBLIC_IP:8000/health
→ {"status": "ok", ...}

http://YOUR_EC2_PUBLIC_IP:8000/docs
→ Swagger UI (disable in production later)
```

---

## Step 6 — HTTPS with Nginx + Let's Encrypt

HTTPS is required for production. The Terraform bootstrap automatically installs Nginx and Certbot on the EC2 instance. You just need to configure DNS and run Certbot once.

### 6.1 — Configure DNS

Point your domain's A record to the EC2 Elastic IP:

```
Type: A
Name: @ (or api, or whatever subdomain you want)
Value: YOUR_EC2_ELASTIC_IP
TTL: 300
```

Wait for DNS to propagate (usually 5–15 minutes). Verify with:
```bash
dig +short yourdomain.com
# Should return your EC2 Elastic IP
```

### 6.2 — Update Nginx config with your domain

SSH into EC2 and replace the `<domain>` placeholder in the Nginx config:

```bash
ssh -i your-key.pem ubuntu@YOUR_EC2_IP

# Replace <domain> with your actual domain
sudo sed -i 's/<domain>/yourdomain.com/g' /etc/nginx/sites-available/cacms
sudo sed -i 's/server_name _;/server_name yourdomain.com;/g' /etc/nginx/sites-available/cacms

# Test config
sudo nginx -t
```

### 6.3 — Obtain TLS certificate with Certbot

```bash
# Issue certificate (Certbot will auto-configure Nginx)
sudo certbot --nginx -d yourdomain.com

# Follow the prompts:
# - Enter your email for renewal notifications
# - Agree to terms of service
# - Choose whether to redirect HTTP to HTTPS (choose yes)

# Verify certificate
sudo certbot certificates
```

### 6.4 — Set up automatic certificate renewal

Certbot installs a systemd timer automatically. Verify it's active:

```bash
sudo systemctl status certbot.timer
# Should show: active (waiting)

# Test renewal dry-run
sudo certbot renew --dry-run
```

Certificates auto-renew 30 days before expiry. No manual action needed.

### 6.5 — Update CORS and restart

```bash
# Update CORS_ORIGINS in .env.production
cd ~/cacms
sed -i 's|CORS_ORIGINS=.*|CORS_ORIGINS=https://yourdomain.com|' .env.production

# Restart API to pick up new CORS setting
docker compose -f docker-compose.aws.yml --env-file .env.production up -d --force-recreate api

# Reload Nginx
sudo systemctl reload nginx
```

### 6.6 — Rebuild Flutter app with HTTPS URL

```bash
# From your local machine
flutter build apk --dart-define=BACKEND_URL=https://yourdomain.com
```

### 6.7 — Verify HTTPS is working

```bash
# From your local machine or browser
curl https://yourdomain.com/health
# → {"status": "ok", ...}

# Verify HTTP redirects to HTTPS
curl -I http://yourdomain.com/health
# → HTTP/1.1 301 Moved Permanently
# → Location: https://yourdomain.com/health
```

---

## Maintenance Commands

```bash
# View logs
docker compose -f docker-compose.aws.yml logs -f api

# Restart API
docker compose -f docker-compose.aws.yml restart api

# Pull latest code and redeploy
git pull
docker compose -f docker-compose.aws.yml --env-file .env.production build api
docker compose -f docker-compose.aws.yml --env-file .env.production up -d

# Run database migrations manually
docker compose -f docker-compose.aws.yml --env-file .env.production exec api alembic upgrade head

# Manual backup
docker compose -f docker-compose.aws.yml --env-file .env.production exec api \
  python scripts/backup_postgres.py

# Check backup status
curl -H "Authorization: Bearer YOUR_TOKEN" http://YOUR_EC2_IP:8000/v1/ops/backup-status
```

---

## Security Checklist Before Going Live

- [ ] `JWT_SECRET` is a random 64-char hex string (not the example value)
- [ ] `BACKUP_ENCRYPTION_KEY` is set
- [ ] RDS is NOT publicly accessible (VPC only)
- [ ] EC2 SSH port 22 is restricted to your IP only
- [ ] `CORS_ORIGINS` contains only your actual domain/IP (no wildcards)
- [ ] `allow_origin_regex` is removed from `main.py` ✅ (already done)
- [ ] Swagger UI disabled in production (add `docs_url=None` to FastAPI() if needed)
- [ ] First owner account created with a strong password
- [ ] Default beta credentials (`admin123`) are NOT in the users table
- [ ] Daily backup is scheduled (cron job or AWS EventBridge)

---

## Cost Estimate (AWS Free Tier — First 12 Months)

| Service | Free Tier | After Free Tier |
|---|---|---|
| EC2 t2.micro | 750 hrs/month free | ~$8.50/month |
| RDS db.t3.micro | 750 hrs/month + 20GB free | ~$15/month |
| Data transfer | 100 GB/month free | $0.09/GB |
| **Total year 1** | **~$0** | **~$25/month** |

For a small clinic pilot, this is essentially free for the first year.
