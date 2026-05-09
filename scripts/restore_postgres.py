"""
Restore a PostgreSQL backup created by scripts/backup_postgres.py.

Usage:
    python scripts/restore_postgres.py path/to/cacms.dump

Environment:
    DATABASE_URL must point to the target PostgreSQL database.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def _pg_url() -> str:
    url = os.environ.get("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/cacms")
    return url.replace("postgresql+asyncpg://", "postgresql://", 1)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/restore_postgres.py path/to/cacms.dump")

    backup_file = Path(sys.argv[1])
    if not backup_file.exists():
        raise SystemExit(f"Backup file not found: {backup_file}")

    subprocess.run(
        ["pg_restore", "--clean", "--if-exists", "--dbname", _pg_url(), str(backup_file)],
        check=True,
    )
    print(f"Backup restored: {backup_file}")


if __name__ == "__main__":
    main()
