"""
Consultation Service

Handles consultation creation and retrieval with SSE event emission.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from cacms.models.appointment import Appointment
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.models.service import Service
from cacms.schemas.consultation import ConsultationCreate
from cacms.services.sse_bus import sse_bus


async def get_appointment(
    db: AsyncSession,
    appointment_id: uuid.UUID,
    clinic_id: uuid.UUID,
) -> Appointment | None:
    result = await db.execute(
        select(Appointment).where(
            Appointment.appointment_id == appointment_id,
            Appointment.clinic_id == clinic_id,
        )
    )
    return result.scalar_one_or_none()


async def get_consultation_by_appointment(
    db: AsyncSession, appointment_id: uuid.UUID
) -> Consultation | None:
    result = await db.execute(
        select(Consultation)
        .options(selectinload(Consultation.services).selectinload(ConsultationService.service))
        .where(Consultation.appointment_id == appointment_id)
    )
    return result.scalar_one_or_none()


async def create_consultation(
    db: AsyncSession,
    data: ConsultationCreate,
    requesting_doctor_id: uuid.UUID,
    clinic_id: uuid.UUID,
) -> Consultation:
    """
    Create a new consultation for an appointment.

    Raises:
        ValueError("APPOINTMENT_NOT_FOUND") if appointment does not exist.
        ValueError("FORBIDDEN") if appointment belongs to a different doctor.
        ValueError("CONSULTATION_EXISTS") if a consultation already exists for the appointment.
    """
    appointment = await get_appointment(db, data.appointment_id, clinic_id)
    if appointment is None:
        raise ValueError("APPOINTMENT_NOT_FOUND")

    if appointment.doctor_id != requesting_doctor_id:
        raise ValueError("FORBIDDEN")

    existing = await db.execute(
        select(Consultation).where(
            Consultation.appointment_id == data.appointment_id,
            Consultation.clinic_id == clinic_id,
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise ValueError("CONSULTATION_EXISTS")

    consultation = Consultation(
        consultation_id=uuid.uuid4(),
        appointment_id=data.appointment_id,
        symptoms=data.symptoms,
        diagnosis=data.diagnosis,
        notes=data.notes,
        next_visit_date=data.next_visit_date,
        clinic_id=clinic_id,
    )
    db.add(consultation)
    await db.flush()  # get consultation_id before creating services

    for item in data.services:
        service_result = await db.execute(
            select(Service).where(Service.service_id == item.service_id, Service.clinic_id == clinic_id)
        )
        if service_result.scalar_one_or_none() is None:
            raise ValueError("SERVICE_NOT_FOUND")
        svc = ConsultationService(
            id=uuid.uuid4(),
            consultation_id=consultation.consultation_id,
            service_id=item.service_id,
            quantity=item.quantity,
            price_applied=item.price_applied,
        )
        db.add(svc)

    # Emit SSE to both doctor and patient channels
    event_data = {
        "consultation_id": str(consultation.consultation_id),
        "appointment_id": str(data.appointment_id),
        "doctor_id": str(appointment.doctor_id),
        "patient_id": str(appointment.patient_id),
    }
    await sse_bus.publish(channel=f"doctor:{appointment.doctor_id}", event_type="consultation_completed", data=event_data)
    await sse_bus.publish(channel=f"patient:{appointment.patient_id}", event_type="consultation_completed", data=event_data)

    await db.commit()

    # Reload with services and appointment eagerly loaded
    result = await db.execute(
        select(Consultation)
        .options(
            selectinload(Consultation.services).selectinload(ConsultationService.service),
            selectinload(Consultation.appointment),
        )
        .where(
            Consultation.consultation_id == consultation.consultation_id,
            Consultation.clinic_id == clinic_id,
        )
    )
    return result.scalar_one()
