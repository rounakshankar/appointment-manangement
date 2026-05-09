"""
Queue Manager Service

Handles atomic queue number assignment and queue advancement using
PostgreSQL advisory locks to prevent race conditions under concurrent load.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select, func, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.appointment import Appointment, AppointmentStatus, VisitType
from cacms.schemas.appointment import CallNextResult
from cacms.services.sse_bus import sse_bus


def _lock_key(doctor_id: uuid.UUID, scheduled_date: date) -> int:
    """Derive a positive 64-bit advisory lock key from (doctor_id, scheduled_date)."""
    return hash((str(doctor_id), scheduled_date.isoformat())) & 0x7FFFFFFFFFFFFFFF


async def assign_queue_number(
    db: AsyncSession,
    doctor_id: uuid.UUID,
    scheduled_date: date,
    visit_type: str,
    clinic_id: uuid.UUID,
) -> int:
    """
    Assign the next queue number for a given doctor/date/visit_type.

    - Acquires a PostgreSQL transaction-level advisory lock keyed on
      (doctor_id, scheduled_date) to serialise concurrent inserts.
    - For normal/follow-up: MAX(queue_number) + 1.
    - For emergency: shift all existing scheduled appointments up by 1,
      then assign queue_number = 1 (or current_min - 1 if gaps exist).
    - The UNIQUE constraint uq_appointments_queue acts as the final guard.

    References: Requirements 2.2, 2.3, 2.4, 2.6, 14.3
    """
    lock_key = _lock_key(doctor_id, scheduled_date)
    await db.execute(
        text("SELECT pg_advisory_xact_lock(:key)"),
        {"key": lock_key},
    )

    if visit_type == VisitType.emergency.value or visit_type == VisitType.emergency:
        # Fetch the current minimum queue number among ALL appointments (any status)
        abs_min_result = await db.execute(
            select(func.min(Appointment.queue_number)).where(
                Appointment.doctor_id == doctor_id,
                Appointment.scheduled_date == scheduled_date,
                Appointment.clinic_id == clinic_id,
            )
        )
        abs_min: int | None = abs_min_result.scalar()

        if abs_min is None:
            # No appointments at all — start at 1
            return 1

        if abs_min > 1:
            # Free slot below the current minimum — use it without shifting
            return abs_min - 1

        # abs_min == 1: shift ALL appointments up by 1 to free slot 1.
        # We shift every row (all statuses) to avoid UNIQUE constraint violations
        # from completed/in-progress rows that sit at low queue numbers.
        # Two-step: add large offset first, then subtract (offset - 1) to land at +1.
        max_result = await db.execute(
            select(func.max(Appointment.queue_number)).where(
                Appointment.doctor_id == doctor_id,
                Appointment.scheduled_date == scheduled_date,
                Appointment.clinic_id == clinic_id,
            )
        )
        current_max: int = max_result.scalar() or 1
        safe_offset = current_max + 10000

        await db.execute(
            text(
                """
                UPDATE appointments
                SET queue_number = queue_number + :offset
                WHERE doctor_id = :doctor_id
                  AND scheduled_date = :scheduled_date
                  AND clinic_id = :clinic_id
                """
            ),
            {
                "doctor_id": str(doctor_id),
                "scheduled_date": scheduled_date,
                "clinic_id": str(clinic_id),
                "offset": safe_offset,
            },
        )
        await db.execute(
            text(
                """
                UPDATE appointments
                SET queue_number = queue_number - :offset + 1
                WHERE doctor_id = :doctor_id
                  AND scheduled_date = :scheduled_date
                  AND clinic_id = :clinic_id
                """
            ),
            {
                "doctor_id": str(doctor_id),
                "scheduled_date": scheduled_date,
                "clinic_id": str(clinic_id),
                "offset": safe_offset,
            },
        )
        return 1

    else:
        # normal or follow-up: MAX + 1
        max_result = await db.execute(
            select(func.max(Appointment.queue_number)).where(
                Appointment.doctor_id == doctor_id,
                Appointment.scheduled_date == scheduled_date,
                Appointment.clinic_id == clinic_id,
            )
        )
        current_max: int | None = max_result.scalar()
        return (current_max or 0) + 1


async def call_next(
    db: AsyncSession,
    doctor_id: uuid.UUID,
    scheduled_date: date,
    clinic_id: uuid.UUID,
) -> CallNextResult:
    """
    Advance the queue for a given doctor/date.

    Within a single transaction:
    1. SELECT FOR UPDATE SKIP LOCKED on the current in-progress appointment.
       If a row exists but cannot be locked (another transaction holds it),
       return QUEUE_CONFLICT. If no in-progress row exists, proceed to step 3.
    2. Mark the locked appointment as completed.
    3. Select the appointment with the minimum queue_number where status=scheduled.
    4. Mark it in-progress.
    5. Emit SSE events: queue_updated → doctor channel, status_changed → patient channel.

    If no scheduled appointments remain, returns CallNextResult(queue_empty=True).

    References: Requirements 4.1–4.5
    """
    # Step 1: Check whether an in-progress appointment exists at all
    # We use a plain SELECT first to detect the "locked by another tx" case.
    check_stmt = (
        select(Appointment)
        .where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == scheduled_date,
            Appointment.clinic_id == clinic_id,
            Appointment.status == AppointmentStatus.in_progress,
        )
        .limit(1)
    )
    check_result = await db.execute(check_stmt)
    existing_in_progress: Appointment | None = check_result.scalar_one_or_none()

    completed_id: uuid.UUID | None = None

    if existing_in_progress is not None:
        # Try to acquire a SKIP LOCKED lock — if we can't, another tx is processing it
        lock_stmt = (
            select(Appointment)
            .where(
                Appointment.appointment_id == existing_in_progress.appointment_id,
                Appointment.clinic_id == clinic_id,
                Appointment.status == AppointmentStatus.in_progress,
            )
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        lock_result = await db.execute(lock_stmt)
        locked_appt: Appointment | None = lock_result.scalar_one_or_none()

        if locked_appt is None:
            # Row exists but is locked by a concurrent Call Next — return conflict
            return CallNextResult(
                completed_appointment_id=None,
                next_appointment_id=None,
                queue_empty=False,
                conflict=True,
            )

        # Step 2: Mark as completed
        locked_appt.status = AppointmentStatus.completed
        db.add(locked_appt)
        completed_id = locked_appt.appointment_id

    # Step 3: Select next scheduled appointment (minimum queue_number)
    next_stmt = (
        select(Appointment)
        .where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == scheduled_date,
            Appointment.clinic_id == clinic_id,
            Appointment.status == AppointmentStatus.scheduled,
        )
        .order_by(Appointment.queue_number.asc())
        .limit(1)
    )
    next_result = await db.execute(next_stmt)
    next_appt: Appointment | None = next_result.scalar_one_or_none()

    if next_appt is None:
        # Emit queue_updated even when queue is empty (completed last patient)
        await sse_bus.publish(
            channel=f"doctor:{doctor_id}",
            event_type="queue_updated",
            data={
                "doctor_id": str(doctor_id),
                "scheduled_date": scheduled_date.isoformat(),
                "completed_appointment_id": str(completed_id) if completed_id else None,
                "next_appointment_id": None,
                "queue_empty": True,
            },
        )
        return CallNextResult(
            completed_appointment_id=completed_id,
            next_appointment_id=None,
            queue_empty=True,
        )

    # Step 4: Mark next appointment as in-progress
    next_appt.status = AppointmentStatus.in_progress
    db.add(next_appt)

    # Step 5: Emit SSE events
    await sse_bus.publish(
        channel=f"doctor:{doctor_id}",
        event_type="queue_updated",
        data={
            "doctor_id": str(doctor_id),
            "scheduled_date": scheduled_date.isoformat(),
            "completed_appointment_id": str(completed_id) if completed_id else None,
            "next_appointment_id": str(next_appt.appointment_id),
            "queue_empty": False,
        },
    )
    await sse_bus.publish(
        channel=f"patient:{next_appt.patient_id}",
        event_type="status_changed",
        data={
            "appointment_id": str(next_appt.appointment_id),
            "patient_id": str(next_appt.patient_id),
            "doctor_id": str(doctor_id),
            "status": AppointmentStatus.in_progress.value,
            "queue_number": next_appt.queue_number,
        },
    )

    return CallNextResult(
        completed_appointment_id=completed_id,
        next_appointment_id=next_appt.appointment_id,
        queue_empty=False,
    )
