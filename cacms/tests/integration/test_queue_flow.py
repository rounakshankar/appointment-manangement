"""
Integration test: core queue flow

Covers the end-to-end flow:
  appointment creation → Call Next → queue state transitions

Tests run against a real PostgreSQL instance (cacms_test database).

Validates:
  - Creating an appointment sets status=scheduled and assigns a queue_number
  - Calling call_next marks the in-progress appointment as completed and the
    next scheduled appointment as in-progress
  - Queue state transitions are consistent (at most one in-progress at a time)

Requirements: 2.1, 2.2, 4.1, 4.2, 4.3
"""

import uuid
from datetime import date

import pytest
import pytest_asyncio
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from cacms.models.appointment import Appointment, AppointmentStatus, VisitType
from cacms.models.doctor import Doctor
from cacms.models.patient import Patient
from cacms.schemas.appointment import AppointmentCreate, CallNextResult
from cacms.services.appointment_service import create_appointment
from cacms.services.queue_manager import assign_queue_number, call_next


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

async def _count_in_progress(db: AsyncSession, doctor_id: uuid.UUID, d: date) -> int:
    result = await db.execute(
        select(func.count()).where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == d,
            Appointment.status == AppointmentStatus.in_progress,
        )
    )
    return result.scalar_one()


async def _count_scheduled(db: AsyncSession, doctor_id: uuid.UUID, d: date) -> int:
    result = await db.execute(
        select(func.count()).where(
            Appointment.doctor_id == doctor_id,
            Appointment.scheduled_date == d,
            Appointment.status == AppointmentStatus.scheduled,
        )
    )
    return result.scalar_one()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_create_appointment_sets_scheduled_status_and_queue_number(
    db: AsyncSession, doctor: Doctor, patient: Patient, today: date
):
    """
    Creating an appointment via create_appointment() must:
    - Set status = scheduled
    - Assign queue_number = 1 (first appointment for this doctor/date)
    """
    data = AppointmentCreate(
        patient_id=patient.patient_id,
        doctor_id=doctor.doctor_id,
        scheduled_date=today,
        visit_type="normal",
    )
    appt = await create_appointment(db, data)

    assert appt.status == AppointmentStatus.scheduled, (
        f"Expected status=scheduled, got {appt.status}"
    )
    assert appt.queue_number == 1, (
        f"Expected queue_number=1 for first appointment, got {appt.queue_number}"
    )
    assert appt.patient_id == patient.patient_id
    assert appt.doctor_id == doctor.doctor_id
    assert appt.scheduled_date == today


@pytest.mark.asyncio
async def test_sequential_queue_numbers_assigned(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    Creating N appointments for the same doctor/date must assign
    queue_numbers 1, 2, ..., N in order.
    """
    # Create 3 patients inline
    patients = []
    for i in range(3):
        pat = Patient(
            patient_id=uuid.uuid4(),
            name=f"Patient {i}",
            phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
            consent_given=True,
        )
        db.add(pat)
        patients.append(pat)
    await db.flush()

    queue_numbers = []
    for pat in patients:
        data = AppointmentCreate(
            patient_id=pat.patient_id,
            doctor_id=doctor.doctor_id,
            scheduled_date=today,
            visit_type="normal",
        )
        appt = await create_appointment(db, data)
        queue_numbers.append(appt.queue_number)

    assert sorted(queue_numbers) == list(range(1, 4)), (
        f"Expected queue numbers {{1,2,3}}, got {queue_numbers}"
    )


@pytest.mark.asyncio
async def test_call_next_advances_queue(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    call_next() must:
    - Mark the first scheduled appointment as in-progress
    - Return next_appointment_id pointing to that appointment
    - queue_empty=False when there are scheduled appointments
    """
    # Seed one patient and appointment
    pat = Patient(
        patient_id=uuid.uuid4(),
        name="Queue Patient",
        phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
        consent_given=True,
    )
    db.add(pat)
    await db.flush()

    data = AppointmentCreate(
        patient_id=pat.patient_id,
        doctor_id=doctor.doctor_id,
        scheduled_date=today,
        visit_type="normal",
    )
    appt = await create_appointment(db, data)
    assert appt.status == AppointmentStatus.scheduled

    # Call Next — no in-progress appointment exists yet
    result: CallNextResult = await call_next(db, doctor.doctor_id, today)

    assert not result.queue_empty, "Queue should not be empty after calling next"
    assert not result.conflict, "Should not be a conflict"
    assert result.next_appointment_id == appt.appointment_id

    # Commit so the status change is visible, then verify DB state
    await db.commit()
    await db.refresh(appt)
    assert appt.status == AppointmentStatus.in_progress, (
        f"Expected in-progress, got {appt.status}"
    )


@pytest.mark.asyncio
async def test_call_next_completes_in_progress_and_advances(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    When an in-progress appointment exists, call_next() must:
    - Mark the in-progress appointment as completed
    - Mark the next scheduled appointment as in-progress
    - Return both completed_appointment_id and next_appointment_id
    """
    # Create 2 patients and appointments
    patients = []
    for i in range(2):
        pat = Patient(
            patient_id=uuid.uuid4(),
            name=f"Patient {i}",
            phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
            consent_given=True,
        )
        db.add(pat)
        patients.append(pat)
    await db.flush()

    appts = []
    for pat in patients:
        data = AppointmentCreate(
            patient_id=pat.patient_id,
            doctor_id=doctor.doctor_id,
            scheduled_date=today,
            visit_type="normal",
        )
        appt = await create_appointment(db, data)
        appts.append(appt)

    # First call_next: no in-progress → appts[0] becomes in-progress
    result1 = await call_next(db, doctor.doctor_id, today)
    assert result1.next_appointment_id == appts[0].appointment_id
    assert not result1.queue_empty

    # Second call_next: appts[0] in-progress → completed; appts[1] → in-progress
    result2 = await call_next(db, doctor.doctor_id, today)
    assert result2.completed_appointment_id == appts[0].appointment_id
    assert result2.next_appointment_id == appts[1].appointment_id
    assert not result2.queue_empty

    # Commit and verify DB state
    await db.commit()
    await db.refresh(appts[0])
    await db.refresh(appts[1])
    assert appts[0].status == AppointmentStatus.completed
    assert appts[1].status == AppointmentStatus.in_progress


@pytest.mark.asyncio
async def test_at_most_one_in_progress_at_a_time(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    Property 3: At-most-one in-progress invariant.

    After any sequence of call_next() operations, the count of in-progress
    appointments for a given (doctor_id, scheduled_date) must never exceed 1.
    """
    N = 5
    patients = []
    for i in range(N):
        pat = Patient(
            patient_id=uuid.uuid4(),
            name=f"Patient {i}",
            phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
            consent_given=True,
        )
        db.add(pat)
        patients.append(pat)
    await db.flush()

    for pat in patients:
        data = AppointmentCreate(
            patient_id=pat.patient_id,
            doctor_id=doctor.doctor_id,
            scheduled_date=today,
            visit_type="normal",
        )
        await create_appointment(db, data)

    # Advance the queue N+1 times (last one will be queue_empty)
    for _ in range(N + 1):
        await call_next(db, doctor.doctor_id, today)
        await db.commit()
        in_progress_count = await _count_in_progress(db, doctor.doctor_id, today)
        assert in_progress_count <= 1, (
            f"Invariant violated: {in_progress_count} in-progress appointments found"
        )


@pytest.mark.asyncio
async def test_call_next_returns_queue_empty_when_no_scheduled(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    When no scheduled appointments remain, call_next() must return
    queue_empty=True with no state changes.
    """
    # No appointments seeded — queue is empty from the start
    result = await call_next(db, doctor.doctor_id, today)
    assert result.queue_empty is True
    assert result.next_appointment_id is None
    assert result.conflict is False


@pytest.mark.asyncio
async def test_call_next_selects_minimum_queue_number(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    Property 4: Call Next selects minimum scheduled queue_number.

    The appointment advanced to in-progress must have the lowest queue_number
    among all scheduled appointments.
    """
    N = 4
    patients = []
    for i in range(N):
        pat = Patient(
            patient_id=uuid.uuid4(),
            name=f"Patient {i}",
            phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
            consent_given=True,
        )
        db.add(pat)
        patients.append(pat)
    await db.flush()

    appts = []
    for pat in patients:
        data = AppointmentCreate(
            patient_id=pat.patient_id,
            doctor_id=doctor.doctor_id,
            scheduled_date=today,
            visit_type="normal",
        )
        appt = await create_appointment(db, data)
        appts.append(appt)

    # Advance through all appointments, verifying each time that the
    # appointment with the minimum scheduled queue_number is selected
    for step in range(N):
        # Find minimum scheduled queue_number before calling next
        result_min = await db.execute(
            select(func.min(Appointment.queue_number)).where(
                Appointment.doctor_id == doctor.doctor_id,
                Appointment.scheduled_date == today,
                Appointment.status == AppointmentStatus.scheduled,
            )
        )
        min_qn = result_min.scalar()

        if min_qn is None:
            break  # No more scheduled appointments

        result = await call_next(db, doctor.doctor_id, today)
        assert not result.queue_empty

        # Commit so the status change is persisted and visible to subsequent queries
        await db.commit()

        # Fetch the newly in-progress appointment
        in_progress_result = await db.execute(
            select(Appointment).where(
                Appointment.doctor_id == doctor.doctor_id,
                Appointment.scheduled_date == today,
                Appointment.status == AppointmentStatus.in_progress,
            )
        )
        in_progress_appt = in_progress_result.scalar_one()
        assert in_progress_appt.queue_number == min_qn, (
            f"Step {step}: expected queue_number={min_qn}, "
            f"got {in_progress_appt.queue_number}"
        )


@pytest.mark.asyncio
async def test_full_queue_flow_end_to_end(
    db: AsyncSession, doctor: Doctor, today: date
):
    """
    End-to-end integration test:
    appointment creation → Call Next × N → all completed

    Verifies the complete lifecycle of a queue for a doctor on a given day.
    """
    N = 3
    patients = []
    for i in range(N):
        pat = Patient(
            patient_id=uuid.uuid4(),
            name=f"E2E Patient {i}",
            phone=f"+91{uuid.uuid4().int % 10_000_000_000:010d}",
            consent_given=True,
        )
        db.add(pat)
        patients.append(pat)
    await db.flush()

    # Step 1: Create N appointments
    appts = []
    for pat in patients:
        data = AppointmentCreate(
            patient_id=pat.patient_id,
            doctor_id=doctor.doctor_id,
            scheduled_date=today,
            visit_type="normal",
        )
        appt = await create_appointment(db, data)
        assert appt.status == AppointmentStatus.scheduled
        assert appt.queue_number > 0
        appts.append(appt)

    # All queue numbers must be unique and form {1..N}
    queue_numbers = {a.queue_number for a in appts}
    assert queue_numbers == set(range(1, N + 1)), (
        f"Expected queue numbers {{1..{N}}}, got {queue_numbers}"
    )

    # Step 2: Advance queue N times
    for i in range(N):
        result = await call_next(db, doctor.doctor_id, today)
        assert not result.conflict
        assert not result.queue_empty
        await db.commit()

        in_progress_count = await _count_in_progress(db, doctor.doctor_id, today)
        assert in_progress_count == 1, (
            f"After call_next #{i+1}: expected 1 in-progress, got {in_progress_count}"
        )

    # Step 3: One more call_next drains the last in-progress → queue empty
    final_result = await call_next(db, doctor.doctor_id, today)
    await db.commit()
    assert final_result.queue_empty is True
    assert final_result.next_appointment_id is None

    # All appointments should now be completed
    result = await db.execute(
        select(func.count()).where(
            Appointment.doctor_id == doctor.doctor_id,
            Appointment.scheduled_date == today,
            Appointment.status == AppointmentStatus.completed,
        )
    )
    completed_count = result.scalar_one()
    assert completed_count == N, (
        f"Expected {N} completed appointments, got {completed_count}"
    )

    # No in-progress appointments remain
    in_progress_count = await _count_in_progress(db, doctor.doctor_id, today)
    assert in_progress_count == 0
