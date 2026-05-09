from cacms.schemas.patient import PatientCreate, PatientOut
from cacms.schemas.appointment import (
    AppointmentCreate,
    AppointmentOut,
    AppointmentStatusUpdate,
    AppointmentScheduleUpdate,
    CallNextResult,
    QueueDashboard,
)
from cacms.schemas.consultation import (
    ConsultationCreate,
    ConsultationServiceItem,
    ConsultationServiceOut,
    ConsultationOut,
    FollowUpPrompt,
)
from cacms.schemas.service import ServiceOut
from cacms.schemas.payment import PaymentCreate, PaymentOut
from cacms.schemas.auth import LoginRequest, TokenResponse, OtpRequest, OtpVerifyRequest
from cacms.schemas.patient_status import PatientStatusResponse, LastVisitSummary
from cacms.schemas.common import ErrorResponse, SSEEvent

__all__ = [
    "PatientCreate", "PatientOut",
    "AppointmentCreate", "AppointmentOut", "AppointmentStatusUpdate",
    "AppointmentScheduleUpdate", "CallNextResult", "QueueDashboard",
    "ConsultationCreate", "ConsultationServiceItem", "ConsultationServiceOut",
    "ConsultationOut", "FollowUpPrompt",
    "ServiceOut",
    "PaymentCreate", "PaymentOut",
    "LoginRequest", "TokenResponse", "OtpRequest", "OtpVerifyRequest",
    "PatientStatusResponse", "LastVisitSummary",
    "ErrorResponse", "SSEEvent",
]
