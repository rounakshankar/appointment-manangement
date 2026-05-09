"""
Appointment Service

Handles appointment creation with capacity checks, queue assignment,
and SSE event emission.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.appointment import Appointment, AppointmentStatus
from cacms.models.doctor import Doctor
from cacms.models.patient import Patient
from cacms.schemas.appointment import AppointmentCreate
from cacms.services import queue_manager
from cacms.services.sse_bus import sse_bus


async def get_patient(db: AsyncSession, patient_id: uuid.UUID, clinic_id: uuid.UUID) -> Patient | None:
    result = await db.execute(
        select(Patient).where(Patient.patient_id == patient_id, Patient.clinic_id == clinic_id)
    )
    return result.scalar_one_or_none()


async def get_doctor(db: AsyncSession, doctor_id: uuid.UUID, clinic_id: uuid.UUID) -> Doctor | None:
    result = await db.execute(
        select(Doctor).where(Doctor.doctor_id == doctor_id, Doctor.clinic_id == clinic_id)
    )
    return result.scalar_one_or_none()


async def check_followup_conflict(
    db: AsyncSession,
    patient_id: uuid.UUID,
    doctor_id: uuid.UUID,
    scheduled_date: date,
    clinic_id: uuid.UUID,
) -> bool:
    """Return True if a follow-up appointment already exists for (patient_id, doctor_id, scheduled_date)."""
    result = await db.execute(
        select(func.count()).where(
            Appointment.patient_id == patient_id,
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == scheduled_date,
            Appointment.clinic_id == clinic_id,
        )
    )
    return result.scalar_one() > 0


async def count_active_appointments(
    db: AsyncSession,
    doctor_id: uuid.UUID,
    scheduled_date: date,
    clinic_id: uuid.UUID,
) -> int:
    """Count scheduled + in-progress appointments for a doctor on a given date."""
    result = await db.execute(
        select(func.count()).where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == scheduled_date,
            Appointment.clinic_id == clinic_id,
            Appointment.status.in_([AppointmentStatus.scheduled, AppointmentStatus.in_progress]),
        )
    )
    return result.scalar_one()


async def get_daily_dashboard(
    db: AsyncSession,
    doctor_id: uuid.UUID,
    scheduled_date: date,
    clinic_id: uuid.UUID,
) -> dict:
    """
    Return dashboard data for a doctor on a given date:
    - total: all appointments for that doctor/date
    - completed: appointments with status=completed
    - remaining: appointments with status=scheduled
    - queue: all appointments ordered by queue_number ASC, with patient_name joined
    """
    from sqlalchemy.orm import selectinload

    # Fetch all appointments for doctor/date, eager-load patient
    stmt = (
        select(Appointment)
        .options(selectinload(Appointment.patient))
        .where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == scheduled_date,
            Appointment.clinic_id == clinic_id,
        )
        .order_by(Appointment.queue_number.asc())
    )
    result = await db.execute(stmt)
    appointments = result.scalars().all()

    total = len(appointments)
    completed = sum(1 for a in appointments if a.status == AppointmentStatus.completed)
    remaining = sum(1 for a in appointments if a.status == AppointmentStatus.scheduled)

    return {
        "total": total,
        "completed": completed,
        "remaining": remaining,
        "queue": appointments,
    }


async def get_appointment_by_id(
    db: AsyncSession,
    appointment_id: uuid.UUID,
    clinic_id: uuid.UUID | None = None,
) -> Appointment | None:
    """Fetch a single appointment by ID with patient eager-loaded."""
    from sqlalchemy.orm import selectinload

    stmt = (
        select(Appointment)
        .options(selectinload(Appointment.patient))
        .where(Appointment.appointment_id == appointment_id)
    )
    if clinic_id is not None:
        stmt = stmt.where(Appointment.clinic_id == clinic_id)
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


async def update_appointment_status(
    db: AsyncSession,
    appointment_id: uuid.UUID,
    new_status: str,
    clinic_id: uuid.UUID,
) -> Appointment:
    """
    Update appointment status to 'no-show' or 'cancelled'.

    - Does NOT reassign queue_number (req 12.2).
    - Caller is responsible for emitting SSE and committing.

    Raises:
        ValueError("APPOINTMENT_NOT_FOUND") if appointment does not exist.
    """
    from datetime import datetime

    appointment = await get_appointment_by_id(db, appointment_id, clinic_id)
    if appointment is None:
        raise ValueError("APPOINTMENT_NOT_FOUND")

    appointment.status = AppointmentStatus(new_status)
    appointment.updated_at = datetime.utcnow()
    return appointment


async def create_appointment(db: AsyncSession, data: AppointmentCreate, clinic_id: uuid.UUID) -> Appointment:
    """
    Create a new appointment.

    Steps:
    1. Validate patient and doctor exist.
    2. Check doctor daily capacity.
    3. Assign queue number via queue_manager.
    4. Persist Appointment with status=scheduled.
    5. Emit appointment_created SSE event.

    Raises:
        ValueError("PATIENT_NOT_FOUND") if patient does not exist.
        ValueError("DOCTOR_NOT_FOUND") if doctor does not exist.
        ValueError("DOCTOR_CAPACITY_REACHED") if doctor is at daily limit.
    """
    patient = await get_patient(db, data.patient_id, clinic_id)
    if patient is None:
        raise ValueError("PATIENT_NOT_FOUND")

    doctor = await get_doctor(db, data.doctor_id, clinic_id)
    if doctor is None:
        raise ValueError("DOCTOR_NOT_FOUND")

    if data.visit_type == "follow-up":
        conflict = await check_followup_conflict(
            db, data.patient_id, data.doctor_id, data.scheduled_date, clinic_id
        )
        if conflict:
            raise ValueError("FOLLOWUP_CONFLICT")

    active_count = await count_active_appointments(db, data.doctor_id, data.scheduled_date, clinic_id)
    if active_count >= doctor.max_patients_per_day:
        raise ValueError("DOCTOR_CAPACITY_REACHED")

    queue_number = await queue_manager.assign_queue_number(
        db, data.doctor_id, data.scheduled_date, data.visit_type, clinic_id
    )

    appointment = Appointment(
        appointment_id=uuid.uuid4(),
        patient_id=data.patient_id,
        doctor_id=data.doctor_id,
        scheduled_date=data.scheduled_date,
        queue_number=queue_number,
        visit_type=data.visit_type,
        status=AppointmentStatus.scheduled,
        clinic_id=clinic_id,
    )
    db.add(appointment)

    # Emit SSE event (persisted within the same transaction)
    await sse_bus.publish(
        channel=f"doctor:{data.doctor_id}",
        event_type="appointment_created",
        data={
            "appointment_id": str(appointment.appointment_id),
            "patient_id": str(appointment.patient_id),
            "doctor_id": str(appointment.doctor_id),
            "queue_number": queue_number,
            "visit_type": data.visit_type,
            "status": AppointmentStatus.scheduled.value,
            "scheduled_date": data.scheduled_date.isoformat(),
        },
    )

    await db.commit()
    await db.refresh(appointment)
    return appointment
