# CACMS Terraform — AWS Free Tier

Provisions the full CACMS infrastructure on AWS using free-tier eligible resources.

## Architecture

```
Browser (user)
      │ HTTP port 80
      ▼
┌─────────────────────────────────────────┐
│  Frontend EC2 — t2.micro (Ubuntu 22.04) │
│  Nginx serves Flutter Web (SPA)         │
│  /api/* proxied to backend private IP   │
│  Elastic IP: public entry point         │
└──────────────────┬──────────────────────┘
                   │ port 8000 (VPC internal only)
                   ▼
┌─────────────────────────────────────────┐
│  Backend EC2 — t2.micro (Ubuntu 22.04)  │
│  FastAPI + Uvicorn (systemd service)    │
│  Redis (apt, localhost only)            │
│  No Docker — runs directly on the OS   │
└──────────────────┬──────────────────────┘
                   │ port 5432 (VPC internal only)
                   ▼
┌─────────────────────────────────────────┐
│  RDS db.t3.micro — PostgreSQL 16        │
│  20 GB encrypted storage                │
│  Private subnets only (no public access)│
└─────────────────────────────────────────┘
```

## Security Group Chain

| Group | Inbound | From |
|-------|---------|------|
| `frontend-sg` | 80, 443 | `0.0.0.0/0` (internet) |
| `frontend-sg` | 22 | `ssh_allowed_cidr` |
| `backend-sg` | 8000 | `frontend-sg` only |
| `backend-sg` | 22 | `ssh_allowed_cidr` |
| `rds-sg` | 5432 | `backend-sg` only |

The backend API port (8000) and database port (5432) are **never exposed to the internet**.

## What Gets Created (17 resources)

```
VPC (10.0.0.0/16)
├── Public Subnet (10.0.1.0/24)
│   ├── Frontend EC2 + Elastic IP
│   └── Backend EC2 + Elastic IP
├── Private Subnet A (10.0.10.0/24)
├── Private Subnet B (10.0.11.0/24)
│   └── RDS db.t3.micro (PostgreSQL 16)
├── Security Group: frontend-sg
├── Security Group: backend-sg
└── Security Group: rds-sg
```

## Prerequisites

1. **AWS account** with free tier active
2. **AWS CLI** configured (`aws configure`)
3. **Terraform >= 1.6** ([download](https://developer.hashicorp.com/terraform/downloads))
4. **EC2 Key Pair** in AWS Console → EC2 → Key Pairs → Create
   - Save `.pem` to `~/.ssh/cacms-key.pem`
5. **Public GitHub repo** — the bootstrap scripts clone via HTTPS

## Quick Start

```bash
cd terraform

# 1. Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit: key pair name, RDS password, JWT secret, superadmin token, git URL

# 2. Initialize
terraform init

# 3. Preview
terraform plan

# 4. Deploy (~20-25 min — RDS + Flutter build are the slow parts)
terraform apply
```

## After Apply

Terraform prints these outputs:

| Output | Value |
|--------|-------|
| `app_url` | `http://FRONTEND_IP` — open in browser |
| `frontend_public_ip` | Frontend EC2 Elastic IP |
| `backend_public_ip` | Backend EC2 Elastic IP (SSH only) |
| `api_health_url` | `http://BACKEND_IP:8000/health` (SSH tunnel to test) |
| `ssh_frontend` | SSH command for frontend EC2 |
| `ssh_backend` | SSH command for backend EC2 |
| `backend_logs` | Stream live API logs |
| `frontend_logs` | Watch Flutter build progress |

### Monitor bootstrap progress

```bash
# Frontend (Flutter build takes 15-20 min)
ssh -i ~/.ssh/cacms-key.pem ubuntu@FRONTEND_IP \
  'tail -f /var/log/cacms-frontend-bootstrap.log'

# Backend
ssh -i ~/.ssh/cacms-key.pem ubuntu@BACKEND_IP \
  'tail -f /var/log/cacms-backend-bootstrap.log'

# Live API logs (after backend is up)
ssh -i ~/.ssh/cacms-key.pem ubuntu@BACKEND_IP \
  'sudo journalctl -u cacms-api -f'
```

### Verify deployment

```bash
# Backend health (via SSH tunnel — port 8000 is not public)
ssh -i ~/.ssh/cacms-key.pem ubuntu@BACKEND_IP \
  'curl -s http://localhost:8000/health'
# Expected: {"status":"ok","checks":{"database":"ok","redis":"ok"}}

# Frontend (public — open in browser)
curl http://FRONTEND_IP
# Expected: Flutter Web HTML page
```

### Create the first clinic owner

```bash
# Via the public API endpoint (register-clinic is open)
curl -X POST http://FRONTEND_IP/api/v1/auth/register-clinic \
  -H "Content-Type: application/json" \
  -d '{"clinic_name":"My Clinic","owner_username":"owner","owner_password":"StrongPass123!"}'
```

## Updating the App

### Backend update (code change)

```bash
ssh -i ~/.ssh/cacms-key.pem ubuntu@BACKEND_IP
cd ~/cacms
git pull origin main
.venv/bin/pip install -e ".[dev]"          # if dependencies changed
set -a && source .env.production && set +a
.venv/bin/alembic upgrade head             # if migrations changed
sudo systemctl restart cacms-api
sudo systemctl status cacms-api
```

### Frontend update (Flutter Web rebuild)

```bash
ssh -i ~/.ssh/cacms-key.pem ubuntu@FRONTEND_IP
cd ~/cacms/cacms_flutter
git pull origin main
/opt/flutter/bin/flutter pub get
/opt/flutter/bin/flutter build web \
  --dart-define=BACKEND_URL=http://BACKEND_PRIVATE_IP:8000 \
  --release
sudo cp -r build/web/. /var/www/cacms/
sudo chown -R www-data:www-data /var/www/cacms
sudo systemctl reload nginx
```

## Teardown

```bash
# WARNING: Destroys everything including the RDS database and all data
# Take a snapshot first if you need the data:
# aws rds create-db-snapshot --db-instance-identifier cacms-db \
#   --db-snapshot-identifier cacms-backup --region ap-south-1

terraform destroy
```

## Cost (AWS Free Tier — First 12 Months)

| Resource | Free Tier | Monthly After |
|----------|-----------|---------------|
| EC2 t2.micro x2 | 750 hrs/month total | ~$17/month |
| RDS db.t3.micro | 750 hrs/month + 20 GB | ~$15/month |
| EBS 20 GB x2 | 30 GB/month | ~$4/month |
| Elastic IP x2 | Free when attached | $0.005/hr if detached |
| Data transfer | 100 GB/month | $0.09/GB |
| **Total year 1** | **~$0** | **~$36/month** |

> Note: Two t2.micro instances together use 1,500 hrs/month but the free tier
> only covers 750 hrs/month total. After the first month you'll be charged for
> the second instance (~$8.50/month). Consider stopping one when not testing.

## Key Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider config |
| `vpc.tf` | VPC, subnets, routing |
| `security_groups.tf` | Frontend, backend, RDS security groups |
| `ec2.tf` | Both EC2 instances + EIPs + CORS update |
| `rds.tf` | PostgreSQL RDS instance |
| `variables.tf` | All input variables |
| `outputs.tf` | Post-apply outputs |
| `backend_user_data.sh.tpl` | Backend bootstrap (Python, Redis, systemd) |
| `frontend_user_data.sh.tpl` | Frontend bootstrap (Flutter build, Nginx) |
| `terraform.tfvars.example` | Template for your secrets |
