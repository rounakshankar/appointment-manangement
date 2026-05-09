"""Tighten tenant-aware constraints.

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-09
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint("uq_patients_phone", "patients", type_="unique")
    op.create_unique_constraint("uq_patients_clinic_phone", "patients", ["clinic_id", "phone"])

    op.drop_constraint("uq_appointments_queue", "appointments", type_="unique")
    op.create_unique_constraint(
        "uq_appointments_clinic_queue",
        "appointments",
        ["clinic_id", "doctor_id", "scheduled_date", "queue_number"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_appointments_clinic_queue", "appointments", type_="unique")
    op.create_unique_constraint(
        "uq_appointments_queue",
        "appointments",
        ["doctor_id", "scheduled_date", "queue_number"],
    )

    op.drop_constraint("uq_patients_clinic_phone", "patients", type_="unique")
    op.create_unique_constraint("uq_patients_phone", "patients", ["phone"])
