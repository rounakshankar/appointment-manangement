"""
Create a timestamped PostgreSQL backup using pg_dump.

Usage:
    python scripts/backup_postgres.py

Environment:
    DATABASE_URL must point to PostgreSQL. postgresql+asyncpg:// URLs are
    converted to postgresql:// for pg_dump.
    BACKUP_DIR controls output directory.
"""

from __future__ import annotations

import os
import subprocess
from datetime import datetime
from pathlib import Path


def _pg_url() -> str:
    url = os.environ.get("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/cacms")
    return url.replace("postgresql+asyncpg://", "postgresql://", 1)


def main() -> None:
    backup_dir = Path(os.environ.get("BACKUP_DIR", "backups"))
    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    output = backup_dir / f"cacms-{timestamp}.dump"

    subprocess.run(
        ["pg_dump", "--format=custom", "--file", str(output), _pg_url()],
        check=True,
    )
    print(f"Backup created: {output}")


if __name__ == "__main__":
    main()
