import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin_or_doctor, require_doctor
from cacms.models.appointment import Appointment
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.schemas.common import ErrorResponse
from cacms.schemas.consultation import ConsultationCreate, ConsultationOut, ConsultationServiceOut, FollowUpPrompt
from cacms.services.consultation_service import create_consultation

router = APIRouter(prefix="/consultations", tags=["consultations"])

_CREATE_ERROR_MAP = {
    "APPOINTMENT_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "Appointment not found"),
    "FORBIDDEN": (status.HTTP_403_FORBIDDEN, "Appointment belongs to a different doctor"),
    "CONSULTATION_EXISTS": (status.HTTP_409_CONFLICT, "A consultation already exists for this appointment"),
    "SERVICE_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "Service not found"),
}


def _build_consultation_out(consultation) -> ConsultationOut:
    services_out = [
        ConsultationServiceOut(
            id=svc.id,
            service_id=svc.service_id,
            quantity=svc.quantity,
            price_applied=svc.price_applied,
            total=svc.total,
            service_name=svc.service.name if svc.service else None,
        )
        for svc in consultation.services
    ]

    follow_up_prompt = None
    if consultation.next_visit_date is not None:
        appt = consultation.appointment
        follow_up_prompt = FollowUpPrompt(
            patient_id=appt.patient_id,
            doctor_id=appt.doctor_id,
            scheduled_date=consultation.next_visit_date,
            visit_type="follow-up",
        )

    return ConsultationOut(
        consultation_id=consultation.consultation_id,
        appointment_id=consultation.appointment_id,
        symptoms=consultation.symptoms,
        diagnosis=consultation.diagnosis,
        notes=consultation.notes,
        next_visit_date=consultation.next_visit_date,
        services=services_out,
        created_at=consultation.created_at,
        follow_up_prompt=follow_up_prompt,
    )


@router.post(
    "",
    response_model=ConsultationOut,
    status_code=status.HTTP_201_CREATED,
    responses={
        403: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
)
async def create_consultation_endpoint(
    body: ConsultationCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_doctor),
):
    """
    Create a consultation for an appointment.

    - Validates appointment belongs to the requesting doctor.
    - Rejects with 409 if a consultation already exists for the appointment.
    - Creates Consultation and ConsultationService line items.
    - If next_visit_date is set, includes a FollowUpPrompt in the response.
    - Emits consultation_completed SSE to doctor and patient channels.

    Requirements: 5.1–5.6, 11.1
    """
    try:
        consultation = await create_consultation(db, body, user.doctor_id, user.clinic_id)
    except ValueError as exc:
        error_code = str(exc)
        http_status, message = _CREATE_ERROR_MAP.get(
            error_code, (status.HTTP_400_BAD_REQUEST, error_code)
        )
        raise HTTPException(
            status_code=http_status,
            detail={"error_code": error_code, "message": message},
        )

    return _build_consultation_out(consultation)


@router.get(
    "/{appointment_id}",
    response_model=ConsultationOut,
    responses={
        403: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
    },
)
async def get_consultation_endpoint(
    appointment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor),
):
    """
    Return the consultation for a given appointment_id.

    - Doctor role: restricted to their own appointments.
    - Admin role: can access any consultation.

    Requirements: 5.5
    """
    # Fetch consultation with services and appointment eagerly loaded
    result = await db.execute(
        select(Consultation)
        .options(
            selectinload(Consultation.services).selectinload(ConsultationService.service),
            selectinload(Consultation.appointment),
        )
        .where(Consultation.appointment_id == appointment_id)
        .where(Consultation.clinic_id == user.clinic_id)
    )
    consultation = result.scalar_one_or_none()

    if consultation is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CONSULTATION_NOT_FOUND", "message": "No consultation found for this appointment"},
        )

    if user.is_doctor and consultation.appointment.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Access to another doctor's consultation is not allowed"},
        )

    return _build_consultation_out(consultation)
