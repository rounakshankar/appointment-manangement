import enum
import uuid
from datetime import datetime, date
from typing import TYPE_CHECKING, Optional
from sqlalchemy import Integer, Date, UniqueConstraint, ForeignKey, text
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base

if TYPE_CHECKING:
    from cacms.models.patient import Patient
    from cacms.models.doctor import Doctor
    from cacms.models.consultation import Consultation


class VisitType(str, enum.Enum):
    normal = "normal"
    follow_up = "follow-up"
    emergency = "emergency"


class AppointmentStatus(str, enum.Enum):
    scheduled = "scheduled"
    in_progress = "in-progress"
    completed = "completed"
    cancelled = "cancelled"
    no_show = "no-show"


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        UniqueConstraint("clinic_id", "doctor_id", "scheduled_date", "queue_number", name="uq_appointments_clinic_queue"),
    )

    appointment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    patient_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("patients.patient_id"), nullable=False, index=True
    )
    doctor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("doctors.doctor_id"), nullable=False, index=True
    )
    scheduled_date: Mapped[date] = mapped_column(Date, nullable=False)
    queue_number: Mapped[int] = mapped_column(Integer, nullable=False)
    visit_type: Mapped[VisitType] = mapped_column(
        SAEnum(VisitType, name="visit_type", create_type=False, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        server_default=text("'normal'::visit_type"),
    )
    status: Mapped[AppointmentStatus] = mapped_column(
        SAEnum(AppointmentStatus, name="appointment_status", create_type=False, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        server_default=text("'scheduled'::appointment_status"),
    )
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
    updated_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.clinic_id"), nullable=False, index=True
    )

    patient: Mapped["Patient"] = relationship("Patient", back_populates="appointments")
    doctor: Mapped["Doctor"] = relationship("Doctor", back_populates="appointments")
    consultation: Mapped[Optional["Consultation"]] = relationship(
        "Consultation", back_populates="appointment", uselist=False
    )
