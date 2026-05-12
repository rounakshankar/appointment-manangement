"""
Backup Router — Phase 1 Deployment Foundation

Endpoints:
  POST /v1/admin/backup          — trigger encrypted backup (owner/admin only)
  GET  /v1/admin/backups         — list available backup files
  GET  /v1/admin/backup/{filename} — stream download a backup file
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse

from cacms.config import settings
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin
from cacms.schemas.common import ErrorResponse
from cacms.services import backup_service

router = APIRouter(prefix="/admin", tags=["backup"])


def _require_encryption_key() -> None:
    """Raise 503 if BACKUP_ENCRYPTION_KEY is not configured."""
    if not settings.BACKUP_ENCRYPTION_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error_code": "BACKUP_NOT_CONFIGURED",
                "message": "BACKUP_ENCRYPTION_KEY is not set. Configure it in your environment.",
            },
        )


@router.post(
    "/backup",
    status_code=status.HTTP_201_CREATED,
    responses={
        503: {"model": ErrorResponse, "description": "Backup not configured"},
        500: {"model": ErrorResponse, "description": "pg_dump failed"},
    },
)
async def trigger_backup(
    _user: UserContext = Depends(require_owner_or_admin),
) -> dict:
    """
    Trigger an encrypted database backup.

    Runs pg_dump, compresses with gzip, encrypts with AES-256-GCM, and writes
    to BACKUP_DIR. Returns the filename of the created backup.

    Requires role: owner or admin.
    """
    _require_encryption_key()

    try:
        filename = backup_service.trigger_backup(
            db_url=settings.DATABASE_URL,
            backup_dir=settings.BACKUP_DIR,
            encryption_key=settings.BACKUP_ENCRYPTION_KEY,
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "error_code": "BACKUP_FAILED",
                "message": str(exc),
            },
        ) from exc

    return {"filename": filename, "message": "Backup created successfully"}


@router.get(
    "/backups",
    responses={
        503: {"model": ErrorResponse, "description": "Backup not configured"},
    },
)
async def list_backups(
    _user: UserContext = Depends(require_owner_or_admin),
) -> list[dict]:
    """
    List all available encrypted backup files.

    Returns filename, size_bytes, and created_at for each file.
    Requires role: owner or admin.
    """
    _require_encryption_key()

    return backup_service.list_backups(settings.BACKUP_DIR)


@router.get(
    "/backup/{filename}",
    responses={
        404: {"model": ErrorResponse, "description": "Backup file not found"},
        400: {"model": ErrorResponse, "description": "Invalid filename"},
        503: {"model": ErrorResponse, "description": "Backup not configured"},
    },
)
async def download_backup(
    filename: str,
    _user: UserContext = Depends(require_owner_or_admin),
) -> FileResponse:
    """
    Stream download an encrypted backup file.

    Validates the filename to prevent path traversal.
    Requires role: owner or admin.
    """
    _require_encryption_key()

    try:
        path = backup_service.get_backup_path(settings.BACKUP_DIR, filename)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error_code": "INVALID_FILENAME", "message": str(exc)},
        ) from exc
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "BACKUP_NOT_FOUND", "message": str(exc)},
        ) from exc

    return FileResponse(
        path=str(path),
        media_type="application/octet-stream",
        filename=filename,
    )
