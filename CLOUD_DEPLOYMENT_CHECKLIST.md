# CACMS Cloud Deployment Checklist

## Minimum Production Setup

- Ubuntu LTS server.
- HTTPS domain with Nginx or Caddy.
- FastAPI app running behind Gunicorn/Uvicorn.
- PostgreSQL database with automated backups.
- `.env` configured with production secrets.
- `JWT_SECRET` generated with at least 32 random bytes.
- `CORS_ORIGINS` restricted to trusted app/web origins.
- Daily `pg_dump` backup job.
- Uptime and disk-space monitoring.
- Error logs retained and easy to export.

## First Deploy Steps

1. Provision VPS or app server.
2. Provision PostgreSQL database.
3. Set environment variables.
4. Run `alembic upgrade head`.
5. Create owner user:

```bash
python scripts/create_owner.py --username owner --password "ChangeMe123!" --clinic-name "Clinic Name"
```

6. Start API process.
7. Configure reverse proxy and HTTPS.
8. Verify `/health`.
9. Verify admin/owner login.
10. Configure backup cron.

## Backup Cron Example

```bash
0 2 * * * cd /opt/cacms && DATABASE_URL="$DATABASE_URL" BACKUP_DIR=/var/backups/cacms python scripts/backup_postgres.py
```

## Required Environment Variables

```text
DATABASE_URL=postgresql+asyncpg://...
JWT_SECRET=...
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60
CORS_ORIGINS=https://your-domain.com
AUTH_RATE_LIMIT=10/minute
BACKUP_DIR=/var/backups/cacms
```

## Scale-Up Path

- Start: one API server plus PostgreSQL.
- 10-20 clinics: separate PostgreSQL or managed DB.
- 50+ clinics: add Redis, PgBouncer, and multiple API servers.
- Horizontal scaling: move SSE from in-process bus to Redis Pub/Sub or Streams.

## Go-Live Gate

- No hardcoded admin password.
- Doctor password login enforced.
- Every business query scoped by `clinic_id`.
- Backup creation tested.
- Restore tested on a separate database.
- Daily report endpoint verified.
- Receipt/consultation summary export verified.
- Monitoring alerts configured.
