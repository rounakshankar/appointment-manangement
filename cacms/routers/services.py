"""
Services Router — full CRUD for admin management.
"""

import uuid
from decimal import Decimal
from typing import Optional, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin, require_owner_or_admin_or_doctor
from cacms.models.service import Service, ServiceCategory
from cacms.schemas.service import ServiceOut
from cacms.schemas.common import ErrorResponse
from cacms.services.service_catalog import get_active_services

router = APIRouter(prefix="/services", tags=["services"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ServiceCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    category: Literal["consultation", "test", "procedure"]
    base_price: Decimal = Field(..., ge=0, decimal_places=2)


class ServiceUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    category: Optional[Literal["consultation", "test", "procedure"]] = None
    base_price: Optional[Decimal] = Field(None, ge=0, decimal_places=2)
    active: Optional[bool] = None


class ServiceOutFull(BaseModel):
    service_id: uuid.UUID
    name: str
    category: str
    base_price: Decimal
    active: bool

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[ServiceOut])
async def list_services(
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_doctor),
):
    """Return all active services. Restricted to admin and doctor roles."""
    return await get_active_services(db, user.clinic_id)


@router.get("/all", response_model=list[ServiceOutFull])
async def list_all_services(
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Return ALL services including inactive. Admin only."""
    result = await db.execute(
        select(Service)
        .where(Service.clinic_id == user.clinic_id)
        .order_by(Service.category, Service.name)
    )
    return result.scalars().all()


@router.post("", response_model=ServiceOutFull, status_code=status.HTTP_201_CREATED)
async def create_service(
    body: ServiceCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Create a new service. Admin only."""
    svc = Service(
        name=body.name,
        category=ServiceCategory(body.category),
        base_price=body.base_price,
        active=True,
        clinic_id=user.clinic_id,
    )
    db.add(svc)
    await db.commit()
    await db.refresh(svc)
    return svc


@router.patch(
    "/{service_id}",
    response_model=ServiceOutFull,
    responses={404: {"model": ErrorResponse}},
)
async def update_service(
    service_id: uuid.UUID,
    body: ServiceUpdate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Update service fields. Admin only."""
    result = await db.execute(
        select(Service).where(Service.service_id == service_id, Service.clinic_id == user.clinic_id)
    )
    svc = result.scalar_one_or_none()
    if not svc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "SERVICE_NOT_FOUND", "message": "Service not found"},
        )
    if body.name is not None:
        svc.name = body.name
    if body.category is not None:
        svc.category = ServiceCategory(body.category)
    if body.base_price is not None:
        svc.base_price = body.base_price
    if body.active is not None:
        svc.active = body.active
    await db.commit()
    await db.refresh(svc)
    return svc


@router.delete(
    "/{service_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={404: {"model": ErrorResponse}},
)
async def deactivate_service(
    service_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin),
):
    """Soft-delete (deactivate) a service. Admin only."""
    result = await db.execute(
        select(Service).where(Service.service_id == service_id, Service.clinic_id == user.clinic_id)
    )
    svc = result.scalar_one_or_none()
    if not svc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "SERVICE_NOT_FOUND", "message": "Service not found"},
        )
    svc.active = False
    await db.commit()
