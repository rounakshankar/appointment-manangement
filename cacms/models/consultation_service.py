import uuid
from decimal import Decimal
from typing import TYPE_CHECKING, Optional
from sqlalchemy import Integer, Numeric, CheckConstraint, ForeignKey, Computed, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base

if TYPE_CHECKING:
    from cacms.models.consultation import Consultation
    from cacms.models.service import Service


class ConsultationService(Base):
    __tablename__ = "consultation_services"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_consultation_services_quantity"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    consultation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("consultations.consultation_id"), nullable=False
    )
    service_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("services.service_id"), nullable=False
    )
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("1"))
    price_applied: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    # GENERATED ALWAYS AS (quantity * price_applied) STORED
    total: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(10, 2),
        Computed("quantity * price_applied", persisted=True),
        nullable=True,
    )

    consultation: Mapped["Consultation"] = relationship("Consultation", back_populates="services")
    service: Mapped["Service"] = relationship("Service")
