import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator
import re


class PatientCreate(BaseModel):
    name: str
    phone: str
    age: Optional[int] = None
    gender: Optional[str] = None
    address: Optional[str] = None
    consent_given: bool = True

    @field_validator("phone")
    @classmethod
    def phone_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("phone must not be empty")
        return v

    @field_validator("gender")
    @classmethod
    def gender_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in ("male", "female", "other"):
            raise ValueError("gender must be male, female, or other")
        return v


class PatientOut(BaseModel):
    patient_id: uuid.UUID
    name: str
    phone: str
    age: Optional[int]
    gender: Optional[str]
    address: Optional[str]
    consent_given: bool
    consent_date: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}
