"""
Public router — unauthenticated endpoints for patients and public queue display.

All endpoints in this router are intentionally unauthenticated. They expose
only non-sensitive, aggregate, or privacy-preserving information.

Endpoints:
  POST /v1/public/request-records                          — email medical records (Task 5.3)
  GET  /v1/public/queue/{clinic_id}/{doctor_id}            — queue status (Task 18.1)
  GET  /v1/public/clinic/{clinic_id}                       — clinic + doctor list (Task 18.2)
  GET  /v1/public/events/queue/{clinic_id}/{doctor_id}     — live queue SSE (Task 18.3)

Rate limiting:
  - /request-records: 3/hour per phone number
  - /queue/* and /clinic/*: 60/minute per IP
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import date
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.database import get_db
from cacms.limiter import limiter
from cacms.models.appointment import Appointment, AppointmentStatus
from cacms.models.clinic import Clinic
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.models.doctor import Doctor
from cacms.services.email_service import ConsultationSummary, EmailService
from cacms.services.patient_service import get_patient_by_phone
from cacms.services.sse_bus import sse_bus

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/public", tags=["public"])

_PUBLIC_RATE_LIMIT = "60/minute"
_RECORDS_RATE_LIMIT = "3/hour"
_KEEP_ALIVE_INTERVAL = 15  # seconds


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _phone_key(request: Request) -> str:
    """Rate-limit key based on the phone number in the request body."""
    try:
        body = request._body  # type: ignore[attr-defined]
        if body:
            data = json.loads(body)
            phone = data.get("phone", "")
            if phone:
                return f"phone:{phone}"
    except Exception:
        pass
    from slowapi.util import get_remote_address
    return get_remote_address(request)


async def _get_clinic_or_404(db: AsyncSession, clinic_id: uuid.UUID) -> Clinic:
    result = await db.execute(select(Clinic).where(Clinic.clinic_id == clinic_id))
    clinic = result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"},
        )
    return clinic


async def _get_doctor_or_404(
    db: AsyncSession, doctor_id: uuid.UUID, clinic_id: uuid.UUID
) -> Doctor:
    result = await db.execute(
        select(Doctor).where(Doctor.doctor_id == doctor_id, Doctor.clinic_id == clinic_id)
    )
    doctor = result.scalar_one_or_none()
    if doctor is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "DOCTOR_NOT_FOUND", "message": "Doctor not found"},
        )
    return doctor


def _format_sse(event_type: str, payload: dict) -> str:
    return f"event: {event_type}\ndata: {json.dumps(payload)}\n\n"


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class RecordRequestBody(BaseModel):
    phone: str
    email: EmailStr

    @field_validator("phone")
    @classmethod
    def phone_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("phone must not be empty")
        return v


_PRIVACY_RESPONSE = {
    "message": (
        "If a patient record exists for this phone number, "
        "a summary will be sent to the provided email"
    )
}


# ---------------------------------------------------------------------------
# Task 5.3 — POST /v1/public/request-records
# ---------------------------------------------------------------------------


@router.post("/request-records", status_code=200)
@limiter.limit(_RECORDS_RATE_LIMIT, key_func=_phone_key)
async def request_records(
    request: Request,
    body: RecordRequestBody,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Email the last 5 consultation summaries to the provided address.

    Always returns the same response regardless of whether the patient exists
    (prevents phone enumeration). Rate-limited to 3/hour per phone number.
    """
    patient = await get_patient_by_phone(db, body.phone)

    if patient is None:
        logger.info("public/request-records: no patient found, returning privacy response")
        return _PRIVACY_RESPONSE

    stmt = (
        select(Consultation)
        .join(Consultation.appointment)
        .options(
            selectinload(Consultation.appointment).selectinload(Appointment.doctor),
            selectinload(Consultation.services).selectinload(ConsultationService.service),
        )
        .where(Appointment.patient_id == patient.patient_id)
        .order_by(Consultation.created_at.desc())
        .limit(5)
    )
    result = await db.execute(stmt)
    consultations = result.scalars().all()

    if not consultations:
        logger.info(
            "public/request-records: patient %s has no consultations", patient.patient_id
        )
        return _PRIVACY_RESPONSE

    summaries: list[ConsultationSummary] = []
    for c in consultations:
        appt = c.appointment
        doctor_name = appt.doctor.name if appt.doctor else str(appt.doctor_id)
        service_lines = [
            f"{cs.service.name if cs.service else cs.service_id} x {cs.quantity}"
            for cs in c.services
        ]
        summaries.append(
            ConsultationSummary(
                consultation_id=str(c.consultation_id),
                date=c.created_at.date(),
                doctor_name=doctor_name,
                symptoms=c.symptoms,
                diagnosis=c.diagnosis,
                notes=c.notes,
                next_visit_date=c.next_visit_date,
                services=service_lines,
            )
        )

    await EmailService.send_visit_summary(
        patient_email=str(body.email),
        patient_name=patient.name,
        consultations=summaries,
    )
    return _PRIVACY_RESPONSE


# ---------------------------------------------------------------------------
# Task 18.1 — GET /v1/public/queue/{clinic_id}/{doctor_id}
# ---------------------------------------------------------------------------


@router.get("/queue/{clinic_id}/{doctor_id}")
@limiter.limit(_PUBLIC_RATE_LIMIT)
async def get_public_queue(
    request: Request,
    clinic_id: uuid.UUID,
    doctor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Return the current queue status for a doctor — no auth required.

    Returns only queue numbers and counts. No patient names, phone numbers,
    or medical data are included.
    """
    clinic = await _get_clinic_or_404(db, clinic_id)
    doctor = await _get_doctor_or_404(db, doctor_id, clinic_id)

    today = date.today()

    # Current in-progress appointment queue number
    in_progress_result = await db.execute(
        select(Appointment.queue_number)
        .where(
            Appointment.clinic_id == clinic_id,
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == today,
            Appointment.status == AppointmentStatus.in_progress,
        )
        .limit(1)
    )
    current_queue_number = in_progress_result.scalar_one_or_none()

    # Count remaining scheduled appointments
    scheduled_result = await db.execute(
        select(func.count()).where(
            Appointment.clinic_id == clinic_id,
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == today,
            Appointment.status == AppointmentStatus.scheduled,
        )
    )
    total_scheduled: int = scheduled_result.scalar_one()

    estimated_wait_minutes = total_scheduled * 10  # 10 min per patient default

    return {
        "clinic_name": clinic.name,
        "doctor_name": doctor.name,
        "specialization": doctor.specialization,
        "current_queue_number": current_queue_number,
        "total_scheduled": total_scheduled,
        "estimated_wait_minutes": estimated_wait_minutes,
    }


# ---------------------------------------------------------------------------
# Task 18.2 — GET /v1/public/clinic/{clinic_id}
# ---------------------------------------------------------------------------


@router.get("/clinic/{clinic_id}")
@limiter.limit(_PUBLIC_RATE_LIMIT)
async def get_public_clinic_info(
    request: Request,
    clinic_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Return clinic name and list of active doctors — no auth required.

    Used by the public queue page to let patients pick their doctor.
    ``is_accepting_patients`` is true when the doctor's scheduled count
    for today is below their daily maximum.
    """
    clinic = await _get_clinic_or_404(db, clinic_id)

    doctors_result = await db.execute(
        select(Doctor)
        .where(Doctor.clinic_id == clinic_id, Doctor.active == True)  # noqa: E712
        .order_by(Doctor.name)
    )
    doctors = doctors_result.scalars().all()

    today = date.today()
    doctor_list = []
    for doc in doctors:
        scheduled_result = await db.execute(
            select(func.count()).where(
                Appointment.clinic_id == clinic_id,
                Appointment.doctor_id == doc.doctor_id,
                Appointment.scheduled_date == today,
                Appointment.status == AppointmentStatus.scheduled,
            )
        )
        scheduled_count: int = scheduled_result.scalar_one()
        is_accepting = scheduled_count < doc.max_patients_per_day

        doctor_list.append({
            "doctor_id": str(doc.doctor_id),
            "name": doc.name,
            "specialization": doc.specialization,
            "is_accepting_patients": is_accepting,
        })

    return {
        "clinic_name": clinic.name,
        "doctors": doctor_list,
    }


# ---------------------------------------------------------------------------
# Task 18.3 — GET /v1/public/events/queue/{clinic_id}/{doctor_id}
# ---------------------------------------------------------------------------

# Fields that must be stripped from public SSE payloads to prevent
# patient data exposure.
_PATIENT_FIELDS = frozenset({"patient_id", "patient_name", "phone", "name"})


def _sanitise_payload(payload: dict) -> dict:
    """Remove patient-identifying fields from an SSE event payload."""
    return {k: v for k, v in payload.items() if k not in _PATIENT_FIELDS}


async def _public_queue_generator(
    clinic_id: uuid.UUID,
    doctor_id: uuid.UUID,
) -> AsyncGenerator[str, None]:
    """Yield sanitised SSE events from the doctor's internal channel."""
    channel = f"doctor:{doctor_id}"
    merged: asyncio.Queue = asyncio.Queue(maxsize=256)

    async def _forward() -> None:
        try:
            async for event in sse_bus.subscribe(channel):
                await merged.put(event)
        except asyncio.CancelledError:
            pass
        finally:
            await merged.put(StopAsyncIteration())

    async def _keep_alive() -> None:
        try:
            while True:
                await asyncio.sleep(_KEEP_ALIVE_INTERVAL)
                await merged.put(None)
        except asyncio.CancelledError:
            pass

    forward_task = asyncio.create_task(_forward())
    keep_alive_task = asyncio.create_task(_keep_alive())

    try:
        while True:
            item = await merged.get()
            if isinstance(item, StopAsyncIteration):
                break
            if item is None:
                yield ": keep-alive\n\n"
            else:
                # Strip all patient identifiers before forwarding
                safe_payload = _sanitise_payload(item.data)
                # Only include queue-relevant fields
                public_payload = {
                    "event_type": item.event_type,
                    "current_queue_number": safe_payload.get("queue_number"),
                    "total_scheduled": safe_payload.get("total_scheduled"),
                }
                yield _format_sse(item.event_type, public_payload)
    except (asyncio.CancelledError, GeneratorExit):
        logger.debug("Public SSE generator for doctor %s closing", doctor_id)
    finally:
        forward_task.cancel()
        keep_alive_task.cancel()


@router.get("/events/queue/{clinic_id}/{doctor_id}")
async def public_queue_sse(
    clinic_id: uuid.UUID,
    doctor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Live queue updates — no auth required.

    Subscribes to the internal doctor SSE channel and forwards events with
    all patient identifiers stripped. Only queue numbers and counts are sent.
    """
    # Validate clinic and doctor exist
    await _get_clinic_or_404(db, clinic_id)
    await _get_doctor_or_404(db, doctor_id, clinic_id)

    return StreamingResponse(
        _public_queue_generator(clinic_id, doctor_id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
