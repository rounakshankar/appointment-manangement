from datetime import date as date_type
from decimal import Decimal

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, require_owner_or_admin
from cacms.models.appointment import Appointment, AppointmentStatus
from cacms.models.consultation import Consultation
from cacms.models.payment import Payment, PaymentStatus
from cacms.schemas.report import DailyReport

router = APIRouter(prefix="/reports", tags=["reports"])


async def _count_status(
    db: AsyncSession,
    clinic_id,
    report_date: date_type,
    status: AppointmentStatus | None = None,
) -> int:
    stmt = select(func.count()).where(
        Appointment.clinic_id == clinic_id,
        Appointment.scheduled_date == report_date,
    )
    if status is not None:
        stmt = stmt.where(Appointment.status == status)
    result = await db.execute(stmt)
    return int(result.scalar_one() or 0)


async def _sum_collection(
    db: AsyncSession,
    clinic_id,
    report_date: date_type,
    status: PaymentStatus | None = None,
) -> Decimal:
    stmt = (
        select(func.coalesce(func.sum(Payment.total_amount), 0))
        .join(Consultation, Consultation.consultation_id == Payment.consultation_id)
        .join(Appointment, Appointment.appointment_id == Consultation.appointment_id)
        .where(
            Payment.clinic_id == clinic_id,
            Appointment.scheduled_date == report_date,
        )
    )
    if status is not None:
        stmt = stmt.where(Payment.status == status)
    result = await db.execute(stmt)
    return result.scalar_one() or Decimal("0.00")


@router.get("/daily", response_model=DailyReport)
async def daily_report(
    request: Request,
    report_date: date_type | None = Query(None),
    db: AsyncSession = Depends(get_db),
    user: UserContext = Depends(require_owner_or_admin),
):
    report_date = report_date or date_type.today()
    result = DailyReport(
        report_date=report_date,
        total_appointments=await _count_status(db, user.clinic_id, report_date),
        scheduled=await _count_status(db, user.clinic_id, report_date, AppointmentStatus.scheduled),
        in_progress=await _count_status(db, user.clinic_id, report_date, AppointmentStatus.in_progress),
        completed_visits=await _count_status(db, user.clinic_id, report_date, AppointmentStatus.completed),
        cancelled=await _count_status(db, user.clinic_id, report_date, AppointmentStatus.cancelled),
        no_show=await _count_status(db, user.clinic_id, report_date, AppointmentStatus.no_show),
        total_collection=await _sum_collection(db, user.clinic_id, report_date),
        paid_collection=await _sum_collection(db, user.clinic_id, report_date, PaymentStatus.paid),
        pending_collection=await _sum_collection(db, user.clinic_id, report_date, PaymentStatus.pending),
        partial_collection=await _sum_collection(db, user.clinic_id, report_date, PaymentStatus.partial),
    )

    # Fire-and-forget metering — non-fatal if metering is unavailable
    metering = getattr(request.app.state, "metering", None)
    if metering is not None:
        try:
            await metering.record(db, user.clinic_id, "report_export")
        except Exception:
            pass  # metering must never block the primary request path

    return result
