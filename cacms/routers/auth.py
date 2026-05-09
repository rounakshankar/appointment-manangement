from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from cacms.database import get_db
from cacms.limiter import limiter
from cacms.models.user import User
from cacms.schemas.auth import LoginRequest, TokenResponse, OtpRequest, OtpVerifyRequest
from cacms.schemas.common import ErrorResponse
from cacms.services.jwt_service import create_token
from cacms.services.otp_service import generate_otp, verify_otp
from cacms.services.password_service import verify_password
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
    "/verify-otp",
    response_model=TokenResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def verify_otp_endpoint(body: OtpVerifyRequest, db: AsyncSession = Depends(get_db)):
    """OTP verification for Patient role. Returns JWT on success."""
    from cacms.services.patient_service import get_patient_by_phone, normalise_phone

    patient = await get_patient_by_phone(db, body.phone)
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "PATIENT_NOT_FOUND", "message": "No patient with that phone number"},
        )

    session = await verify_otp(db, patient.phone, body.otp)
    if not session:
        session = await verify_otp(db, normalise_phone(body.phone), body.otp)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Invalid or expired OTP"},
        )

    token = create_token({
        "sub": str(patient.patient_id),
        "role": "patient",
        "clinic_id": str(patient.clinic_id),
    })
    return TokenResponse(
        access_token=token,
        role="patient",
        user_id=str(patient.patient_id),
        clinic_id=str(patient.clinic_id),
    )


@router.post(
    "/request-otp",
    status_code=200,
    responses={404: {"model": ErrorResponse}},
)
@limiter.limit(settings.AUTH_RATE_LIMIT)
async def request_otp(request: Request, body: OtpRequest, db: AsyncSession = Depends(get_db)):
    """Generate and (stub) send OTP to patient's phone."""
    from cacms.services.patient_service import get_patient_by_phone

    patient = await get_patient_by_phone(db, body.phone)
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "PATIENT_NOT_FOUND", "message": "No patient with that phone number"},
        )

    otp = await generate_otp(db, patient.phone)
    print(f"[OTP STUB] Phone: {patient.phone}  OTP: {otp}")
    return {"message": "OTP sent"}
