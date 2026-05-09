"""
Patient Status Service

Resolves the current appointment state for a patient and returns
the appropriate status response per requirement 8.1.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.models.appointment import Appointment, AppointmentStatus
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.schemas.patient_status import (
    AppointmentSummary,
    ConsultationSummary,
    LastVisitSummary,
    PatientStatusResponse,
    ServiceLineItem,
)


def _appt_to_summary(appt: Appointment) -> AppointmentSummary:
    return AppointmentSummary(
        appointment_id=str(appt.appointment_id),
        patient_id=str(appt.patient_id),
        doctor_id=str(appt.doctor_id),
        scheduled_date=appt.scheduled_date,
        queue_number=appt.queue_number,
        visit_type=appt.visit_type.value if hasattr(appt.visit_type, "value") else str(appt.visit_type),
        status=appt.status.value if hasattr(appt.status, "value") else str(appt.status),
        created_at=appt.created_at.isoformat(),
        updated_at=appt.updated_at.isoformat(),
        patient_name=None,
    )


def _consult_to_summary(consultation: Consultation, appt: Appointment) -> ConsultationSummary:
    services = [
        ServiceLineItem(
            id=str(cs.id),
            service_id=str(cs.service_id),
            quantity=cs.quantity,
            price_applied=float(cs.price_applied),
            total=float(cs.total) if cs.total is not None else None,
            service_name=cs.service.name if cs.service else None,
        )
        for cs in consultation.services
    ]
    return ConsultationSummary(
        consultation_id=str(consultation.consultation_id),
        appointment_id=str(consultation.appointment_id),
        symptoms=consultation.symptoms,
        diagnosis=consultation.diagnosis,
        notes=consultation.notes,
        next_visit_date=consultation.next_visit_date,
        services=services,
        created_at=consultation.created_at.isoformat(),
    )


async def get_patient_status(
    db: AsyncSession,
    patient_id: uuid.UUID,
    clinic_id: uuid.UUID,
) -> PatientStatusResponse:
    """
    Return the current appointment status for a patient.

    States (req 8.1):
    - no_appointment: no appointment today → show last visit summary
    - scheduled: today's appointment is scheduled → show queue position
    - in-progress: today's appointment is in-progress → indicate being seen
    - completed: today's appointment is completed → show diagnosis, services, next_visit_date
    """
    today = date.today()

    stmt = (
        select(Appointment)
        .options(
            selectinload(Appointment.doctor),
            selectinload(Appointment.consultation).selectinload(
                Consultation.services
            ).selectinload(ConsultationService.service),
        )
        .where(
            Appointment.patient_id == patient_id,
            Appointment.clinic_id == clinic_id,
            Appointment.scheduled_date == today,
            Appointment.status.in_([
                AppointmentStatus.scheduled,
                AppointmentStatus.in_progress,
                AppointmentStatus.completed,
            ]),
        )
        .order_by(Appointment.queue_number.asc())
        .limit(1)
    )
    result = await db.execute(stmt)
    today_appt = result.scalar_one_or_none()

    if today_appt is None:
        last_visit = await _get_last_visit_summary(db, patient_id, clinic_id)
        return PatientStatusResponse(status="no_appointment", last_visit=last_visit)

    doctor_name = today_appt.doctor.name if today_appt.doctor else None
    doctor_spec = today_appt.doctor.specialization if today_appt.doctor else None
    appt_summary = _appt_to_summary(today_appt)

    if today_appt.status == AppointmentStatus.scheduled:
        ahead_result = await db.execute(
            select(func.count()).where(
                Appointment.doctor_id == today_appt.doctor_id,
                Appointment.clinic_id == clinic_id,
                Appointment.scheduled_date == today,
                Appointment.status == AppointmentStatus.scheduled,
                Appointment.queue_number < today_appt.queue_number,
            )
        )
        patients_ahead = ahead_result.scalar_one()
        return PatientStatusResponse(
            status="scheduled",
            appointment=appt_summary,
            queue_position=today_appt.queue_number,
            patients_ahead=patients_ahead,
            doctor_name=doctor_name,
            doctor_specialization=doctor_spec,
        )

    if today_appt.status == AppointmentStatus.in_progress:
        return PatientStatusResponse(
            status="in-progress",
            appointment=appt_summary,
            queue_position=today_appt.queue_number,
            doctor_name=doctor_name,
            doctor_specialization=doctor_spec,
        )

    # completed
    consult_summary = None
    if today_appt.consultation:
        consult_summary = _consult_to_summary(today_appt.consultation, today_appt)

    return PatientStatusResponse(
        status="completed",
        appointment=appt_summary,
        consultation=consult_summary,
        doctor_name=doctor_name,
        doctor_specialization=doctor_spec,
    )


async def _get_last_visit_summary(
    db: AsyncSession,
    patient_id: uuid.UUID,
    clinic_id: uuid.UUID,
) -> LastVisitSummary | None:
    stmt = (
        select(Appointment)
        .options(
            selectinload(Appointment.doctor),
            selectinload(Appointment.consultation),
        )
        .where(
            Appointment.patient_id == patient_id,
            Appointment.clinic_id == clinic_id,
            Appointment.status == AppointmentStatus.completed,
        )
        .order_by(Appointment.scheduled_date.desc(), Appointment.queue_number.desc())
        .limit(1)
    )
    result = await db.execute(stmt)
    last_appt = result.scalar_one_or_none()

    if last_appt is None or last_appt.consultation is None:
        return None

    consultation = last_appt.consultation
    return LastVisitSummary(
        date=last_appt.scheduled_date.isoformat(),
        doctor_name=last_appt.doctor.name if last_appt.doctor else "Unknown",
        diagnosis=consultation.diagnosis,
        next_visit_date=consultation.next_visit_date.isoformat() if consultation.next_visit_date else None,
    )
