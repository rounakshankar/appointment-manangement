"""
Integration test: core queue flow (HTTP API layer)

End-to-end test covering:
  1. Register a patient via POST /v1/patients
  2. Create multiple appointments (normal + emergency) via POST /v1/appointments
  3. Verify queue ordering (emergency gets queue_number=1)
  4. Call Next via PATCH /v1/appointments/{id}/clinical — verify status transitions
  5. Verify at-most-one in-progress invariant after each Call Next
  6. Verify dashboard counts (total, completed, remaining) update correctly
  7. Verify queue is empty after all appointments are processed

Uses httpx.AsyncClient with ASGITransport — no running server required,
but a real PostgreSQL database IS required.

Requirements: 2.1–2.7, 3.1–3.4, 4.1–4.5
"""

import uuid
from datetime import date

import pytest
import httpx
from httpx import AsyncClient, ASGITransport

from cacms.main import app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


async def test_register_patient_via_api(http_client: AsyncClient, admin_token: str):
    """POST /v1/patients creates a patient and returns 201 with a UUID."""
    phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
    resp = await http_client.post(
        "/v1/patients",
        json={"name": "API Patient", "phone": phone, "consent_given": True},
        headers=_auth(admin_token),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert "patient_id" in body
    assert body["phone"] == phone
    assert body["consent_given"] is True


async def test_create_appointment_returns_scheduled_with_queue_number(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """POST /v1/appointments returns status=scheduled and a positive queue_number."""
    resp = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "normal",
        },
        headers=_auth(admin_token),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "scheduled"
    assert body["queue_number"] >= 1
    assert body["visit_type"] == "normal"


async def test_emergency_appointment_gets_queue_number_one(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    Emergency appointment must receive queue_number=1, shifting existing
    scheduled appointments up.

    Requirements: 2.3
    """
    # Create 2 normal patients first
    patient_ids = []
    for i in range(2):
        phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
        pr = await http_client.post(
            "/v1/patients",
            json={"name": f"Normal Patient {i}", "phone": phone, "consent_given": True},
            headers=_auth(admin_token),
        )
        assert pr.status_code == 201
        patient_ids.append(pr.json()["patient_id"])

    # Book 2 normal appointments
    normal_appts = []
    for pid in patient_ids:
        ar = await http_client.post(
            "/v1/appointments",
            json={
                "patient_id": pid,
                "doctor_id": seeded_doctor["doctor_id"],
                "scheduled_date": test_date,
                "visit_type": "normal",
            },
            headers=_auth(admin_token),
        )
        assert ar.status_code == 201
        normal_appts.append(ar.json())

    # Normal appointments should have queue_numbers 1 and 2
    normal_qns = sorted(a["queue_number"] for a in normal_appts)
    assert normal_qns == [1, 2], f"Expected [1, 2], got {normal_qns}"

    # Now book an emergency appointment
    emerg_phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
    ep = await http_client.post(
        "/v1/patients",
        json={"name": "Emergency Patient", "phone": emerg_phone, "consent_given": True},
        headers=_auth(admin_token),
    )
    assert ep.status_code == 201
    emerg_pid = ep.json()["patient_id"]

    er = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": emerg_pid,
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "emergency",
        },
        headers=_auth(admin_token),
    )
    assert er.status_code == 201, er.text
    emerg_appt = er.json()
    assert emerg_appt["queue_number"] == 1, (
        f"Emergency appointment must get queue_number=1, got {emerg_appt['queue_number']}"
    )


async def test_call_next_transitions_status_to_in_progress(
    http_client: AsyncClient,
    admin_token: str,
    doctor_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """
    PATCH /v1/appointments/{id}/clinical must mark the first scheduled
    appointment as in-progress.

    Requirements: 4.1, 4.2
    """
    # Create one appointment
    ar = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "normal",
        },
        headers=_auth(admin_token),
    )
    assert ar.status_code == 201
    appt_id = ar.json()["appointment_id"]

    # Call Next using the appointment_id as context
    cn = await http_client.patch(
        f"/v1/appointments/{appt_id}/clinical",
        headers=_auth(doctor_token),
    )
    assert cn.status_code == 200, cn.text
    result = cn.json()
    assert result["queue_empty"] is False
    assert result["conflict"] is False
    assert result["next_appointment_id"] == appt_id

    # Verify the appointment is now in-progress
    get_resp = await http_client.get(
        f"/v1/appointments/{appt_id}",
        headers=_auth(doctor_token),
    )
    assert get_resp.status_code == 200
    assert get_resp.json()["status"] == "in-progress"


async def test_at_most_one_in_progress_invariant(
    http_client: AsyncClient,
    admin_token: str,
    doctor_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    After each Call Next, the dashboard must show at most one in-progress
    appointment.

    Requirements: 4.2, 14.4
    """
    N = 4
    appt_ids = []
    for i in range(N):
        phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
        pr = await http_client.post(
            "/v1/patients",
            json={"name": f"Invariant Patient {i}", "phone": phone, "consent_given": True},
            headers=_auth(admin_token),
        )
        assert pr.status_code == 201
        pid = pr.json()["patient_id"]

        ar = await http_client.post(
            "/v1/appointments",
            json={
                "patient_id": pid,
                "doctor_id": seeded_doctor["doctor_id"],
                "scheduled_date": test_date,
                "visit_type": "normal",
            },
            headers=_auth(admin_token),
        )
        assert ar.status_code == 201
        appt_ids.append(ar.json()["appointment_id"])

    # Use the first appointment as the context for all Call Next calls
    context_id = appt_ids[0]

    for step in range(N):
        cn = await http_client.patch(
            f"/v1/appointments/{context_id}/clinical",
            headers=_auth(doctor_token),
        )
        assert cn.status_code == 200, f"Step {step}: {cn.text}"

        # Check dashboard: in-progress count must be ≤ 1
        dash = await http_client.get(
            "/v1/appointments/today",
            params={"doctor_id": seeded_doctor["doctor_id"], "date": test_date},
            headers=_auth(doctor_token),
        )
        assert dash.status_code == 200
        queue = dash.json()["queue"]
        in_progress = [a for a in queue if a["status"] == "in-progress"]
        assert len(in_progress) <= 1, (
            f"Step {step}: at-most-one invariant violated — "
            f"{len(in_progress)} in-progress appointments"
        )


async def test_dashboard_counts_update_correctly(
    http_client: AsyncClient,
    admin_token: str,
    doctor_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    Dashboard total/completed/remaining counts must reflect the current
    queue state after each Call Next.

    Requirements: 3.1, 3.2, 3.3
    """
    N = 3
    appt_ids = []
    for i in range(N):
        phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
        pr = await http_client.post(
            "/v1/patients",
            json={"name": f"Dashboard Patient {i}", "phone": phone, "consent_given": True},
            headers=_auth(admin_token),
        )
        assert pr.status_code == 201
        pid = pr.json()["patient_id"]

        ar = await http_client.post(
            "/v1/appointments",
            json={
                "patient_id": pid,
                "doctor_id": seeded_doctor["doctor_id"],
                "scheduled_date": test_date,
                "visit_type": "normal",
            },
            headers=_auth(admin_token),
        )
        assert ar.status_code == 201
        appt_ids.append(ar.json()["appointment_id"])

    # Initial dashboard: total=N, completed=0, remaining=N
    dash = await http_client.get(
        "/v1/appointments/today",
        params={"doctor_id": seeded_doctor["doctor_id"], "date": test_date},
        headers=_auth(doctor_token),
    )
    assert dash.status_code == 200
    d = dash.json()
    assert d["total"] == N
    assert d["completed"] == 0
    assert d["remaining"] == N

    context_id = appt_ids[0]

    # Advance through all N appointments
    for step in range(N):
        cn = await http_client.patch(
            f"/v1/appointments/{context_id}/clinical",
            headers=_auth(doctor_token),
        )
        assert cn.status_code == 200, f"Step {step}: {cn.text}"

        dash = await http_client.get(
            "/v1/appointments/today",
            params={"doctor_id": seeded_doctor["doctor_id"], "date": test_date},
            headers=_auth(doctor_token),
        )
        assert dash.status_code == 200
        d = dash.json()
        assert d["total"] == N
        # After step+1 Call Nexts, step appointments are completed
        # (the last Call Next completes the final in-progress, leaving 0 remaining)
        assert d["completed"] == step, (
            f"Step {step}: expected completed={step}, got {d['completed']}"
        )
        assert d["remaining"] == N - step - 1, (
            f"Step {step}: expected remaining={N - step - 1}, got {d['remaining']}"
        )

    # Final Call Next drains the last in-progress → queue empty
    cn = await http_client.patch(
        f"/v1/appointments/{context_id}/clinical",
        headers=_auth(doctor_token),
    )
    assert cn.status_code == 200
    assert cn.json()["queue_empty"] is True

    # Final dashboard: total=N, completed=N, remaining=0
    dash = await http_client.get(
        "/v1/appointments/today",
        params={"doctor_id": seeded_doctor["doctor_id"], "date": test_date},
        headers=_auth(doctor_token),
    )
    assert dash.status_code == 200
    d = dash.json()
    assert d["total"] == N
    assert d["completed"] == N
    assert d["remaining"] == 0


async def test_queue_empty_after_all_appointments_processed(
    http_client: AsyncClient,
    admin_token: str,
    doctor_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    After all appointments are processed, Call Next must return queue_empty=True
    and the dashboard must show remaining=0.

    Requirements: 4.3, 4.5
    """
    N = 2
    appt_ids = []
    for i in range(N):
        phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
        pr = await http_client.post(
            "/v1/patients",
            json={"name": f"Empty Queue Patient {i}", "phone": phone, "consent_given": True},
            headers=_auth(admin_token),
        )
        assert pr.status_code == 201
        pid = pr.json()["patient_id"]

        ar = await http_client.post(
            "/v1/appointments",
            json={
                "patient_id": pid,
                "doctor_id": seeded_doctor["doctor_id"],
                "scheduled_date": test_date,
                "visit_type": "normal",
            },
            headers=_auth(admin_token),
        )
        assert ar.status_code == 201
        appt_ids.append(ar.json()["appointment_id"])

    context_id = appt_ids[0]

    # Advance N times to put all through in-progress
    for _ in range(N):
        cn = await http_client.patch(
            f"/v1/appointments/{context_id}/clinical",
            headers=_auth(doctor_token),
        )
        assert cn.status_code == 200

    # One final Call Next should drain the last in-progress and return queue_empty
    cn = await http_client.patch(
        f"/v1/appointments/{context_id}/clinical",
        headers=_auth(doctor_token),
    )
    assert cn.status_code == 200
    result = cn.json()
    assert result["queue_empty"] is True
    assert result["next_appointment_id"] is None

    # Dashboard confirms remaining=0
    dash = await http_client.get(
        "/v1/appointments/today",
        params={"doctor_id": seeded_doctor["doctor_id"], "date": test_date},
        headers=_auth(doctor_token),
    )
    assert dash.status_code == 200
    assert dash.json()["remaining"] == 0


async def test_full_end_to_end_queue_flow(
    http_client: AsyncClient,
    admin_token: str,
    doctor_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    Full end-to-end integration test:
      1. Register patients via POST /v1/patients
      2. Create normal + emergency appointments via POST /v1/appointments
      3. Verify emergency gets queue_number=1
      4. Call Next through all appointments via PATCH /v1/appointments/{id}/clinical
      5. Verify at-most-one in-progress invariant at each step
      6. Verify dashboard counts update correctly
      7. Verify queue is empty after all appointments are processed

    Requirements: 2.1–2.7, 3.1–3.4, 4.1–4.5
    """
    doctor_id = seeded_doctor["doctor_id"]

    # --- Step 1: Register 3 patients ---
    patient_ids = []
    for i in range(3):
        phone = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
        pr = await http_client.post(
            "/v1/patients",
            json={"name": f"E2E Patient {i}", "phone": phone, "consent_given": True},
            headers=_auth(admin_token),
        )
        assert pr.status_code == 201, pr.text
        patient_ids.append(pr.json()["patient_id"])

    # --- Step 2: Create 2 normal appointments ---
    appt_ids = []
    for pid in patient_ids[:2]:
        ar = await http_client.post(
            "/v1/appointments",
            json={
                "patient_id": pid,
                "doctor_id": doctor_id,
                "scheduled_date": test_date,
                "visit_type": "normal",
            },
            headers=_auth(admin_token),
        )
        assert ar.status_code == 201, ar.text
        appt_ids.append(ar.json()["appointment_id"])

    # --- Step 3: Create 1 emergency appointment ---
    er = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": patient_ids[2],
            "doctor_id": doctor_id,
            "scheduled_date": test_date,
            "visit_type": "emergency",
        },
        headers=_auth(admin_token),
    )
    assert er.status_code == 201, er.text
    emerg_appt = er.json()
    emerg_appt_id = emerg_appt["appointment_id"]

    # Emergency must have queue_number=1
    assert emerg_appt["queue_number"] == 1, (
        f"Emergency must get queue_number=1, got {emerg_appt['queue_number']}"
    )

    # --- Step 4: Verify initial dashboard ---
    dash = await http_client.get(
        "/v1/appointments/today",
        params={"doctor_id": doctor_id, "date": test_date},
        headers=_auth(doctor_token),
    )
    assert dash.status_code == 200
    d = dash.json()
    assert d["total"] == 3
    assert d["completed"] == 0
    assert d["remaining"] == 3

    # Queue must be ordered by queue_number ASC; emergency is first
    queue = d["queue"]
    assert queue[0]["appointment_id"] == emerg_appt_id, (
        "Emergency appointment must appear first in the queue"
    )

    # --- Step 5: Call Next through all 3 appointments ---
    # Use the emergency appointment as the context for all Call Next calls
    context_id = emerg_appt_id

    total_appts = 3
    for step in range(total_appts):
        cn = await http_client.patch(
            f"/v1/appointments/{context_id}/clinical",
            headers=_auth(doctor_token),
        )
        assert cn.status_code == 200, f"Step {step}: {cn.text}"
        result = cn.json()
        assert result["conflict"] is False
        assert result["queue_empty"] is False

        # At-most-one in-progress invariant
        dash = await http_client.get(
            "/v1/appointments/today",
            params={"doctor_id": doctor_id, "date": test_date},
            headers=_auth(doctor_token),
        )
        assert dash.status_code == 200
        queue = dash.json()["queue"]
        in_progress = [a for a in queue if a["status"] == "in-progress"]
        assert len(in_progress) <= 1, (
            f"Step {step}: at-most-one invariant violated — "
            f"{len(in_progress)} in-progress appointments"
        )

    # --- Step 6: Final Call Next drains the last in-progress ---
    cn = await http_client.patch(
        f"/v1/appointments/{context_id}/clinical",
        headers=_auth(doctor_token),
    )
    assert cn.status_code == 200, cn.text
    assert cn.json()["queue_empty"] is True

    # --- Step 7: Final dashboard — queue is empty ---
    dash = await http_client.get(
        "/v1/appointments/today",
        params={"doctor_id": doctor_id, "date": test_date},
        headers=_auth(doctor_token),
    )
    assert dash.status_code == 200
    d = dash.json()
    assert d["total"] == 3
    assert d["completed"] == 3
    assert d["remaining"] == 0
