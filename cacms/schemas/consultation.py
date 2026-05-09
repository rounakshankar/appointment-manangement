import uuid
from datetime import datetime, date
from decimal import Decimal
from typing import Optional, List
from pydantic import BaseModel


class ConsultationServiceItem(BaseModel):
    service_id: uuid.UUID
    quantity: int = 1
    price_applied: Decimal


class ConsultationCreate(BaseModel):
    appointment_id: uuid.UUID
    symptoms: str
    diagnosis: str
    notes: Optional[str] = None
    next_visit_date: Optional[date] = None
    services: List[ConsultationServiceItem] = []


class ConsultationServiceOut(BaseModel):
    id: uuid.UUID
    service_id: uuid.UUID
    quantity: int
    price_applied: Decimal
    total: Optional[Decimal]
    service_name: Optional[str] = None

    model_config = {"from_attributes": True}


class FollowUpPrompt(BaseModel):
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    scheduled_date: date
    visit_type: str = "follow-up"


class ConsultationOut(BaseModel):
    consultation_id: uuid.UUID
    appointment_id: uuid.UUID
    symptoms: str
    diagnosis: str
    notes: Optional[str]
    next_visit_date: Optional[date]
    services: List[ConsultationServiceOut] = []
    created_at: datetime
    follow_up_prompt: Optional[FollowUpPrompt] = None

    model_config = {"from_attributes": True}
