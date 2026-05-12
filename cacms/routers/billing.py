"""
Billing router — plan information endpoints (no payment gateway).

Clinics pay directly via cash or UPI. The operator activates plans manually
via the super-admin API. This router only exposes read-only plan information
so the Flutter billing screen can display what's available and the current
subscription status.

Endpoints:
  GET /v1/billing/plans   — public; list all plans with prices and features
  GET /v1/billing/status  — owner only; current plan status + renewal info
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.config.plans import PLAN_FEATURES, PLAN_MONTHLY_PRICES, PLAN_TIERS
from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner
from cacms.models.clinic import Clinic
from cacms.schemas.common import ErrorResponse

router = APIRouter(prefix="/billing", tags=["billing"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _days_remaining(plan_expires_at: Optional[datetime]) -> Optional[int]:
    if plan_expires_at is None:
        return None
    now = datetime.now(tz=timezone.utc)
    expires = plan_expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    return max(0, (expires - now).days)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class PlanInfo(BaseModel):
    name: str
    price_inr: int
    features: dict[str, Any]


class PlansListResponse(BaseModel):
    plans: list[PlanInfo]


class BillingStatusResponse(BaseModel):
    plan: str
    plan_status: str
    plan_expires_at: Optional[datetime]
    days_remaining: Optional[int]
    message: Optional[str] = None


# ---------------------------------------------------------------------------
# GET /v1/billing/plans  (no auth)
# ---------------------------------------------------------------------------


@router.get(
    "/plans",
    response_model=PlansListResponse,
)
async def list_plans() -> PlansListResponse:
    """Return all available plans with their monthly prices (INR) and feature sets.

    No authentication required — used by the Flutter billing screen to show
    what's available before the owner decides to upgrade.

    ``enterprise`` is included with a price of 0 to indicate bespoke/contact-us
    pricing; the Flutter screen should render it as "Contact us".
    """
    plans = [
        PlanInfo(
            name=plan,
            price_inr=PLAN_MONTHLY_PRICES.get(plan, 0),
            features=PLAN_FEATURES[plan],
        )
        for plan in PLAN_TIERS
    ]
    return PlansListResponse(plans=plans)


# ---------------------------------------------------------------------------
# GET /v1/billing/status  (owner only)
# ---------------------------------------------------------------------------


@router.get(
    "/status",
    response_model=BillingStatusResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def get_billing_status(
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> BillingStatusResponse:
    """Return the clinic's current plan, status, expiry, and a renewal message.

    When ``plan_status`` is ``'grace'``, a human-readable message is included
    so the Flutter screen can prompt the owner to contact support.
    """
    result = await db.execute(select(Clinic).where(Clinic.clinic_id == user.clinic_id))
    clinic = result.scalar_one_or_none()
    if clinic is None:
        from fastapi import HTTPException, status as http_status
        raise HTTPException(
            status_code=http_status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"},
        )

    message: Optional[str] = None
    if clinic.plan_status == "grace":
        message = "Your plan has expired. Please contact support to renew."

    return BillingStatusResponse(
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        plan_expires_at=clinic.plan_expires_at,
        days_remaining=_days_remaining(clinic.plan_expires_at),
        message=message,
    )
