import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin
from cacms.models.clinic import Clinic
from cacms.models.doctor import Doctor
from cacms.models.user import User
from cacms.schemas.common import ErrorResponse
from cacms.schemas.user import UserCreate, UserOut, UserUpdate
from cacms.services.password_service import hash_password
from cacms.services.plan_enforcer import plan_enforcer

router = APIRouter(prefix="/users", tags=["users"])


async def _validate_linked_doctor(
    db: AsyncSession,
    clinic_id: uuid.UUID,
    role: str,
    linked_doctor_id: uuid.UUID | None,
) -> None:
    if role == "doctor" and linked_doctor_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error_code": "DOCTOR_LINK_REQUIRED", "message": "Doctor users must be linked to a doctor."},
        )
    if linked_doctor_id is None:
        return

    result = await db.execute(
        select(Doctor).where(
            Doctor.doctor_id == linked_doctor_id,
            Doctor.clinic_id == clinic_id,
        )
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "DOCTOR_NOT_FOUND", "message": "Linked doctor not found in this clinic."},
        )


@router.get("", response_model=list[UserOut])
async def list_users(
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner_or_admin),
):
    result = await db.execute(
        select(User)
        .where(User.clinic_id == user.clinic_id)
        .order_by(User.created_at.desc())
    )
    return result.scalars().all()


@router.post(
    "",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}, 409: {"model": ErrorResponse}},
)
async def create_user(
    body: UserCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserContext = Depends(require_owner_or_admin),
):
    await _validate_linked_doctor(db, current_user.clinic_id, body.role, body.linked_doctor_id)

    # Enforce max_staff plan limit (counts all non-owner active staff users)
    clinic_result = await db.execute(select(Clinic).where(Clinic.clinic_id == current_user.clinic_id))
    clinic = clinic_result.scalar_one_or_none()
    if clinic is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail={"error_code": "CLINIC_NOT_FOUND", "message": "Clinic not found"})

    staff_count_result = await db.execute(
        select(func.count()).where(
            User.clinic_id == current_user.clinic_id,
            User.active == True,  # noqa: E712
            User.role != "owner",
        )
    )
    current_staff_count = staff_count_result.scalar_one()
    plan_enforcer.check_limit(clinic, "max_staff", current_staff_count)

    staff_user = User(
        username=body.username.strip(),
        password_hash=hash_password(body.password),
        role=body.role,
        linked_doctor_id=body.linked_doctor_id if body.role == "doctor" else None,
        clinic_id=current_user.clinic_id,
        active=True,
    )
    db.add(staff_user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error_code": "USER_CONFLICT", "message": "Username already exists."},
        )
    await db.refresh(staff_user)
    return staff_user


@router.patch(
    "/{user_id}",
    response_model=UserOut,
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}, 409: {"model": ErrorResponse}},
)
async def update_user(
    user_id: uuid.UUID,
    body: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserContext = Depends(require_owner_or_admin),
):
    result = await db.execute(
        select(User).where(User.user_id == user_id, User.clinic_id == current_user.clinic_id)
    )
    staff_user = result.scalar_one_or_none()
    if staff_user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "USER_NOT_FOUND", "message": "User not found."},
        )

    target_role = body.role or staff_user.role
    target_linked_doctor_id = body.linked_doctor_id
    if target_linked_doctor_id is None and target_role == "doctor":
        target_linked_doctor_id = staff_user.linked_doctor_id
    await _validate_linked_doctor(db, current_user.clinic_id, target_role, target_linked_doctor_id)

    if body.username is not None:
        staff_user.username = body.username.strip()
    if body.password is not None:
        staff_user.password_hash = hash_password(body.password)
    if body.role is not None:
        staff_user.role = body.role
    if body.linked_doctor_id is not None or target_role != "doctor":
        staff_user.linked_doctor_id = target_linked_doctor_id if target_role == "doctor" else None
    if body.active is not None:
        staff_user.active = body.active

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error_code": "USER_CONFLICT", "message": "Username already exists."},
        )
    await db.refresh(staff_user)
    return staff_user
