from datetime import date
from decimal import Decimal

from pydantic import BaseModel


class DailyReport(BaseModel):
    report_date: date
    total_appointments: int
    scheduled: int
    in_progress: int
    completed_visits: int
    cancelled: int
    no_show: int
    total_collection: Decimal
    paid_collection: Decimal
    pending_collection: Decimal
    partial_collection: Decimal
