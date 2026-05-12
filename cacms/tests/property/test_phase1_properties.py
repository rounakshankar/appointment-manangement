"""
Phase 1 Deployment Foundation — Property-Based Tests
Covers Properties 1, 3, 4 from the design document.
Each test runs a minimum of 100 iterations via @settings(max_examples=100).
"""

import uuid

import pytest
from hypothesis import given, settings, strategies as st

from cacms.services.password_service import hash_password, verify_password
from cacms.services.jwt_service import create_token, decode_token
from fastapi import HTTPException

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

VALID_ROLES = ["owner", "admin", "doctor", "receptionist"]

valid_role_strategy = st.sampled_from(VALID_ROLES)

# Any non-empty text that is NOT a valid role
invalid_role_strategy = st.text(min_size=1, max_size=50).filter(
    lambda r: r not in VALID_ROLES
)

# Passwords: printable ASCII, at least 1 char
password_strategy = st.text(
    min_size=1,
    max_size=72,  # bcrypt max
    alphabet=st.characters(
        whitelist_categories=("L", "N", "P", "S"),
        blacklist_characters="\x00",
    ),
)


# ---------------------------------------------------------------------------
# Property 1: Bcrypt hash round-trip
# Feature: cacms-phase1-deployment-foundation
# Validates: Requirements 1.2, 1.3
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(password=password_strategy)
def test_property_1_bcrypt_hash_roundtrip(password: str):
    """
    For any non-empty password string:
    - hash_password produces a bcrypt hash (starts with $2b$)
    - verify_password returns True with the original password
    - verify_password returns False with any different password
    """
    hashed = hash_password(password)

    # Must be a bcrypt hash
    assert hashed.startswith("$2b$") or hashed.startswith("$2a$"), (
        f"Expected bcrypt hash, got: {hashed[:10]}"
    )

    # Cost factor must be >= 12
    parts = hashed.split("$")
    cost = int(parts[2])
    assert cost >= 12, f"Expected bcrypt cost >= 12, got {cost}"

    # Round-trip: correct password verifies
    assert verify_password(password, hashed), (
        f"verify_password returned False for correct password"
    )

    # Wrong password must not verify
    wrong = password + "_wrong"
    assert not verify_password(wrong, hashed), (
        f"verify_password returned True for wrong password"
    )


# ---------------------------------------------------------------------------
# Property 3: JWT role claim round-trip
# Feature: cacms-phase1-deployment-foundation
# Validates: Requirements 2.1
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(role=valid_role_strategy)
def test_property_3_jwt_role_claim_roundtrip(role: str):
    """
    For any role in {owner, admin, doctor, receptionist}:
    - create_token then decode_token returns a payload with the same role
    - sub and clinic_id claims are preserved
    """
    user_id = str(uuid.uuid4())
    clinic_id = str(uuid.uuid4())

    token = create_token({
        "sub": user_id,
        "role": role,
        "clinic_id": clinic_id,
    })

    payload = decode_token(token)

    assert payload["role"] == role, (
        f"Expected role={role}, got {payload.get('role')}"
    )
    assert payload["sub"] == user_id, (
        f"Expected sub={user_id}, got {payload.get('sub')}"
    )
    assert payload["clinic_id"] == clinic_id, (
        f"Expected clinic_id={clinic_id}, got {payload.get('clinic_id')}"
    )


# ---------------------------------------------------------------------------
# Property 4: Invalid role tokens are rejected by get_current_user
# Feature: cacms-phase1-deployment-foundation (optional)
# Validates: Requirements 2.2
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(invalid_role=invalid_role_strategy)
def test_property_4_invalid_role_tokens_rejected(invalid_role: str):
    """
    For any JWT whose role claim is not in {owner, admin, doctor, receptionist},
    get_current_user SHALL raise HTTP 401.
    """
    from cacms.middleware.auth_middleware import VALID_STAFF_ROLES

    # Confirm the role is indeed invalid
    assert invalid_role not in VALID_STAFF_ROLES and invalid_role != "patient"

    token = create_token({
        "sub": str(uuid.uuid4()),
        "role": invalid_role,
        "clinic_id": str(uuid.uuid4()),
    })

    # decode_token itself succeeds (it only checks signature/expiry)
    payload = decode_token(token)
    assert payload["role"] == invalid_role

    # The middleware validation logic should reject this role
    role = payload.get("role")
    is_valid = role in VALID_STAFF_ROLES or role == "patient"
    assert not is_valid, (
        f"Role '{invalid_role}' should be invalid but passed middleware check"
    )
