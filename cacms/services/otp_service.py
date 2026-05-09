import random
import string
from datetime import datetime, timedelta
from typing import Optional

import bcrypt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from cacms.models.otp_session import OtpSession
from cacms.config import settings


async def generate_otp(db: AsyncSession, phone: str) -> str:
    """Generate a 6-digit OTP, store its bcrypt hash in otp_sessions, return plaintext OTP."""
    otp = "".join(random.choices(string.digits, k=6))
    otp_hash = bcrypt.hashpw(otp.encode(), bcrypt.gensalt()).decode()
    expires_at = datetime.utcnow() + timedelta(seconds=settings.OTP_TTL_SECONDS)

    session = OtpSession(
        phone=phone,
        otp_hash=otp_hash,
        expires_at=expires_at,
        verified=False,
    )
    db.add(session)
    await db.commit()
    return otp


async def verify_otp(db: AsyncSession, phone: str, otp: str) -> Optional[OtpSession]:
    """
    Verify OTP for a phone number.
    Returns the OtpSession on success, None on failure.
    Marks the session as verified to prevent reuse.
    """
    now = datetime.utcnow()

    result = await db.execute(
        select(OtpSession)
        .where(
            OtpSession.phone == phone,
            OtpSession.verified == False,  # noqa: E712
            OtpSession.expires_at > now,
        )
        .order_by(OtpSession.created_at.desc())
        .limit(1)
    )
    session = result.scalar_one_or_none()

    if not session:
        return None

    if not bcrypt.checkpw(otp.encode(), session.otp_hash.encode()):
        return None

    session.verified = True
    await db.commit()
    return session
