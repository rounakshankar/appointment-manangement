from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin_or_receptionist
from cacms.schemas.common import ErrorResponse
from cacms.schemas.payment import PaymentCreate, PaymentOut
from cacms.services.payment_service import create_payment

router = APIRouter(prefix="/payments", tags=["payments"])


@router.post(
    "",
    response_model=PaymentOut,
    status_code=status.HTTP_201_CREATED,
    responses={
        404: {"model": ErrorResponse},
    },
)
async def create_payment_endpoint(
    body: PaymentCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_receptionist),
):
    """
    Record a payment for a consultation.

    - Validates consultation_id exists; returns 404 PAYMENT_CONSULTATION_NOT_FOUND if not.
    - Creates Payment record with status=pending by default.
    - Accepts payment_mode: cash | upi | card.
    - Accepts status: pending | paid | partial.

    Requirements: 7.1–7.4
    """
    try:
        payment = await create_payment(db, body, user.clinic_id)
    except ValueError as exc:
        error_code = str(exc)
        if error_code == "PAYMENT_CONSULTATION_NOT_FOUND":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error_code": error_code, "message": "Consultation not found."},
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error_code": error_code, "message": error_code},
        )

    return payment
