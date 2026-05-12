import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import Text, Boolean, ForeignKey, text, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from cacms.database import Base


class Permission(Base):
    __tablename__ = "permissions"

    permission_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))


class RolePermission(Base):
    __tablename__ = "role_permissions"

    role_permission_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    role: Mapped[str] = mapped_column(String(50), nullable=False)
    permission_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("permissions.permission_id"), nullable=False
    )
    clinic_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.clinic_id"), nullable=True, index=True
    )  # Null = global role, specific clinic_id = clinic-specific override
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))