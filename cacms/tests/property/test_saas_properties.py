"""
CACMS Phase 1 SaaS Completion — Property-Based Tests
Covers Properties 3–7 from the design document (plan features and PlanEnforcer).
Each test runs a minimum of 100 iterations via @settings(max_examples=100).

Feature: cacms-phase1-saas-completion
"""

from __future__ import annotations

import uuid
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from hypothesis import given, settings, strategies as st

from cacms.config.plans import (
    PLAN_FEATURES,
    PLAN_TIERS,
    REQUIRED_PLAN_KEYS,
)
from cacms.services.plan_enforcer import PlanEnforcer

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BOOLEAN_FEATURE_KEYS = [k for k, v in PLAN_FEATURES["free"].items() if isinstance(v, bool)]
NUMERIC_LIMIT_KEYS = [k for k, v in PLAN_FEATURES["free"].items() if v is None or isinstance(v, int)]


def make_clinic(plan: str) -> MagicMock:
    """Return a mock Clinic with the given plan name."""
    clinic = MagicMock()
    clinic.plan = plan
    return clinic


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

plan_name_strategy = st.sampled_from(PLAN_TIERS)

# Two distinct plan indices for tier-ordering tests
two_plan_indices_strategy = st.integers(min_value=0, max_value=len(PLAN_TIERS) - 1)


# ---------------------------------------------------------------------------
# Property 3: PLAN_FEATURES completeness — every plan has all required keys
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 2.2
# ---------------------------------------------------------------------------

def test_property_3_plan_features_completeness():
    """
    For every plan name in PLAN_FEATURES, the plan's feature dict SHALL contain
    all required keys defined in REQUIRED_PLAN_KEYS.
    """
    for plan_name, features in PLAN_FEATURES.items():
        missing = REQUIRED_PLAN_KEYS - set(features.keys())
        assert not missing, (
            f"Plan '{plan_name}' is missing required keys: {missing}"
        )


# ---------------------------------------------------------------------------
# Property 4: Plan tier ordering — higher tiers have non-decreasing numeric limits
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 2.4
# ---------------------------------------------------------------------------

def _numeric_value(v: int | None) -> float:
    """Treat None (unlimited) as infinity for comparison purposes."""
    return float("inf") if v is None else float(v)


@settings(max_examples=100, deadline=None)
@given(
    lower_idx=two_plan_indices_strategy,
    higher_idx=two_plan_indices_strategy,
)
def test_property_4_plan_tier_ordering(lower_idx: int, higher_idx: int):
    """
    For any two plans where one is higher in the tier ordering
    (free < starter < clinic < pro < enterprise), the higher plan's numeric
    limits SHALL be >= the lower plan's limits.
    None (unlimited) is treated as greater than any finite value.
    """
    if lower_idx >= higher_idx:
        return  # Only test when higher_idx is strictly above lower_idx

    lower_plan = PLAN_TIERS[lower_idx]
    higher_plan = PLAN_TIERS[higher_idx]

    lower_features = PLAN_FEATURES[lower_plan]
    higher_features = PLAN_FEATURES[higher_plan]

    for key in NUMERIC_LIMIT_KEYS:
        lower_val = _numeric_value(lower_features.get(key))
        higher_val = _numeric_value(higher_features.get(key))
        assert higher_val >= lower_val, (
            f"Plan '{higher_plan}' has a lower limit for '{key}' ({higher_features.get(key)}) "
            f"than plan '{lower_plan}' ({lower_features.get(key)})"
        )


# ---------------------------------------------------------------------------
# Property 5: PlanEnforcer rejects features not in plan
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 3.2
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(plan_name=plan_name_strategy)
def test_property_5_plan_enforcer_rejects_disabled_features(plan_name: str):
    """
    For any clinic with a given plan, and for any feature name that is False
    in that plan's feature dict, calling PlanEnforcer.check_feature SHALL raise
    HTTPException with status 402 and error_code='PLAN_LIMIT_EXCEEDED'.
    """
    enforcer = PlanEnforcer()
    clinic = make_clinic(plan_name)
    features = PLAN_FEATURES[plan_name]

    disabled_features = [k for k, v in features.items() if v is False]

    for feature_name in disabled_features:
        with pytest.raises(HTTPException) as exc_info:
            enforcer.check_feature(clinic, feature_name)

        assert exc_info.value.status_code == 402, (
            f"Expected 402 for plan='{plan_name}', feature='{feature_name}', "
            f"got {exc_info.value.status_code}"
        )
        detail = exc_info.value.detail
        assert detail["error_code"] == "PLAN_LIMIT_EXCEEDED", (
            f"Expected error_code='PLAN_LIMIT_EXCEEDED', got {detail.get('error_code')}"
        )


# ---------------------------------------------------------------------------
# Property 6: PlanEnforcer rejects counts at or above finite limits
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 3.3
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(plan_name=plan_name_strategy, extra=st.integers(min_value=0, max_value=100))
def test_property_6_plan_enforcer_rejects_at_or_above_limit(plan_name: str, extra: int):
    """
    For any clinic with a given plan, and for any resource with a finite (non-None)
    limit L, PlanEnforcer.check_limit SHALL:
    - raise HTTP 402 when count >= L
    - NOT raise when count < L
    """
    enforcer = PlanEnforcer()
    clinic = make_clinic(plan_name)
    features = PLAN_FEATURES[plan_name]

    finite_resources = {k: v for k, v in features.items() if isinstance(v, int) and v > 0}

    for resource_name, limit in finite_resources.items():
        # count = limit + extra (always >= limit) → must raise
        count_at_or_above = limit + extra
        with pytest.raises(HTTPException) as exc_info:
            enforcer.check_limit(clinic, resource_name, count_at_or_above)

        assert exc_info.value.status_code == 402, (
            f"Expected 402 for plan='{plan_name}', resource='{resource_name}', "
            f"count={count_at_or_above}, limit={limit}"
        )
        detail = exc_info.value.detail
        assert detail["error_code"] == "PLAN_LIMIT_EXCEEDED"

        # count = limit - 1 (strictly below limit) → must NOT raise
        if limit > 0:
            enforcer.check_limit(clinic, resource_name, limit - 1)  # should not raise


# ---------------------------------------------------------------------------
# Property 7: PlanEnforcer allows all counts when limit is None
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 3.4
# ---------------------------------------------------------------------------

@settings(max_examples=100, deadline=None)
@given(plan_name=plan_name_strategy, count=st.integers(min_value=0, max_value=10_000))
def test_property_7_plan_enforcer_unlimited_never_raises(plan_name: str, count: int):
    """
    For any clinic whose plan has None for a given resource limit, calling
    PlanEnforcer.check_limit with any non-negative integer count SHALL NOT raise.
    """
    enforcer = PlanEnforcer()
    clinic = make_clinic(plan_name)
    features = PLAN_FEATURES[plan_name]

    unlimited_resources = [k for k, v in features.items() if v is None]

    for resource_name in unlimited_resources:
        # Must never raise, regardless of count
        try:
            enforcer.check_limit(clinic, resource_name, count)
        except HTTPException as exc:
            pytest.fail(
                f"check_limit raised HTTP {exc.status_code} for plan='{plan_name}', "
                f"resource='{resource_name}' (None limit), count={count}. "
                "Unlimited resources must never raise."
            )


# ---------------------------------------------------------------------------
# Property 8: Metering record-then-read round trip
# Feature: cacms-phase1-saas-completion
# Validates: Requirements 4.4, 4.6
# ---------------------------------------------------------------------------
# These tests require a real PostgreSQL database. They are skipped automatically
# when the test database is not reachable (same pattern as test_properties.py).

import os
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from cacms.services.metering_service import MeteringService
from cacms.tests.integration.conftest import TEST_DATABASE_URL


@pytest_asyncio.fixture(scope="module")
async def _metering_db_available() -> None:
    """Skip Property 8 tests when the test database is unreachable."""
    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception as exc:
        pytest.skip(
            f"Property 8 test database not available ({TEST_DATABASE_URL}): {exc}. "
            "Set TEST_DATABASE_URL to a reachable PostgreSQL instance."
        )
    finally:
        await engine.dispose()


@pytest.mark.asyncio
@settings(max_examples=50, deadline=None)
@given(
    event_type=st.sampled_from(["appointment_created", "report_export", "otp_sent"]),
    quantity=st.integers(min_value=1, max_value=20),
)
async def test_property_8_metering_record_then_read_roundtrip(
    event_type: str, quantity: int, _metering_db_available: None
) -> None:
    """
    Feature: cacms-phase1-saas-completion, Property 8: Metering record-then-read round trip

    For any clinic ID, event type, and positive quantity:
    - call MeteringService.record(...)
    - then call MeteringService.get_monthly_usage(...) for the same clinic and current month
    - the returned count for that event type SHALL be >= the recorded quantity.

    Validates: Requirements 4.4, 4.6
    """
    from datetime import datetime, timezone

    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    # Use a fresh clinic_id per run so counts don't accumulate across examples
    clinic_id = uuid.uuid4()
    now = datetime.now(tz=timezone.utc)

    # MeteringService without Redis — exercises the DB-only path
    service = MeteringService(redis_client=None)

    async with session_factory() as db:
        # We need a real clinic row for the FK constraint.
        # Insert a minimal clinic directly.
        await db.execute(
            text(
                "INSERT INTO clinics (clinic_id, name) VALUES (:cid, :name) "
                "ON CONFLICT DO NOTHING"
            ),
            {"cid": str(clinic_id), "name": f"Metering Test Clinic {clinic_id.hex[:8]}"},
        )
        await db.commit()

        await service.record(db, clinic_id, event_type, quantity=quantity)

        usage = await service.get_monthly_usage(db, clinic_id, now.year, now.month)

    await engine.dispose()

    recorded = usage.get(event_type, 0)
    assert recorded >= quantity, (
        f"Expected usage['{event_type}'] >= {quantity}, got {recorded}"
    )
