import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from cacms.models.patient import Patient
from cacms.schemas.patient import PatientCreate


def normalise_phone(phone: str) -> str:
    """
    Normalise a phone number to E.164 format with +91 prefix.
    Accepts: 9876543210 / 09876543210 / +919876543210 / 919876543210
    Returns: +919876543210
    """
    p = phone.strip().replace(" ", "").replace("-", "")
    if p.startswith("+91"):
        p = p[3:]
    elif p.startswith("91") and len(p) == 12:
        p = p[2:]
    elif p.startswith("0") and len(p) == 11:
        p = p[1:]
    # Keep only digits now
    p = "".join(c for c in p if c.isdigit())
    return f"+91{p}"


def _bare_digits(phone: str) -> str:
    """Return just the 10-digit number without any prefix."""
    p = normalise_phone(phone)
    return p[3:]  # strip +91


async def get_patient_by_phone(
    db: AsyncSession,
    phone: str,
    clinic_id: uuid.UUID | None = None,
) -> Optional[Patient]:
    """
    Lookup patient by phone. Tries three formats:
    1. Normalised: +91XXXXXXXXXX
    2. Raw input as-is
    3. Bare 10 digits (for legacy records stored without prefix)
    """
    candidates = list(dict.fromkeys([
        normalise_phone(phone),
        phone.strip(),
        _bare_digits(phone),
    ]))
    for candidate in candidates:
        stmt = select(Patient).where(Patient.phone == candidate)
        if clinic_id is not None:
            stmt = stmt.where(Patient.clinic_id == clinic_id)
        result = await db.execute(stmt)
        patient = result.scalar_one_or_none()
        if patient is not None:
            return patient
    return None


async def create_patient(db: AsyncSession, data: PatientCreate, clinic_id: uuid.UUID) -> Patient:
    """
    Create a new patient with UUID PK, consent_given=True, consent_date=now().
    Phone is normalised to +91XXXXXXXXXX format before storage.
    Raises IntegrityError if phone already exists (caller should convert to 409).
    """
    patient = Patient(
        patient_id=uuid.uuid4(),
        name=data.name,
        phone=normalise_phone(data.phone),
        age=data.age,
        gender=data.gender,
        address=data.address,
        consent_given=True,
        consent_date=datetime.utcnow(),
        clinic_id=clinic_id,
    )
    db.add(patient)
    try:
        await db.commit()
        await db.refresh(patient)
    except IntegrityError:
        await db.rollback()
        raise
    return patient
