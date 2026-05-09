import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal
from pydantic import BaseModel


class PaymentCreate(BaseModel):
    consultation_id: uuid.UUID
    total_amount: Decimal
    payment_mode: Literal["cash", "upi", "card"]
    status: Literal["pending", "paid", "partial"] = "pending"


class PaymentOut(BaseModel):
    payment_id: uuid.UUID
    consultation_id: uuid.UUID
    total_amount: Decimal
    payment_mode: str
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}
