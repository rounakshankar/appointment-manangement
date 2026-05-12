"""Liveness / readiness style health checks."""

from __future__ import annotations

import logging
from typing import Any

from sqlalchemy import text

from cacms.config import settings
from cacms.database import AsyncSessionLocal

logger = logging.getLogger(__name__)


async def run_health_checks() -> tuple[bool, dict[str, Any]]:
    """
    Returns (healthy, payload). Database is required; Redis is checked only if REDIS_URL is set.
    """
    checks: dict[str, Any] = {}
    ok = True

    try:
        async with AsyncSessionLocal() as session:
            await session.execute(text("SELECT 1"))
        checks["database"] = {"status": "ok"}
    except Exception as exc:
        ok = False
        logger.warning("Health check: database failed: %s", exc)
        checks["database"] = {"status": "error", "error": type(exc).__name__}

    if settings.REDIS_URL:
        try:
            import redis.asyncio as redis_async

            client = redis_async.from_url(
                settings.REDIS_URL,
                socket_connect_timeout=2.0,
            )
            try:
                pong = await client.ping()
                if pong:
                    checks["redis"] = {"status": "ok"}
                else:
                    ok = False
                    checks["redis"] = {"status": "error", "error": "PING failed"}
            finally:
                await client.aclose()
        except Exception as exc:
            ok = False
            logger.warning("Health check: redis failed: %s", exc)
            checks["redis"] = {"status": "error", "error": type(exc).__name__}

    return ok, checks
