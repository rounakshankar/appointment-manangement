import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import Text, Integer, Boolean, CheckConstraint, text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from cacms.database import Base


class Clinic(Base):
    __tablename__ = "clinics"
    __table_args__ = (
        CheckConstraint(
            "plan IN ('free','starter','clinic','pro','enterprise')",
            name="ck_clinics_plan",
        ),
    )

    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))

    # ── Plan / billing fields ────────────────────────────────────────────────
    plan: Mapped[str] = mapped_column(Text, nullable=False, server_default=text("'free'"))
    plan_status: Mapped[str] = mapped_column(Text, nullable=False, server_default=text("'active'"))
    billing_email: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    max_doctors: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    max_staff: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    plan_activated_at: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True), nullable=True
    )
    plan_expires_at: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True), nullable=True
    )
    plan_note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # ── Clinic profile fields (used on patient receipts) ─────────────────────
    clinic_address: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    clinic_phone: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    clinic_gstin: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    clinic_reg_number: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    receipt_header: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    receipt_footer: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
