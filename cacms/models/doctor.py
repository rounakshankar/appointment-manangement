import uuid
from datetime import datetime
from typing import TYPE_CHECKING, List
from sqlalchemy import Text, Boolean, Integer, ForeignKey, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base

if TYPE_CHECKING:
    from cacms.models.appointment import Appointment


class Doctor(Base):
    __tablename__ = "doctors"

    doctor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    specialization: Mapped[str | None] = mapped_column(Text, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    max_patients_per_day: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("40"))
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.clinic_id"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))

    appointments: Mapped[List["Appointment"]] = relationship("Appointment", back_populates="doctor")
