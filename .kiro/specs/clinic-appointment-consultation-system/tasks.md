# Implementation Plan: Clinic Appointment & Consultation Management System (CACMS)

## Overview

Implement the CACMS backend (FastAPI + async SQLAlchemy + PostgreSQL) and Flutter frontend (Admin, Doctor, Patient apps) in sequential, dependency-ordered steps. Each task builds on the previous. Property-based tests use Hypothesis and are placed close to the implementation they validate.

---

## Tasks

- [x] 1. Project scaffolding and environment setup
  - Create the `cacms/` Python package with the directory structure defined in the design: `models/`, `schemas/`, `routers/`, `services/`, `middleware/`, `tests/unit/`, `tests/integration/`, `tests/property/`
  - Create `main.py` (FastAPI app factory with `/v1/` prefix router mount), `config.py` (Pydantic `BaseSettings` reading env vars: `DATABASE_URL`, `JWT_SECRET`, `JWT_ALGORITHM`, `OTP_TTL_SECONDS`), `database.py` (async SQLAlchemy engine, `AsyncSession` factory, `get_db` dependency)
  - Add `pyproject.toml` / `requirements.txt` with: `fastapi`, `uvicorn`, `sqlalchemy[asyncio]`, `asyncpg`, `alembic`, `pydantic[email]`, `python-jose[cryptography]`, `passlib[bcrypt]`, `hypothesis`, `pytest`, `pytest-asyncio`, `httpx`
  - Create `cacms_flutter/` with `pubspec.yaml` declaring dependencies: `flutter_riverpod`, `dio`, `go_router`, `flutter_secure_storage`, `eventsource`
  - _Requirements: 13.1, 14.1_

- [x] 2. PostgreSQL schema and Alembic migrations
  - [x] 2.1 Write the initial Alembic migration with the full DDL from the design: `doctors`, `patients`, `appointments` (with `appointment_status` and `visit_type` enums, UNIQUE constraint on `(doctor_id, scheduled_date, queue_number)`, partial unique index `uq_one_inprogress_per_doctor_date`), `consultations`, `consultation_services` (with generated `total` column), `services`, `payments`, `audit_logs`, `otp_sessions`, `sse_events`
    - Include all indexes: `idx_patients_phone`, `idx_appointments_doctor_date`, `idx_appointments_patient`, `idx_audit_logs_actor`, `idx_audit_logs_resource`, `idx_sse_events_channel_seq`, `idx_otp_sessions_phone`
    - Include all foreign key constraints per Requirement 14.6
    - _Requirements: 14.1–14.7_
  - [ ]* 2.2 Write a migration smoke test that applies and rolls back the migration against a test database, asserting all tables and indexes exist

- [x] 3. SQLAlchemy ORM models
  - [x] 3.1 Implement ORM models in `models/` for all tables: `Patient`, `Doctor`, `Appointment`, `Consultation`, `ConsultationService`, `Service`, `Payment`, `AuditLog`, `OtpSession`, `SseEvent`
    - Use `mapped_column` / `Mapped` typed annotations (SQLAlchemy 2.x style)
    - Declare relationships: `Appointment.patient`, `Appointment.doctor`, `Consultation.appointment`, `Consultation.services`, `Payment.consultation`
    - _Requirements: 14.2–14.6_
  - [ ]* 3.2 Write unit tests asserting model field types, constraints, and relationship declarations load without error

- [x] 4. Pydantic schemas
  - Implement all request/response schemas in `schemas/`: `PatientCreate`, `PatientOut`, `AppointmentCreate`, `AppointmentOut`, `CallNextResult`, `ConsultationCreate`, `ConsultationServiceItem`, `ConsultationOut`, `FollowUpPrompt`, `ServiceOut`, `PaymentCreate`, `PaymentOut`, `PatientStatusResponse`, `SSEEvent`, `ErrorResponse`
  - Ensure `ErrorResponse` contains `error_code: str` and `message: str` per Requirement 13.3
  - _Requirements: 13.3, 5.1, 7.1, 11.1_

- [x] 5. Authentication — JWT (Admin/Doctor)
  - [x] 5.1 Implement `routers/auth.py`: `POST /v1/auth/login` — validate credentials against `doctors` table (hashed password), issue signed JWT with claims `sub` (doctor_id or admin_id), `role` (`admin`|`doctor`), `exp`
    - Implement `services/jwt_service.py` with `create_token(payload)` and `decode_token(token) -> dict` using `python-jose`
    - _Requirements: 10.1, 10.6_
  - [ ]* 5.2 Write unit tests for `create_token` / `decode_token`: valid token round-trip, expired token raises, tampered signature raises

- [x] 6. Authentication — OTP (Patient)
  - [x] 6.1 Implement `services/otp_service.py`: `generate_otp(phone) -> str` (6-digit, stored as bcrypt hash in `otp_sessions` with `expires_at = now() + OTP_TTL_SECONDS`), `verify_otp(phone, otp) -> OtpSession`
    - Implement `POST /v1/auth/verify-otp` in `routers/auth.py`: create OTP session, (stub) send OTP, on verification return a short-lived JWT with `role=patient` and `sub=patient_id`
    - _Requirements: 10.2, 10.6_
  - [ ]* 6.2 Write unit tests for OTP expiry (expired session rejected), already-verified session rejected, correct OTP accepted

- [x] 7. Auth middleware and role-based access control
  - [x] 7.1 Implement `middleware/auth_middleware.py`: FastAPI dependency `get_current_user(token: str) -> UserContext` that decodes JWT, extracts `role` and `sub`, raises `401` if missing/invalid, raises `403` if role insufficient for the requested endpoint
    - Define role permission map covering all endpoints per Requirements 10.3–10.5
    - _Requirements: 10.3–10.7_
  - [ ]* 7.2 Write unit tests for each role/endpoint combination: Admin allowed on all, Doctor restricted to own resources, Patient restricted to own status/summary, missing token → 401, wrong role → 403

- [x] 8. Patient registration and lookup
  - [x] 8.1 Implement `routers/patients.py` and `services/patient_service.py`:
    - `POST /v1/patients` — create patient with UUID PK, `consent_given=true`, `consent_date=now()`; return 409 `PATIENT_CONFLICT` if phone exists
    - `GET /v1/patients?phone=` — lookup by phone using indexed query; return 404 `PATIENT_NOT_FOUND` if not found
    - Phone must NOT appear as a URL path parameter
    - _Requirements: 1.1–1.7_
  - [ ]* 8.2 Write property test for patient phone uniqueness
    - **Property 7: Patient phone uniqueness**
    - **Validates: Requirements 1.4, 1.5**
    - Generate sequences of registration attempts with randomly duplicated phone numbers; assert second registration with same phone returns 409 and only one record exists in DB
  - [ ]* 8.3 Write unit tests: successful registration returns patient with UUID, lookup by existing phone returns record within 500ms (mocked), lookup by unknown phone returns 404

- [x] 9. Queue Manager — atomic queue number assignment
  - [x] 9.1 Implement `services/queue_manager.py`: `assign_queue_number(db, doctor_id, scheduled_date, visit_type) -> int`
    - Acquire `pg_advisory_xact_lock` keyed on `hash((doctor_id, scheduled_date))`
    - For `normal`/`follow-up`: `MAX(queue_number) + 1` for that `(doctor_id, scheduled_date)`
    - For `emergency`: shift all existing `scheduled` appointments' queue numbers up by 1 (UPDATE), assign queue_number = 1 (or the current minimum − 1 if gaps exist)
    - All within a single transaction; rely on UNIQUE constraint `uq_appointments_queue` as final guard
    - _Requirements: 2.2, 2.3, 2.4, 2.6, 14.3_
  - [ ]* 9.2 Write property test for queue number uniqueness and sequential assignment
    - **Property 1: Queue number uniqueness and sequential assignment**
    - **Validates: Requirements 2.2, 2.4, 2.6, 14.3**
    - Generate N concurrent `assign_queue_number` calls for the same `(doctor_id, scheduled_date)`; assert resulting queue_numbers == {1, 2, …, N}
  - [ ]* 9.3 Write property test for emergency queue priority
    - **Property 2: Emergency queue priority**
    - **Validates: Requirements 2.3**
    - Generate a set of existing scheduled appointments, then create an emergency appointment; assert emergency queue_number < all prior scheduled queue_numbers

- [x] 10. Appointment creation endpoint
  - [x] 10.1 Implement `routers/appointments.py` and `services/appointment_service.py`: `POST /v1/appointments`
    - Validate `patient_id` and `doctor_id` exist
    - Check doctor daily capacity: count `scheduled` + `in-progress` appointments; reject with 409 `DOCTOR_CAPACITY_REACHED` if at limit
    - Call `queue_manager.assign_queue_number`
    - Persist `Appointment` with `status=scheduled`
    - Emit `appointment_created` SSE event to `doctor:{doctor_id}` channel
    - Return created appointment within 1 second
    - _Requirements: 2.1–2.7_
  - [ ]* 10.2 Write property test for doctor daily capacity enforcement
    - **Property 8: Doctor daily capacity enforcement**
    - **Validates: Requirements 2.5**
    - Generate appointments up to `max_patients_per_day`, then attempt one more; assert overflow returns 409 and appointment count does not exceed limit
  - [ ]* 10.3 Write unit tests: successful creation returns appointment with queue_number, capacity-exceeded returns 409, invalid patient_id returns 404

- [x] 11. Doctor queue dashboard
  - Implement `GET /v1/appointments/today` and `GET /v1/appointments/{id}` in `routers/appointments.py`
    - `today` endpoint: accepts `doctor_id` and `date` query params; returns total count, completed count, remaining (scheduled-only) count, and queue list ordered by `queue_number` ASC; restrict to requesting doctor's `doctor_id`
    - `{id}` endpoint: return single appointment with patient name, visit_type, queue_number, status
    - _Requirements: 3.1–3.4_
  - [ ]* 11.1 Write property test for dashboard remaining count
    - **Property 11: Dashboard remaining count excludes terminal statuses**
    - **Validates: Requirements 3.1, 12.3**
    - Generate appointments in mixed statuses (`scheduled`, `in-progress`, `completed`, `no-show`, `cancelled`); assert remaining count equals count of `scheduled`-only appointments

- [x] 12. Call Next — atomic queue advancement
  - [x] 12.1 Implement `queue_manager.call_next(db, doctor_id, scheduled_date) -> CallNextResult`
    - Within a single transaction:
      1. `SELECT FOR UPDATE SKIP LOCKED` on the current `in-progress` appointment; if none locked → return `QUEUE_CONFLICT` or no-op
      2. Mark locked appointment as `completed`
      3. Select appointment with minimum `queue_number` where `status=scheduled` for that doctor/date
      4. Mark it `in-progress`
    - If no scheduled appointments remain, return `CallNextResult(queue_empty=True)`
    - Emit `queue_updated` SSE to `doctor:{doctor_id}` and `status_changed` SSE to `patient:{patient_id}` for the newly in-progress patient
    - _Requirements: 4.1–4.5_
  - [x] 12.2 Wire `PATCH /v1/appointments/{id}/clinical` to call `queue_manager.call_next`
    - _Requirements: 4.1, 4.5_
  - [ ]* 12.3 Write property test for at-most-one in-progress invariant
    - **Property 3: At-most-one in-progress invariant**
    - **Validates: Requirements 4.2, 14.4**
    - Generate arbitrary sequences of Call Next operations; assert `in-progress` count ≤ 1 at all times
  - [ ]* 12.4 Write property test for Call Next selecting minimum scheduled queue_number
    - **Property 4: Call Next selects minimum scheduled queue_number**
    - **Validates: Requirements 4.1, 4.2**
    - Generate queue states with multiple scheduled appointments; assert the appointment advanced to `in-progress` has the lowest `queue_number` among all `scheduled` appointments
  - [ ]* 12.5 Write property test for Call Next serialization under concurrency
    - **Property 5: Call Next serialization under concurrency**
    - **Validates: Requirements 4.4**
    - Simulate two concurrent Call Next calls for the same doctor/date; assert exactly one succeeds and the other returns conflict/no-op, leaving queue in consistent state

- [x] 13. Checkpoint — core queue flow
  - Ensure all tests pass for tasks 1–12. Verify that appointment creation → Call Next → queue state transitions work end-to-end in an integration test against a real PostgreSQL instance. Ask the user if questions arise.

- [x] 14. Services catalog
  - Implement `routers/services.py` and `services/service_catalog.py`: `GET /v1/services`
    - Return all `Service` records where `active=true`, including `service_id`, `name`, `category`, `base_price`
    - Restrict to Admin and Doctor roles
    - _Requirements: 6.1–6.3_
  - [ ]* 14.1 Write unit tests: active services returned, inactive services excluded, unauthenticated request returns 401

- [x] 15. Consultation recording
  - [x] 15.1 Implement `routers/consultations.py` and `services/consultation_service.py`: `POST /v1/consultations`
    - Validate `appointment_id` belongs to requesting doctor
    - Reject with 409 `CONSULTATION_EXISTS` if a consultation already exists for that appointment
    - Create `Consultation` record; create `ConsultationService` line items for each service in the request
    - If `next_visit_date` is non-null, include a `FollowUpPrompt` in the response with pre-filled `patient_id`, `doctor_id`, `visit_type=follow-up`, `scheduled_date=next_visit_date`
    - Emit `consultation_completed` SSE to `doctor:{doctor_id}` and `patient:{patient_id}`
    - _Requirements: 5.1–5.6, 11.1_
  - [x] 15.2 Implement `GET /v1/consultations/{appointment_id}`
    - Return consultation with services; restrict to Doctor (own) and Admin
    - _Requirements: 5.5_
  - [ ]* 15.3 Write property test for consultation one-to-one with appointment
    - **Property 6: Consultation one-to-one with appointment**
    - **Validates: Requirements 5.2, 14.5**
    - Attempt to create two consultations for the same appointment_id; assert second returns 409 and only one consultation record exists
  - [ ]* 15.4 Write property test for follow-up prompt correctness
    - **Property 12: Follow-up prompt contains correct pre-filled data**
    - **Validates: Requirements 11.1**
    - Generate consultations with random `next_visit_date` values; assert follow-up prompt `patient_id`, `doctor_id`, `scheduled_date`, and `visit_type` exactly match the consultation's appointment data and provided date
  - [ ]* 15.5 Write unit tests: consultation created with services, missing appointment returns 404, duplicate consultation returns 409, follow-up prompt absent when `next_visit_date` is null

- [x] 16. Follow-up appointment creation
  - Implement follow-up confirmation: when Admin/Doctor confirms the follow-up prompt, `POST /v1/appointments` with `visit_type=follow-up` applies all standard queue assignment rules
  - Reject with 409 `FOLLOWUP_CONFLICT` if an appointment already exists for the same `(patient_id, doctor_id, scheduled_date)`
  - _Requirements: 11.2, 11.3_
  - [ ]* 16.1 Write unit tests: confirmed follow-up creates appointment with `visit_type=follow-up`, duplicate follow-up returns 409

- [x] 17. No-show and cancellation handling
  - Implement `PATCH /v1/appointments/{id}/status` in `routers/appointments.py`
    - Accept `status` values `no-show` or `cancelled` only on this endpoint
    - Persist status change; do NOT reassign `queue_number`
    - Emit `queue_updated` SSE to `doctor:{doctor_id}`
    - _Requirements: 12.1–12.3_
  - [ ]* 17.1 Write unit tests: no-show persists status, queue_number unchanged, cancelled persists status, invalid status value returns 422

- [x] 18. Payment recording
  - Implement `routers/payments.py` and `services/payment_service.py`: `POST /v1/payments`
    - Validate `consultation_id` exists; reject with 404 `PAYMENT_CONSULTATION_NOT_FOUND` if not
    - Create `Payment` record with `status=pending`
    - Accept `payment_mode` in (`cash`, `upi`, `card`) and `status` in (`pending`, `paid`, `partial`)
    - _Requirements: 7.1–7.4_
  - [ ]* 18.1 Write unit tests: payment created with correct fields, invalid consultation_id returns 404, invalid payment_mode returns 422

- [x] 19. Audit logging middleware
  - [x] 19.1 Implement `middleware/audit_middleware.py` as a FastAPI middleware (or dependency): after every successful mutating request (POST, PATCH, DELETE with 2xx response), insert one `AuditLog` row capturing `actor_id`, `actor_role`, `action` (HTTP method + path), `resource`, `resource_id`, `payload` (request body), `created_at`
    - _Requirements: 10.8_
  - [ ]* 19.2 Write property test for audit log completeness
    - **Property 10: Audit log completeness**
    - **Validates: Requirements 10.8**
    - Execute any mutating operation (create patient, create appointment, create consultation, record payment); assert exactly one `audit_log` row is created per operation with correct `actor_id`, `actor_role`, `action`, `resource`, and `resource_id`

- [x] 20. SSE event bus
  - [x] 20.1 Implement `services/sse_bus.py`: in-process async fan-out using `asyncio.Queue` per subscriber
    - `publish(channel, event_type, data, event_id)`: persist row to `sse_events` table (for replay), then push to all active subscribers on that channel
    - `subscribe(channel) -> AsyncGenerator[SSEEvent, None]`: register subscriber queue, yield events, handle disconnect cleanup
    - `unsubscribe(channel, subscriber_id)`: remove subscriber queue, release resources within 30 seconds of disconnect
    - _Requirements: 9.1–9.6_
  - [x] 20.2 Implement `routers/events.py`: SSE endpoints
    - `GET /v1/events/doctor/{doctor_id}`: require JWT (Admin or Doctor role); on connect with `Last-Event-ID` header, replay all `sse_events` rows for `channel=doctor:{doctor_id}` with `sequence > last_sequence` before resuming live delivery
    - `GET /v1/events/patient/{patient_id}`: require OTP-issued JWT (Patient role); same replay logic for `channel=patient:{patient_id}`
    - Return `text/event-stream` responses with `id:`, `event:`, `data:` fields; include monotonically increasing sequence as event ID
    - _Requirements: 8.2–8.4, 9.1–9.6_
  - [ ]* 20.3 Write property test for SSE event ordering and no-duplication
    - **Property 9: SSE event ordering and no-duplication per channel**
    - **Validates: Requirements 8.3, 8.4, 9.3**
    - Publish N events to a channel; assert subscriber receives them in sequence order with no duplicates; disconnect and reconnect with `Last-Event-ID`; assert missed events replayed exactly once

- [x] 21. Patient live status endpoint
  - Implement `POST /v1/patient/appointment-status` in `routers/patient_status.py`
    - Require Patient-role JWT; return status based on current appointment: no active appointment (last visit summary), `scheduled` (queue position), `in-progress` (being seen), `completed` (diagnosis, services, next visit date)
    - _Requirements: 8.1_
  - [ ]* 21.1 Write unit tests for each status branch: no appointment, scheduled, in-progress, completed

- [x] 22. Checkpoint — full backend
  - Ensure all backend tests pass. Run the full integration test suite covering: appointment creation → Call Next → consultation → payment flow; SSE stream connection, event delivery, and `Last-Event-ID` reconnection; concurrent appointment creation hitting the UNIQUE constraint; doctor capacity limit enforcement. Ask the user if questions arise.

- [x] 23. Flutter design system
  - [x] 23.1 Implement `cacms_flutter/lib/core/theme/app_colors.dart`: define all color tokens from the UI/UX design — `primary (#1A6B8A)`, `primaryLight (#E8F4F8)`, `accent (#F4A261)`, `success (#2D9E6B)`, `warning (#E9C46A)`, `danger (#E63946)`, neutral scale (`neutral900/600/200/50`), `surface`
  - [x] 23.2 Implement `cacms_flutter/lib/core/theme/app_typography.dart`: Inter font scale — `headi
  ng1` (24sp/700), `heading2` (18sp/600), `heading3` (16sp/600), `body` (14sp/400), `caption` (12sp/400), `badge` (11sp/700), `mono` (JetBrains Mono 13sp/500 for queue numbers)
  - [x] 23.3 Implement `cacms_flutter/lib/core/theme/app_theme.dart`: compose `ThemeData` from colors and typography; define card elevation levels (0/1/2/3) matching the design spec shadow values
  - [x] 23.4 Implement shared UI components in `cacms_flutter/lib/core/widgets/`:
    - `StatusChip` — renders appointment status with correct background/text color and icon per the status chip table (scheduled=amber, in-progress=blue, completed=green, cancelled=grey, no-show=red)
    - `VisitTypeBadge` — normal/follow-up/emergency badge with correct colors
    - `QueueNumberDisplay` — large monospace queue number widget used on patient status screen
    - `SseIndicator` — live/reconnecting/disconnected dot indicator with label
    - `AppToast` — success/warning/error toast with auto-dismiss durations (success 3s, warning 2s, error 5s dismissible)
    - `EmptyState` — icon + message widget for empty queue, no appointment, etc.
  - _UI/UX Design: Design System, Status Chips, Visit Type Badges_

- [x] 24. Flutter core infrastructure
  - [x] 24.1 Implement `cacms_flutter/lib/core/api/api_client.dart`: Dio-based HTTP client with base URL config, JWT/OTP token injection via interceptor, error response parsing into typed `ApiError` (with `error_code` and `message`)
  - [x] 24.2 Implement `cacms_flutter/lib/core/api/sse_client.dart`: SSE client using `eventsource` package; supports `Last-Event-ID` header on reconnect; exposes `Stream<SseEvent>`; on disconnect transitions `SseIndicator` to reconnecting state with exponential backoff (1s, 2s, 4s); on reconnect sends `Last-Event-ID` and transitions back to live state
  - [x] 24.3 Implement `cacms_flutter/lib/core/auth/token_storage.dart`: secure token read/write using `flutter_secure_storage`; expose `saveToken`, `getToken`, `clearToken`
  - [x] 24.4 Implement shared Dart models in `cacms_flutter/lib/core/models/`: `Patient`, `Appointment`, `Consultation`, `Service`, `Payment`, `SseEvent` — matching backend Pydantic schemas
  - _Requirements: 10.1, 10.2, 8.3, 8.4_

- [x] 25. Flutter Admin screens (UI)
  - [x] 25.1 Implement Admin login screen (`features/admin/login/login_screen.dart`): CACMS logo + "Clinic Management" subtitle, username/password fields, full-width primary LOGIN button, loading spinner state (fields disabled), error banner below button for invalid credentials — matches screen A1 in UI/UX design
  - [x] 25.2 Implement Admin home screen (`features/admin/home/home_screen.dart`) as a two-panel layout:
    - Left panel (60% on tablet, full width on phone): patient lookup input with search icon; patient found card (name, age, gender, last visit); not-found inline registration form (name, age, gender, consent checkbox, REGISTER & CONTINUE button); appointment creation form (doctor dropdown, date picker defaulting to today, visit_type selector with emergency shown in red, CREATE APPOINTMENT button in accent color)
    - Right panel (40% on tablet, bottom sheet FAB on phone): live queue panel with doctor selector, total/done/remaining counts, ordered queue rows with `StatusChip` and `VisitTypeBadge`, `SseIndicator` at bottom
    - On phone: right panel accessible via floating "View Queue →" button opening a bottom sheet
    - _UI/UX Design: A2 — Admin Home_
  - [x] 25.3 Implement patient lookup states in the left panel:
    - Empty: phone input only
    - Searching: spinner inside input field
    - Found: patient card slides in below input with name, age, gender, last visit date
    - Not found: inline registration form expands with animation
    - _UI/UX Design: A2 Patient Lookup States_
  - [x] 25.4 Implement appointment creation feedback:
    - Success: `AppToast` "Queue #N assigned to [Name]" (3s); queue panel updates live via SSE
    - Capacity error: red inline message "Dr. [Name] has reached today's limit"
    - Emergency selection: visit type chip shows red ⚡ badge preview before submission
    - _UI/UX Design: A2 Appointment Creation States_
  - [x] 25.5 Implement Admin payment modal (`features/admin/payment/payment_modal.dart`): consultation summary with services line items and total, segmented control for payment mode (Cash/UPI/Card), amount input pre-filled with total, status dropdown (Paid/Partial/Pending), RECORD PAYMENT button, Cancel link — matches screen A3 in UI/UX design
    - _Requirements: 1.1–1.3, 2.1–2.3, 7.1–7.3_
  - [ ]* 25.6 Write Flutter widget tests for: patient lookup (found state, not-found state with registration form), appointment creation (success toast, capacity error), payment modal (all payment modes, submit)

- [x] 26. Flutter Doctor screens (UI)
  - [x] 26.1 Implement Doctor login screen (`features/doctor/login/login_screen.dart`): same layout as Admin login with "Doctor Portal" subtitle — matches screen D1 in UI/UX design
  - [x] 26.2 Implement Doctor queue dashboard screen (`features/doctor/queue_dashboard/queue_dashboard_screen.dart`):
    - Header: doctor name, specialization, today's date, settings icon
    - Stats row: three cards — Total, Done, Remaining — using `heading1` size numbers

       - CALL NEXT PATIENT button: full-width, accent color (`#F4A261`), large touch target; loading spinner state that disables button to prevent double-tap; on success animates queue list update; on `QUEUE_EMPTY` transitions to grey "Queue Complete ✓" button with `EmptyState` widget; on `QUEUE_CONFLICT` shows `AppToast` "Retry in a moment" and re-enables after 1s
    - "NOW SEEING" card: patient name, queue number, visit type badge, START CONSULTATION button
    - Queue list: rows ordered by `queue_number` ASC; each row shows queue number (mono font), patient name, `VisitTypeBadge`, `StatusChip`; emergency rows pinned above other scheduled rows with ⚡ icon; completed rows rendered in muted style; tap row to expand no-show/cancel actions
    - `SseIndicator` at bottom; queue list updates in real-time on `appointment_created` and `queue_updated` SSE events
    - _UI/UX Design: D2 — Doctor Queue Dashboard_
  - [x] 26.3 Implement Doctor consultation form screen (`features/doctor/consultation/consultation_screen.dart`):
    - App bar with back arrow, patient name, queue number, visit type badge
    - Scrollable form: SYMPTOMS multiline field (min 3 rows), DIAGNOSIS multiline field, NOTES optional multiline field
    - SERVICES section: "Add Service" button opens bottom sheet; added services shown as line items with name, quantity, price, remove (✕) button; running total displayed
    - Add Service bottom sheet: search field, services grouped by category (Consultation / Tests / Procedures), each row shows name, price, (+) add button
    - NEXT VISIT DATE optional date picker field with calendar icon
    - COMPLETE CONSULTATION primary button at bottom
    - _UI/UX Design: D3 — Consultation Form_
  - [x] 26.4 Implement follow-up prompt bottom sheet (`features/doctor/consultation/followup_sheet.dart`): shown after successful consultation save when `next_visit_date` is set; displays pre-filled patient, doctor, date, visit type = Follow-Up; BOOK FOLLOW-UP primary button; "Skip for now" text link — matches follow-up prompt in UI/UX design
    - _Requirements: 3.1–3.4, 4.1–4.5, 5.1–5.5, 11.1_
  - [ ]* 26.5 Write Flutter widget tests for: queue dashboard stats row, Call Next (success/conflict/empty states), queue list SSE update (mock SSE), consultation form submission, follow-up bottom sheet (shown/hidden based on next_visit_date)

- [x] 27. Flutter Patient screens (UI)
  - [x] 27.1 Implement Patient OTP phone entry screen (`features/patient/otp_login/phone_screen.dart`): CACMS logo, "Patient Portal" subtitle, +91 prefix + phone number input, SEND OTP full-width button, privacy note below button — matches screen P1 in UI/UX design
  - [x] 27.2 Implement Patient OTP verification screen (`features/patient/otp_login/otp_screen.dart`): back arrow, masked phone display, 6-digit OTP input boxes (auto-advance on digit entry, supports SMS autofill), VERIFY button, countdown resend timer ("Resend OTP in 00:45"), error message slot below OTP boxes — matches screen P2 in UI/UX design
  - [x] 27.3 Implement Patient live status screen (`features/patient/live_status/live_status_screen.dart`) with four distinct UI states:
    - No appointment: "No appointment today" heading + `EmptyState`, LAST VISIT card with date, doctor, diagnosis, next visit date
    - Scheduled: `QueueNumberDisplay` (large mono number), "Dr. [Name] is on #N" subtitle, estimated wait text, `SseIndicator`
    - In-progress: pulsing blue "▶ You are being seen now" card with doctor name and specialization
    - Completed: "Visit complete ✓" heading, VISIT SUMMARY card with date, doctor, diagnosis, services line items with prices, total, next visit date
    - Screen subscribes to `/events/patient/{patient_id}` SSE stream; transitions between states on `status_changed` and `consultation_completed` events without requiring manual refresh
    - `SseIndicator` shows live/reconnecting/disconnected; on reconnect sends `Last-Event-ID` and replays missed state changes
    - _UI/UX Design: P3 — Patient Live Status, all four states_
    - _Requirements: 8.1–8.4, 10.2_
  - [x] 27.4 Write Flutter widget tests for: phone entry (valid/invalid input), OTP verification (correct OTP, wrong OTP error, resend timer), live status screen (all four state renders with mocked API + SSE)

- [x] 28. Integration tests
  - [x] 28.1 Write integration test: full happy-path flow — register patient → create appointment → Call Next → record consultation with services → record payment; assert each step returns correct data and SSE events are emitted
  - [x] 28.2 Write integration test: concurrent appointment creation — fire N simultaneous `POST /v1/appointments` for same doctor/date; assert queue_numbers are {1..N} with no duplicates or gaps
  - [x] 28.3 Write integration test: SSE reconnection — connect to doctor stream, receive events, disconnect, reconnect with `Last-Event-ID`, assert missed events replayed in order
  - [x] 28.4 Write integration test: doctor capacity limit — create appointments up to `max_patients_per_day`, assert next creation returns 409 `DOCTOR_CAPACITY_REACHED`
  - _Requirements: 2.4, 2.6, 4.4, 8.4, 9.3_

- [x] 29. Final checkpoint — full system
  - Ensure all backend and Flutter tests pass. Verify property-based tests (Hypothesis) run a minimum of 100 iterations each. Ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests are tagged with their design property number and the requirements they validate
- Checkpoints at tasks 13, 22, and 29 ensure incremental validation before proceeding
- The `uq_one_inprogress_per_doctor_date` partial unique index (task 2.1) is the database-level guard for Property 3; the advisory lock in `assign_queue_number` (task 9.1) is the guard for Properties 1 and 2
- UI tasks (23–27) reference the `ui-ux-design.md` spec for exact screen layouts, color tokens, interaction states, and responsive breakpoints
