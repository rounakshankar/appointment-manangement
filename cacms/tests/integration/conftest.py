"""
Integration test fixtures.

Uses a real PostgreSQL instance (cacms_test database).
Set TEST_DATABASE_URL env var to override the default connection string.

Each test gets a fresh AsyncSession. Cleanup is done by truncating all
application tables after each test (since the service layer calls db.commit()
internally, savepoint-based rollback is not viable).

HTTP-layer fixtures (http_client, admin_token, doctor_token, seeded_doctor,
seeded_patient, test_date) are provided for tests that exercise the API via
httpx.AsyncClient + ASGITransport.
"""

from __future__ import annotations

import os
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from cacms.models.appointment import Appointment, AppointmentStatus, VisitType
from cacms.models.clinic import Clinic
from cacms.models.consultation import Consultation
from cacms.models.consultation_service import ConsultationService
from cacms.models.doctor import Doctor
from cacms.models.patient import Patient
from cacms.models.payment import Payment, PaymentMode, PaymentStatus
from cacms.models.permission import Permission, RolePermission
from cacms.models.service import Service, ServiceCategory
from cacms.models.user import User
from cacms.services.password_service import hash_password

# ---------------------------------------------------------------------------
# Connection URL — override via TEST_DATABASE_URL env var
# ---------------------------------------------------------------------------
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/cacms_test",
)

_TRUNCATE_SQL = """
TRUNCATE TABLE
    consultation_services,
    payments,
    consultations,
    appointments,
    sse_events,
    audit_logs,
    otp_sessions,
    role_permissions,
    permissions,
    services,
    patients,
    doctors,
    users,
    clinics
RESTART IDENTITY CASCADE
"""


async def _truncate_all(connection: Any) -> None:
    await connection.execute(text(_TRUNCATE_SQL))


# ---------------------------------------------------------------------------
# DB connectivity check — skip all integration tests if DB is unavailable
# ---------------------------------------------------------------------------


def pytest_configure(config: pytest.Config) -> None:
    """Register the 'integration' marker to avoid PytestUnknownMarkWarning."""
    config.addinivalue_line("markers", "integration: mark test as requiring a real DB")


@pytest_asyncio.fixture(scope="session", autouse=True)
async def _check_db_available() -> None:
    """
    Session-scoped fixture that verifies the test database is reachable.
    Skips the entire session if the connection fails.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception as exc:
        pytest.skip(
            f"Test database not available ({TEST_DATABASE_URL}): {exc}. "
            "Set TEST_DATABASE_URL to a reachable PostgreSQL instance."
        )
    finally:
        await engine.dispose()


# ---------------------------------------------------------------------------
# Service-layer DB fixture (used by test_queue_flow.py)
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def db() -> Any:
    """
    Provide an AsyncSession backed by a real PostgreSQL connection.

    After each test, truncate all tables to restore a clean state.
    NullPool ensures no connection state leaks between tests.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with session_factory() as session:
        yield session

    async with engine.begin() as conn:
        await _truncate_all(conn)

    await engine.dispose()


@pytest_asyncio.fixture
async def clinic(db: AsyncSession) -> Clinic:
    """A clinic row for model fixtures."""
    c = Clinic(name=f"Test Clinic {uuid.uuid4().hex[:8]}")
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return c


@pytest_asyncio.fixture
async def doctor(db: AsyncSession, clinic: Clinic) -> Doctor:
    """Seed a test doctor (service-layer tests)."""
    doc = Doctor(
        doctor_id=uuid.uuid4(),
        name=f"Dr. Test {uuid.uuid4().hex[:6]}",
        specialization="General",
        active=True,
        max_patients_per_day=10,
        clinic_id=clinic.clinic_id,
    )
    db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return doc


@pytest_asyncio.fixture
async def patient(db: AsyncSession, clinic: Clinic) -> Patient:
    """Seed a test patient (service-layer tests)."""
    pat = Patient(
        patient_id=uuid.uuid4(),
        name="Test Patient",
        phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
        consent_given=True,
        clinic_id=clinic.clinic_id,
    )
    db.add(pat)
    await db.commit()
    await db.refresh(pat)
    return pat


@pytest_asyncio.fixture
async def user_admin(db: AsyncSession, clinic: Clinic) -> User:
    """Staff user with admin role (service-layer tests)."""
    u = User(
        username=f"admin_{uuid.uuid4().hex[:8]}",
        password_hash=hash_password("test-password-123"),
        role="admin",
        clinic_id=clinic.clinic_id,
        active=True,
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


@pytest_asyncio.fixture
async def service_row(db: AsyncSession, clinic: Clinic) -> Service:
    """Billable service linked to the test clinic."""
    svc = Service(
        name=f"Consult {uuid.uuid4().hex[:4]}",
        category=ServiceCategory.consultation,
        base_price=Decimal("150.00"),
        active=True,
        clinic_id=clinic.clinic_id,
    )
    db.add(svc)
    await db.commit()
    await db.refresh(svc)
    return svc


@pytest_asyncio.fixture
async def appointment_row(
    db: AsyncSession,
    clinic: Clinic,
    doctor: Doctor,
    patient: Patient,
    today: date,
) -> Appointment:
    """Single scheduled appointment."""
    appt = Appointment(
        patient_id=patient.patient_id,
        doctor_id=doctor.doctor_id,
        scheduled_date=today,
        queue_number=1,
        visit_type=VisitType.normal,
        status=AppointmentStatus.scheduled,
        clinic_id=clinic.clinic_id,
    )
    db.add(appt)
    await db.commit()
    await db.refresh(appt)
    return appt


@pytest_asyncio.fixture
async def consultation_row(
    db: AsyncSession,
    clinic: Clinic,
    appointment_row: Appointment,
) -> Consultation:
    """Consultation for appointment_row."""
    cons = Consultation(
        appointment_id=appointment_row.appointment_id,
        symptoms="cough",
        diagnosis="cold",
        notes=None,
        clinic_id=clinic.clinic_id,
    )
    db.add(cons)
    await db.commit()
    await db.refresh(cons)
    return cons


@pytest_asyncio.fixture
async def consultation_service_row(
    db: AsyncSession,
    consultation_row: Consultation,
    service_row: Service,
) -> ConsultationService:
    """Line item on a consultation."""
    row = ConsultationService(
        consultation_id=consultation_row.consultation_id,
        service_id=service_row.service_id,
        quantity=1,
        price_applied=service_row.base_price,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


@pytest_asyncio.fixture
async def payment_row(
    db: AsyncSession,
    clinic: Clinic,
    consultation_row: Consultation,
) -> Payment:
    """Payment for consultation_row."""
    pay = Payment(
        consultation_id=consultation_row.consultation_id,
        total_amount=Decimal("150.00"),
        payment_mode=PaymentMode.cash,
        status=PaymentStatus.paid,
        clinic_id=clinic.clinic_id,
    )
    db.add(pay)
    await db.commit()
    await db.refresh(pay)
    return pay


@pytest_asyncio.fixture
async def permission_row(db: AsyncSession) -> Permission:
    """Global permission row."""
    p = Permission(
        name=f"perm_{uuid.uuid4().hex[:8]}",
        description="Test permission",
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


@pytest_asyncio.fixture
async def role_permission_row(
    db: AsyncSession,
    permission_row: Permission,
    clinic: Clinic,
) -> RolePermission:
    """Role grant for admin at test clinic."""
    rp = RolePermission(
        role="admin",
        permission_id=permission_row.permission_id,
        clinic_id=clinic.clinic_id,
    )
    db.add(rp)
    await db.commit()
    await db.refresh(rp)
    return rp


@pytest.fixture
def today() -> date:
    return date.today()


# ---------------------------------------------------------------------------
# HTTP-layer fixtures (used by test_core_queue_flow.py)
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def http_client() -> Any:
    """
    httpx.AsyncClient backed by the FastAPI app via ASGITransport.

    The app's database dependency is overridden to use the test database URL.
    A clinic row is inserted for JWT `clinic_id` claims. All tables are truncated
    after each test.
    """
    import cacms.config as _cfg
    import cacms.database as _db_module

    original_url = _cfg.settings.DATABASE_URL
    _cfg.settings.DATABASE_URL = TEST_DATABASE_URL

    test_engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    test_session_factory = async_sessionmaker(test_engine, expire_on_commit=False)

    original_engine = _db_module.engine
    original_factory = _db_module.AsyncSessionLocal

    _db_module.engine = test_engine
    _db_module.AsyncSessionLocal = test_session_factory

    clinic_id = uuid.uuid4()
    async with test_engine.begin() as conn:
        await conn.execute(
            text("INSERT INTO clinics (clinic_id, name) VALUES (:id, :name)"),
            {"id": clinic_id, "name": "HTTP Test Clinic"},
        )

    async def _override_get_db() -> Any:
        async with test_session_factory() as session:
            try:
                yield session
            finally:
                await session.close()

    from cacms.database import get_db
    from cacms.main import app

    app.dependency_overrides[get_db] = _override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        setattr(client, "_cacms_clinic_id", clinic_id)
        yield client

    _db_module.engine = original_engine
    _db_module.AsyncSessionLocal = original_factory
    _cfg.settings.DATABASE_URL = original_url
    app.dependency_overrides.pop(get_db, None)

    async with test_engine.begin() as conn:
        await _truncate_all(conn)

    await test_engine.dispose()


@pytest.fixture
def admin_token(http_client: AsyncClient) -> str:
    """JWT for an admin in the HTTP test clinic."""
    from cacms.services.jwt_service import create_token

    cid: uuid.UUID = http_client._cacms_clinic_id  # type: ignore[attr-defined]
    return create_token(
        {
            "sub": str(uuid.uuid4()),
            "role": "admin",
            "clinic_id": str(cid),
        }
    )


@pytest_asyncio.fixture
async def seeded_doctor(http_client: AsyncClient) -> dict:
    """
    Seed a Doctor row directly in the test DB and return its dict representation.

    Doctor creation is not exposed via API in tasks 1–12, so we insert directly.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    doctor_id = uuid.uuid4()
    doctor_name = f"Dr. HTTP {uuid.uuid4().hex[:6]}"
    clinic_id: uuid.UUID = http_client._cacms_clinic_id  # type: ignore[attr-defined]

    async with session_factory() as session:
        doc = Doctor(
            doctor_id=doctor_id,
            name=doctor_name,
            specialization="General",
            active=True,
            max_patients_per_day=20,
            clinic_id=clinic_id,
        )
        session.add(doc)
        await session.commit()

    await engine.dispose()

    return {
        "doctor_id": str(doctor_id),
        "name": doctor_name,
    }


@pytest.fixture
def doctor_token(seeded_doctor: dict, http_client: AsyncClient) -> str:
    """JWT token for the seeded doctor."""
    from cacms.services.jwt_service import create_token

    cid: uuid.UUID = http_client._cacms_clinic_id  # type: ignore[attr-defined]
    did = seeded_doctor["doctor_id"]
    return create_token(
        {
            "sub": did,
            "role": "doctor",
            "clinic_id": str(cid),
            "linked_doctor_id": did,
        }
    )


@pytest_asyncio.fixture
async def seeded_patient(http_client: AsyncClient, admin_token: str) -> dict:
    """Register a patient via the API and return the response body."""
    phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
    resp = await http_client.post(
        "/v1/patients",
        json={"name": "Fixture Patient", "phone": phone, "consent_given": True},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.fixture
def test_date() -> str:
    """
    A date string (YYYY-MM-DD) for use in HTTP-layer tests.

    Uses tomorrow to avoid conflicts with any real data that might exist
    for today in a shared test database.
    """
    return (date.today() + timedelta(days=1)).isoformat()
