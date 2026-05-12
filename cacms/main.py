import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from cacms.config import settings
from cacms.exception_handlers import (
    http_exception_handler,
    request_validation_handler,
    unhandled_exception_handler,
)
from cacms.health import run_health_checks
from cacms.limiter import limiter
from cacms.middleware.audit_middleware import AuditMiddleware
from cacms.observability import configure_logging, init_sentry

configure_logging()
init_sentry()

_logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler.

    On startup:
      1. Run an immediate plan-expiry check (catches plans that expired while
         the app was offline).
      2. Launch the 24-hour background loop for ongoing expiry checks.
    """
    from cacms.database import AsyncSessionLocal
    from cacms.services.plan_expiry_service import expire_overdue_plans, run_expiry_check_loop
    from cacms.services.metering_service import MeteringService

    # Initialise MeteringService with optional Redis client
    redis_client = None
    if settings.REDIS_URL:
        try:
            import redis.asyncio as aioredis
            redis_client = aioredis.from_url(settings.REDIS_URL)
        except Exception as exc:
            _logger.warning("Could not connect to Redis for metering — %s", exc)
    app.state.metering = MeteringService(redis_client=redis_client)

    # Immediate startup plan-expiry check
    try:
        async with AsyncSessionLocal() as db:
            count = await expire_overdue_plans(db)
            if count:
                _logger.info(
                    "Startup plan expiry check: transitioned %d clinic(s) to grace", count
                )
    except Exception as exc:
        _logger.error("Startup plan expiry check failed — %s", exc, exc_info=True)

    # Launch daily background loop (fire-and-forget)
    task = asyncio.create_task(run_expiry_check_loop(AsyncSessionLocal))

    yield  # application runs here

    # Graceful shutdown: cancel the background task
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="CACMS API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url=None if settings.ENVIRONMENT == "production" else "/docs",
    redoc_url=None if settings.ENVIRONMENT == "production" else "/redoc",
)

# Attach limiter to app state (required by slowapi)
app.state.limiter = limiter


def get_metering(request: Request):
    """FastAPI dependency that returns the MeteringService from app.state."""
    return getattr(request.app.state, "metering", None)


async def _custom_rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=429,
        content={"error_code": "RATE_LIMIT_EXCEEDED", "message": str(exc), "detail": None},
    )


app.add_exception_handler(RateLimitExceeded, _custom_rate_limit_handler)
app.add_exception_handler(RequestValidationError, request_validation_handler)
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)

# Audit middleware must be added before CORS so it runs on the way out after CORS headers are set.
# Starlette applies middleware in reverse-registration order (last added = outermost),
# so add AuditMiddleware first to make it the innermost wrapper (runs after routing).
app.add_middleware(AuditMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(SlowAPIMiddleware)

from cacms.routers import auth, patients, appointments, services, consultations, payments, events, users, reports, ops, exports, backup
from cacms.routers import doctors, public, superadmin, clinic, billing
app.include_router(auth.router, prefix="/v1")
app.include_router(users.router, prefix="/v1")
app.include_router(patients.router, prefix="/v1")
app.include_router(appointments.router, prefix="/v1")
app.include_router(services.router, prefix="/v1")
app.include_router(consultations.router, prefix="/v1")
app.include_router(payments.router, prefix="/v1")
app.include_router(events.router, prefix="/v1")
app.include_router(reports.router, prefix="/v1")
app.include_router(ops.router, prefix="/v1")
app.include_router(exports.router, prefix="/v1")
app.include_router(backup.router, prefix="/v1")
app.include_router(doctors.router, prefix="/v1")
app.include_router(public.router, prefix="/v1")
app.include_router(superadmin.router, prefix="/v1")
app.include_router(clinic.router, prefix="/v1")
app.include_router(billing.router, prefix="/v1")


@app.get("/health")
async def health():
    healthy, checks = await run_health_checks()
    status = "ok" if healthy else "degraded"
    payload = {"status": status, "environment": settings.ENVIRONMENT, "checks": checks}
    return JSONResponse(
        status_code=200 if healthy else 503,
        content=payload,
    )
