"""
MeteringService — records and aggregates per-clinic usage events.

Design decisions:
- record() writes to PostgreSQL first (durable), then increments Redis (fast reads).
- Redis failure is non-fatal: a warning is logged and the request continues normally.
- get_monthly_usage() reads from Redis when available; falls back to a DB aggregate.
- The service is instantiated once at startup and stored on app.state.metering.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.usage_event import UsageEvent

logger = logging.getLogger(__name__)

# Redis TTL: 90 days in seconds
_REDIS_TTL_SECONDS = 7_776_000


def _redis_key(clinic_id: uuid.UUID, event_type: str, year: int, month: int) -> str:
    """Build the Redis counter key for a clinic/event/month combination."""
    return f"usage:{clinic_id}:{event_type}:{year}:{month}"


class MeteringService:
    """Records usage events to PostgreSQL and caches monthly counts in Redis."""

    def __init__(self, redis_client: Any = None) -> None:
        """
        Args:
            redis_client: An optional ``redis.asyncio`` client instance.
                          When ``None``, all Redis operations are skipped silently.
        """
        self._redis = redis_client

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def record(
        self,
        db: AsyncSession,
        clinic_id: uuid.UUID,
        event_type: str,
        quantity: int = 1,
        metadata: Optional[dict] = None,
    ) -> None:
        """Persist a UsageEvent row and increment the Redis monthly counter.

        Redis failure is non-fatal — the DB write is never rolled back due to a
        Redis error.

        Args:
            db: Active async SQLAlchemy session.
            clinic_id: The clinic this event belongs to.
            event_type: Identifier string, e.g. ``'appointment_created'``.
            quantity: How many units to record (default 1).
            metadata: Optional arbitrary JSON payload stored alongside the event.
        """
        now = datetime.now(tz=timezone.utc)

        # 1. Persist to PostgreSQL (durable)
        event = UsageEvent(
            clinic_id=clinic_id,
            event_type=event_type,
            quantity=quantity,
            event_metadata=metadata,
        )
        db.add(event)
        await db.commit()

        # 2. Increment Redis counter (best-effort)
        if self._redis is not None:
            key = _redis_key(clinic_id, event_type, now.year, now.month)
            try:
                pipe = self._redis.pipeline()
                pipe.incrby(key, quantity)
                pipe.expire(key, _REDIS_TTL_SECONDS)
                await pipe.execute()
            except Exception as exc:  # redis.exceptions.RedisError or ConnectionError
                logger.warning(
                    "MeteringService: Redis increment failed for clinic=%s event=%s — %s",
                    clinic_id,
                    event_type,
                    exc,
                )

    async def get_monthly_usage(
        self,
        db: AsyncSession,
        clinic_id: uuid.UUID,
        year: int,
        month: int,
    ) -> dict[str, int]:
        """Return ``{event_type: count}`` for the given clinic and calendar month.

        Reads from Redis when available; falls back to a ``GROUP BY`` aggregate
        query against ``usage_events`` when Redis is unavailable or the key is
        missing.

        Args:
            db: Active async SQLAlchemy session.
            clinic_id: The clinic to query.
            year: Calendar year (e.g. 2026).
            month: Calendar month (1–12).

        Returns:
            A dict mapping event type strings to their total quantity for the month.
            Returns an empty dict when no events exist.
        """
        if self._redis is not None:
            try:
                result = await self._get_monthly_usage_from_redis(clinic_id, year, month)
                if result is not None:
                    return result
            except Exception as exc:
                logger.warning(
                    "MeteringService: Redis read failed for clinic=%s %d-%02d — %s",
                    clinic_id,
                    year,
                    month,
                    exc,
                )

        return await self._get_monthly_usage_from_db(db, clinic_id, year, month)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    async def _get_monthly_usage_from_redis(
        self,
        clinic_id: uuid.UUID,
        year: int,
        month: int,
    ) -> Optional[dict[str, int]]:
        """Scan Redis for all usage keys matching this clinic/month.

        Returns ``None`` when no keys are found (triggers DB fallback).
        """
        pattern = f"usage:{clinic_id}:*:{year}:{month}"
        keys: list[bytes] = []

        # Use SCAN to avoid blocking the Redis server
        cursor = 0
        while True:
            cursor, batch = await self._redis.scan(cursor, match=pattern, count=100)
            keys.extend(batch)
            if cursor == 0:
                break

        if not keys:
            return None

        values = await self._redis.mget(*keys)
        result: dict[str, int] = {}
        prefix = f"usage:{clinic_id}:"
        suffix = f":{year}:{month}"

        for key_bytes, value in zip(keys, values):
            key_str = key_bytes.decode() if isinstance(key_bytes, bytes) else key_bytes
            # Extract event_type from key: usage:{clinic_id}:{event_type}:{year}:{month}
            inner = key_str[len(prefix):]          # "{event_type}:{year}:{month}"
            event_type = inner[: -len(suffix)]     # "{event_type}"
            result[event_type] = int(value) if value else 0

        return result

    async def _get_monthly_usage_from_db(
        self,
        db: AsyncSession,
        clinic_id: uuid.UUID,
        year: int,
        month: int,
    ) -> dict[str, int]:
        """Aggregate usage_events for the given clinic and calendar month from DB."""
        stmt = (
            select(
                UsageEvent.event_type,
                func.sum(UsageEvent.quantity).label("total"),
            )
            .where(
                UsageEvent.clinic_id == clinic_id,
                func.extract("year", UsageEvent.created_at) == year,
                func.extract("month", UsageEvent.created_at) == month,
            )
            .group_by(UsageEvent.event_type)
        )
        rows = (await db.execute(stmt)).all()
        return {row.event_type: int(row.total) for row in rows}
