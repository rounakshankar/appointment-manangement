"""
SSE endpoints for real-time event streaming.

GET /v1/events/doctor/{doctor_id}  — Admin or Doctor role
GET /v1/events/patient/{patient_id} — Patient role (OTP-issued JWT)
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.database import get_db
from cacms.middleware.auth_middleware import UserContext, get_current_user
from cacms.models.doctor import Doctor
from cacms.models.patient import Patient
from cacms.models.sse_event import SseEvent
from cacms.services.sse_bus import sse_bus

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/events", tags=["events"])

_KEEP_ALIVE_INTERVAL = 15  # seconds


def _format_sse(sequence: int, event_type: str, payload: dict) -> str:
    """Format a single SSE message."""
    data = json.dumps(payload)
    return f"id: {sequence}\nevent: {event_type}\ndata: {data}\n\n"


async def _replay_events(
    db: AsyncSession,
    channel: str,
    last_event_id: Optional[str],
) -> AsyncGenerator[str, None]:
    """Yield SSE-formatted strings for all stored events after last_event_id."""
    if last_event_id is None:
        return

    try:
        last_seq = int(last_event_id)
    except (ValueError, TypeError):
        return

    result = await db.execute(
        select(SseEvent)
        .where(SseEvent.channel == channel)
        .where(SseEvent.sequence > last_seq)
        .order_by(SseEvent.sequence.asc())
    )
    rows = result.scalars().all()
    for row in rows:
        yield _format_sse(row.sequence, row.event_type, row.payload)


async def event_generator(
    db: AsyncSession,
    channel: str,
    last_event_id: Optional[str],
) -> AsyncGenerator[str, None]:
    """
    Async generator that:
    1. Replays stored events (if Last-Event-ID provided)
    2. Streams live events from the SSE bus
    3. Sends keep-alive comments every 15 seconds
    """
    # Phase 1: replay missed events from DB
    async for chunk in _replay_events(db, channel, last_event_id):
        yield chunk

    # Phase 2: live events + keep-alive
    # Use a shared queue so both the live subscriber and a keep-alive timer
    # can push items; None sentinel = keep-alive ping.
    merged: asyncio.Queue = asyncio.Queue(maxsize=512)

    async def _forward_live() -> None:
        try:
            async for event in sse_bus.subscribe(channel):
                await merged.put(event)
        except asyncio.CancelledError:
            pass
        finally:
            await merged.put(StopAsyncIteration())  # signal end

    async def _keep_alive_loop() -> None:
        try:
            while True:
                await asyncio.sleep(_KEEP_ALIVE_INTERVAL)
                await merged.put(None)
        except asyncio.CancelledError:
            pass

    forward_task = asyncio.create_task(_forward_live())
    keep_alive_task = asyncio.create_task(_keep_alive_loop())

    try:
        while True:
            item = await merged.get()
            if isinstance(item, StopAsyncIteration):
                break
            if item is None:
                # Keep-alive comment
                yield ": keep-alive\n\n"
            else:
                seq_val = getattr(item, "sequence", None) or item.event_id
                yield _format_sse(seq_val, item.event_type, item.data)
    except (asyncio.CancelledError, GeneratorExit):
        logger.debug("SSE generator for channel %s closing", channel)
    finally:
        forward_task.cancel()
        keep_alive_task.cancel()


def _sse_response(generator: AsyncGenerator[str, None]) -> StreamingResponse:
    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/doctor/{doctor_id}")
async def doctor_sse(
    doctor_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserContext = Depends(get_current_user),
):
    """
    SSE stream for a doctor channel.
    Requires Admin or Doctor role. Doctors may only subscribe to their own channel.
    """
    if current_user.role not in ("admin", "doctor"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Insufficient permissions"},
        )
    if current_user.role == "doctor" and current_user.doctor_id != doctor_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot subscribe to another doctor's channel"},
        )
    result = await db.execute(
        select(Doctor).where(Doctor.doctor_id == doctor_id, Doctor.clinic_id == current_user.clinic_id)
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "DOCTOR_NOT_FOUND", "message": "Doctor not found"},
        )

    channel = f"doctor:{doctor_id}"
    last_event_id: Optional[str] = request.headers.get("Last-Event-ID")

    return _sse_response(event_generator(db, channel, last_event_id))


@router.get("/patient/{patient_id}")
async def patient_sse(
    patient_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: UserContext = Depends(get_current_user),
):
    """
    SSE stream for a patient channel.
    Requires Patient role. Patients may only subscribe to their own channel.
    """
    if current_user.role != "patient":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Insufficient permissions"},
        )
    if current_user.patient_id != patient_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error_code": "FORBIDDEN", "message": "Cannot subscribe to another patient's channel"},
        )
    result = await db.execute(
        select(Patient).where(Patient.patient_id == patient_id, Patient.clinic_id == current_user.clinic_id)
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "PATIENT_NOT_FOUND", "message": "Patient not found"},
        )

    channel = f"patient:{patient_id}"
    last_event_id: Optional[str] = request.headers.get("Last-Event-ID")

    return _sse_response(event_generator(db, channel, last_event_id))
