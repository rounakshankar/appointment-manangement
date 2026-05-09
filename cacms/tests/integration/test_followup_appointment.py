"""
Integration tests: follow-up appointment creation (Task 16)

Covers:
  - Confirmed follow-up creates appointment with visit_type=follow-up and queue assignment
  - Duplicate follow-up for same (patient_id, doctor_id, scheduled_date) returns 409 FOLLOWUP_CONFLICT

Requirements: 11.2, 11.3
"""

import uuid
from datetime import date, timedelta

import pytest
from httpx import AsyncClient


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_followup_appointment_created_with_correct_visit_type(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """
    POST /v1/appointments with visit_type=follow-up must create an appointment
    with status=scheduled, a positive queue_number, and visit_type=follow-up.

    Requirements: 11.2
    """
    resp = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "follow-up",
        },
        headers=_auth(admin_token),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["visit_type"] == "follow-up"
    assert body["status"] == "scheduled"
    assert body["queue_number"] >= 1
    assert body["patient_id"] == seeded_patient["patient_id"]
    assert body["doctor_id"] == seeded_doctor["doctor_id"]


async def test_followup_applies_standard_queue_assignment(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    test_date: str,
):
    """
    A follow-up appointment must receive the next sequential queue_number
    after existing appointments (same rules as normal).

    Requirements: 11.2, 2.2
    """
    # Create a normal appointment first
    phone1 = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
    p1 = await http_client.post(
        "/v1/patients",
        json={"name": "Normal Patient", "phone": phone1, "consent_given": True},
        headers=_auth(admin_token),
    )
    assert p1.status_code == 201
    pid1 = p1.json()["patient_id"]

    r1 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": pid1,
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "normal",
        },
        headers=_auth(admin_token),
    )
    assert r1.status_code == 201
    assert r1.json()["queue_number"] == 1

    # Create a follow-up appointment for a different patient on the same date
    phone2 = f"+91{uuid.uuid4().int % 10_000_000_000:010d}"
    p2 = await http_client.post(
        "/v1/patients",
        json={"name": "Follow-up Patient", "phone": phone2, "consent_given": True},
        headers=_auth(admin_token),
    )
    assert p2.status_code == 201
    pid2 = p2.json()["patient_id"]

    r2 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": pid2,
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "follow-up",
        },
        headers=_auth(admin_token),
    )
    assert r2.status_code == 201
    assert r2.json()["queue_number"] == 2
    assert r2.json()["visit_type"] == "follow-up"


async def test_duplicate_followup_returns_409_followup_conflict(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """
    A second follow-up appointment for the same (patient_id, doctor_id, scheduled_date)
    must return 409 with error_code=FOLLOWUP_CONFLICT.

    Requirements: 11.3
    """
    payload = {
        "patient_id": seeded_patient["patient_id"],
        "doctor_id": seeded_doctor["doctor_id"],
        "scheduled_date": test_date,
        "visit_type": "follow-up",
    }

    # First follow-up — should succeed
    r1 = await http_client.post("/v1/appointments", json=payload, headers=_auth(admin_token))
    assert r1.status_code == 201, r1.text

    # Second follow-up — same patient/doctor/date — must conflict
    r2 = await http_client.post("/v1/appointments", json=payload, headers=_auth(admin_token))
    assert r2.status_code == 409, r2.text
    body = r2.json()
    assert body["detail"]["error_code"] == "FOLLOWUP_CONFLICT"


async def test_followup_conflict_does_not_block_different_date(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """
    A follow-up for the same patient/doctor but a different date must succeed.

    Requirements: 11.3 (conflict is scoped to same date)
    """
    other_date = (date.fromisoformat(test_date) + timedelta(days=7)).isoformat()

    r1 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "follow-up",
        },
        headers=_auth(admin_token),
    )
    assert r1.status_code == 201, r1.text

    r2 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": other_date,
            "visit_type": "follow-up",
        },
        headers=_auth(admin_token),
    )
    assert r2.status_code == 201, r2.text
    assert r2.json()["visit_type"] == "follow-up"


async def test_normal_appointment_not_blocked_by_followup_conflict_check(
    http_client: AsyncClient,
    admin_token: str,
    seeded_doctor: dict,
    seeded_patient: dict,
    test_date: str,
):
    """
    The FOLLOWUP_CONFLICT check must only apply to visit_type=follow-up.
    A normal appointment for the same patient/doctor/date must not be blocked.

    Requirements: 11.3
    """
    # Create a follow-up first
    r1 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "follow-up",
        },
        headers=_auth(admin_token),
    )
    assert r1.status_code == 201, r1.text

    # A normal appointment for the same patient/doctor/date must still succeed
    r2 = await http_client.post(
        "/v1/appointments",
        json={
            "patient_id": seeded_patient["patient_id"],
            "doctor_id": seeded_doctor["doctor_id"],
            "scheduled_date": test_date,
            "visit_type": "normal",
        },
        headers=_auth(admin_token),
    )
    assert r2.status_code == 201, r2.text
    assert r2.json()["visit_type"] == "normal"
