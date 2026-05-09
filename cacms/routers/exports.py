import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import PlainTextResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin_or_doctor
from cacms.models.appointment import Appointment
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.models.payment import Payment
from cacms.schemas.common import ErrorResponse

router = APIRouter(prefix="/exports", tags=["exports"])


@router.get(
    "/receipt/{payment_id}",
    response_class=PlainTextResponse,
    responses={404: {"model": ErrorResponse}},
)
async def export_receipt(
    payment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner_or_admin_or_doctor),
):
    result = await db.execute(
        select(Payment)
        .options(
            selectinload(Payment.consultation)
            .selectinload(Consultation.appointment)
            .selectinload(Appointment.patient),
            selectinload(Payment.consultation)
            .selectinload(Consultation.appointment)
            .selectinload(Appointment.doctor),
        )
        .where(Payment.payment_id == payment_id, Payment.clinic_id == user.clinic_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "PAYMENT_NOT_FOUND", "message": "Payment not found."},
        )

    appt = payment.consultation.appointment
    if user.is_doctor and appt.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot export another doctor's receipt."},
        )

    return "\n".join([
        "CACMS RECEIPT",
        f"Receipt ID: {payment.payment_id}",
        f"Date: {payment.created_at.date()}",
        f"Patient: {appt.patient.name if appt.patient else appt.patient_id}",
        f"Doctor: {appt.doctor.name if appt.doctor else appt.doctor_id}",
        f"Amount: {payment.total_amount}",
        f"Mode: {payment.payment_mode.value}",
        f"Status: {payment.status.value}",
    ])


@router.get(
    "/prescription/{consultation_id}",
    response_class=PlainTextResponse,
    responses={404: {"model": ErrorResponse}},
)
async def export_prescription(
    consultation_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner_or_admin_or_doctor),
):
    result = await db.execute(
        select(Consultation)
        .options(
            selectinload(Consultation.appointment).selectinload(Appointment.patient),
            selectinload(Consultation.appointment).selectinload(Appointment.doctor),
            selectinload(Consultation.services).selectinload(ConsultationService.service),
        )
        .where(Consultation.consultation_id == consultation_id, Consultation.clinic_id == user.clinic_id)
    )
    consultation = result.scalar_one_or_none()
    if consultation is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CONSULTATION_NOT_FOUND", "message": "Consultation not found."},
        )

    appt = consultation.appointment
    if user.is_doctor and appt.doctor_id != user.doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot export another doctor's prescription."},
        )

    service_lines = [
        f"- {item.service.name if item.service else item.service_id} x {item.quantity}: {item.total}"
        for item in consultation.services
    ] or ["- No services recorded"]

    return "\n".join([
        "CACMS CONSULTATION SUMMARY",
        f"Consultation ID: {consultation.consultation_id}",
        f"Date: {consultation.created_at.date()}",
        f"Patient: {appt.patient.name if appt.patient else appt.patient_id}",
        f"Doctor: {appt.doctor.name if appt.doctor else appt.doctor_id}",
        "",
        f"Symptoms: {consultation.symptoms}",
        f"Diagnosis: {consultation.diagnosis}",
        f"Notes: {consultation.notes or '-'}",
        f"Next Visit: {consultation.next_visit_date or '-'}",
        "",
        "Services:",
        *service_lines,
    ])
