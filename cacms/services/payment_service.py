"""
Payment Service

Handles payment creation with consultation validation.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.consultation import Consultation
from cacms.models.payment import Payment
from cacms.schemas.payment import PaymentCreate


async def create_payment(db: AsyncSession, data: PaymentCreate, clinic_id: uuid.UUID) -> Payment:
    """
    Create a new payment record for a consultation.

    Raises:
        ValueError("PAYMENT_CONSULTATION_NOT_FOUND") if consultation does not exist.
    """
    result = await db.execute(
        select(Consultation).where(
            Consultation.consultation_id == data.consultation_id,
            Consultation.clinic_id == clinic_id,
        )
    )
    if result.scalar_one_or_none() is None:
        raise ValueError("PAYMENT_CONSULTATION_NOT_FOUND")

    payment = Payment(
        payment_id=uuid.uuid4(),
        consultation_id=data.consultation_id,
        total_amount=data.total_amount,
        payment_mode=data.payment_mode,
        status=data.status,
        clinic_id=clinic_id,
    )
    db.add(payment)
    await db.commit()
    await db.refresh(payment)
    return payment
