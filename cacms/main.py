from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from cacms.config import settings
from cacms.limiter import limiter
from cacms.middleware.audit_middleware import AuditMiddleware

app = FastAPI(title="CACMS API", version="1.0.0")

# Attach limiter to app state (required by slowapi)
app.state.limiter = limiter


async def _custom_rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=429,
        content={"error_code": "RATE_LIMIT_EXCEEDED", "message": str(exc)},
    )


app.add_exception_handler(RateLimitExceeded, _custom_rate_limit_handler)

# Audit middleware must be added before CORS so it runs on the way out after CORS headers are set.
# Starlette applies middleware in reverse-registration order (last added = outermost),
# so add AuditMiddleware first to make it the innermost wrapper (runs after routing).
app.add_middleware(AuditMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_origin_regex=".*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(SlowAPIMiddleware)

from cacms.routers import auth, patients, appointments, services, consultations, payments, events, users, reports, ops, exports
from cacms.routers import patient_status, doctors
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
app.include_router(patient_status.router, prefix="/v1")
app.include_router(doctors.router, prefix="/v1")


@app.get("/health")
async def health():
    return {"status": "ok"}
