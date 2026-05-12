# Requirements Document

## Introduction

CACMS (Clinic Appointment & Consultation Management System) is a multi-tenant clinic management SaaS platform. Phase 0 (cleanup) and the security/deployment foundation of Phase 1 are already complete. This spec covers the remaining commercial and SaaS layer of Phase 1: plan management, usage metering, billing via Razorpay, SMS OTP via MSG91, a super-admin API, Flutter settings and billing screens, Nginx/HTTPS infrastructure, and documentation cleanup.

The system must enforce per-plan feature limits, record usage events, integrate real payment subscriptions, and expose owner-facing and super-admin-facing management APIs — all without breaking the existing multi-tenant data isolation or authentication model.

## Glossary

- **CACMS_API**: The FastAPI backend application serving all clinic tenants.
- **Clinic**: A registered tenant identified by `clinic_id`.
- **Owner**: The `owner`-role user who registered the clinic and has full administrative rights within it.
- **Plan**: A named tier (`free`, `starter`, `clinic`, `pro`, `enterprise`) that defines feature limits for a Clinic.
- **Plan_Enforcer**: The service component that checks whether a Clinic's current plan permits a requested action or resource count.
- **Metering_Service**: The service component that records and aggregates usage events per Clinic per calendar month.
- **Usage_Event**: A single recorded occurrence of a billable or trackable action (e.g., OTP sent, appointment created, report exported).
- **Billing_Service**: The service component that manages Razorpay subscription lifecycle for a Clinic.
- **SMS_Service**: The service component that sends SMS messages via MSG91.
- **Super_Admin**: An internal operator who authenticates using a static `SUPERADMIN_TOKEN` environment variable (not a JWT).
- **Razorpay**: The third-party payment gateway used for subscription billing.
- **MSG91**: The third-party SMS gateway used for OTP delivery.
- **Webhook**: An HTTP callback sent by Razorpay to notify CACMS_API of subscription or payment events.
- **Grace_Period**: A state (`plan_status = 'grace'`) where a Clinic retains access after a payment failure, pending resolution.
- **AdminShell**: The Flutter bottom-navigation container that hosts all admin-facing screens.

---

## Requirements

### Requirement 1: Clinic Plan & Billing Fields

**User Story:** As an owner, I want my clinic record to carry plan and billing metadata, so that the system can enforce limits and display subscription status accurately.

#### Acceptance Criteria

1. THE CACMS_API SHALL add `plan` (TEXT, default `'free'`), `plan_status` (TEXT, default `'active'`), `billing_email` (TEXT, nullable), `max_doctors` (INT, nullable), and `max_staff` (INT, nullable) columns to the `clinics` table via an Alembic migration.
2. THE CACMS_API SHALL update the `Clinic` SQLAlchemy ORM model to reflect all five new columns.
3. WHEN a new clinic is registered via `POST /v1/auth/register-clinic`, THE CACMS_API SHALL set `plan = 'free'` and `plan_status = 'active'` as defaults without requiring the caller to supply them.
4. THE CACMS_API SHALL accept only the values `free`, `starter`, `clinic`, `pro`, and `enterprise` as valid plan names wherever plan is stored or validated.

---

### Requirement 2: Plan Features Configuration

**User Story:** As a developer, I want a single authoritative configuration file for plan limits, so that all enforcement logic reads from one place and plan changes require only one edit.

#### Acceptance Criteria

1. THE CACMS_API SHALL provide a `PLAN_FEATURES` dictionary in `cacms/config/plans.py` that maps each plan name to its limits and feature flags.
2. THE `PLAN_FEATURES` dictionary SHALL include the following keys for every plan: `max_doctors`, `max_staff`, `max_appointments_per_month`, `max_otps_per_month`, `can_export_reports`, `can_export_pdf`, `whatsapp_reminders`, `multi_branch`, `api_access`, `lab_integrations`.
3. THE `PLAN_FEATURES` dictionary SHALL define `free` plan limits as: `max_doctors=1`, `max_staff=3`, `max_appointments_per_month=200`, `max_otps_per_month=100`, `can_export_reports=False`, `can_export_pdf=False`, and all advanced flags (`whatsapp_reminders`, `multi_branch`, `api_access`, `lab_integrations`) set to `False`.
4. THE `PLAN_FEATURES` dictionary SHALL define progressively higher limits for `starter`, `clinic`, `pro`, and `enterprise` plans, with `enterprise` having no hard numeric caps (represented as `None`).

---

### Requirement 3: Plan Enforcer Service

**User Story:** As a clinic owner, I want the system to block actions that exceed my plan's limits and tell me to upgrade, so that I understand why an action was rejected.

#### Acceptance Criteria

1. THE CACMS_API SHALL provide a `PlanEnforcer` class in `cacms/services/plan_enforcer.py` with a `check_feature(clinic, feature_name)` method and a `check_limit(clinic, resource_name, current_count)` method.
2. WHEN `check_feature` is called with a feature that the clinic's plan does not include, THE `PlanEnforcer` SHALL raise an HTTP 402 response with `error_code = 'PLAN_LIMIT_EXCEEDED'` and a message indicating which plan upgrade is needed.
3. WHEN `check_limit` is called and `current_count` is greater than or equal to the plan's limit for that resource, THE `PlanEnforcer` SHALL raise an HTTP 402 response with `error_code = 'PLAN_LIMIT_EXCEEDED'` and a message indicating the limit and the current count.
4. WHEN `check_limit` is called and the plan's limit for that resource is `None` (unlimited), THE `PlanEnforcer` SHALL allow the action without raising an error.
5. THE CACMS_API SHALL invoke `PlanEnforcer.check_limit` for `max_doctors` before creating a new doctor record.
6. THE CACMS_API SHALL invoke `PlanEnforcer.check_limit` for `max_staff` before creating a new staff user record.

---

### Requirement 4: Usage Metering

**User Story:** As an owner, I want the system to track how many OTPs, appointments, and report exports my clinic uses each month, so that I can monitor consumption against my plan limits.

#### Acceptance Criteria

1. THE CACMS_API SHALL create a `usage_events` table with columns: `id` (UUID PK), `clinic_id` (UUID FK → clinics), `event_type` (TEXT), `quantity` (INT, default 1), `metadata` (JSONB, nullable), `billed` (BOOLEAN, default false), `created_at` (TIMESTAMPTZ, default now()) via an Alembic migration.
2. THE CACMS_API SHALL provide a `UsageEvent` SQLAlchemy ORM model in `cacms/models/usage_event.py`.
3. THE CACMS_API SHALL provide a `MeteringService` class in `cacms/services/metering_service.py` with a `record(clinic_id, event_type, quantity, metadata)` async method and a `get_monthly_usage(clinic_id, year, month)` async method.
4. WHEN `record` is called, THE `MeteringService` SHALL increment a Redis counter keyed by `usage:{clinic_id}:{event_type}:{year}:{month}` and persist a `UsageEvent` row to the database.
5. IF Redis is unavailable when `record` is called, THE `MeteringService` SHALL persist the `UsageEvent` row to the database and log a warning without raising an error to the caller.
6. WHEN `get_monthly_usage` is called, THE `MeteringService` SHALL return a dictionary of `event_type → count` for the specified clinic and month, reading from Redis when available and falling back to a database aggregate query.
7. WHEN `POST /v1/auth/request-otp` successfully generates an OTP, THE CACMS_API SHALL call `MeteringService.record` with `event_type = 'otp_sent'`.
8. WHEN `POST /v1/appointments` successfully creates an appointment, THE CACMS_API SHALL call `MeteringService.record` with `event_type = 'appointment_created'`.
9. WHEN `GET /v1/reports/daily` is called successfully, THE CACMS_API SHALL call `MeteringService.record` with `event_type = 'report_export'`.

---

### Requirement 5: Clinic Management API

**User Story:** As an owner, I want API endpoints to view and update my clinic's profile and see my current usage, so that I can manage my subscription and stay within plan limits.

#### Acceptance Criteria

1. THE CACMS_API SHALL expose `GET /v1/clinic` that returns the authenticated clinic's `clinic_id`, `name`, `plan`, `plan_status`, and `billing_email`, accessible only to the `owner` role.
2. THE CACMS_API SHALL expose `PATCH /v1/clinic` that accepts `name` (optional) and `billing_email` (optional) and updates the clinic record, accessible only to the `owner` role.
3. WHEN `PATCH /v1/clinic` is called with a `name` that is an empty string or whitespace-only, THE CACMS_API SHALL return HTTP 422 with a validation error.
4. THE CACMS_API SHALL expose `GET /v1/clinic/usage` that returns the current calendar month's usage summary as a dictionary of `event_type → count` for the authenticated clinic, accessible only to the `owner` role.
5. THE CACMS_API SHALL expose `GET /v1/clinic/plan` that returns the clinic's current plan name, plan status, the full feature limits for that plan from `PLAN_FEATURES`, and the current month's usage counts for metered resources, accessible only to the `owner` role.

---

### Requirement 6: Super-Admin API

**User Story:** As a super-admin operator, I want internal API endpoints to list clinics, change plans, and view platform statistics, so that I can manage the SaaS platform without needing a database client.

#### Acceptance Criteria

1. THE CACMS_API SHALL expose `GET /v1/superadmin/clinics`, `PATCH /v1/superadmin/clinics/{clinic_id}/plan`, and `GET /v1/superadmin/stats` endpoints protected by a static `SUPERADMIN_TOKEN` environment variable passed as a Bearer token, not by JWT.
2. WHEN a request to any `/v1/superadmin/*` endpoint is made without the correct `SUPERADMIN_TOKEN`, THE CACMS_API SHALL return HTTP 401.
3. THE CACMS_API SHALL expose `GET /v1/superadmin/clinics` that returns a paginated list of all clinics with `clinic_id`, `name`, `plan`, `plan_status`, and `created_at`.
4. THE CACMS_API SHALL expose `PATCH /v1/superadmin/clinics/{clinic_id}/plan` that accepts a `plan` field and updates the target clinic's plan; IF the `clinic_id` does not exist, THE CACMS_API SHALL return HTTP 404.
5. THE CACMS_API SHALL expose `GET /v1/superadmin/stats` that returns `total_clinics` (count of all clinics), `total_appointments_today` (count of appointments with `scheduled_date = today()` across all clinics), and `mrr_estimate` (a numeric estimate calculated from active paid subscriptions).
6. THE CACMS_API SHALL read `SUPERADMIN_TOKEN` from the application settings and raise a startup error if it is not set when `ENVIRONMENT = 'production'`.

---

### Requirement 7: Razorpay Subscription Billing

**User Story:** As an owner, I want to subscribe to a paid plan through Razorpay, so that my clinic can access premium features and the system automatically updates my plan status based on payment events.

#### Acceptance Criteria

1. THE CACMS_API SHALL add the Razorpay Python SDK to project dependencies.
2. THE CACMS_API SHALL provide a `BillingService` class in `cacms/services/billing_service.py` with `create_subscription(clinic_id, plan_name)`, `cancel_subscription(clinic_id)`, and `get_subscription_status(clinic_id)` async methods.
3. THE CACMS_API SHALL expose `GET /v1/billing/plans` that returns the list of available plans with their names, prices (in INR paise), and feature summaries, accessible without authentication.
4. THE CACMS_API SHALL expose `POST /v1/billing/subscribe` that creates a Razorpay subscription for the requested plan and returns the Razorpay subscription ID and a payment link, accessible only to the `owner` role.
5. WHEN `POST /v1/billing/subscribe` is called for a plan that is the same as the clinic's current plan, THE CACMS_API SHALL return HTTP 409 with `error_code = 'ALREADY_SUBSCRIBED'`.
6. THE CACMS_API SHALL expose `GET /v1/billing/status` that returns the clinic's current `plan`, `plan_status`, and Razorpay subscription ID if one exists, accessible only to the `owner` role.
7. THE CACMS_API SHALL expose `POST /v1/billing/webhook` that accepts Razorpay webhook payloads and verifies the `X-Razorpay-Signature` header using the `RAZORPAY_WEBHOOK_SECRET` environment variable before processing.
8. WHEN the webhook event `subscription.charged` is received and signature verification passes, THE CACMS_API SHALL set the clinic's `plan_status = 'active'` and update `plan` to the subscribed plan.
9. WHEN the webhook event `subscription.halted` is received and signature verification passes, THE CACMS_API SHALL set the clinic's `plan_status = 'grace'`.
10. WHEN the webhook event `payment.failed` is received and signature verification passes, THE CACMS_API SHALL log the failure with the clinic ID and payment details.
11. IF webhook signature verification fails, THE CACMS_API SHALL return HTTP 400 and not process the event.

---

### Requirement 8: SMS OTP Integration (MSG91)

**User Story:** As a patient, I want to receive my OTP via SMS, so that I can log in without needing to ask clinic staff for the code.

#### Acceptance Criteria

1. THE CACMS_API SHALL provide an `SMS_Service` class in `cacms/services/sms_service.py` with a `send_sms(phone, message)` async method that sends messages via the MSG91 API.
2. THE CACMS_API SHALL add `MSG91_AUTH_KEY`, `MSG91_SENDER_ID`, and `MSG91_OTP_TEMPLATE_ID` to the application settings in `cacms/config.py`.
3. WHEN `POST /v1/auth/request-otp` is called and `MSG91_AUTH_KEY` is set, THE CACMS_API SHALL call `SMS_Service.send_sms` to deliver the OTP to the patient's phone number.
4. WHEN `POST /v1/auth/request-otp` is called and `MSG91_AUTH_KEY` is not set, THE CACMS_API SHALL log the OTP to the application log at INFO level and return `{"message": "OTP sent"}` without calling MSG91.
5. IF `SMS_Service.send_sms` raises an exception due to a MSG91 API error, THE CACMS_API SHALL log the error and return HTTP 502 with `error_code = 'SMS_DELIVERY_FAILED'`.
6. THE CACMS_API SHALL remove the `print(f"[OTP STUB]...")` statement from `cacms/routers/auth.py` and replace it with the `SMS_Service` call.

---

### Requirement 9: Flutter Clinic Settings Screen

**User Story:** As an owner using the Flutter app, I want a Settings screen that shows my clinic profile, current plan, and usage, so that I can manage my clinic and understand my consumption at a glance.

#### Acceptance Criteria

1. THE CACMS_API Flutter client SHALL provide a `ClinicSettingsScreen` widget in `cacms_flutter/lib/features/admin/settings/clinic_settings_screen.dart`.
2. WHEN the `ClinicSettingsScreen` loads, THE Flutter_Client SHALL call `GET /v1/clinic` and `GET /v1/clinic/plan` and display the clinic name, plan name, plan status, and billing email.
3. THE `ClinicSettingsScreen` SHALL allow the owner to edit the clinic name and billing email and submit changes via `PATCH /v1/clinic`.
4. WHEN `PATCH /v1/clinic` returns a success response, THE Flutter_Client SHALL display a confirmation message and refresh the displayed clinic data.
5. THE `ClinicSettingsScreen` SHALL display the current month's usage for `otp_sent`, `appointment_created`, and `report_export` alongside the plan's corresponding limits.
6. THE `ClinicSettingsScreen` SHALL display an "Upgrade Plan" button that navigates to the `BillingScreen`.
7. THE `AdminShell` SHALL include a Settings tab that renders the `ClinicSettingsScreen`, visible only when the authenticated user has the `owner` role.

---

### Requirement 10: Flutter Billing Screen

**User Story:** As an owner using the Flutter app, I want a Billing screen that shows available plans and lets me subscribe, so that I can upgrade my clinic without leaving the app.

#### Acceptance Criteria

1. THE Flutter_Client SHALL provide a `BillingScreen` widget in `cacms_flutter/lib/features/admin/billing/billing_screen.dart`.
2. WHEN the `BillingScreen` loads, THE Flutter_Client SHALL call `GET /v1/billing/plans` and display each plan's name, price, and key features.
3. WHEN the `BillingScreen` loads, THE Flutter_Client SHALL call `GET /v1/billing/status` and highlight the clinic's current plan.
4. THE `BillingScreen` SHALL display the subscription status (`active`, `grace`, or `cancelled`) with a human-readable label.
5. WHEN the owner taps "Subscribe" on a plan, THE Flutter_Client SHALL call `POST /v1/billing/subscribe` and open the returned payment link in the device browser.
6. IF `POST /v1/billing/subscribe` returns HTTP 409 (`ALREADY_SUBSCRIBED`), THE Flutter_Client SHALL display a message indicating the clinic is already on that plan.
7. THE `AdminShell` SHALL include a Billing tab that renders the `BillingScreen`, visible only when the authenticated user has the `owner` role.

---

### Requirement 11: Nginx and HTTPS Setup

**User Story:** As a system operator, I want CACMS to be served over HTTPS with Nginx as a reverse proxy, so that all traffic is encrypted and the deployment meets production security standards.

#### Acceptance Criteria

1. THE Deployment SHALL provide an Nginx configuration file at `nginx/cacms.conf` that terminates TLS, proxies HTTP requests to FastAPI on `localhost:8000`, and sets `proxy_buffering off` for SSE endpoints.
2. THE Deployment SHALL update the Terraform EC2 configuration to install and enable Nginx on the provisioned instance and open port 443 in the security group.
3. THE Deployment SHALL add Let's Encrypt Certbot installation and certificate provisioning commands to `user_data.sh.tpl`.
4. THE Deployment SHALL update `DEPLOYMENT_AWS.md` with step-by-step HTTPS setup instructions covering DNS configuration, Certbot execution, and certificate renewal.
5. WHEN the Nginx configuration is applied, THE Deployment SHALL redirect all HTTP (port 80) requests to HTTPS (port 443).

---

### Requirement 12: Disable Swagger in Production

**User Story:** As a security-conscious operator, I want the Swagger and ReDoc UIs disabled in production, so that internal API documentation is not publicly accessible.

#### Acceptance Criteria

1. WHEN `ENVIRONMENT` is set to `production`, THE CACMS_API SHALL initialise FastAPI with `docs_url=None` and `redoc_url=None`.
2. WHEN `ENVIRONMENT` is not `production`, THE CACMS_API SHALL initialise FastAPI with the default Swagger UI at `/docs` and ReDoc at `/redoc`.

---

### Requirement 13: Update BETA_SETUP.md

**User Story:** As a developer onboarding to the project, I want the setup guide to reflect the current state of the codebase, so that I don't follow outdated instructions that no longer work.

#### Acceptance Criteria

1. THE `BETA_SETUP.md` SHALL remove all references to the hardcoded `admin123` password and the statement that any password works for doctors.
2. THE `BETA_SETUP.md` SHALL document the `seed_admin.py` and `scripts/create_owner.py` flows as the correct way to create initial users.
3. THE `BETA_SETUP.md` SHALL document the Flutter `ServerSetupScreen` as the recommended first-run flow for configuring the backend URL.
4. THE `BETA_SETUP.md` SHALL document the MSG91 dev-mode fallback behaviour: when `MSG91_AUTH_KEY` is not set, OTPs are logged to the server console.
