"""Logging and error monitoring (Sentry) setup for Phase 0."""

from __future__ import annotations

import logging
import sys
from typing import Any

from cacms.config import settings


def configure_logging() -> None:
    """Structured stderr logging for the API process."""
    level = logging.DEBUG if settings.ENVIRONMENT == "development" else logging.INFO
    root = logging.getLogger()
    root.setLevel(level)
    if not root.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setLevel(level)
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)s [%(name)s] %(message)s",
                datefmt="%Y-%m-%dT%H:%M:%S",
            )
        )
        root.addHandler(handler)


def init_sentry() -> None:
    """Initialize Sentry when SENTRY_DSN is set; no-op otherwise."""
    dsn = (settings.SENTRY_DSN or "").strip()
    if not dsn:
        return
    try:
        import sentry_sdk
        from sentry_sdk.integrations.fastapi import FastApiIntegration
        from sentry_sdk.integrations.logging import LoggingIntegration
    except ImportError:
        logging.getLogger(__name__).warning(
            "SENTRY_DSN is set but sentry-sdk is not installed; skipping Sentry init"
        )
        return

    sentry_sdk.init(
        dsn=dsn,
        environment=settings.ENVIRONMENT,
        integrations=[
            FastApiIntegration(),
            LoggingIntegration(level=logging.INFO, event_level=logging.ERROR),
        ],
        traces_sample_rate=settings.SENTRY_TRACES_SAMPLE_RATE,
    )


def capture_exception(exc: BaseException, **extra: Any) -> None:
    """Send exception to Sentry if initialized."""
    dsn = (settings.SENTRY_DSN or "").strip()
    if not dsn:
        return
    try:
        import sentry_sdk
    except ImportError:
        return
    with sentry_sdk.push_scope() as scope:
        for k, v in extra.items():
            scope.set_extra(k, v)
        sentry_sdk.capture_exception(exc)
