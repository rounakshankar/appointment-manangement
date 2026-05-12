"""Add clinics table, users table, and clinic_id to all business tables.

Revision ID: 0002
Revises: 0001
Create Date: 2026-04-19
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import text

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

BUSINESS_TABLES = [
    "patients",
    "doctors",
    "appointments",
    "consultations",
    "services",
    "payments",
    "audit_logs",
]


def upgrade() -> None:
    conn = op.get_bind()

    # ── 1. Create clinics table ──────────────────────────────────────────────
    op.create_table(
        "clinics",
        sa.Column("clinic_id", UUID(as_uuid=True), primary_key=True,
                  server_default=text("gen_random_uuid()")),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False,
                  server_default=text("now()")),
    )

    # ── 2. Seed one default clinic and capture its UUID ──────────────────────
    result = conn.execute(
        text("INSERT INTO clinics (name) VALUES ('Default Clinic') RETURNING clinic_id")
    )
    clinic_id = result.scalar()

    # ── 3. Add clinic_id to each business table ──────────────────────────────
    for table in BUSINESS_TABLES:
        # Add nullable first so back-fill can run
        op.add_column(table, sa.Column("clinic_id", UUID(as_uuid=True), nullable=True))

        # Back-fill all existing rows
        conn.execute(
            text(f"UPDATE {table} SET clinic_id = :cid"),
            {"cid": clinic_id},
        )

        # Now enforce NOT NULL
        op.alter_column(table, "clinic_id", nullable=False)

        # FK constraint
        op.create_foreign_key(
            f"fk_{table}_clinic_id",
            table, "clinics",
            ["clinic_id"], ["clinic_id"],
        )

        # Index for efficient filtered queries
        op.create_index(f"idx_{table}_clinic_id", table, ["clinic_id"])

    # ── 4. Create users table ────────────────────────────────────────────────
    op.create_table(
        "users",
        sa.Column("user_id", UUID(as_uuid=True), primary_key=True,
                  server_default=text("gen_random_uuid()")),
        sa.Column("username", sa.Text(), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("role", sa.Text(), nullable=False),
        sa.Column("linked_doctor_id", UUID(as_uuid=True), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=text("true")),
        sa.Column("clinic_id", UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False,
                  server_default=text("now()")),
        sa.UniqueConstraint("username", name="uq_users_username"),
        sa.ForeignKeyConstraint(["clinic_id"], ["clinics.clinic_id"],
                                name="fk_users_clinic_id"),
        sa.ForeignKeyConstraint(["linked_doctor_id"], ["doctors.doctor_id"],
                                name="fk_users_linked_doctor"),
        sa.CheckConstraint(
            "role IN ('owner', 'admin', 'doctor', 'doc_assistant', 'receptionist')",
            name="ck_users_role",
        ),
    )
    op.create_index("idx_users_clinic_id", "users", ["clinic_id"])
    op.create_index("idx_users_username", "users", ["username"])


def downgrade() -> None:
    op.drop_table("users")

    for table in reversed(BUSINESS_TABLES):
        op.drop_index(f"idx_{table}_clinic_id", table_name=table)
        op.drop_constraint(f"fk_{table}_clinic_id", table, type_="foreignkey")
        op.drop_column(table, "clinic_id")

    op.drop_table("clinics")
