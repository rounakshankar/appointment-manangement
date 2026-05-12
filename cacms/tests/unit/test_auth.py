"""
Unit tests for auth router — Phase 1 Deployment Foundation
Tests: correct credentials → 200 + JWT; wrong password → 401; unknown username → 401
Validates: Requirements 1.3, 1.7
"""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.main import app
from cacms.models.user import User
from cacms.services.password_service import hash_password


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_user(username: str, password: str, role: str = "admin") -> User:
    """Build a User ORM object with a real bcrypt hash."""
    clinic_id = uuid.uuid4()
    return User(
        user_id=uuid.uuid4(),
        username=username,
        password_hash=hash_password(password),
        role=role,
        active=True,
        clinic_id=clinic_id,
        linked_doctor_id=None,
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """TestClient with a mocked DB session."""
    return TestClient(app, raise_server_exceptions=False)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestLoginEndpoint:
    """POST /v1/auth/login"""

    def test_correct_credentials_returns_200_and_jwt(self):
        """Correct username + password → 200 with access_token."""
        user = _make_user("testadmin", "correct_password", role="admin")

        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = user

        mock_db = AsyncMock(spec=AsyncSession)
        mock_db.execute = AsyncMock(return_value=mock_result)

        async def override_get_db():
            yield mock_db

        from cacms.database import get_db
        app.dependency_overrides[get_db] = override_get_db

        try:
            with TestClient(app) as c:
                resp = c.post(
                    "/v1/auth/login",
                    json={"username": "testadmin", "password": "correct_password"},
                )
            assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
            data = resp.json()
            assert "access_token" in data
            assert data["role"] == "admin"
            assert len(data["access_token"]) > 20  # non-trivial JWT
        finally:
            app.dependency_overrides.clear()

    def test_wrong_password_returns_401(self):
        """Correct username but wrong password → 401 UNAUTHORIZED."""
        user = _make_user("testadmin", "correct_password", role="admin")

        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = user

        mock_db = AsyncMock(spec=AsyncSession)
        mock_db.execute = AsyncMock(return_value=mock_result)

        async def override_get_db():
            yield mock_db

        from cacms.database import get_db
        app.dependency_overrides[get_db] = override_get_db

        try:
            with TestClient(app) as c:
                resp = c.post(
                    "/v1/auth/login",
                    json={"username": "testadmin", "password": "wrong_password"},
                )
            assert resp.status_code == 401, f"Expected 401, got {resp.status_code}"
            data = resp.json()
            # The exception handler returns detail as top-level or nested
            error_code = (
                data.get("error_code")
                or (data.get("detail") or {}).get("error_code")
            )
            assert error_code == "UNAUTHORIZED"
        finally:
            app.dependency_overrides.clear()

    def test_unknown_username_returns_401(self):
        """Username not in DB → 401 UNAUTHORIZED."""
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None  # user not found

        mock_db = AsyncMock(spec=AsyncSession)
        mock_db.execute = AsyncMock(return_value=mock_result)

        async def override_get_db():
            yield mock_db

        from cacms.database import get_db
        app.dependency_overrides[get_db] = override_get_db

        try:
            with TestClient(app) as c:
                resp = c.post(
                    "/v1/auth/login",
                    json={"username": "nobody", "password": "any_password"},
                )
            assert resp.status_code == 401, f"Expected 401, got {resp.status_code}"
            data = resp.json()
            error_code = (
                data.get("error_code")
                or (data.get("detail") or {}).get("error_code")
            )
            assert error_code == "UNAUTHORIZED"
        finally:
            app.dependency_overrides.clear()

    def test_inactive_user_returns_401(self):
        """Inactive user (active=False) → 401 because query filters active=True."""
        # The query in auth.py filters WHERE active = True, so inactive users
        # return None from scalar_one_or_none — same as unknown username.
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None

        mock_db = AsyncMock(spec=AsyncSession)
        mock_db.execute = AsyncMock(return_value=mock_result)

        async def override_get_db():
            yield mock_db

        from cacms.database import get_db
        app.dependency_overrides[get_db] = override_get_db

        try:
            with TestClient(app) as c:
                resp = c.post(
                    "/v1/auth/login",
                    json={"username": "inactive_user", "password": "any_password"},
                )
            assert resp.status_code == 401
        finally:
            app.dependency_overrides.clear()

    def test_jwt_contains_role_and_clinic_id(self):
        """Returned JWT payload must contain role and clinic_id claims."""
        import base64
        import json

        user = _make_user("owner_user", "secure_pass_123", role="owner")

        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = user

        mock_db = AsyncMock(spec=AsyncSession)
        mock_db.execute = AsyncMock(return_value=mock_result)

        async def override_get_db():
            yield mock_db

        from cacms.database import get_db
        app.dependency_overrides[get_db] = override_get_db

        try:
            with TestClient(app) as c:
                resp = c.post(
                    "/v1/auth/login",
                    json={"username": "owner_user", "password": "secure_pass_123"},
                )
            assert resp.status_code == 200
            token = resp.json()["access_token"]

            # Decode JWT payload (no signature verification — client-side check)
            parts = token.split(".")
            assert len(parts) == 3
            padded = parts[1] + "=" * (4 - len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(padded))

            assert payload["role"] == "owner"
            assert "clinic_id" in payload
            assert "sub" in payload
        finally:
            app.dependency_overrides.clear()
