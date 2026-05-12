# Implementation Plan: CACMS Phase 1 SaaS Completion

## Overview

Implement the commercial and SaaS layer on top of the existing multi-tenant CACMS backend: plan tiers, usage metering, manual subscription management (no payment gateway — clinics pay you directly via cash/UPI), super-admin API, Flutter settings/billing screens, Nginx/HTTPS infrastructure, public queue display, email-based patient record access, and documentation cleanup. Tasks are ordered by dependency so each step builds on a stable foundation.

**Patient model change:** Patient OTP login is removed entirely. Patients never log in. Queue position is shown publicly via a shareable URL/QR code. Medical records are delivered by email on request (phone number + destination email). This eliminates SMS costs, OTP friction, and the entire patient auth layer.

**Billing model:** No payment gateway. Clinics pay you directly (cash or UPI scan). You manually activate their plan via the super-admin API. This is the right approach for a small-clinic pilot — add Razorpay later when you have 20+ paying clinics and manual management becomes a bottleneck.

## Tasks

- [x] 1. Database migration and ORM model updates
  - [x] 1.1 Write Alembic migration `0005_saas_layer.py`
    - Add plan/billing fields to `clinics` table: `plan` (TEXT, default `'free'`), `plan_status` (TEXT, default `'active'`), `billing_email` (TEXT, nullable), `max_doctors` (INT, nullable), `max_staff` (INT, nullable), `plan_activated_at` (TIMESTAMPTZ, nullable), `plan_expires_at` (TIMESTAMPTZ, nullable), `plan_note` (TEXT, nullable)
    - Add clinic profile fields to `clinics` table: `clinic_address` (TEXT, nullable), `clinic_phone` (TEXT, nullable), `clinic_gstin` (TEXT, nullable — GST registration number), `clinic_reg_number` (TEXT, nullable — clinic/hospital registration number), `receipt_header` (TEXT, nullable — custom text printed at top of patient receipt), `receipt_footer` (TEXT, nullable — custom text at bottom, e.g. "Thank you for visiting")
    - Add `CHECK` constraint `ck_clinics_plan` enforcing `plan IN ('free','starter','clinic','pro','enterprise')`
    - Create `usage_events` table: `id` (UUID PK, `gen_random_uuid()`), `clinic_id` (UUID FK → clinics ON DELETE CASCADE), `event_type` (TEXT NOT NULL), `quantity` (INT NOT NULL DEFAULT 1), `metadata` (JSONB nullable), `billed` (BOOLEAN NOT NULL DEFAULT false), `created_at` (TIMESTAMPTZ NOT NULL DEFAULT now())
    - Create index `idx_usage_events_clinic_month ON usage_events (clinic_id, event_type, created_at)`
    - _Requirements: 1.1, 4.1_

  - [x] 1.2 Update `Clinic` SQLAlchemy ORM model in `cacms/models/clinic.py`
    - Add plan/billing mapped columns: `plan`, `plan_status`, `billing_email`, `max_doctors`, `max_staff`, `plan_activated_at`, `plan_expires_at`, `plan_note`
    - Add clinic profile mapped columns: `clinic_address`, `clinic_phone`, `clinic_gstin`, `clinic_reg_number`, `receipt_header`, `receipt_footer`
    - Add `CheckConstraint` for valid plan values in `__table_args__`
    - _Requirements: 1.2_

  - [x] 1.3 Create `UsageEvent` SQLAlchemy ORM model in `cacms/models/usage_event.py`
    - Define all columns matching the migration schema
    - Add the model to `cacms/models/__init__.py` exports
    - _Requirements: 4.2_

- [x] 2. Plan features configuration and PlanEnforcer service
  - [x] 2.1 Create `cacms/config/plans.py` with `PLAN_FEATURES` dict and `PLAN_TIERS` list
    - Define `PLAN_TIERS = ["free", "starter", "clinic", "pro", "enterprise"]`
    - Define `PLAN_FEATURES` with keys for every plan: `max_doctors`, `max_staff`, `max_appointments_per_month`, `can_export_reports`, `can_export_pdf`, `multi_branch`, `api_access`, `lab_integrations`
    - Free plan: `max_doctors=1`, `max_staff=3`, `max_appointments_per_month=200`, all boolean flags `False`
    - Starter: `max_doctors=1`, `max_staff=5`, `max_appointments_per_month=None`, `can_export_reports=True`
    - Clinic: `max_doctors=5`, `max_staff=10`, `max_appointments_per_month=None`, `can_export_reports=True`, `can_export_pdf=True`, `lab_integrations=True`
    - Pro: all `None` limits, all features `True`
    - Enterprise: same as Pro
    - Define `PLAN_MONTHLY_PRICES` dict in INR (not paise — for display): `{"free": 0, "starter": 999, "clinic": 2999, "pro": 7999}`
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ]* 2.2 Write property test for PLAN_FEATURES completeness (Property 3)
    - **Property 3: PLAN_FEATURES completeness — every plan has all required keys**
    - For every plan name in `PLAN_FEATURES`, assert all ten required keys are present
    - **Validates: Requirements 2.2**

  - [ ]* 2.3 Write property test for plan tier ordering (Property 4)
    - **Property 4: Plan tier ordering — higher tiers have non-decreasing numeric limits**
    - `@given` two plan names from `PLAN_TIERS`; for the higher-ranked plan, assert each numeric limit is ≥ the lower plan's limit (treating `None` as greater than any finite value)
    - **Validates: Requirements 2.4**

  - [x] 2.4 Create `PlanEnforcer` class in `cacms/services/plan_enforcer.py`
    - Implement `check_feature(clinic, feature_name) -> None`: raises HTTP 402 with `error_code='PLAN_LIMIT_EXCEEDED'` when the feature is `False` for the clinic's plan
    - Implement `check_limit(clinic, resource_name, current_count) -> None`: raises HTTP 402 when `current_count >= limit` and limit is not `None`; no-op when limit is `None`
    - Implement `get_plan_features(clinic) -> dict`: returns the `PLAN_FEATURES` entry for the clinic's plan
    - Error response shape: `{"error_code": "PLAN_LIMIT_EXCEEDED", "message": "...", "detail": {"resource": ..., "limit": ..., "current": ..., "upgrade_url": "/v1/billing/plans"}}`
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 2.5 Write property test for PlanEnforcer feature rejection (Property 5)
    - **Property 5: PlanEnforcer rejects features not in plan**
    - `@given` plan name + feature name that is `False` in that plan; assert `check_feature` raises `HTTPException` with status 402 and `error_code='PLAN_LIMIT_EXCEEDED'`
    - **Validates: Requirements 3.2**

  - [x] 2.6 Write property test for PlanEnforcer limit enforcement (Property 6)
    - **Property 6: PlanEnforcer rejects counts at or above finite limits**
    - `@given` plan name + resource with finite limit `L` + integer `count`; assert `check_limit` raises 402 when `count >= L` and does not raise when `count < L`
    - **Validates: Requirements 3.3**

  - [x] 2.7 Write property test for PlanEnforcer unlimited plans (Property 7)
    - **Property 7: PlanEnforcer allows all counts when limit is None**
    - `@given` plan name with `None` limit for a resource + any non-negative integer `count`; assert `check_limit` never raises
    - **Validates: Requirements 3.4**

- [x] 3. MeteringService and UsageEvent integration
  - [x] 3.1 Create `MeteringService` class in `cacms/services/metering_service.py`
    - Implement `async record(db, clinic_id, event_type, quantity=1, metadata=None)`: inserts a `UsageEvent` row, then increments Redis counter `usage:{clinic_id}:{event_type}:{year}:{month}` with TTL 7,776,000 seconds; catches `redis.exceptions.RedisError` and `ConnectionError`, logs a warning, and continues without re-raising
    - Implement `async get_monthly_usage(db, clinic_id, year, month)`: reads from Redis when available; falls back to a `GROUP BY event_type` aggregate query against `usage_events`
    - _Requirements: 4.3, 4.4, 4.5, 4.6_

  - [x] 3.2 Write property test for metering record-then-read round trip (Property 8)
    - **Property 8: Metering record-then-read round trip**
    - `@given` clinic ID + event type + positive quantity; call `record` then `get_monthly_usage` for the same clinic and current month; assert returned count for that event type is ≥ the recorded quantity
    - **Validates: Requirements 4.4, 4.6**

- [x] 4. Config additions in `cacms/config.py`
  - Add `SUPERADMIN_TOKEN: str = ""` to `Settings`
  - Add `model_validator` that raises `ValueError` at startup when `ENVIRONMENT == 'production'` and `SUPERADMIN_TOKEN == ''`, following the existing `JWT_SECRET` validator pattern
  - Remove `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` — no payment gateway needed
  - _Requirements: 6.6_

- [x] 5. EmailService implementation
  - **Context:** Patient OTP login is being removed entirely. Patients never need to log in. Queue info is public. If a patient wants their medical records (diagnosis, prescription, visit history), they request it via email — the system emails a PDF summary to the address registered on their patient record.

  - [x] 5.1 Add `EMAIL_FROM`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` to `cacms/config.py`
    - All optional (empty string defaults); when not configured, email sending is skipped and logged
    - _New requirement: email-based patient record delivery_

  - [x] 5.2 Create `EmailService` class in `cacms/services/email_service.py`
    - Implement `async send_visit_summary(patient_email, patient_name, consultation)`: sends a plain-text email with the consultation summary (diagnosis, services, next visit date, doctor name, date)
    - Uses Python `smtplib` with `aiosmtplib` for async sending; falls back to logging when SMTP not configured
    - On SMTP error, log the error and raise HTTP 502 with `error_code='EMAIL_DELIVERY_FAILED'`
    - _New requirement: async email delivery with dev fallback_

  - [x] 5.3 Create patient record request endpoint `POST /v1/public/request-records`
    - No authentication required
    - Accepts: `phone` (patient's registered phone number), `email` (where to send the records)
    - Looks up the patient by phone; if found, emails the last 5 consultation summaries as plain text to the provided email
    - Rate-limited to 3 requests per phone number per hour (prevents abuse)
    - Returns `{"message": "If a patient record exists for this phone number, a summary will be sent to the provided email"}` — always the same response regardless of whether the patient exists (prevents phone enumeration)
    - Does NOT require the email to match the registered email — patient provides where they want it sent
    - _New requirement: privacy-respecting patient data access without login_

- [x] 6. Manual subscription management (no payment gateway)
  - **Context:** Clinics pay you directly — cash or UPI scan. You activate their plan manually via the super-admin API. No Razorpay, no payment gateway, no 2% transaction fee. Add a payment gateway later when you have 20+ paying clinics.

  - [x] 6.1 Extend `PATCH /v1/superadmin/clinics/{clinic_id}/plan` to support full manual activation
    - Accept: `plan` (plan name), `plan_status` (`active` or `grace` or `free`), `plan_note` (optional text, e.g. "Paid ₹999 via UPI ref TXN123 on 10-May-2026"), `plan_expires_at` (optional ISO date — when the paid period ends)
    - When `plan_expires_at` is set and is in the past, automatically set `plan_status = 'grace'`
    - This is the only way to activate a paid plan — you do it manually after receiving payment
    - _Manual billing workflow: clinic pays you → you log into super-admin → activate their plan_

  - [x] 6.2 Add plan expiry check on startup and daily cron
    - On app startup and once daily (via a background task using `asyncio` — no Celery needed at this scale), query all clinics where `plan_expires_at < now()` and `plan_status = 'active'`; set their `plan_status = 'grace'`
    - Log each transition: `"Clinic {name} ({clinic_id}) moved to grace — plan expired {plan_expires_at}"`
    - _Automatic grace period when paid period ends without renewal_

  - [x] 6.3 Add `GET /v1/clinic/subscription` endpoint (owner-facing)
    - Returns: `plan`, `plan_status`, `plan_expires_at`, `days_remaining` (null if no expiry set)
    - If `plan_status = 'grace'`, include message: `"Your plan has expired. Please contact support to renew."`
    - Owner can see when their plan expires and contact you to renew
    - _No self-serve payment — owner contacts you directly_

- [x] 7. New backend routers
  - [x] 7.1 Create `cacms/routers/clinic.py`
    - All endpoints protected by `require_owner` dependency
    - `GET /v1/clinic`: return `clinic_id`, `name`, `plan`, `plan_status`, `billing_email`, and all clinic profile fields (`clinic_address`, `clinic_phone`, `clinic_gstin`, `clinic_reg_number`, `receipt_header`, `receipt_footer`)
    - `PATCH /v1/clinic`: accept optional fields — `name`, `billing_email`, `clinic_address`, `clinic_phone`, `clinic_gstin`, `clinic_reg_number`, `receipt_header`, `receipt_footer`; validate that `name`, if provided, is not empty or whitespace-only (return 422 otherwise); update clinic record
    - `GET /v1/clinic/usage`: return `MeteringService.get_monthly_usage` for the current calendar month
    - `GET /v1/clinic/plan`: return plan name, status, full `PLAN_FEATURES` entry, and current month's usage counts
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ]* 7.2 Write property test for Clinic PATCH name round trip (Property 9)
    - **Property 9: Clinic PATCH name round trip**
    - `@given` non-empty, non-whitespace string; call `PATCH /v1/clinic` then `GET /v1/clinic`; assert returned `name` equals the submitted value
    - **Validates: Requirements 5.2**

  - [ ]* 7.3 Write property test for Clinic PATCH whitespace rejection (Property 10)
    - **Property 10: Clinic PATCH rejects whitespace-only names**
    - `@given` strings composed entirely of whitespace characters; assert `PATCH /v1/clinic` returns HTTP 422
    - **Validates: Requirements 5.3**

  - [x] 7.4 Create `cacms/routers/superadmin.py`
    - Implement `require_superadmin` dependency: reads `Authorization: Bearer <token>` header; compares to `settings.SUPERADMIN_TOKEN`; raises HTTP 401 with `error_code='UNAUTHORIZED'` on mismatch — no JWT decode
    - `GET /v1/superadmin/clinics`: paginated list of all clinics (`clinic_id`, `name`, `plan`, `plan_status`, `created_at`)
    - `PATCH /v1/superadmin/clinics/{clinic_id}/plan`: update clinic plan; return 404 if clinic not found
    - `GET /v1/superadmin/stats`: return `total_clinics`, `total_appointments_today`, `mrr_estimate` (sum of `PLAN_MONTHLY_PRICES` for active paid clinics)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ]* 7.5 Write property test for superadmin token auth (Property 11)
    - **Property 11: Superadmin token auth — wrong token always returns 401**
    - `@given` arbitrary Bearer token string that is not equal to `settings.SUPERADMIN_TOKEN`; assert all three superadmin endpoints return HTTP 401; assert the correct token does not return 401
    - **Validates: Requirements 6.1, 6.2**

  - [x] 7.6 Create `cacms/routers/billing.py` — plan info only (no payment gateway)
    - `GET /v1/billing/plans`: no auth required; return list of plans with names, prices in INR, and feature summaries from `PLAN_FEATURES` — used by the Flutter billing screen to show what's available
    - `GET /v1/billing/status`: `require_owner`; return `plan`, `plan_status`, `plan_expires_at`, `days_remaining`, and a human-readable renewal message when in grace period
    - No subscribe/webhook endpoints — payment is handled offline (cash/UPI to you directly)
    - _Simple plan display — no payment processing_

- [x] 8. Wire metering into existing routers and remove patient OTP auth
  - [x] 8.1 Update `cacms/routers/auth.py` — remove patient OTP endpoints
    - Remove `POST /v1/auth/request-otp` endpoint entirely — patients no longer log in
    - Remove `POST /v1/auth/verify-otp` endpoint entirely — no patient JWT is issued
    - Remove the `print(f"[OTP STUB]...")` statement
    - Keep `otp_service.py` and `otp_sessions` table in place (may be used for staff 2FA in a future phase) but do not expose them via API
    - Update `cacms/routers/events.py`: remove `GET /v1/events/patient/{patient_id}` endpoint — patients no longer have a JWT to authenticate SSE streams; the public SSE stream (task 18.3) replaces this
    - Update `cacms/routers/patient_status.py`: remove `POST /v1/patient/appointment-status` endpoint — this required patient JWT which no longer exists; the public queue endpoint (task 18.1) replaces this
    - Remove the `patient` role from `VALID_STAFF_ROLES` in `auth_middleware.py` and from `require_patient` dependency — no patient tokens are issued
    - Update `cacms/main.py` to remove `patient_status.router` from the registered routers
    - _Removes the entire patient auth layer — zero SMS cost, zero login friction_

  - [ ]* 8.2 Write property test for registration defaults (Property 1)
    - **Property 1: New clinic registration always defaults to free/active plan**
    - `@given` valid clinic name + owner username + password; assert the resulting clinic record has `plan='free'` and `plan_status='active'`
    - **Validates: Requirements 1.3**

  - [ ]* 8.3 Write property test for plan name validation (Property 2)
    - **Property 2: Plan name validation rejects all non-canonical values**
    - `@given` arbitrary string not in `{'free','starter','clinic','pro','enterprise'}`; assert storing or validating it as a plan name is rejected with a validation error
    - **Validates: Requirements 1.4**

  - [x] 8.4 Update `cacms/routers/appointments.py` — appointment metering
    - After a successful `POST /v1/appointments`, call `MeteringService.record(db, clinic_id, 'appointment_created')`
    - _Requirements: 4.8_

  - [x] 8.5 Update `cacms/routers/reports.py` — report export metering
    - After a successful `GET /v1/reports/daily`, call `MeteringService.record(db, clinic_id, 'report_export')`
    - _Requirements: 4.9_

  - [x] 8.6 Upgrade `cacms/routers/exports.py` — clinic-branded patient receipt
    - Update `GET /v1/exports/receipt/{payment_id}` to pull clinic profile fields from the `clinics` table and include them in the receipt output
    - Receipt format (plain text, structured for printing):
      ```
      ========================================
      {receipt_header or clinic_name}
      {clinic_address}
      Phone: {clinic_phone}
      GSTIN: {clinic_gstin}   Reg: {clinic_reg_number}
      ========================================
      RECEIPT
      Receipt No : {payment_id short}
      Date       : {date}
      ----------------------------------------
      Patient    : {patient_name}
      Doctor     : {doctor_name}
      ----------------------------------------
      Services:
        {service_name} x {qty}    ₹{price}
        ...
      ----------------------------------------
      Total      : ₹{total_amount}
      Paid via   : {payment_mode}
      Status     : {payment_status}
      ========================================
      {receipt_footer or "Thank you for visiting"}
      ========================================
      ```
    - Fields that are `null` in the clinic profile are simply omitted from the output (no blank lines for missing GSTIN etc.)
    - Add `GET /v1/exports/receipt/{payment_id}?format=json` query param that returns the same data as structured JSON (for Flutter to render a styled receipt card)
    - _Each clinic's receipt looks different based on their profile — no hardcoded clinic info_

- [x] 9. Wire plan enforcement into existing routers
  - [x] 9.1 Update `cacms/routers/doctors.py` — enforce `max_doctors` limit
    - Before inserting a new doctor record, query the current doctor count for the clinic and call `PlanEnforcer.check_limit(clinic, 'max_doctors', count)`
    - _Requirements: 3.5_

  - [x] 9.2 Update `cacms/routers/users.py` — enforce `max_staff` limit
    - Before inserting a new staff user record, query the current staff count for the clinic and call `PlanEnforcer.check_limit(clinic, 'max_staff', count)`
    - _Requirements: 3.6_

- [x] 10. Update `cacms/main.py`
  - Conditionally set `docs_url` and `redoc_url` based on `ENVIRONMENT`: `None` when `production`, default paths otherwise
  - Register the three new routers: `clinic.router`, `superadmin.router`, `billing.router` all with `prefix="/v1"`
  - Add `@app.on_event("startup")` handler that initialises `MeteringService` with an optional Redis client (from `settings.REDIS_URL`) and attaches it to `app.state.metering`
  - Add `get_metering` FastAPI dependency function
  - _Requirements: 12.1, 12.2_

  - [ ]* 10.1 Write property test for docs disabled in production (Property 16)
    - **Property 16: Docs disabled in production for any environment value**
    - Assert that a FastAPI app instance created with `ENVIRONMENT='production'` has `docs_url=None` and `redoc_url=None`
    - **Validates: Requirements 12.1**

- [x] 11. Backend checkpoint — ensure all tests pass
  - Run `pytest` (or `pytest --tb=short`) and confirm all unit tests and property tests pass
  - Verify the Alembic migration applies cleanly against a fresh test database: `alembic upgrade head`
  - Ensure all tests pass; ask the user if questions arise.

- [x] 12. Flutter ClinicSettingsScreen
  - [x] 12.1 Create `cacms_flutter/lib/features/admin/settings/clinic_settings_screen.dart`
    - `StatefulWidget` with `FutureBuilder` for initial load
    - On load: parallel calls to `GET /v1/clinic` and `GET /v1/clinic/plan`
    - **Section 1 — Clinic Profile** (used on patient receipts):
      - Clinic name (editable)
      - Address (editable multiline)
      - Phone (editable)
      - GSTIN (editable, optional)
      - Registration number (editable, optional)
      - Receipt header (editable, optional — custom text at top of receipt)
      - Receipt footer (editable, optional — e.g. "Thank you for visiting")
    - **Section 2 — Billing Info:**
      - Billing email (editable)
      - Plan name and status badge
      - Plan expiry date if set
    - **Section 3 — Usage:**
      - Usage table showing `appointment_created` and `report_export` counts vs. plan limits
    - On save: call `PATCH /v1/clinic` with all changed fields; show `SnackBar` on success; re-fetch
    - "Upgrade Plan" button → navigates to `BillingScreen`
    - _Requirements: 9.1–9.6_

  - [ ]* 12.2 Write Flutter widget test for ClinicSettingsScreen
    - Mock API responses; verify all three sections render
    - Verify save submits `PATCH /v1/clinic` with correct fields
    - _Requirements: 9.2–9.5_

- [x] 13. Flutter BillingScreen
  - [x] 13.1 Create `cacms_flutter/lib/features/admin/billing/billing_screen.dart`
    - On load: parallel calls to `GET /v1/billing/plans` and `GET /v1/billing/status`
    - Render a scrollable list of plan cards; each card shows name, price formatted as ₹X/month, and key feature bullets
    - Highlight the current plan card with a border or badge
    - Display subscription status (`active`, `grace`, `free`) with a human-readable label
    - If `plan_status = 'grace'` or `plan = 'free'`, show a contact card: "To upgrade, contact us on WhatsApp: [your number]" or "Email: [your email]" — no in-app payment flow
    - If `plan_expires_at` is set, show "Plan renews on [date]" or "Plan expired on [date]"
    - _Simple plan display — clinic contacts you to upgrade, you activate manually_

  - [ ]* 13.2 Write Flutter widget test for BillingScreen
    - Mock `GET /v1/billing/plans` and `GET /v1/billing/status`; verify plan cards render and current plan is highlighted
    - Verify grace period message shows when `plan_status = 'grace'`
    - Verify contact info is displayed for upgrade
    - _Requirements: 10.2, 10.3, 10.4_

- [x] 14. AdminShell updates — owner-only tabs
  - Modify `AdminShell` to decode the user's role from the JWT stored in `flutter_secure_storage` (no extra API call)
  - Conditionally add Settings tab (renders `ClinicSettingsScreen`) and Billing tab (renders `BillingScreen`) when `role == 'owner'`
  - Build the `IndexedStack` children list dynamically to match the tab list
  - _Requirements: 9.7, 10.7_

  - [ ]* 14.1 Write Flutter widget test for AdminShell role-based tabs
    - Verify Settings and Billing tabs appear when `role='owner'`
    - Verify they do not appear for `doctor`, `staff`, or `patient` roles
    - _Requirements: 9.7, 10.7_

- [x] 15. Nginx configuration and Terraform updates
  - [x] 15.1 Create `nginx/cacms.conf`
    - Upstream block pointing to `127.0.0.1:8000`
    - HTTP server block: `listen 80`, redirect all requests to HTTPS with `return 301 https://$host$request_uri`
    - HTTPS server block: `listen 443 ssl`, TLS certificate paths for Let's Encrypt, `proxy_pass` to upstream with `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` headers
    - `/v1/events/` location block: `proxy_buffering off`, `proxy_cache off`, `proxy_http_version 1.1`, `chunked_transfer_encoding on`
    - _Requirements: 11.1, 11.5_

  - [x] 15.2 Update Terraform EC2 configuration (`terraform/ec2.tf`)
    - Add Nginx installation and `systemctl enable nginx` to `user_data.sh.tpl`
    - Add Let's Encrypt Certbot installation and certificate provisioning commands to `user_data.sh.tpl`
    - Open port 443 in the EC2 security group
    - _Requirements: 11.2, 11.3_

  - [x] 15.3 Update `DEPLOYMENT_AWS.md` with HTTPS setup instructions
    - Document DNS configuration steps
    - Document Certbot execution command and certificate renewal setup
    - _Requirements: 11.4_

- [x] 16. Update `BETA_SETUP.md`
  - Remove all references to the hardcoded `admin123` password and the statement that any password works for doctors
  - Document `seed_admin.py` and `scripts/create_owner.py` as the correct flows for creating initial users
  - Document the Flutter `ServerSetupScreen` as the recommended first-run flow for configuring the backend URL
  - Document the MSG91 dev-mode fallback: when `MSG91_AUTH_KEY` is not set, OTPs are logged to the server console
  - _Requirements: 13.1, 13.2, 13.3, 13.4_

- [x] 17. Final checkpoint — ensure all tests pass
  - Run the full test suite (`pytest`) and confirm all unit tests, property tests, and integration tests pass
  - Run `nginx -t` to verify Nginx config syntax
  - Verify Terraform plan applies cleanly (`terraform plan`)
  - Ensure all tests pass; ask the user if questions arise.

- [ ] 18. Public queue display and patient record access via email
  - **Context:** Patients never log in. Queue position is public information shown via a shareable URL/QR code. If a patient wants their medical records, they submit their phone number and an email address — the system emails a summary. No OTP, no app login, no SMS cost.

  - [x] 18.1 Create public queue status endpoint `GET /v1/public/queue/{clinic_id}/{doctor_id}`
    - No authentication required
    - Returns: `clinic_name`, `doctor_name`, `specialization`, `current_queue_number` (the in-progress patient's queue number, or `null` if none), `total_scheduled` (remaining patients), `estimated_wait_minutes` (remaining × 10 min default, configurable per clinic later)
    - Does NOT return any patient names, phone numbers, or medical data — only queue numbers and counts
    - Returns 404 if `clinic_id` or `doctor_id` does not exist
    - Rate-limited to 60 requests/minute per IP
    - _Replaces patient OTP login for queue visibility_

  - [x] 18.2 Create public clinic info endpoint `GET /v1/public/clinic/{clinic_id}`
    - No authentication required
    - Returns: `clinic_name`, list of active doctors with `doctor_id`, `name`, `specialization`, `is_accepting_patients` (true if scheduled count < max_patients_per_day)
    - Used by the public queue page to let patients pick their doctor
    - Rate-limited to 60 requests/minute per IP
    - _Enables clinic discovery for the public queue page_

  - [x] 18.3 Create public SSE stream `GET /v1/public/events/queue/{clinic_id}/{doctor_id}`
    - No authentication required
    - Subscribes to the existing `doctor:{doctor_id}` SSE channel internally
    - Filters outgoing event payloads to only include: `current_queue_number`, `total_scheduled`, `event_type`
    - Strips all patient identifiers (`patient_id`, `patient_name`, `phone`) before forwarding to the public stream
    - Returns 404 if clinic or doctor does not exist
    - _Live queue updates with zero patient data exposure_

  - [x] 18.4 Create `cacms/routers/public.py` and register it in `main.py`
    - Groups all three public endpoints (18.1, 18.2, 18.3) under prefix `/v1/public`
    - No auth middleware applied to this router
    - Register in `main.py` with `prefix="/v1"` alongside other routers
    - _Single router for all unauthenticated public endpoints_

  - [x] 18.5 Create Flutter public queue screen `cacms_flutter/lib/features/public/public_queue_screen.dart`
    - Accessible without login — entry point is a QR code scan or shared link
    - On load: calls `GET /v1/public/clinic/{clinic_id}` to show clinic name and doctor list
    - After doctor selection (or if `doctor_id` is in the URL): calls `GET /v1/public/queue/{clinic_id}/{doctor_id}`
    - Displays: clinic name, doctor name, current queue number being seen, patients ahead, estimated wait
    - Subscribes to `GET /v1/public/events/queue/{clinic_id}/{doctor_id}` for live updates
    - Shows `SseIndicator` (live/reconnecting/disconnected)
    - "Request My Records" button → navigates to `RecordRequestScreen` (task 18.7)
    - _Zero-friction patient queue visibility_

  - [x] 18.6 Add QR code / shareable link generation to doctor queue dashboard
    - In `DoctorQueueDashboardScreen`, add a "Share Queue Link" icon button in the app bar
    - Generates URL: `https://{server_url}/queue/{clinic_id}/{doctor_id}`
    - Shows a `QrImageView` dialog (use `qr_flutter` package) that staff can display on a waiting room screen or print
    - Also shows the plain URL for copying
    - Add `qr_flutter` and `url_launcher` to `pubspec.yaml` dependencies
    - _Clinic staff can onboard patients to the public queue in seconds_

  - [x] 18.7 Create Flutter record request screen `cacms_flutter/lib/features/public/record_request_screen.dart`
    - Accessible without login — linked from the public queue screen
    - Two fields: phone number (pre-filled if coming from queue screen context) and email address
    - "Send My Records" button → calls `POST /v1/public/request-records`
    - Shows a confirmation message: "If we have records for this number, we'll email them shortly"
    - Same message regardless of whether the patient exists (prevents phone enumeration)
    - _Patient data access without any login_

  - [x] 18.8 Remove Flutter patient OTP screens from the main navigation
    - Remove `PatientPhoneScreen` and `PatientOtpScreen` from `main.dart` role selection
    - Remove the "Patient" role card from `_RoleSelectionScreen` — patients don't log in
    - Remove `PatientLiveStatusScreen` from the navigation — replaced by `PublicQueueScreen`
    - Keep the Dart files in place (don't delete) but comment them out with a note: "Replaced by public queue flow in Phase 1 SaaS completion"
    - _Cleans up the app navigation to reflect the new patient model_

  - [x] 18.9 Update `BETA_SETUP.md` with new patient flow
    - Document the public queue URL format: `http://{server}/v1/public/queue/{clinic_id}/{doctor_id}`
    - Document that patients check queue position without any login
    - Document the record request flow: phone + email → email delivery
    - Remove references to patient OTP login from the "What's wired" table

- [x] 19. Final checkpoint — ensure all tests pass
  - Run the full test suite (`pytest`) and confirm all unit tests, property tests, and integration tests pass
  - Run `nginx -t` to verify Nginx config syntax
  - Verify Terraform plan applies cleanly (`terraform plan`)
  - Verify `GET /v1/public/queue/{clinic_id}/{doctor_id}` returns data without any auth token
  - Verify `GET /v1/public/events/queue/{clinic_id}/{doctor_id}` SSE stream does not include patient names, phone numbers, or patient IDs in any event payload
  - Verify `POST /v1/public/request-records` always returns the same response regardless of whether the phone number exists
  - Verify `POST /v1/auth/request-otp` and `POST /v1/auth/verify-otp` return 404 (removed endpoints)
  - Ensure all tests pass; ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Required property tests (Properties 5, 6, 7, 8) must be implemented alongside their parent tasks
- Each task references specific requirements for traceability
- The Hypothesis library is already present in the project (`.hypothesis/` directory exists)
- Checkpoints at tasks 11 and 19 ensure incremental validation before proceeding to the next layer
- All metering calls are fire-and-forget — Redis failures must never block the primary request path
- **No patient login — ever.** Queue info is public. Medical records are delivered by email on request. Zero SMS cost, zero OTP friction.
- **No payment gateway.** Clinics pay you directly (cash or UPI). You activate their plan via `PATCH /v1/superadmin/clinics/{id}/plan`. Add Razorpay in Phase 2 when manual management becomes a bottleneck (typically 20+ paying clinics).
- **Email config is optional.** When SMTP is not configured, record request emails are logged to the server console (dev mode). Clinics can configure SMTP later without any code changes.
- **Your billing workflow:** Clinic owner contacts you → you receive cash/UPI → you call `PATCH /v1/superadmin/clinics/{id}/plan` with `plan=starter`, `plan_status=active`, `plan_expires_at=2026-06-10`, `plan_note="Paid ₹999 UPI ref TXN123"` → done.
