"""
Auth router — JWT login and clinic registration.

Patient OTP login has been removed entirely (Phase 1 SaaS redesign).
Patients never log in — queue info is public, medical records are delivered
by email on request via POST /v1/public/request-records.

otp_service.py and the otp_sessions table are kept in place for potential
staff 2FA in a future phase but are not exposed via API.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from cacms.database import get_db
from cacms.limiter import limiter
from cacms.models.user import User
from cacms.models.clinic import Clinic
from cacms.schemas.auth import LoginRequest, TokenResponse, ClinicRegistrationRequest, ClinicRegistrationResponse
from cacms.schemas.common import ErrorResponse
from cacms.services.jwt_service import create_token
from cacms.services.password_service import verify_password, hash_password
from cacms.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/login",
    response_model=TokenResponse,
    responses={401: {"model": ErrorResponse}},
)
@limiter.limit(settings.AUTH_RATE_LIMIT)
async def login(request: Request, body: LoginRequest, db: AsyncSession = Depends(get_db)):
    """JWT login — queries users table, verifies bcrypt hash."""
    result = await db.execute(
        select(User).where(User.username == body.username, User.active == True)  # noqa: E712
    )
    user = result.scalar_one_or_none()

    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Invalid credentials"},
        )

    token = create_token({
        "sub": str(user.user_id),
        "role": user.role,
        "clinic_id": str(user.clinic_id),
        "linked_doctor_id": str(user.linked_doctor_id) if user.linked_doctor_id else None,
    })
    return TokenResponse(
        access_token=token,
        role=user.role,
        user_id=str(user.user_id),
        clinic_id=str(user.clinic_id),
        linked_doctor_id=str(user.linked_doctor_id) if user.linked_doctor_id else None,
    )


@router.post(
    "/register-clinic",
    response_model=ClinicRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
    responses={400: {"model": ErrorResponse}, 409: {"model": ErrorResponse}},
)
@limiter.limit("5/minute")
async def register_clinic(request: Request, body: ClinicRegistrationRequest, db: AsyncSession = Depends(get_db)):
    """Register a new clinic and create the owner user."""
    # Check if clinic name already exists
    clinic_result = await db.execute(select(Clinic).where(Clinic.name == body.clinic_name))
    if clinic_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error_code": "CLINIC_EXISTS", "message": "Clinic with this name already exists"},
        )

    # Check if username already exists
    user_result = await db.execute(select(User).where(User.username == body.owner_username))
    if user_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error_code": "USERNAME_EXISTS", "message": "Username already exists"},
        )

    # Create clinic
    clinic = Clinic(name=body.clinic_name)
    db.add(clinic)
    await db.flush()  # Get clinic_id

    # Create owner user
    owner_user = User(
        username=body.owner_username,
        password_hash=hash_password(body.owner_password),
        role="owner",
        clinic_id=clinic.clinic_id,
        active=True,
    )
    db.add(owner_user)
    await db.commit()
    await db.refresh(owner_user)

    # Create JWT token
    token = create_token({
        "sub": str(owner_user.user_id),
        "role": owner_user.role,
        "clinic_id": str(owner_user.clinic_id),
        "linked_doctor_id": None,
    })

    return ClinicRegistrationResponse(
        clinic_id=str(clinic.clinic_id),
        clinic_name=clinic.name,
        owner_user_id=str(owner_user.user_id),
        access_token=token,
    )
