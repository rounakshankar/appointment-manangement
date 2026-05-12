"""
Clinic router — owner-facing endpoints for clinic profile, plan, usage, and subscription.

All endpoints require the ``owner`` role.

Endpoints:
  GET   /v1/clinic               — full clinic profile           (Task 7.1)
  PATCH /v1/clinic               — update clinic profile         (Task 7.1)
  GET   /v1/clinic/usage         — current month usage summary   (Task 7.1)
  GET   /v1/clinic/plan          — plan features + usage         (Task 7.1)
  GET   /v1/clinic/subscription  — plan status + days remaining  (Task 6.3)
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.config.plans import PLAN_FEATURES
from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner
from cacms.models.clinic import Clinic
from cacms.schemas.common import ErrorResponse
from cacms.services.metering_service import MeteringService

router = APIRouter(prefix="/clinic", tags=["clinic"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _get_clinic_or_404(db: AsyncSession, clinic_id) -> Clinic:
    """Fetch the clinic record for the authenticated owner, raising 404 if missing."""
    result = await db.execute(select(Clinic).where(Clinic.clinic_id == clinic_id))
    clinic = result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"},
        )
    return clinic


def _days_remaining(plan_expires_at: Optional[datetime]) -> Optional[int]:
    """Return whole days until expiry, or None when no expiry is set."""
    if plan_expires_at is None:
        return None
    now = datetime.now(tz=timezone.utc)
    expires = plan_expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    delta = expires - now
    return max(0, delta.days)


def _get_metering(request: Request) -> Optional[MeteringService]:
    """Return the MeteringService from app.state, or None if not initialised."""
    return getattr(request.app.state, "metering", None)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class ClinicProfileResponse(BaseModel):
    clinic_id: str
    name: str
    plan: str
    plan_status: str
    billing_email: Optional[str]
    clinic_address: Optional[str]
    clinic_phone: Optional[str]
    clinic_gstin: Optional[str]
    clinic_reg_number: Optional[str]
    receipt_header: Optional[str]
    receipt_footer: Optional[str]


class ClinicUpdateRequest(BaseModel):
    name: Optional[str] = None
    billing_email: Optional[str] = None
    clinic_address: Optional[str] = None
    clinic_phone: Optional[str] = None
    clinic_gstin: Optional[str] = None
    clinic_reg_number: Optional[str] = None
    receipt_header: Optional[str] = None
    receipt_footer: Optional[str] = None

    @field_validator("name")
    @classmethod
    def name_not_whitespace(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("name must not be empty or whitespace-only")
        return v


class ClinicPlanResponse(BaseModel):
    plan: str
    plan_status: str
    features: dict[str, Any]
    usage: dict[str, int]


class SubscriptionResponse(BaseModel):
    plan: str
    plan_status: str
    plan_expires_at: Optional[datetime]
    days_remaining: Optional[int]
    message: Optional[str] = None


# ---------------------------------------------------------------------------
# Task 7.1 — GET /v1/clinic
# ---------------------------------------------------------------------------


@router.get(
    "",
    response_model=ClinicProfileResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def get_clinic(
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> ClinicProfileResponse:
    """Return the full clinic profile including all receipt/billing fields."""
    clinic = await _get_clinic_or_404(db, user.clinic_id)
    return ClinicProfileResponse(
        clinic_id=str(clinic.clinic_id),
        name=clinic.name,
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        billing_email=clinic.billing_email,
        clinic_address=clinic.clinic_address,
        clinic_phone=clinic.clinic_phone,
        clinic_gstin=clinic.clinic_gstin,
        clinic_reg_number=clinic.clinic_reg_number,
        receipt_header=clinic.receipt_header,
        receipt_footer=clinic.receipt_footer,
    )


# ---------------------------------------------------------------------------
# Task 7.1 — PATCH /v1/clinic
# ---------------------------------------------------------------------------


@router.patch(
    "",
    response_model=ClinicProfileResponse,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
    },
)
async def update_clinic(
    body: ClinicUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> ClinicProfileResponse:
    """Update editable clinic profile fields.

    Only fields present in the request body are updated (partial update).
    ``name`` is rejected with HTTP 422 when it is empty or whitespace-only.
    """
    clinic = await _get_clinic_or_404(db, user.clinic_id)

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(clinic, field, value)

    await db.commit()
    await db.refresh(clinic)

    return ClinicProfileResponse(
        clinic_id=str(clinic.clinic_id),
        name=clinic.name,
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        billing_email=clinic.billing_email,
        clinic_address=clinic.clinic_address,
        clinic_phone=clinic.clinic_phone,
        clinic_gstin=clinic.clinic_gstin,
        clinic_reg_number=clinic.clinic_reg_number,
        receipt_header=clinic.receipt_header,
        receipt_footer=clinic.receipt_footer,
    )


# ---------------------------------------------------------------------------
# Task 7.1 — GET /v1/clinic/usage
# ---------------------------------------------------------------------------


@router.get(
    "/usage",
    response_model=dict,
    responses={401: {"model": ErrorResponse}},
)
async def get_clinic_usage(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> dict:
    """Return the current calendar month's usage summary as ``{event_type: count}``."""
    metering: Optional[MeteringService] = _get_metering(request)
    if metering is None:
        return {}

    now = datetime.now(tz=timezone.utc)
    return await metering.get_monthly_usage(db, user.clinic_id, now.year, now.month)


# ---------------------------------------------------------------------------
# Task 7.1 — GET /v1/clinic/plan
# ---------------------------------------------------------------------------


@router.get(
    "/plan",
    response_model=ClinicPlanResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def get_clinic_plan(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> ClinicPlanResponse:
    """Return the clinic's plan name, status, full feature limits, and current usage."""
    clinic = await _get_clinic_or_404(db, user.clinic_id)
    features = PLAN_FEATURES.get(clinic.plan, PLAN_FEATURES["free"])

    metering: Optional[MeteringService] = _get_metering(request)
    usage: dict[str, int] = {}
    if metering is not None:
        now = datetime.now(tz=timezone.utc)
        usage = await metering.get_monthly_usage(db, user.clinic_id, now.year, now.month)

    return ClinicPlanResponse(
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        features=features,
        usage=usage,
    )


# ---------------------------------------------------------------------------
# Task 6.3 — GET /v1/clinic/subscription
# ---------------------------------------------------------------------------


@router.get(
    "/subscription",
    response_model=SubscriptionResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def get_subscription(
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner),
) -> SubscriptionResponse:
    """Return the clinic's current plan status and expiry information.

    When ``plan_status`` is ``'grace'``, a human-readable renewal message is
    included so the owner knows to contact support.
    """
    clinic = await _get_clinic_or_404(db, user.clinic_id)

    message: Optional[str] = None
    if clinic.plan_status == "grace":
        message = "Your plan has expired. Please contact support to renew."

    return SubscriptionResponse(
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        plan_expires_at=clinic.plan_expires_at,
        days_remaining=_days_remaining(clinic.plan_expires_at),
        message=message,
    )
