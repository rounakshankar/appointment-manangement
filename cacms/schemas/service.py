import uuid
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel


class ServiceOut(BaseModel):
    service_id: uuid.UUID
    name: str
    category: str
    base_price: Decimal
    active: bool

    model_config = {"from_attributes": True}
