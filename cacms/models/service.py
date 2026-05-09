import enum
import uuid
from datetime import datetime
from decimal import Decimal
from sqlalchemy import Text, Numeric, Boolean, ForeignKey, text
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base


class ServiceCategory(str, enum.Enum):
    consultation = "consultation"
    test = "test"
    procedure = "procedure"


class Service(Base):
    __tablename__ = "services"

    service_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[ServiceCategory] = mapped_column(
        SAEnum(ServiceCategory, name="service_category", create_type=False), nullable=False
    )
    base_price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.clinic_id"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
