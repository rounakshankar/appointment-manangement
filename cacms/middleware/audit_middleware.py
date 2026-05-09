import json
import logging
import re
import uuid
from typing import Optional

from jose import JWTError, jwt
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

from cacms.config import settings
from cacms.database import AsyncSessionLocal
from cacms.models.audit_log import AuditLog

logger = logging.getLogger(__name__)

_MUTATING_METHODS = {"POST", "PATCH", "DELETE"}
_UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.IGNORECASE
)


def _extract_actor(request: Request) -> tuple[Optional[uuid.UUID], Optional[str], Optional[uuid.UUID]]:
    """Decode JWT and return (actor_id, actor_role, clinic_id). Returns Nones on any failure."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None, None, None
    token = auth_header[len("Bearer "):]
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        sub = payload.get("sub")
        role = payload.get("role")
        clinic_id = payload.get("clinic_id")
        if not sub or not role:
            return None, None, None
        return uuid.UUID(sub), role, uuid.UUID(clinic_id) if clinic_id else None
    except (JWTError, ValueError, AttributeError):
        return None, None, None


def _extract_resource(path: str) -> str:
    """Return the resource name from the URL path (second segment after /v1/)."""
    # e.g. /v1/appointments/some-uuid  →  "appointments"
    parts = [p for p in path.split("/") if p]
    # parts[0] == "v1", parts[1] == resource
    if len(parts) >= 2:
        return parts[1]
    if len(parts) == 1:
        return parts[0]
    return path


def _extract_resource_id(path: str) -> Optional[uuid.UUID]:
    """Return the first UUID found in the URL path, or None."""
    match = _UUID_RE.search(path)
    if match:
        try:
            return uuid.UUID(match.group())
        except ValueError:
            pass
    return None


class AuditMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next) -> Response:
        # Read and buffer the request body so the route handler can still read it.
        body_bytes: bytes = await request.body()

        # Monkey-patch _body so downstream can still call request.body() / request.json()
        async def _receive():
            return {"type": "http.request", "body": body_bytes, "more_body": False}

        request._receive = _receive  # type: ignore[attr-defined]

        response: Response = await call_next(request)

        method = request.method.upper()
        status_code = response.status_code

        if method in _MUTATING_METHODS and 200 <= status_code < 300:
            actor_id, actor_role, clinic_id = _extract_actor(request)
            path = request.url.path
            action = f"{method} {path}"
            resource = _extract_resource(path)
            resource_id = _extract_resource_id(path)

            if clinic_id is None:
                logger.debug("AuditMiddleware: skipping %s because clinic_id is unavailable", action)
                return response

            payload_data = None
            if body_bytes:
                try:
                    payload_data = json.loads(body_bytes)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    payload_data = None

            try:
                async with AsyncSessionLocal() as session:
                    log_entry = AuditLog(
                        actor_id=actor_id or uuid.UUID(int=0),
                        actor_role=actor_role or "anonymous",
                        action=action,
                        resource=resource,
                        resource_id=resource_id,
                        payload=payload_data,
                        clinic_id=clinic_id,
                    )
                    session.add(log_entry)
                    await session.commit()
            except Exception:
                logger.exception("AuditMiddleware: failed to write audit log for %s", action)

        return response
