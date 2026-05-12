"""
Doctors Router — full CRUD for admin management.
"""

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin, require_owner_or_admin_or_doctor_or_receptionist
from cacms.models.clinic import Clinic
from cacms.models.doctor import Doctor
from cacms.schemas.common import ErrorResponse
from cacms.services.plan_enforcer import plan_enforcer

router = APIRouter(prefix="/doctors", tags=["doctors"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class DoctorOut(BaseModel):
    doctor_id: uuid.UUID
    name: str
    specialization: Optional[str]
    max_patients_per_day: int
    active: bool

    model_config = {"from_attributes": True}


class DoctorCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    specialization: Optional[str] = None
    max_patients_per_day: int = Field(40, ge=1, le=500)


class DoctorUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    specialization: Optional[str] = None
    max_patients_per_day: Optional[int] = Field(None, ge=1, le=500)
    active: Optional[bool] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[DoctorOut])
async def list_doctors(
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor_or_receptionist),
):
    """Return all active doctors ordered by name."""
    result = await db.execute(
        select(Doctor)
        .where(Doctor.active == True, Doctor.clinic_id == user.clinic_id)  # noqa: E712
        .order_by(Doctor.name)
    )
    return result.scalars().all()


@router.get("/all", response_model=list[DoctorOut])
async def list_all_doctors(
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Return ALL doctors including inactive. Admin only."""
    result = await db.execute(
        select(Doctor).where(Doctor.clinic_id == user.clinic_id).order_by(Doctor.name)
    )
    return result.scalars().all()


@router.post("", response_model=DoctorOut, status_code=status.HTTP_201_CREATED)
async def create_doctor(
    body: DoctorCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Create a new doctor. Enforces max_doctors plan limit."""
    # Fetch clinic for plan enforcement
    clinic_result = await db.execute(select(Clinic).where(Clinic.clinic_id == user.clinic_id))
    clinic = clinic_result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"})

    # Count active doctors for this clinic
    count_result = await db.execute(
        select(func.count()).where(Doctor.clinic_id == user.clinic_id, Doctor.active == True)  # noqa: E712
    )
    current_count = count_result.scalar_one()

    # Enforce plan limit — raises HTTP 402 if at or above limit
    plan_enforcer.check_limit(clinic, "max_doctors", current_count)

    doctor = Doctor(
        name=body.name,
        specialization=body.specialization,
        max_patients_per_day=body.max_patients_per_day,
        active=True,
        clinic_id=user.clinic_id,
    )
    db.add(doctor)
    await db.commit()
    await db.refresh(doctor)
    return doctor


@router.patch(
    "/{doctor_id}",
    response_model=DoctorOut,
    responses={404: {"model": ErrorResponse}},
)
async def update_doctor(
    doctor_id: uuid.UUID,
    body: DoctorUpdate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Update doctor fields. Admin only."""
    result = await db.execute(
        select(Doctor).where(Doctor.doctor_id == doctor_id, Doctor.clinic_id == user.clinic_id)
    )
    doctor = result.scalar_one_or_none()
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "DOCTOR_NOT_FOUND", "message": "Doctor not found"},
        )
    if body.name is not None:
        doctor.name = body.name
    if body.specialization is not None:
        doctor.specialization = body.specialization
    if body.max_patients_per_day is not None:
        doctor.max_patients_per_day = body.max_patients_per_day
    if body.active is not None:
        doctor.active = body.active
    await db.commit()
    await db.refresh(doctor)
    return doctor


@router.delete(
    "/{doctor_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={404: {"model": ErrorResponse}},
)
async def deactivate_doctor(
    doctor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Soft-delete (deactivate) a doctor. Admin only."""
    result = await db.execute(
        select(Doctor).where(Doctor.doctor_id == doctor_id, Doctor.clinic_id == user.clinic_id)
    )
    doctor = result.scalar_one_or_none()
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "DOCTOR_NOT_FOUND", "message": "Doctor not found"},
        )
    doctor.active = False
    await db.commit()
