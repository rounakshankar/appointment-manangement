"""
Backup Service — Phase 1 Deployment Foundation

Provides encrypted database backup using:
  - pg_dump via subprocess
  - gzip compression
  - AES-256-GCM encryption (PBKDF2-HMAC-SHA256, 100k iterations)

File format: [16-byte salt][12-byte nonce][ciphertext + 16-byte GCM tag]
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_SALT_LEN = 16
_NONCE_LEN = 12
_KEY_LEN = 32          # AES-256
_KDF_ITERATIONS = 100_000
_SAFE_FILENAME_RE = re.compile(r"^cacms_backup_\d{8}_\d{6}\.enc$")


# ---------------------------------------------------------------------------
# Key derivation
# ---------------------------------------------------------------------------

def _derive_key(password: str, salt: bytes) -> bytes:
    """Derive a 32-byte AES key from a password using PBKDF2-HMAC-SHA256."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=_KEY_LEN,
        salt=salt,
        iterations=_KDF_ITERATIONS,
    )
    return kdf.derive(password.encode("utf-8"))


# ---------------------------------------------------------------------------
# Encrypt / decrypt helpers (exposed for property tests)
# ---------------------------------------------------------------------------

def encrypt(plaintext: bytes, password: str) -> bytes:
    """
    Encrypt plaintext bytes with AES-256-GCM.

    Returns: salt (16) + nonce (12) + ciphertext+tag
    """
    salt = os.urandom(_SALT_LEN)
    nonce = os.urandom(_NONCE_LEN)
    key = _derive_key(password, salt)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    return salt + nonce + ciphertext


def decrypt(data: bytes, password: str) -> bytes:
    """
    Decrypt bytes produced by encrypt().

    Raises ValueError on authentication failure (wrong key / tampered data).
    """
    if len(data) < _SALT_LEN + _NONCE_LEN + 16:
        raise ValueError("Ciphertext too short — data may be corrupt")
    salt = data[:_SALT_LEN]
    nonce = data[_SALT_LEN:_SALT_LEN + _NONCE_LEN]
    ciphertext = data[_SALT_LEN + _NONCE_LEN:]
    key = _derive_key(password, salt)
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ciphertext, None)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def trigger_backup(db_url: str, backup_dir: str, encryption_key: str) -> str:
    """
    Run pg_dump, gzip-compress the output, encrypt with AES-256-GCM, and
    write to backup_dir.

    Returns the filename of the created backup (e.g. cacms_backup_20260510_143022.enc).

    Raises:
        RuntimeError: if pg_dump exits non-zero (no partial file is left on disk).
        ValueError: if encryption_key is empty.
    """
    if not encryption_key:
        raise ValueError("BACKUP_ENCRYPTION_KEY is not set")

    # Convert asyncpg URL to plain psycopg2 URL for pg_dump
    pg_url = db_url.replace("postgresql+asyncpg://", "postgresql://", 1)

    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    filename = f"cacms_backup_{timestamp}.enc"
    backup_path = Path(backup_dir) / filename
    backup_path.parent.mkdir(parents=True, exist_ok=True)

    # Write to a temp file first — only move to final path on success
    tmp_fd, tmp_path = tempfile.mkstemp(dir=backup_dir, prefix=".cacms_backup_tmp_")
    try:
        os.close(tmp_fd)

        # Run pg_dump and capture stdout
        result = subprocess.run(
            ["pg_dump", "--format=plain", pg_url],
            capture_output=True,
        )

        if result.returncode != 0:
            stderr = result.stderr.decode("utf-8", errors="replace")
            raise RuntimeError(
                f"pg_dump failed (exit {result.returncode}): {stderr[:500]}"
            )

        # Compress
        import gzip
        compressed = gzip.compress(result.stdout, compresslevel=6)

        # Encrypt
        encrypted = encrypt(compressed, encryption_key)

        # Write to temp file, then rename atomically
        with open(tmp_path, "wb") as f:
            f.write(encrypted)

        os.replace(tmp_path, backup_path)
        return filename

    except Exception:
        # Clean up temp file on any failure — no partial files left
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass
        raise


def list_backups(backup_dir: str) -> list[dict]:
    """
    Scan backup_dir for *.enc files.

    Returns a list of dicts with keys: filename, size_bytes, created_at (ISO string).
    Sorted by creation time descending (newest first).
    """
    d = Path(backup_dir)
    if not d.exists():
        return []

    backups = []
    for p in d.iterdir():
        if p.is_file() and p.suffix == ".enc":
            stat = p.stat()
            backups.append({
                "filename": p.name,
                "size_bytes": stat.st_size,
                "created_at": datetime.utcfromtimestamp(stat.st_mtime).isoformat() + "Z",
            })

    backups.sort(key=lambda b: b["created_at"], reverse=True)
    return backups


def get_backup_path(backup_dir: str, filename: str) -> Path:
    """
    Validate filename and return the full Path.

    Raises:
        ValueError: if filename contains path traversal or doesn't match expected pattern.
        FileNotFoundError: if the file doesn't exist.
    """
    # Reject path traversal and unexpected filenames
    if "/" in filename or "\\" in filename or ".." in filename:
        raise ValueError(f"Invalid backup filename: {filename!r}")

    if not _SAFE_FILENAME_RE.match(filename):
        raise ValueError(
            f"Filename {filename!r} does not match expected pattern "
            "cacms_backup_YYYYMMDD_HHMMSS.enc"
        )

    path = Path(backup_dir) / filename
    if not path.exists():
        raise FileNotFoundError(f"Backup file not found: {filename}")

    return path
