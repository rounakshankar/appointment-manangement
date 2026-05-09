"""
Create or update the first owner account for a clinic.

Usage:
    python scripts/create_owner.py --username owner --password "ChangeMe123!" --clinic-name "Default Clinic"
"""

from __future__ import annotations

import argparse
import asyncio

from sqlalchemy import select

from cacms.database import AsyncSessionLocal
from cacms.models.clinic import Clinic
from cacms.models.user import User
from cacms.services.password_service import hash_password


async def run(username: str, password: str, clinic_name: str) -> None:
    async with AsyncSessionLocal() as db:
        clinic_result = await db.execute(select(Clinic).where(Clinic.name == clinic_name))
        clinic = clinic_result.scalar_one_or_none()
        if clinic is None:
            clinic = Clinic(name=clinic_name)
            db.add(clinic)
            await db.flush()

        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if user is None:
            user = User(
                username=username,
                password_hash=hash_password(password),
                role="owner",
                clinic_id=clinic.clinic_id,
                active=True,
            )
            db.add(user)
            action = "created"
        else:
            user.password_hash = hash_password(password)
            user.role = "owner"
            user.clinic_id = clinic.clinic_id
            user.active = True
            action = "updated"

        await db.commit()
        print(f"Owner user {action}: {username} / clinic={clinic.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--clinic-name", default="Default Clinic")
    args = parser.parse_args()
    asyncio.run(run(args.username, args.password, args.clinic_name))


if __name__ == "__main__":
    main()
