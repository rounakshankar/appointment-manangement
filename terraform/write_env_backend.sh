#!/bin/bash
# Write .env.production for the backend EC2
mkdir -p /home/ubuntu/cacms
cat > /home/ubuntu/cacms/.env.production << 'ENVEOF'
ENVIRONMENT=production
DATABASE_URL=postgresql+asyncpg://cacms_user:i0hDFuXeISrbq4tRJNmmEQ@cacms-db.cl42wmgs4lqi.ap-south-1.rds.amazonaws.com:5432/cacms
JWT_SECRET=a9bb2c152367d64379a675c31bec6f000f84b4bf318c98a1e48c922d10cc2171
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60
CORS_ORIGINS=REPLACE_WITH_FRONTEND_IP
OTP_TTL_SECONDS=300
AUTH_RATE_LIMIT=10/minute
BACKUP_ENCRYPTION_KEY=4a9aad0064c35c9d7dd7dc4172d958ab81e5301313777c5496df77361d5246f0
BACKUP_DIR=/var/backups/cacms
REDIS_URL=redis://127.0.0.1:6379/0
SENTRY_DSN=
SENTRY_TRACES_SAMPLE_RATE=0.1
SUPERADMIN_TOKEN=77eb82f8b02da64eda8d93ac7a6394a3fcfacf3a054457199818f59d7b0c5acc
ENVEOF
chmod 600 /home/ubuntu/cacms/.env.production
chown ubuntu:ubuntu /home/ubuntu/cacms/.env.production
sudo mkdir -p /var/backups/cacms
sudo chown ubuntu:ubuntu /var/backups/cacms
echo "ENV_WRITTEN"
