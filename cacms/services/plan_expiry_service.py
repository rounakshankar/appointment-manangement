"""
PlanExpiryService — checks for expired clinic plans and moves them to grace status.

Runs:
  1. Once at application startup (catches any plans that expired while the app was down).
  2. Once every 24 hours via an asyncio background task (no Celery needed at this scale).

Design decisions:
- A single DB query fetches all affected clinics in one round-trip.
- Each transition is logged individually so the operator can audit the history.
- The background loop catches all exceptions so a transient DB error never kills the task.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

logger = logging.getLogger(__name__)

# How often the background loop runs (seconds).  24 hours.
_CHECK_INTERVAL_SECONDS = 86_400


async def expire_overdue_plans(db: AsyncSession) -> int:
    """Set ``plan_status = 'grace'`` for every clinic whose plan has expired.

    A clinic is considered overdue when:
      - ``plan_expires_at`` is not NULL and is strictly in the past
      - ``plan_status`` is currently ``'active'``

    Returns the number of clinics transitioned.
    """
    now = datetime.now(tz=timezone.utc)

    # Fetch affected clinics so we can log each transition individually.
    from cacms.models.clinic import Clinic  # local import avoids circular deps at module load

    result = await db.execute(
        select(Clinic).where(
            Clinic.plan_expires_at < now,
            Clinic.plan_status == "active",
        )
    )
    clinics = result.scalars().all()

    if not clinics:
        return 0

    for clinic in clinics:
        clinic.plan_status = "grace"
        logger.info(
            "Clinic %s (%s) moved to grace — plan expired %s",
            clinic.name,
            clinic.clinic_id,
            clinic.plan_expires_at,
        )

    await db.commit()
    return len(clinics)


async def run_expiry_check_loop(session_factory: async_sessionmaker) -> None:
    """Background task: run ``expire_overdue_plans`` once every 24 hours.

    Designed to be started with ``asyncio.create_task`` from the FastAPI
    startup handler.  Runs indefinitely until the event loop is closed.

    Args:
        session_factory: An ``async_sessionmaker`` bound to the app's engine.
                         Used to open a fresh session for each check cycle.
    """
    while True:
        await asyncio.sleep(_CHECK_INTERVAL_SECONDS)
        try:
            async with session_factory() as db:
                count = await expire_overdue_plans(db)
                if count:
                    logger.info("Plan expiry cron: transitioned %d clinic(s) to grace", count)
                else:
                    logger.debug("Plan expiry cron: no expired plans found")
        except Exception as exc:  # noqa: BLE001
            logger.error("Plan expiry cron: unexpected error — %s", exc, exc_info=True)
