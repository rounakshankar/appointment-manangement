import uuid
from datetime import datetime, date
from typing import TYPE_CHECKING, Optional, List
from sqlalchemy import Text, Date, UniqueConstraint, ForeignKey, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base

if TYPE_CHECKING:
    from cacms.models.appointment import Appointment
    from cacms.models.consultation_service import ConsultationService
    from cacms.models.payment import Payment


class Consultation(Base):
    __tablename__ = "consultations"
    __table_args__ = (
        UniqueConstraint("appointment_id", name="uq_consultations_appointment"),
    )

    consultation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    appointment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("appointments.appointment_id"), nullable=False
    )
    symptoms: Mapped[str] = mapped_column(Text, nullable=False)
    diagnosis: Mapped[str] = mapped_column(Text, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    next_visit_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
    updated_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.clinic_id"), nullable=False, index=True
    )

    appointment: Mapped["Appointment"] = relationship("Appointment", back_populates="consultation")
    services: Mapped[List["ConsultationService"]] = relationship(
        "ConsultationService", back_populates="consultation", cascade="all, delete-orphan"
    )
    payment: Mapped[Optional["Payment"]] = relationship(
        "Payment", back_populates="consultation", uselist=False
    )
