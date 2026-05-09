import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.service import Service


async def get_active_services(db: AsyncSession, clinic_id: uuid.UUID) -> list[Service]:
    """Return all services where active=True."""
    result = await db.execute(
        select(Service).where(Service.active == True, Service.clinic_id == clinic_id)  # noqa: E712
    )
    return list(result.scalars().all())
