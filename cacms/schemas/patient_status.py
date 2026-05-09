import uuid
from datetime import date
from decimal import Decimal
from typing import Optional, List
from pydantic import BaseModel


class ServiceLineItem(BaseModel):
    id: Optional[str] = None
    service_id: Optional[str] = None
    quantity: int
    price_applied: float = 0.0
    total: Optional[float] = None
    service_name: Optional[str] = None


class ConsultationSummary(BaseModel):
    consultation_id: Optional[str] = None
    appointment_id: Optional[str] = None
    symptoms: Optional[str] = None
    diagnosis: str
    notes: Optional[str] = None
    next_visit_date: Optional[date] = None
    services: List[ServiceLineItem] = []
    created_at: Optional[str] = None


class AppointmentSummary(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str
    scheduled_date: date
    queue_number: int
    visit_type: str
    status: str
    created_at: str
    updated_at: str
    patient_name: Optional[str] = None


class LastVisitSummary(BaseModel):
    """Kept for backward compat — also used in no_appointment state."""
    date: Optional[str] = None
    doctor_name: Optional[str] = None
    diagnosis: Optional[str] = None
    next_visit_date: Optional[str] = None


class PatientStatusResponse(BaseModel):
    # Flutter expects 'status' key with values: no_appointment | scheduled | in-progress | completed
    status: str
    appointment: Optional[AppointmentSummary] = None
    consultation: Optional[ConsultationSummary] = None
    queue_position: Optional[int] = None
    patients_ahead: Optional[int] = None
    doctor_name: Optional[str] = None
    doctor_specialization: Optional[str] = None
    last_visit: Optional[LastVisitSummary] = None
