from pathlib import Path

from fastapi import APIRouter, Depends

from cacms.config import settings
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin

router = APIRouter(prefix="/ops", tags=["operations"])


@router.get("/backup-status")
async def backup_status(
    _user: UserContext = Depends(require_owner_or_admin),
):
    backup_dir = Path(settings.BACKUP_DIR)
    backup_files = []
    if backup_dir.exists():
        backup_files = sorted(
            [p for p in backup_dir.iterdir() if p.is_file()],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

    latest = backup_files[0] if backup_files else None
    return {
        "backup_dir": str(backup_dir),
        "backup_dir_exists": backup_dir.exists(),
        "backup_count": len(backup_files),
        "latest_backup_file": latest.name if latest else None,
        "latest_backup_size_bytes": latest.stat().st_size if latest else None,
        "latest_backup_modified_at": latest.stat().st_mtime if latest else None,
    }
