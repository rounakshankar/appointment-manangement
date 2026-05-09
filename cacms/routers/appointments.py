import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin_or_receptionist, require_owner_or_admin_or_doctor, require_doctor
from cacms.schemas.appointment import AppointmentCreate, AppointmentOut, AppointmentStatusUpdate, CallNextResult, QueueDashboard
from cacms.schemas.common import ErrorResponse
from cacms.services.appointment_service import (
    create_appointment,
    get_appointment_by_id,
    get_daily_dashboard,
    update_appointment_status,
)
from cacms.services import queue_manager
from cacms.services.sse_bus import sse_bus

router = APIRouter(prefix="/appointments", tags=["appointments"])


@router.post(
    "",
    response_model=AppointmentOut,
    status_code=status.HTTP_201_CREATED,
    responses={
        404: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
)
async def book_appointment(
    body: AppointmentCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_receptionist),
):
    """
    Create a new appointment.

    - Validates patient and doctor exist (404 if not).
    - Checks doctor daily capacity (409 DOCTOR_CAPACITY_REACHED if at limit).
    - Assigns queue number atomically.
    - Persists appointment with status=scheduled.
    - Emits appointment_created SSE event to doctor:{doctor_id} channel.
    """
    _error_map = {
        "PATIENT_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "Patient not found"),
        "DOCTOR_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "Doctor not found"),
        "DOCTOR_CAPACITY_REACHED": (
            status.HTTP_409_CONFLICT,
            "Doctor has reached the maximum number of patients for today",
        ),
        "FOLLOWUP_CONFLICT": (
            status.HTTP_409_CONFLICT,
            "A follow-up appointment already exists for this patient, doctor, and date",
        ),
    }

    try:
        appointment = await create_appointment(db, body, user.clinic_id)
    except ValueError as exc:
        error_code = str(exc)
        http_status, message = _error_map.get(
            error_code, (status.HTTP_400_BAD_REQUEST, error_code)
        )
        raise HTTPException(
            status_code=http_status,
            detail={"error_code": error_code, "message": message},
        )

    return appointment


@router.get(
    "/today",
    response_model=QueueDashboard,
    responses={
        403: {"model": ErrorResponse},
    },
)
async def get_today_dashboard(
    doctor_id: uuid.UUID = Query(..., description="Doctor UUID to fetch dashboard for"),
    date: Optional[date] = Query(None, description="Date (YYYY-MM-DD); defaults to today"),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor),
):
    """
    Return the daily queue dashboard for a doctor.

    - Doctor role: restricted to their own doctor_id (from JWT).
    - Admin role: can query any doctor_id.
    - Returns total, completed, remaining (scheduled only), and queue ordered by queue_number ASC.
    """
    from datetime import date as date_type

    target_date = date if date is not None else date_type.today()

    # Enforce doctor can only see their own data (req 3.4)
    if user.is_doctor and user.doctor_id != doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Access to other doctor's data is not allowed"},
        )

    dashboard = await get_daily_dashboard(db, doctor_id, target_date, user.clinic_id)

    # Build AppointmentOut list with patient_name populated
    queue_out = []
    for appt in dashboard["queue"]:
        patient_name = appt.patient.name if appt.patient else None
        out = AppointmentOut(
            appointment_id=appt.appointment_id,
            patient_id=appt.patient_id,
            doctor_id=appt.doctor_id,
            scheduled_date=appt.scheduled_date,
            queue_number=appt.queue_number,
            visit_type=appt.visit_type,
            status=appt.status,
            created_at=appt.created_at,
            updated_at=appt.updated_at,
            patient_name=patient_name,
        )
        queue_out.append(out)

    return QueueDashboard(
        total=dashboard["total"],
        completed=dashboard["completed"],
        remaining=dashboard["remaining"],
        queue=queue_out,
    )


@router.get(
    "/{appointment_id}",
    response_model=AppointmentOut,
    responses={
        403: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
    },
)
async def get_appointment(
    appointment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor),
):
    """
    Return a single appointment by ID.

    - Includes patient_name, visit_type, queue_number, status.
    - Doctor role: restricted to appointments belonging to their own doctor_id.
    - Admin role: can access any appointment.
    """
    appt = await get_appointment_by_id(db, appointment_id, user.clinic_id)
    if appt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "APPOINTMENT_NOT_FOUND", "message": "Appointment not found"},
        )

    # Enforce doctor can only see their own appointments (req 3.4)
    if user.is_doctor and appt.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Access to other doctor's appointment is not allowed"},
        )

    patient_name = appt.patient.name if appt.patient else None
    return AppointmentOut(
        appointment_id=appt.appointment_id,
        patient_id=appt.patient_id,
        doctor_id=appt.doctor_id,
        scheduled_date=appt.scheduled_date,
        queue_number=appt.queue_number,
        visit_type=appt.visit_type,
        status=appt.status,
        created_at=appt.created_at,
        updated_at=appt.updated_at,
        patient_name=patient_name,
    )


@router.patch(
    "/{appointment_id}/clinical",
    response_model=CallNextResult,
    responses={
        404: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
)
async def call_next_patient(
    appointment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_doctor),
):
    """
    Advance the queue for the requesting doctor (Call Next).

    - Marks the current in-progress appointment as completed.
    - Marks the next scheduled appointment (lowest queue_number) as in-progress.
    - Emits queue_updated SSE to doctor channel and status_changed SSE to patient channel.
    - Returns QUEUE_CONFLICT (409) if a concurrent Call Next is already in progress.
    - Returns queue_empty=True when no scheduled appointments remain.

    The appointment_id path parameter identifies the doctor's context appointment
    (used to resolve doctor_id and scheduled_date).

    Requirements: 4.1–4.5
    """
    appt = await get_appointment_by_id(db, appointment_id, user.clinic_id)
    if appt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "APPOINTMENT_NOT_FOUND", "message": "Appointment not found"},
        )

    # Doctors can only advance their own queue
    if user.is_doctor and appt.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot advance another doctor's queue"},
        )

    result = await queue_manager.call_next(db, appt.doctor_id, appt.scheduled_date, user.clinic_id)

    if result.conflict:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error_code": "QUEUE_CONFLICT",
                "message": "A concurrent Call Next request is already in progress.",
            },
        )

    await db.commit()
    return result


@router.patch(
    "/{appointment_id}/status",
    response_model=AppointmentOut,
    responses={
        403: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
    },
)
async def update_status(
    appointment_id: uuid.UUID,
    body: AppointmentStatusUpdate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor),
):
    """
    Mark an appointment as no-show or cancelled.

    - Persists the status change without reassigning queue_number (req 12.2).
    - Emits queue_updated SSE to doctor:{doctor_id} channel (req 12.1).
    - Doctor role: restricted to their own appointments.

    Requirements: 12.1–12.3
    """
    try:
        appt = await update_appointment_status(db, appointment_id, body.status, user.clinic_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "APPOINTMENT_NOT_FOUND", "message": "Appointment not found"},
        )

    # Enforce doctor can only update their own appointments
    if user.is_doctor and appt.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot update another doctor's appointment"},
        )

    await sse_bus.publish(
        channel=f"doctor:{appt.doctor_id}",
        event_type="queue_updated",
        data={
            "appointment_id": str(appt.appointment_id),
            "doctor_id": str(appt.doctor_id),
            "queue_number": appt.queue_number,
            "status": body.status,
        },
    )

    await db.commit()
    await db.refresh(appt)

    patient_name = appt.patient.name if appt.patient else None
    return AppointmentOut(
        appointment_id=appt.appointment_id,
        patient_id=appt.patient_id,
        doctor_id=appt.doctor_id,
        scheduled_date=appt.scheduled_date,
        queue_number=appt.queue_number,
        visit_type=appt.visit_type,
        status=appt.status,
        created_at=appt.created_at,
        updated_at=appt.updated_at,
        patient_name=patient_name,
    )
