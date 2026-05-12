import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


StaffRole = Literal["owner", "admin", "doctor", "doc_assistant", "receptionist"]


class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=120)
    password: str = Field(..., min_length=8, max_length=256)
    role: StaffRole
    linked_doctor_id: uuid.UUID | None = None


class UserUpdate(BaseModel):
    username: str | None = Field(None, min_length=3, max_length=120)
    password: str | None = Field(None, min_length=8, max_length=256)
    role: StaffRole | None = None
    linked_doctor_id: uuid.UUID | None = None
    active: bool | None = None


class UserOut(BaseModel):
    user_id: uuid.UUID
    username: str
    role: str
    linked_doctor_id: uuid.UUID | None
    active: bool
    clinic_id: uuid.UUID
    created_at: datetime

    model_config = {"from_attributes": True}
