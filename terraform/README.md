# CACMS Terraform — AWS Free Tier

Provisions the full CACMS infrastructure on AWS using free-tier eligible resources.

## What Gets Created

```
AWS Account
└── VPC (10.0.0.0/16)
    ├── Public Subnet (10.0.1.0/24)  ← EC2 lives here
    │   └── EC2 t2.micro (Ubuntu 22.04)
    │       ├── Docker: cacms-api (port 8000)
    │       ├── Docker: redis:7-alpine (internal)
    │       └── Elastic IP (stable public IP)
    ├── Private Subnet A (10.0.10.0/24)  ← RDS lives here
    ├── Private Subnet B (10.0.11.0/24)  ← RDS subnet group (2 AZs required)
    │   └── RDS db.t3.micro (PostgreSQL 16, 20 GB, encrypted)
    ├── Security Group: ec2-sg  (SSH from your IP, port 8000 public)
    └── Security Group: rds-sg  (port 5432 from EC2 only)
```

## Prerequisites

1. **AWS account** with free tier active
2. **AWS CLI** installed and configured (`aws configure`)
3. **Terraform >= 1.6** installed ([download](https://developer.hashicorp.com/terraform/downloads))
4. **EC2 Key Pair** created in AWS Console → EC2 → Key Pairs → Create
   - Download the `.pem` file and save to `~/.ssh/cacms-key.pem`
   - `chmod 400 ~/.ssh/cacms-key.pem`
5. **Your public IP** — run `curl ifconfig.me`

## Quick Start

```bash
# 1. Enter the terraform directory
cd terraform

# 2. Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (key pair name, IP, secrets, git URL)

# 3. Initialize Terraform
terraform init

# 4. Preview what will be created
terraform plan

# 5. Deploy (takes ~10-15 minutes — RDS takes the longest)
terraform apply

# 6. Note the outputs:
#    ec2_public_ip       → your server's IP
#    api_health_url      → verify deployment
#    flutter_build_command → build your APK
#    ssh_command         → connect to EC2
#    seed_owner_command  → create first clinic owner
```

## After Apply

### Verify the deployment

```bash
# Check health (may take 3-5 minutes for bootstrap to complete)
curl http://YOUR_EC2_IP:8000/health
# Expected: {"status": "ok", ...}

# Watch bootstrap logs
ssh -i ~/.ssh/cacms-key.pem ubuntu@YOUR_EC2_IP 'tail -f /var/log/cacms-bootstrap.log'
```

### Create the first clinic owner

```bash
ssh -i ~/.ssh/cacms-key.pem ubuntu@YOUR_EC2_IP \
  'cd ~/cacms && docker compose -f docker-compose.aws.yml --env-file .env.production exec api \
   python scripts/create_owner.py \
   --username owner \
   --password "YourStrongPassword123!" \
   --clinic-name "Your Clinic Name"'
```

### Build the Flutter APK

```bash
# From your local machine
cd cacms_flutter
flutter build apk --dart-define=BACKEND_URL=http://YOUR_EC2_IP:8000
# APK: build/app/outputs/flutter-apk/app-release.apk
```

## Outputs Reference

| Output | Description |
|--------|-------------|
| `ec2_public_ip` | Stable Elastic IP for your server |
| `rds_endpoint` | RDS hostname (internal to VPC) |
| `api_health_url` | `http://IP:8000/health` |
| `api_docs_url` | `http://IP:8000/docs` (Swagger) |
| `flutter_build_command` | Ready-to-run Flutter build command |
| `ssh_command` | SSH into EC2 |
| `seed_owner_command` | Create first owner account |
| `bootstrap_log_command` | Watch bootstrap progress |

## Updating the App

```bash
# SSH into EC2
ssh -i ~/.ssh/cacms-key.pem ubuntu@YOUR_EC2_IP

# Pull latest code and redeploy
cd ~/cacms
git pull origin main
docker compose -f docker-compose.aws.yml --env-file .env.production build api
docker compose -f docker-compose.aws.yml --env-file .env.production up -d
```

## Teardown

```bash
# WARNING: This destroys everything including the RDS database
terraform destroy
```

## Cost (AWS Free Tier — First 12 Months)

| Resource | Free Tier | Monthly After |
|----------|-----------|---------------|
| EC2 t2.micro | 750 hrs/month | ~$8.50 |
| RDS db.t3.micro | 750 hrs/month + 20 GB | ~$15.00 |
| EBS 20 GB gp2 | 30 GB/month | ~$2.00 |
| Elastic IP | Free when attached | $0.005/hr if detached |
| Data transfer | 100 GB/month | $0.09/GB |
| **Total year 1** | **~$0** | **~$25/month** |

> Keep EC2 and RDS running continuously — stopping/starting doesn't save money on free tier
> and risks losing your Elastic IP association.
