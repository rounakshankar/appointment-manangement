"""
Integration test fixtures.

Uses a real PostgreSQL instance (cacms_test database).
Set TEST_DATABASE_URL env var to override the default connection string.

Each test gets a fresh AsyncSession. Cleanup is done by truncating the
relevant tables after each test (since the service layer calls db.commit()
internally, savepoint-based rollback is not viable).

HTTP-layer fixtures (http_client, admin_token, doctor_token, seeded_doctor,
seeded_patient, test_date) are provided for tests that exercise the API via
httpx.AsyncClient + ASGITransport.
"""

import os
import uuid
from datetime import date, timedelta

import pytest
import pytest_asyncio
import httpx
from httpx import AsyncClient, ASGITransport
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import NullPool

from cacms.models.doctor import Doctor
from cacms.models.patient import Patient

# ---------------------------------------------------------------------------
# Connection URL — override via TEST_DATABASE_URL env var
# ---------------------------------------------------------------------------
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/cacms_test",
)

# Tables to truncate between tests (in dependency order)
_TRUNCATE_TABLES = [
    "sse_events",
    "appointments",
    "patients",
    "doctors",
]


# ---------------------------------------------------------------------------
# DB connectivity check — skip all integration tests if DB is unavailable
# ---------------------------------------------------------------------------

def pytest_configure(config):
    """Register the 'integration' marker to avoid PytestUnknownMarkWarning."""
    config.addinivalue_line("markers", "integration: mark test as requiring a real DB")


@pytest_asyncio.fixture(scope="session", autouse=True)
async def _check_db_available():
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
async def db():
    """
    Provide an AsyncSession backed by a real PostgreSQL connection.

    After each test, truncate the relevant tables to restore a clean state.
    NullPool ensures no connection state leaks between tests.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with session_factory() as session:
        yield session

    # Cleanup: truncate tables after the test
    async with engine.begin() as conn:
        for table in _TRUNCATE_TABLES:
            await conn.execute(text(f"TRUNCATE TABLE {table} CASCADE"))

    await engine.dispose()


@pytest_asyncio.fixture
async def doctor(db: AsyncSession):
    """Seed a test doctor (service-layer tests)."""
    doc = Doctor(
        doctor_id=uuid.uuid4(),
        name=f"Dr. Test {uuid.uuid4().hex[:6]}",
        specialization="General",
        active=True,
        max_patients_per_day=10,
    )
    db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return doc


@pytest_asyncio.fixture
async def patient(db: AsyncSession):
    """Seed a test patient (service-layer tests)."""
    pat = Patient(
        patient_id=uuid.uuid4(),
        name="Test Patient",
        phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
        consent_given=True,
    )
    db.add(pat)
    await db.commit()
    await db.refresh(pat)
    return pat


@pytest.fixture
def today():
    return date.today()


# ---------------------------------------------------------------------------
# HTTP-layer fixtures (used by test_core_queue_flow.py)
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def _http_engine():
    """
    Session-scoped async engine for HTTP-layer test setup/teardown.
    Yields the engine and disposes it after all HTTP tests complete.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def http_client():
    """
    httpx.AsyncClient backed by the FastAPI app via ASGITransport.

    The app's database dependency is overridden to use the test database URL.
    Tables are truncated after each test.
    """
    import cacms.config as _cfg
    import cacms.database as _db_module

    # Point the app at the test database for this test
    original_url = _cfg.settings.DATABASE_URL
    _cfg.settings.DATABASE_URL = TEST_DATABASE_URL

    # Rebuild the engine and session factory so the app uses the test DB
    test_engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    test_session_factory = async_sessionmaker(test_engine, expire_on_commit=False)

    original_engine = _db_module.engine
    original_factory = _db_module.AsyncSessionLocal

    _db_module.engine = test_engine
    _db_module.AsyncSessionLocal = test_session_factory

    async def _override_get_db():
        async with test_session_factory() as session:
            try:
                yield session
            finally:
                await session.close()

    from cacms.main import app
    from cacms.database import get_db
    app.dependency_overrides[get_db] = _override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    # Restore original engine/factory
    _db_module.engine = original_engine
    _db_module.AsyncSessionLocal = original_factory
    _cfg.settings.DATABASE_URL = original_url
    app.dependency_overrides.pop(get_db, None)

    # Truncate tables
    async with test_engine.begin() as conn:
        for table in _TRUNCATE_TABLES:
            await conn.execute(text(f"TRUNCATE TABLE {table} CASCADE"))

    await test_engine.dispose()


@pytest.fixture
def admin_token() -> str:
    """JWT token for the admin user."""
    from cacms.services.jwt_service import create_token
    return create_token({"sub": "admin", "role": "admin"})


@pytest_asyncio.fixture
async def seeded_doctor(http_client: AsyncClient, admin_token: str) -> dict:
    """
    Seed a Doctor row directly in the test DB and return its dict representation.

    Doctor creation is not exposed via API in tasks 1–12, so we insert directly.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    doctor_id = uuid.uuid4()
    doctor_name = f"Dr. HTTP {uuid.uuid4().hex[:6]}"

    async with session_factory() as session:
        doc = Doctor(
            doctor_id=doctor_id,
            name=doctor_name,
            specialization="General",
            active=True,
            max_patients_per_day=20,
        )
        session.add(doc)
        await session.commit()

    await engine.dispose()

    return {
        "doctor_id": str(doctor_id),
        "name": doctor_name,
    }


@pytest.fixture
def doctor_token(seeded_doctor: dict) -> str:
    """JWT token for the seeded doctor."""
    from cacms.services.jwt_service import create_token
    return create_token({"sub": seeded_doctor["doctor_id"], "role": "doctor"})


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
