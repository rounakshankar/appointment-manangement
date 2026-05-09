"""
Patient Status Router

POST /v1/patient/appointment-status — Patient role only.
Returns the current appointment state for the authenticated patient.

Requirements: 8.1
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import require_patient
from cacms.schemas.common import ErrorResponse
from cacms.schemas.patient_status import PatientStatusResponse
from cacms.services.patient_status_service import get_patient_status

router = APIRouter(prefix="/patient", tags=["patient-status"])


@router.post(
    "/appointment-status",
    response_model=PatientStatusResponse,
    responses={
        401: {"model": ErrorResponse},
        403: {"model": ErrorResponse},
    },
)
async def appointment_status(
    db: AsyncSession = Depends(get_db),
    user=Depends(require_patient),
):
    """
    Return the current appointment status for the authenticated patient.

    States (req 8.1):
    - `no_appointment`: no appointment today → last visit summary
    - `scheduled`: appointment is queued → queue_number and patients_ahead
    - `in_progress`: currently being seen → queue_number
    - `completed`: consultation done → diagnosis, services, next_visit_date

    Requires Patient-role JWT (issued via OTP auth flow).
    The patient_id is derived from the JWT `sub` claim.
    """
    return await get_patient_status(db, user.patient_id, user.clinic_id)
