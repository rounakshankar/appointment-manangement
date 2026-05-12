"""
Exports router — patient receipts and consultation prescriptions.

GET /v1/exports/receipt/{payment_id}           — plain-text clinic-branded receipt
GET /v1/exports/receipt/{payment_id}?format=json — same data as structured JSON
GET /v1/exports/prescription/{consultation_id} — plain-text prescription summary
"""

import uuid
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin_or_doctor
from cacms.models.appointment import Appointment
from cacms.models.clinic import Clinic
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.models.payment import Payment
from cacms.schemas.common import ErrorResponse

router = APIRouter(prefix="/exports", tags=["exports"])


# ---------------------------------------------------------------------------
# Receipt rendering helpers
# ---------------------------------------------------------------------------


def _short_id(uid: uuid.UUID) -> str:
    """Return the last 8 hex chars of a UUID for compact receipt numbers."""
    return str(uid).replace("-", "")[-8:].upper()


def _build_receipt_lines(
    payment: Payment,
    clinic: Clinic,
) -> list[str]:
    """Build the plain-text receipt line list from payment + clinic profile.

    Null clinic profile fields are omitted entirely (no blank lines).
    """
    appt = payment.consultation.appointment
    patient_name = appt.patient.name if appt.patient else str(appt.patient_id)
    doctor_name = appt.doctor.name if appt.doctor else str(appt.doctor_id)

    header = clinic.receipt_header or clinic.name
    footer = clinic.receipt_footer or "Thank you for visiting"

    lines: list[str] = ["=" * 40, header]

    if clinic.clinic_address:
        lines.append(clinic.clinic_address)

    if clinic.clinic_phone:
        lines.append(f"Phone: {clinic.clinic_phone}")

    # GSTIN and Reg on the same line when both present, otherwise individually
    gstin_reg_parts = []
    if clinic.clinic_gstin:
        gstin_reg_parts.append(f"GSTIN: {clinic.clinic_gstin}")
    if clinic.clinic_reg_number:
        gstin_reg_parts.append(f"Reg: {clinic.clinic_reg_number}")
    if gstin_reg_parts:
        lines.append("   ".join(gstin_reg_parts))

    lines += [
        "=" * 40,
        "RECEIPT",
        f"Receipt No : {_short_id(payment.payment_id)}",
        f"Date       : {payment.created_at.date()}",
        "-" * 40,
        f"Patient    : {patient_name}",
        f"Doctor     : {doctor_name}",
        "-" * 40,
        "Services:",
    ]

    for cs in payment.consultation.services:
        svc_name = cs.service.name if cs.service else str(cs.service_id)
        lines.append(f"  {svc_name} x {cs.quantity}    \u20b9{cs.price_applied}")

    lines += [
        "-" * 40,
        f"Total      : \u20b9{payment.total_amount}",
        f"Paid via   : {payment.payment_mode.value}",
        f"Status     : {payment.status.value}",
        "=" * 40,
        footer,
        "=" * 40,
    ]
    return lines


def _build_receipt_json(payment: Payment, clinic: Clinic) -> dict:
    """Return the receipt data as a structured dict for Flutter rendering."""
    appt = payment.consultation.appointment
    return {
        "receipt_no": _short_id(payment.payment_id),
        "date": str(payment.created_at.date()),
        "clinic": {
            "name": clinic.receipt_header or clinic.name,
            "address": clinic.clinic_address,
            "phone": clinic.clinic_phone,
            "gstin": clinic.clinic_gstin,
            "reg_number": clinic.clinic_reg_number,
        },
        "patient": appt.patient.name if appt.patient else str(appt.patient_id),
        "doctor": appt.doctor.name if appt.doctor else str(appt.doctor_id),
        "services": [
            {
                "name": cs.service.name if cs.service else str(cs.service_id),
                "quantity": cs.quantity,
                "price": str(cs.price_applied),
                "total": str(cs.total),
            }
            for cs in payment.consultation.services
        ],
        "total_amount": str(payment.total_amount),
        "payment_mode": payment.payment_mode.value,
        "payment_status": payment.status.value,
        "footer": clinic.receipt_footer or "Thank you for visiting",
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get(
    "/receipt/{payment_id}",
    responses={
        200: {"content": {"text/plain": {}, "application/json": {}}},
        404: {"model": ErrorResponse},
    },
)
async def export_receipt(
    payment_id: uuid.UUID,
    format: Optional[Literal["json"]] = Query(None, description="Pass 'json' for structured output"),
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner_or_admin_or_doctor),
):
    """Return a clinic-branded patient receipt.

    - Default: plain-text formatted for printing.
    - ``?format=json``: structured JSON for Flutter to render a styled receipt card.

    Clinic profile fields (address, phone, GSTIN, reg number, header, footer)
    are pulled from the clinic record. Null fields are omitted from the output.
    """
    result = await db.execute(
        select(Payment)
        .options(
            selectinload(Payment.consultation)
            .selectinload(Consultation.appointment)
            .selectinload(Appointment.patient),
            selectinload(Payment.consultation)
            .selectinload(Consultation.appointment)
            .selectinload(Appointment.doctor),
            selectinload(Payment.consultation)
            .selectinload(Consultation.services)
            .selectinload(ConsultationService.service),
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

    # Fetch clinic profile
    clinic_result = await db.execute(
        select(Clinic).where(Clinic.clinic_id == user.clinic_id)
    )
    clinic = clinic_result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found."},
        )

    if format == "json":
        return JSONResponse(content=_build_receipt_json(payment, clinic))

    return PlainTextResponse("\n".join(_build_receipt_lines(payment, clinic)))


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
