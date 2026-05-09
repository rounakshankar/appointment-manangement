from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_owner_or_admin_or_receptionist
from cacms.schemas.common import ErrorResponse
from cacms.schemas.patient import PatientCreate, PatientOut
from cacms.services.patient_service import create_patient, get_patient_by_phone

router = APIRouter(prefix="/patients", tags=["patients"])


@router.post(
    "",
    response_model=PatientOut,
    status_code=status.HTTP_201_CREATED,
    responses={409: {"model": ErrorResponse}},
)
async def register_patient(
    body: PatientCreate,
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_receptionist),
):
    """Create a new patient. Returns 409 if phone already exists."""
    try:
        patient = await create_patient(db, body, user.clinic_id)
    except IntegrityError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error_code": "PATIENT_CONFLICT", "message": "A patient with this phone number already exists"},
        )
    return patient


@router.get(
    "",
    response_model=PatientOut,
    responses={404: {"model": ErrorResponse}},
)
async def lookup_patient(
    phone: str = Query(..., description="Patient phone number to look up"),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_owner_or_admin_or_receptionist),
):
    """Lookup a patient by phone number. Phone is passed as a query parameter, never in the URL path."""
    patient = await get_patient_by_phone(db, phone, user.clinic_id)
    if not patient:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "PATIENT_NOT_FOUND", "message": "No patient found with that phone number"},
        )
    return patient
