"""initial schema

Revision ID: 0001
Revises: None
Create Date: 2024-01-01 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- Sequence for sse_events ---
    op.execute("CREATE SEQUENCE IF NOT EXISTS sse_events_sequence_seq")

    # --- ENUMs ---
    appointment_status = postgresql.ENUM(
        "scheduled", "in-progress", "completed", "cancelled", "no-show",
        name="appointment_status",
        create_type=True,
    )
    appointment_status.create(op.get_bind())

    visit_type = postgresql.ENUM(
        "normal", "follow-up", "emergency",
        name="visit_type",
        create_type=True,
    )
    visit_type.create(op.get_bind())

    service_category = postgresql.ENUM(
        "consultation", "test", "procedure",
        name="service_category",
        create_type=True,
    )
    service_category.create(op.get_bind())

    payment_mode = postgresql.ENUM(
        "cash", "upi", "card",
        name="payment_mode",
        create_type=True,
    )
    payment_mode.create(op.get_bind())

    payment_status = postgresql.ENUM(
        "pending", "paid", "partial",
        name="payment_status",
        create_type=True,
    )
    payment_status.create(op.get_bind())

    # --- Table: doctors ---
    op.create_table(
        "doctors",
        sa.Column(
            "doctor_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("specialization", sa.Text(), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("max_patients_per_day", sa.Integer(), nullable=False, server_default=sa.text("40")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("doctor_id"),
    )

    # --- Table: patients ---
    op.create_table(
        "patients",
        sa.Column(
            "patient_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("phone", sa.Text(), nullable=False),
        sa.Column("age", sa.Integer(), nullable=True),
        sa.Column(
            "gender",
            sa.Text(),
            sa.CheckConstraint("gender IN ('male', 'female', 'other')", name="ck_patients_gender"),
            nullable=True,
        ),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("consent_given", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("consent_date", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("patient_id"),
        sa.UniqueConstraint("phone", name="uq_patients_phone"),
    )

    # --- Table: appointments ---
    op.create_table(
        "appointments",
        sa.Column(
            "appointment_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("patient_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("doctor_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("scheduled_date", sa.Date(), nullable=False),
        sa.Column("queue_number", sa.Integer(), nullable=False),
        sa.Column(
            "visit_type",
            postgresql.ENUM(
                "normal", "follow-up", "emergency",
                name="visit_type",
                create_type=False,
            ),
            nullable=False,
            server_default=sa.text("'normal'::visit_type"),
        ),
        sa.Column(
            "status",
            postgresql.ENUM(
                "scheduled", "in-progress", "completed", "cancelled", "no-show",
                name="appointment_status",
                create_type=False,
            ),
            nullable=False,
            server_default=sa.text("'scheduled'::appointment_status"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.patient_id"]),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.doctor_id"]),
        sa.PrimaryKeyConstraint("appointment_id"),
        sa.UniqueConstraint("doctor_id", "scheduled_date", "queue_number", name="uq_appointments_queue"),
    )

    # --- Table: consultations ---
    op.create_table(
        "consultations",
        sa.Column(
            "consultation_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("appointment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("symptoms", sa.Text(), nullable=False),
        sa.Column("diagnosis", sa.Text(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("next_visit_date", sa.Date(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["appointment_id"], ["appointments.appointment_id"]),
        sa.PrimaryKeyConstraint("consultation_id"),
        sa.UniqueConstraint("appointment_id", name="uq_consultations_appointment"),
    )

    # --- Table: services ---
    op.create_table(
        "services",
        sa.Column(
            "service_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column(
            "category",
            postgresql.ENUM(
                "consultation", "test", "procedure",
                name="service_category",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column("base_price", sa.Numeric(10, 2), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("service_id"),
    )

    # --- Table: consultation_services (with GENERATED ALWAYS AS STORED via raw SQL) ---
    op.execute("""
        CREATE TABLE consultation_services (
            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            consultation_id UUID NOT NULL REFERENCES consultations(consultation_id),
            service_id      UUID NOT NULL REFERENCES services(service_id),
            quantity        INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
            price_applied   NUMERIC(10,2) NOT NULL,
            total           NUMERIC(10,2) GENERATED ALWAYS AS (quantity * price_applied) STORED
        )
    """)

    # --- Table: payments ---
    op.create_table(
        "payments",
        sa.Column(
            "payment_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("consultation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("total_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column(
            "payment_mode",
            postgresql.ENUM(
                "cash", "upi", "card",
                name="payment_mode",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column(
            "status",
            postgresql.ENUM(
                "pending", "paid", "partial",
                name="payment_status",
                create_type=False,
            ),
            nullable=False,
            server_default=sa.text("'pending'::payment_status"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["consultation_id"], ["consultations.consultation_id"]),
        sa.PrimaryKeyConstraint("payment_id"),
    )

    # --- Table: audit_logs ---
    op.create_table(
        "audit_logs",
        sa.Column(
            "log_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("actor_role", sa.Text(), nullable=False),
        sa.Column("action", sa.Text(), nullable=False),
        sa.Column("resource", sa.Text(), nullable=False),
        sa.Column("resource_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("payload", postgresql.JSONB(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("log_id"),
    )

    # --- Table: otp_sessions ---
    op.create_table(
        "otp_sessions",
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("phone", sa.Text(), nullable=False),
        sa.Column("otp_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("session_id"),
    )

    # --- Table: sse_events ---
    op.create_table(
        "sse_events",
        sa.Column(
            "event_id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("channel", sa.Text(), nullable=False),
        sa.Column("event_type", sa.Text(), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column(
            "sequence",
            sa.BigInteger(),
            nullable=True,
            server_default=sa.text("nextval('sse_events_sequence_seq')"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("event_id"),
    )

    # --- Regular indexes ---
    op.create_index("idx_patients_phone", "patients", ["phone"])
    op.create_index("idx_appointments_doctor_date", "appointments", ["doctor_id", "scheduled_date"])
    op.create_index("idx_appointments_patient", "appointments", ["patient_id"])
    op.create_index("idx_audit_logs_actor", "audit_logs", ["actor_id"])
    op.create_index("idx_audit_logs_resource", "audit_logs", ["resource", "resource_id"])
    op.create_index("idx_sse_events_channel_seq", "sse_events", ["channel", "sequence"])
    op.create_index("idx_otp_sessions_phone", "otp_sessions", ["phone"])

    # --- Partial unique index (raw SQL — Alembic doesn't support WHERE clause natively) ---
    op.execute("""
        CREATE UNIQUE INDEX uq_one_inprogress_per_doctor_date
            ON appointments (doctor_id, scheduled_date)
            WHERE status = 'in-progress'
    """)


def downgrade() -> None:
    # --- Drop partial index ---
    op.execute("DROP INDEX IF EXISTS uq_one_inprogress_per_doctor_date")

    # --- Drop regular indexes ---
    op.drop_index("idx_otp_sessions_phone", table_name="otp_sessions")
    op.drop_index("idx_sse_events_channel_seq", table_name="sse_events")
    op.drop_index("idx_audit_logs_resource", table_name="audit_logs")
    op.drop_index("idx_audit_logs_actor", table_name="audit_logs")
    op.drop_index("idx_appointments_patient", table_name="appointments")
    op.drop_index("idx_appointments_doctor_date", table_name="appointments")
    op.drop_index("idx_patients_phone", table_name="patients")

    # --- Drop tables in reverse dependency order ---
    op.drop_table("sse_events")
    op.drop_table("otp_sessions")
    op.drop_table("audit_logs")
    op.drop_table("payments")
    op.execute("DROP TABLE IF EXISTS consultation_services")
    op.drop_table("services")
    op.drop_table("consultations")
    op.drop_table("appointments")
    op.drop_table("patients")
    op.drop_table("doctors")

    # --- Drop sequence ---
    op.execute("DROP SEQUENCE IF EXISTS sse_events_sequence_seq")

    # --- Drop ENUMs ---
    postgresql.ENUM(name="payment_status", create_type=False).drop(op.get_bind())
    postgresql.ENUM(name="payment_mode", create_type=False).drop(op.get_bind())
    postgresql.ENUM(name="service_category", create_type=False).drop(op.get_bind())
    postgresql.ENUM(name="visit_type", create_type=False).drop(op.get_bind())
    postgresql.ENUM(name="appointment_status", create_type=False).drop(op.get_bind())
