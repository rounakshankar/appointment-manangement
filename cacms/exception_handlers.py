"""Global HTTP exception handlers — structured JSON for all errors (Phase 0)."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from cacms.observability import capture_exception

logger = logging.getLogger(__name__)


def _validation_errors(exc: RequestValidationError) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for err in exc.errors():
        loc = err.get("loc", ())
        path = ".".join(str(x) for x in loc if x != "body")
        out.append(
            {
                "field": path or "body",
                "message": err.get("msg", "Invalid value"),
                "type": err.get("type", ""),
            }
        )
    return out


async def request_validation_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error_code": "VALIDATION_ERROR",
            "message": "Request validation failed",
            "errors": _validation_errors(exc),
        },
    )


async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    detail = exc.detail
    if isinstance(detail, dict):
        body = {
            "error_code": str(detail.get("error_code", "HTTP_ERROR")),
            "message": str(detail.get("message", "")),
            "detail": detail.get("detail"),
        }
    elif isinstance(detail, list):
        body = {
            "error_code": "HTTP_ERROR",
            "message": "Request failed",
            "detail": detail,
        }
    else:
        body = {
            "error_code": "HTTP_ERROR",
            "message": str(detail),
            "detail": None,
        }
    return JSONResponse(status_code=exc.status_code, content=body)


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    capture_exception(exc, path=str(request.url.path), method=request.method)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error_code": "INTERNAL_ERROR",
            "message": "An unexpected error occurred",
            "detail": None,
        },
    )
