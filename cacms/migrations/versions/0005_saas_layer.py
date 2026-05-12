"""saas_layer — plan/billing fields, clinic profile fields, usage_events table

Revision ID: 0005_saas_layer
Revises: 0004_add_permissions_system
Create Date: 2026-05-10 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB

# revision identifiers, used by Alembic.
revision: str = "0005_saas_layer"
down_revision: Union[str, None] = "0004_add_permissions_system"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── 1. Plan / billing fields on clinics ─────────────────────────────────
    op.add_column("clinics", sa.Column("plan", sa.Text(), nullable=False, server_default="free"))
    op.add_column("clinics", sa.Column("plan_status", sa.Text(), nullable=False, server_default="active"))
    op.add_column("clinics", sa.Column("billing_email", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("max_doctors", sa.Integer(), nullable=True))
    op.add_column("clinics", sa.Column("max_staff", sa.Integer(), nullable=True))
    op.add_column("clinics", sa.Column("plan_activated_at", sa.TIMESTAMP(timezone=True), nullable=True))
    op.add_column("clinics", sa.Column("plan_expires_at", sa.TIMESTAMP(timezone=True), nullable=True))
    op.add_column("clinics", sa.Column("plan_note", sa.Text(), nullable=True))

    # ── 2. Clinic profile fields on clinics ──────────────────────────────────
    op.add_column("clinics", sa.Column("clinic_address", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("clinic_phone", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("clinic_gstin", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("clinic_reg_number", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("receipt_header", sa.Text(), nullable=True))
    op.add_column("clinics", sa.Column("receipt_footer", sa.Text(), nullable=True))

    # ── 3. CHECK constraint on plan values ───────────────────────────────────
    op.create_check_constraint(
        "ck_clinics_plan",
        "clinics",
        "plan IN ('free','starter','clinic','pro','enterprise')",
    )

    # ── 4. usage_events table ────────────────────────────────────────────────
    op.create_table(
        "usage_events",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("clinic_id", UUID(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.Text(), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("metadata", JSONB(), nullable=True),
        sa.Column("billed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(
            ["clinic_id"],
            ["clinics.clinic_id"],
            name="fk_usage_events_clinic_id",
            ondelete="CASCADE",
        ),
    )

    # ── 5. Index for efficient monthly aggregation ───────────────────────────
    op.create_index(
        "idx_usage_events_clinic_month",
        "usage_events",
        ["clinic_id", "event_type", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("idx_usage_events_clinic_month", table_name="usage_events")
    op.drop_table("usage_events")

    op.drop_constraint("ck_clinics_plan", "clinics", type_="check")

    # Clinic profile fields
    op.drop_column("clinics", "receipt_footer")
    op.drop_column("clinics", "receipt_header")
    op.drop_column("clinics", "clinic_reg_number")
    op.drop_column("clinics", "clinic_gstin")
    op.drop_column("clinics", "clinic_phone")
    op.drop_column("clinics", "clinic_address")

    # Plan / billing fields
    op.drop_column("clinics", "plan_note")
    op.drop_column("clinics", "plan_expires_at")
    op.drop_column("clinics", "plan_activated_at")
    op.drop_column("clinics", "max_staff")
    op.drop_column("clinics", "max_doctors")
    op.drop_column("clinics", "billing_email")
    op.drop_column("clinics", "plan_status")
    op.drop_column("clinics", "plan")
