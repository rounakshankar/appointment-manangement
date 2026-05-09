import uuid
from datetime import datetime, date
from typing import Optional, Literal
from pydantic import BaseModel


class AppointmentCreate(BaseModel):
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    scheduled_date: date
    visit_type: Literal["normal", "follow-up", "emergency"]


class AppointmentStatusUpdate(BaseModel):
    status: Literal["no-show", "cancelled"]


class AppointmentScheduleUpdate(BaseModel):
    scheduled_date: date


class AppointmentOut(BaseModel):
    appointment_id: uuid.UUID
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    scheduled_date: date
    queue_number: int
    visit_type: str
    status: str
    created_at: datetime
    updated_at: datetime
    # Joined fields
    patient_name: Optional[str] = None

    model_config = {"from_attributes": True}


class CallNextResult(BaseModel):
    completed_appointment_id: Optional[uuid.UUID] = None
    next_appointment_id: Optional[uuid.UUID] = None
    queue_empty: bool = False
    conflict: bool = False


class QueueDashboard(BaseModel):
    total: int
    completed: int
    remaining: int
    queue: list[AppointmentOut]
