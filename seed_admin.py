"""
seed_admin.py — Phase 1 Deployment Foundation

Standalone script that creates the first owner account for a clinic.
Reads credentials from environment variables SEED_ADMIN_USERNAME and SEED_ADMIN_PASSWORD.

Usage:
    SEED_ADMIN_USERNAME=owner SEED_ADMIN_PASSWORD=SecurePass123! python seed_admin.py

Or with a .env file:
    python seed_admin.py

Requirements:
    - SEED_ADMIN_PASSWORD must be at least 12 characters (exits non-zero if not)
    - Idempotent: skips insert if username already exists
    - Hashes password with bcrypt cost 12
    - Inserts into users table with role="owner" and the first clinic's clinic_id
"""

from __future__ import annotations

import asyncio
import os
import sys

from sqlalchemy import select

from cacms.database import AsyncSessionLocal
from cacms.models.clinic import Clinic
from cacms.models.user import User
from cacms.services.password_service import hash_password

_MIN_PASSWORD_LENGTH = 12


def _load_env() -> tuple[str, str]:
    """Load and validate SEED_ADMIN_USERNAME and SEED_ADMIN_PASSWORD from env."""
    # Support .env file via python-dotenv if available
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass

    username = os.environ.get("SEED_ADMIN_USERNAME", "").strip()
    password = os.environ.get("SEED_ADMIN_PASSWORD", "").strip()

    errors = []
    if not username:
        errors.append("SEED_ADMIN_USERNAME is not set or empty")
    if not password:
        errors.append("SEED_ADMIN_PASSWORD is not set or empty")
    elif len(password) < _MIN_PASSWORD_LENGTH:
        errors.append(
            f"SEED_ADMIN_PASSWORD is too short ({len(password)} chars). "
            f"Minimum length is {_MIN_PASSWORD_LENGTH} characters."
        )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)

    return username, password


async def run(username: str, password: str) -> None:
    """Insert owner user if not already present."""
    async with AsyncSessionLocal() as db:
        # Find the first clinic (Phase 1 operates with one clinic)
        clinic_result = await db.execute(select(Clinic).limit(1))
        clinic = clinic_result.scalar_one_or_none()

        if clinic is None:
            print(
                "ERROR: No clinic found in the database. "
                "Run Alembic migrations first: alembic upgrade head",
                file=sys.stderr,
            )
            sys.exit(1)

        # Check if username already exists (idempotent)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        existing = user_result.scalar_one_or_none()

        if existing is not None:
            print(
                f"INFO: User '{username}' already exists (role={existing.role}). "
                "No changes made."
            )
            return

        # Create owner user with bcrypt cost 12
        user = User(
            username=username,
            password_hash=hash_password(password),
            role="owner",
            clinic_id=clinic.clinic_id,
            active=True,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

        print(
            f"SUCCESS: Owner account created.\n"
            f"  Username : {username}\n"
            f"  Role     : owner\n"
            f"  Clinic   : {clinic.name} ({clinic.clinic_id})\n"
            f"  User ID  : {user.user_id}"
        )


def main() -> None:
    username, password = _load_env()
    asyncio.run(run(username, password))


if __name__ == "__main__":
    main()
