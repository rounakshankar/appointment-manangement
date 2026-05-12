"""
Super-admin router — internal management API for the CACMS platform operator.

Authentication: static Bearer token from settings.SUPERADMIN_TOKEN.
No JWT decode — completely independent of the clinic auth layer.

Endpoints:
  PATCH /v1/superadmin/clinics/{clinic_id}/plan  — manual plan activation  (Task 6.1)
  GET   /v1/superadmin/clinics                   — paginated clinic list    (Task 7.4)
  GET   /v1/superadmin/stats                     — platform statistics      (Task 7.4)
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.config import settings
from cacms.config.plans import PLAN_MONTHLY_PRICES, PLAN_TIERS
from cacms.database import get_db
from cacms.models.appointment import Appointment
from cacms.models.clinic import Clinic
from cacms.schemas.common import ErrorResponse

router = APIRouter(prefix="/superadmin", tags=["superadmin"])

_bearer_scheme = HTTPBearer(auto_error=False)

VALID_PLAN_STATUSES = {"active", "grace", "free"}


# ---------------------------------------------------------------------------
# Auth dependency
# ---------------------------------------------------------------------------


async def require_superadmin(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
) -> None:
    """Validate the static SUPERADMIN_TOKEN Bearer token.

    Completely independent of JWT — no decode, no DB lookup.
    Raises HTTP 401 on any mismatch or missing token.
    """
    token = credentials.credentials if credentials else None
    if not token or token != settings.SUPERADMIN_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Invalid or missing superadmin token"},
        )


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class PlanActivationRequest(BaseModel):
    """Body for manual plan activation by the super-admin."""

    plan: str
    plan_status: str = "active"
    plan_note: Optional[str] = None
    plan_expires_at: Optional[datetime] = None

    @field_validator("plan")
    @classmethod
    def plan_must_be_valid(cls, v: str) -> str:
        if v not in PLAN_TIERS:
            raise ValueError(
                f"Invalid plan '{v}'. Must be one of: {', '.join(PLAN_TIERS)}"
            )
        return v

    @field_validator("plan_status")
    @classmethod
    def plan_status_must_be_valid(cls, v: str) -> str:
        if v not in VALID_PLAN_STATUSES:
            raise ValueError(
                f"Invalid plan_status '{v}'. Must be one of: {', '.join(sorted(VALID_PLAN_STATUSES))}"
            )
        return v


class PlanActivationResponse(BaseModel):
    clinic_id: str
    name: str
    plan: str
    plan_status: str
    plan_note: Optional[str]
    plan_activated_at: Optional[datetime]
    plan_expires_at: Optional[datetime]


class ClinicListItem(BaseModel):
    clinic_id: str
    name: str
    plan: str
    plan_status: str
    created_at: datetime


class ClinicListResponse(BaseModel):
    items: list[ClinicListItem]
    total: int
    page: int
    page_size: int


class PlatformStatsResponse(BaseModel):
    total_clinics: int
    total_appointments_today: int
    mrr_estimate: int  # INR, not paise


# ---------------------------------------------------------------------------
# Task 6.1 — PATCH /v1/superadmin/clinics/{clinic_id}/plan
# ---------------------------------------------------------------------------


@router.patch(
    "/clinics/{clinic_id}/plan",
    response_model=PlanActivationResponse,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
    },
)
async def activate_clinic_plan(
    clinic_id: uuid.UUID,
    body: PlanActivationRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_superadmin),
) -> PlanActivationResponse:
    """Manually activate or change a clinic's plan.

    This is the only way to move a clinic to a paid plan — the operator does
    this after receiving payment (cash or UPI). No payment gateway involved.

    Business rules:
    - If ``plan_expires_at`` is provided and is in the past, ``plan_status``
      is automatically set to ``'grace'`` regardless of the submitted value.
    - ``plan_activated_at`` is always stamped to now() when this endpoint is called.
    """
    result = await db.execute(select(Clinic).where(Clinic.clinic_id == clinic_id))
    clinic = result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"},
        )

    now = datetime.now(tz=timezone.utc)

    # Auto-downgrade to grace when expiry is already in the past
    effective_status = body.plan_status
    if body.plan_expires_at is not None:
        expires = body.plan_expires_at
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < now:
            effective_status = "grace"

    clinic.plan = body.plan
    clinic.plan_status = effective_status
    clinic.plan_note = body.plan_note
    clinic.plan_expires_at = body.plan_expires_at
    clinic.plan_activated_at = now

    await db.commit()
    await db.refresh(clinic)

    return PlanActivationResponse(
        clinic_id=str(clinic.clinic_id),
        name=clinic.name,
        plan=clinic.plan,
        plan_status=clinic.plan_status,
        plan_note=clinic.plan_note,
        plan_activated_at=clinic.plan_activated_at,
        plan_expires_at=clinic.plan_expires_at,
    )


# ---------------------------------------------------------------------------
# Task 7.4 — GET /v1/superadmin/clinics
# ---------------------------------------------------------------------------


@router.get(
    "/clinics",
    response_model=ClinicListResponse,
    responses={401: {"model": ErrorResponse}},
)
async def list_clinics(
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_superadmin),
) -> ClinicListResponse:
    """Return a paginated list of all clinics on the platform."""
    offset = (page - 1) * page_size

    # Total count
    count_result = await db.execute(select(func.count()).select_from(Clinic))
    total = count_result.scalar_one()

    # Page of results ordered by creation date (newest first)
    rows_result = await db.execute(
        select(Clinic)
        .order_by(Clinic.created_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    clinics = rows_result.scalars().all()

    return ClinicListResponse(
        items=[
            ClinicListItem(
                clinic_id=str(c.clinic_id),
                name=c.name,
                plan=c.plan,
                plan_status=c.plan_status,
                created_at=c.created_at,
            )
            for c in clinics
        ],
        total=total,
        page=page,
        page_size=page_size,
    )


# ---------------------------------------------------------------------------
# Task 7.4 — GET /v1/superadmin/stats
# ---------------------------------------------------------------------------


@router.get(
    "/stats",
    response_model=PlatformStatsResponse,
    responses={401: {"model": ErrorResponse}},
)
async def get_platform_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_superadmin),
) -> PlatformStatsResponse:
    """Return high-level platform statistics.

    - ``total_clinics``: count of all registered clinics.
    - ``total_appointments_today``: appointments with ``scheduled_date = today()``
      across all clinics.
    - ``mrr_estimate``: sum of monthly prices (INR) for all active paid clinics.
      Calculated from ``PLAN_MONTHLY_PRICES`` — does not include ``free`` or
      ``enterprise`` (bespoke pricing).
    """
    today = date.today()

    # Total clinics
    total_clinics_result = await db.execute(
        select(func.count()).select_from(Clinic)
    )
    total_clinics: int = total_clinics_result.scalar_one()

    # Appointments today (across all clinics)
    appts_today_result = await db.execute(
        select(func.count())
        .select_from(Appointment)
        .where(Appointment.scheduled_date == today)
    )
    total_appointments_today: int = appts_today_result.scalar_one()

    # MRR estimate: fetch all active paid clinics and sum their plan prices
    paid_clinics_result = await db.execute(
        select(Clinic.plan).where(
            Clinic.plan_status == "active",
            Clinic.plan != "free",
        )
    )
    plan_names = paid_clinics_result.scalars().all()
    mrr_estimate = sum(PLAN_MONTHLY_PRICES.get(p, 0) for p in plan_names)

    return PlatformStatsResponse(
        total_clinics=total_clinics,
        total_appointments_today=total_appointments_today,
        mrr_estimate=mrr_estimate,
    )
