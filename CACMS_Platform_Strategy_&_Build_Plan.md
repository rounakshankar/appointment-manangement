# CACMS — Platform Strategy & Complete Build Plan

> Clinic Appointment & Consultation Management System  
> From single-clinic tool → multi-tenant SaaS platform  
> Document version: 1.0 | Stack: FastAPI + PostgreSQL + Flutter

---

## Table of Contents

1. [Product Vision](#1-product-vision)
2. [Customer Segments](#2-customer-segments)
3. [Monetization Structure](#3-monetization-structure)
4. [Technical Architecture](#4-technical-architecture)
5. [Feature Flag & Plan Enforcement](#5-feature-flag--plan-enforcement)
6. [Usage Metering System](#6-usage-metering-system)
7. [Add-on Services](#7-add-on-services)
8. [Marketplace Integrations](#8-marketplace-integrations)
9. [Operations Model](#9-operations-model)
10. [Build Roadmap — Phase by Phase](#10-build-roadmap--phase-by-phase)
11. [Database Migration Plan](#11-database-migration-plan)
12. [Revenue Projections](#12-revenue-projections)
13. [Growth & GTM Strategy](#13-growth--gtm-strategy)
14. [Risk Register](#14-risk-register)

---

## 1. Product Vision

CACMS is a vertical SaaS platform for Indian clinics — from solo practitioners to multi-branch hospital chains. The platform follows a single umbrella model: one subscription for the core platform, layered with pay-per-use add-ons and a third-party marketplace.

**Core value proposition:**
- Real-time queue management that actually works on mobile
- OTP-based patient access (no app download required)
- Billing + consultation in one workflow
- Role-based access for every clinic staff type

**The Shopify model for healthcare:** base platform subscription + usage-based add-ons + marketplace revenue share.

---

## 2. Customer Segments

### 2.1 Solo Doctor

**Profile:** MBBS/MD in private practice, 20–40 patients/day, one receptionist.

| Attribute | Detail |
|-----------|--------|
| Plan | Starter ₹999/month |
| Doctors | 1 |
| Staff | 1 receptionist |
| Queue | Single personal queue |
| Billing | Per-consultation |
| Add-ons used | OTPs, Rx PDFs |
| Typical monthly spend | ₹1,200–1,800 |
| Acquisition channel | Doctor WhatsApp groups, IMA chapters |
| Decision maker | The doctor themselves |
| Sales cycle | Self-serve, < 1 day |

**Pain points solved:** Paper registers replaced, no-show SMS reminders, digital receipts.

---

### 2.2 Small Clinic (2–5 Doctors)

**Profile:** Polyclinic or specialty clinic with shared reception and multiple consulting rooms.

| Attribute | Detail |
|-----------|--------|
| Plan | Clinic ₹2,999/month |
| Doctors | 2–5 |
| Staff | Receptionist + admin |
| Queue | Per-doctor queue + shared reception dashboard |
| Billing | Multi-service, split payment modes |
| Add-ons used | WhatsApp reminders, lab booking, reports |
| Typical monthly spend | ₹4,000–6,000 |
| Acquisition channel | Referrals, medical equipment dealers |
| Decision maker | Clinic owner/admin |
| Sales cycle | Demo call + 1 week trial |

**Pain points solved:** Inter-doctor coordination, multi-mode payment tracking, centralized patient records.

---

### 2.3 Multi-Branch / Chain

**Profile:** Group practices, diagnostic centres with outpatient wings, franchise clinics.

| Attribute | Detail |
|-----------|--------|
| Plan | Pro ₹7,999/month |
| Doctors | Unlimited |
| Staff | Branch admins + central owner view |
| Queue | Per-branch dashboards |
| Billing | Consolidated cross-branch reporting |
| Add-ons used | API access, custom exports, pharmacy tie-up |
| Typical monthly spend | ₹12,000–20,000 |
| Acquisition channel | Direct outreach, LinkedIn |
| Decision maker | Operations head or promoter |
| Sales cycle | 2–4 weeks, POC required |

---

### 2.4 Enterprise (Hospital Chains / NGOs)

**Profile:** 10+ branch hospital chains, corporate health programs, government clinics.

| Attribute | Detail |
|-----------|--------|
| Plan | Custom pricing, minimum ₹25,000/month |
| Features | White-label, on-premise option, SSO, SLA |
| Support | On-call dedicated team |
| Sales cycle | 1–3 months, legal review |

---

## 3. Monetization Structure

### 3.1 Subscription Tiers

| Plan | Price | Doctors | Staff | OTPs/month | Appointments |
|------|-------|---------|-------|------------|--------------|
| Free | ₹0 | 1 | 1 receptionist | 10 | 50 |
| Starter | ₹999 | 1 | 2 | 100 | Unlimited |
| Clinic | ₹2,999 | 5 | 10 | 500 | Unlimited |
| Pro | ₹7,999 | Unlimited | Unlimited | 2,000 | Unlimited |
| Enterprise | Custom | Unlimited | Unlimited | Custom | Unlimited |

**Free tier strategy:**
- 50 appointments = 2 real clinic days. They will hit the wall fast.
- No data exports — they can see everything, can't take it out.
- Upgrade prompt appears at 80% of limit used (email + in-app).
- No credit card required to sign up.

---

### 3.2 Pay-Per-Use Add-ons

#### Communications

| Item | Unit price | Bulk pack |
|------|-----------|-----------|
| OTP SMS | ₹0.20 / SMS | 1,000 SMS = ₹150 |
| Appointment reminder SMS | ₹0.30 / SMS | — |
| WhatsApp message (WATI/Interakt) | ₹0.50 / message | — |
| Bulk pack (1,000 messages) | ₹350 | — |

#### Documents

| Item | Unit price | Unlock option |
|------|-----------|---------------|
| Digital prescription PDF | ₹1.50 / doc | ₹499/month unlimited |
| Report export (PDF) | ₹50 / export | Included in Clinic+ |
| Bulk history export | ₹200 / run | — |
| Audit log archive | ₹199 / month | — |

#### Storage

| Item | Price |
|------|-------|
| Base storage | 2 GB free per clinic |
| Additional storage | ₹99 / GB / month |
| X-ray / scan file upload | ₹2 / file |

---

### 3.3 One-Time Fees

| Service | Price |
|---------|-------|
| Clinic onboarding & setup | ₹2,000–5,000 |
| Data migration from old system | ₹5,000–15,000 |
| Staff training session (remote) | ₹1,500 / session |
| Custom integration (Enterprise) | ₹20,000+ |

---

### 3.4 Marketplace Revenue Share

| Partner type | Revenue model | Estimated per clinic/month |
|-------------|---------------|---------------------------|
| Diagnostic labs (Thyrocare, SRL, Lal Path) | ₹20–80 referral per test booked | ₹500–2,000 |
| Pharmacy (Netmeds, PharmEasy, 1mg) | 3–8% margin per fulfilled order | ₹300–1,500 |
| Insurance / TPA | ₹50–200 per claim filed | ₹200–1,000 |
| Medical equipment | 2–5% affiliate | Occasional |

Marketplace earnings are passive once integrations are live. Target Phase 3.

---

## 4. Technical Architecture

### 4.1 Current Stack (your FastAPI app)

```
cacms/
├── main.py              # App entry point
├── config.py            # Configuration
├── database.py          # DB connection
├── models/              # SQLAlchemy models
├── schemas/             # Pydantic schemas
├── routers/             # API endpoints
├── services/            # Business logic
└── middleware/          # Custom middleware
```

### 4.2 Target Architecture

```
                        ┌─────────────────────────────────────┐
                        │           Flutter App               │
                        │  Admin | Doctor | Patient Portal    │
                        └───────────────┬─────────────────────┘
                                        │ HTTPS
                        ┌───────────────▼─────────────────────┐
                        │        Load Balancer (Nginx)         │
                        └───────────────┬─────────────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
    ┌─────────▼────────┐     ┌──────────▼────────┐    ┌──────────▼──────────┐
    │  Core API        │     │  Worker (Celery)   │    │  Report Service     │
    │  (FastAPI)       │     │  Async jobs        │    │  Heavy exports      │
    └─────────┬────────┘     └──────────┬─────────┘    └──────────┬──────────┘
              │                         │                         │
    ┌─────────▼─────────────────────────▼─────────────────────────▼──────────┐
    │                        PostgreSQL (Primary)                             │
    │                        + Read Replica (for reports)                     │
    └─────────────────────────────────────────────────────────────────────────┘
              │
    ┌─────────▼──────────┐
    │   Redis             │
    │   Queue state       │
    │   SSE pub/sub       │
    │   Usage counters    │
    └─────────────────────┘
```

### 4.3 Service Boundaries

#### Core Services (your existing FastAPI — extend these)

| Service | Responsibility | Location |
|---------|---------------|----------|
| Auth service | JWT issue/validate, OTP generation | `routers/auth.py` |
| Tenant resolver | Extract `clinic_id` from JWT, attach to request | `middleware/tenant.py` (new) |
| Appointment engine | Queue logic, priority, emergency slots | `services/appointment.py` |
| Consultation service | Service billing, diagnosis, follow-up | `services/consultation.py` |
| Patient portal | OTP login, live queue status via SSE | `routers/patient.py` |
| Audit logger | Log all write actions per clinic | `middleware/audit.py` |

#### Platform Services (add in Phase 2)

| Service | Responsibility | Tech |
|---------|---------------|------|
| Billing engine | Subscription management, invoice gen | Razorpay + webhooks |
| Notification hub | Route SMS/WhatsApp/email | WATI, Twilio, SendGrid |
| Usage metering | Count billable events per clinic | Redis counters → PostgreSQL |
| Report generator | Heavy exports, runs async | Celery + ReportLab/WeasyPrint |
| Storage manager | File uploads, CDN links | AWS S3 or GCS |
| Webhook dispatcher | Push events to Pro/Enterprise clients | Celery async |

### 4.4 Multi-Tenancy Strategy

**Recommended: Row-level tenancy with PostgreSQL Row Level Security (RLS)**

Every table gets `clinic_id`. RLS policies enforce isolation at the database level.

```sql
-- Add to every table
ALTER TABLE appointments ADD COLUMN clinic_id UUID NOT NULL;
ALTER TABLE patients ADD COLUMN clinic_id UUID NOT NULL;
ALTER TABLE consultations ADD COLUMN clinic_id UUID NOT NULL;
-- ... all tables

-- Enable RLS
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

-- Policy: users can only see their own clinic's data
CREATE POLICY clinic_isolation ON appointments
  USING (clinic_id = current_setting('app.current_clinic_id')::UUID);
```

**In your FastAPI middleware:**

```python
# middleware/tenant.py
from fastapi import Request
from sqlalchemy import text

async def tenant_middleware(request: Request, call_next):
    token = extract_jwt(request)
    clinic_id = token.get("clinic_id")
    
    async with get_db() as db:
        await db.execute(
            text("SET LOCAL app.current_clinic_id = :id"),
            {"id": str(clinic_id)}
        )
    
    request.state.clinic_id = clinic_id
    return await call_next(request)
```

---

## 5. Feature Flag & Plan Enforcement

### 5.1 Plan Features Matrix

```python
# config/plans.py

PLAN_FEATURES = {
    "free": {
        "max_doctors": 1,
        "max_staff": 1,
        "max_appointments_per_month": 50,
        "max_otps_per_month": 10,
        "can_export_reports": False,
        "can_export_pdf": False,
        "whatsapp_reminders": False,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": False,
    },
    "starter": {
        "max_doctors": 1,
        "max_staff": 2,
        "max_appointments_per_month": None,  # unlimited
        "max_otps_per_month": 100,
        "can_export_reports": True,
        "can_export_pdf": False,
        "whatsapp_reminders": False,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": False,
    },
    "clinic": {
        "max_doctors": 5,
        "max_staff": 10,
        "max_appointments_per_month": None,
        "max_otps_per_month": 500,
        "can_export_reports": True,
        "can_export_pdf": True,
        "whatsapp_reminders": True,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": True,
    },
    "pro": {
        "max_doctors": None,
        "max_staff": None,
        "max_appointments_per_month": None,
        "max_otps_per_month": 2000,
        "can_export_reports": True,
        "can_export_pdf": True,
        "whatsapp_reminders": True,
        "multi_branch": True,
        "api_access": True,
        "lab_integrations": True,
    },
}
```

### 5.2 Enforcement in Services

```python
# services/plan_enforcer.py

class PlanEnforcer:
    def __init__(self, clinic_id: UUID, db: AsyncSession):
        self.clinic_id = clinic_id
        self.db = db

    async def check_feature(self, feature: str):
        plan = await self._get_clinic_plan()
        features = PLAN_FEATURES[plan]
        if not features.get(feature):
            raise HTTPException(
                status_code=402,
                detail=f"Feature '{feature}' requires a higher plan. Upgrade at cacms.in/upgrade"
            )

    async def check_limit(self, resource: str, current_count: int):
        plan = await self._get_clinic_plan()
        limit = PLAN_FEATURES[plan].get(f"max_{resource}")
        if limit is not None and current_count >= limit:
            raise HTTPException(
                status_code=402,
                detail=f"Plan limit reached for {resource}. Upgrade to continue."
            )
```

---

## 6. Usage Metering System

This is the most critical piece to build before charging for add-ons.

### 6.1 Metering Table

```sql
CREATE TABLE usage_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id   UUID NOT NULL REFERENCES clinics(id),
    event_type  VARCHAR(50) NOT NULL,  -- 'otp_sent', 'rx_pdf_generated', 'sms_sent', 'export_run'
    quantity    INTEGER NOT NULL DEFAULT 1,
    metadata    JSONB,                 -- { "phone": "...", "patient_id": "..." }
    billed      BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_usage_clinic_month ON usage_events (clinic_id, event_type, created_at);
```

### 6.2 Metering Service

```python
# services/metering.py

class MeteringService:
    async def record(self, clinic_id: UUID, event_type: str, 
                     quantity: int = 1, metadata: dict = None):
        event = UsageEvent(
            clinic_id=clinic_id,
            event_type=event_type,
            quantity=quantity,
            metadata=metadata or {}
        )
        self.db.add(event)
        await self.db.commit()
        
        # Also increment Redis counter for real-time limit checks
        key = f"usage:{clinic_id}:{event_type}:{current_month()}"
        await redis.incr(key, quantity)
        await redis.expire(key, 90 * 86400)  # 90 days TTL

    async def get_monthly_usage(self, clinic_id: UUID, event_type: str) -> int:
        key = f"usage:{clinic_id}:{event_type}:{current_month()}"
        count = await redis.get(key)
        if count is None:
            # Fallback to DB if Redis cold
            count = await self._count_from_db(clinic_id, event_type)
        return int(count or 0)
```

### 6.3 Usage in Routers

```python
# routers/patient.py (example: OTP send)

@router.post("/otp/send")
async def send_otp(phone: str, clinic_id: UUID, 
                   metering: MeteringService = Depends(),
                   enforcer: PlanEnforcer = Depends()):
    
    current = await metering.get_monthly_usage(clinic_id, "otp_sent")
    await enforcer.check_limit("otps_per_month", current)
    
    # Send OTP
    await sms_service.send_otp(phone)
    
    # Record usage
    await metering.record(clinic_id, "otp_sent", metadata={"phone": phone})
    
    return {"status": "sent"}
```

---

## 7. Add-on Services

### 7.1 SMS / WhatsApp (Notification Hub)

**Provider:** WATI (WhatsApp), MSG91 or Textlocal (SMS)

```python
# services/notifications.py

class NotificationHub:
    async def send_sms(self, clinic_id: UUID, phone: str, message: str):
        await self.metering.record(clinic_id, "sms_sent")
        # Deduct from included quota or bill to add-on balance
        await self.msg91.send(phone, message)

    async def send_whatsapp(self, clinic_id: UUID, phone: str, 
                             template: str, params: dict):
        await self.enforcer.check_feature("whatsapp_reminders")
        await self.metering.record(clinic_id, "whatsapp_sent")
        await self.wati.send_template(phone, template, params)
```

**Appointment reminder automation:**

```python
# Celery task — runs daily at 8 AM
@celery.task
async def send_appointment_reminders():
    tomorrow = date.today() + timedelta(days=1)
    appointments = await get_appointments_for_date(tomorrow)
    
    for appt in appointments:
        clinic = await get_clinic(appt.clinic_id)
        if clinic.plan in ["clinic", "pro"] or clinic.whatsapp_credits > 0:
            await notification_hub.send_whatsapp(
                clinic_id=appt.clinic_id,
                phone=appt.patient.phone,
                template="appointment_reminder",
                params={"doctor": appt.doctor.name, "time": appt.slot_time}
            )
```

### 7.2 Prescription PDF Generator

**Library:** WeasyPrint (HTML → PDF) or ReportLab

```python
# services/prescription.py

class PrescriptionService:
    async def generate_pdf(self, consultation_id: UUID, clinic_id: UUID) -> bytes:
        await self.enforcer.check_feature("rx_pdf")
        
        consultation = await self.get_consultation(consultation_id)
        
        html = self.render_template("prescription.html", {
            "clinic": consultation.clinic,
            "doctor": consultation.doctor,
            "patient": consultation.patient,
            "medicines": consultation.medicines,
            "diagnosis": consultation.diagnosis,
            "date": consultation.created_at,
        })
        
        pdf_bytes = weasyprint.HTML(string=html).write_pdf()
        
        # Store in S3
        url = await self.storage.upload(
            key=f"prescriptions/{clinic_id}/{consultation_id}.pdf",
            data=pdf_bytes
        )
        
        # Record billable event
        await self.metering.record(clinic_id, "rx_pdf_generated", 
                                    metadata={"consultation_id": str(consultation_id)})
        
        return url
```

### 7.3 Report Exporter

Reports are heavy — run them async via Celery, email the download link.

```python
# tasks/reports.py

@celery.task(bind=True, max_retries=3)
def generate_report(self, clinic_id: str, report_type: str, 
                    date_from: str, date_to: str, user_email: str):
    try:
        data = fetch_report_data(clinic_id, report_type, date_from, date_to)
        pdf = render_report_pdf(data, report_type)
        url = upload_to_s3(pdf, clinic_id, report_type)
        send_report_email(user_email, url, report_type)
        record_usage(clinic_id, "report_export")
    except Exception as exc:
        raise self.retry(exc=exc, countdown=60)
```

---

## 8. Marketplace Integrations

### 8.1 Lab Integration Flow

```
Doctor writes order → CACMS sends to lab API → Patient gets SMS with collection info
                                              → Results uploaded to patient portal
                                              → CACMS earns referral fee
```

**Integration pattern (Thyrocare example):**

```python
# services/labs.py

class LabService:
    async def book_test(self, clinic_id: UUID, prescription_id: UUID,
                         lab_code: str, tests: list[str], 
                         patient: Patient) -> LabBooking:
        await self.enforcer.check_feature("lab_integrations")
        
        # Call lab API
        booking = await self.thyrocare_client.create_order({
            "tests": tests,
            "patient_name": patient.name,
            "patient_phone": patient.phone,
            "address": patient.address,
            "referring_clinic_id": str(clinic_id),  # for referral tracking
        })
        
        # Store booking
        await self.db.add(LabBooking(
            clinic_id=clinic_id,
            prescription_id=prescription_id,
            lab_code=lab_code,
            booking_ref=booking.reference,
            status="booked"
        ))
        
        # Metering (for referral commission tracking)
        await self.metering.record(clinic_id, "lab_referral",
                                    metadata={"lab": lab_code, "tests": tests})
        
        return booking
```

### 8.2 Pharmacy Integration

```python
# services/pharmacy.py

class PharmacyService:
    async def send_prescription(self, prescription_id: UUID, 
                                 pharmacy: str) -> PharmacyOrder:
        prescription = await self.get_prescription(prescription_id)
        
        # Convert to pharmacy API format
        order = await self.pharmacy_client(pharmacy).create_order({
            "medicines": prescription.medicines,
            "patient_phone": prescription.patient.phone,
            "delivery_address": prescription.patient.address,
            "clinic_referral_id": str(prescription.clinic_id),
        })
        
        return order
```

---

## 9. Operations Model

### 9.1 Onboarding Flow

```
Day 0    → Clinic signs up → Free tier auto-activated → Welcome email sent
Day 1–3  → Hit appointment limit → Upgrade prompt shown (in-app + email)
Week 1   → For Clinic+ plans: setup call scheduled
           Data migration from existing Excel/paper system
           Staff accounts created and trained
Week 2   → Go-live on paid plan
Month 1  → Success check-in call
           Upsell review: are they close to doctor/staff limit?
Month 3  → Expansion check: multiple branches? → Pro pitch
```

### 9.2 Support Tiers

| Plan | Channel | SLA |
|------|---------|-----|
| Free | Docs + community forum | No SLA |
| Starter | Email | 48h response |
| Clinic | Email + WhatsApp | 12h response |
| Pro | Dedicated CSM + WhatsApp | 4h response |
| Enterprise | On-call + phone | Custom SLA |

### 9.3 Billing Operations

**Subscription billing with Razorpay:**

1. Clinic selects plan → Razorpay subscription created
2. Monthly auto-charge on renewal date
3. Webhook `subscription.charged` → update `clinic.plan_status = active`
4. Webhook `subscription.halted` → downgrade to Free after 7-day grace
5. Add-on usage billed monthly as additional invoice

**Invoice structure:**
- Line 1: Base subscription (Starter/Clinic/Pro)
- Line 2+: Add-on usage (OTPs over quota, PDFs generated, storage)
- GST 18% applied on all

### 9.4 Churn Prevention

| Signal | Trigger | Action |
|--------|---------|--------|
| 0 appointments in 7 days | Automated | "Are you okay?" check-in email |
| Usage dropped 50% | Automated | CSM call (Clinic+) |
| Approaching plan limit | 80% used | Upgrade nudge email + in-app |
| Payment failed | Webhook | Retry + grace period notification |
| Renewal in 7 days | Scheduled | Summary of value email |

---

## 10. Build Roadmap — Phase by Phase

### Phase 0 — Cleanup (Before anything else) — 1 week

**Goal:** Make existing codebase production-ready as a single-clinic app.

- [ ] Add proper error handling to all routers (try/catch + structured error responses)
- [ ] Add request validation with Pydantic v2
- [ ] Set up Alembic migrations properly (ensure `alembic_version` table is consistent)
- [ ] Add basic logging (Python `logging` module → Sentry)
- [ ] Write `.env.example` with all required variables documented
- [ ] Add health check endpoint `GET /health`
- [ ] Set up pytest fixtures for all models
- [ ] Docker Compose for local dev (app + postgres + redis)

---

### Phase 1 — Multi-Tenancy Foundation — 3–4 weeks

**Goal:** Transform single-clinic app into a multi-tenant platform.

#### Week 1 — Data model

- [ ] Add `clinics` table (id, name, plan, plan_status, created_at, billing_email)
- [ ] Add `clinic_id` (UUID, NOT NULL) to every existing table:
  - `users`, `patients`, `appointments`, `consultations`, `payments`, `audit_logs`
- [ ] Create and run Alembic migrations
- [ ] Enable PostgreSQL Row Level Security on all tables
- [ ] Write RLS policies for each table
- [ ] Add `tenant_id` to JWT payload during auth

#### Week 2 — Middleware & enforcement

- [ ] Build `TenantMiddleware` — extracts `clinic_id` from JWT, sets PG session variable
- [ ] Build `PlanEnforcer` class (see Section 5)
- [ ] Add `PLAN_FEATURES` config dict
- [ ] Add `UsageEvent` model and `usage_events` table
- [ ] Build `MeteringService` with Redis + DB fallback (see Section 6)
- [ ] Wire metering into OTP send, appointment create, export endpoints

#### Week 3 — Subscription billing

- [ ] Install `razorpay` Python SDK
- [ ] Create Razorpay plans for each tier (Starter/Clinic/Pro)
- [ ] Build `POST /billing/subscribe` endpoint
- [ ] Build webhook handler `POST /billing/webhook`
  - Handle: `subscription.charged`, `subscription.halted`, `payment.failed`
- [ ] Build `GET /billing/usage` endpoint (current month breakdown)
- [ ] Upgrade prompt API `GET /billing/upgrade-options`

#### Week 4 — Admin portal

- [ ] Super-admin panel (your internal tool, not customer-facing):
  - List all clinics + plan + MRR
  - Manually change a clinic's plan
  - View usage per clinic
  - Impersonate a clinic for support
- [ ] Build clinic self-serve billing page in Flutter app
  - Current plan, usage this month, upgrade button

**Deliverable:** Multiple clinics can sign up, each isolated, billing charges correctly.

---

### Phase 2 — Add-ons & Notifications — 4–6 weeks

**Goal:** Launch SMS, WhatsApp, and PDF add-ons. Make them billed automatically.

#### Communications

- [ ] Integrate MSG91 (SMS) — OTP + reminder
- [ ] Integrate WATI (WhatsApp Business API)
- [ ] Build `NotificationHub` service (see Section 7.1)
- [ ] Appointment reminder Celery task (daily @ 8 AM)
- [ ] SMS credit top-up flow (add credits to clinic account)
- [ ] Monthly invoice includes SMS overage

#### Documents

- [ ] Set up WeasyPrint or ReportLab
- [ ] Design prescription PDF template (clinic logo, doctor reg. number, Rx symbol)
- [ ] Build `PrescriptionService.generate_pdf()` (see Section 7.2)
- [ ] Store PDFs in AWS S3 / Google Cloud Storage
- [ ] Patient receives WhatsApp link to download Rx
- [ ] Build async report exporter via Celery (see Section 7.3)
- [ ] Email delivery of completed reports

#### Infrastructure

- [ ] Set up Redis (AWS ElastiCache or self-hosted)
- [ ] Migrate SSE queue updates to Redis pub/sub (supports multiple app instances)
- [ ] Set up Celery + Redis broker
- [ ] Set up S3 bucket + IAM roles for file storage

**Deliverable:** Clinics can receive reminders, get PDFs, and are billed for usage automatically.

---

### Phase 3 — Marketplace & Scale — 6–8 weeks

**Goal:** Launch lab and pharmacy integrations. Enable Pro/Enterprise features.

#### Lab integrations

- [ ] Research and shortlist lab APIs (Thyrocare has a partner program)
- [ ] Build `LabService` with pluggable provider pattern (see Section 8.1)
- [ ] Lab booking UI in Flutter (doctor → order tests after consultation)
- [ ] Patient notification (collection time, sample pickup)
- [ ] Lab result upload → patient portal
- [ ] Referral tracking → monthly payout from lab

#### Pharmacy

- [ ] Integrate PharmEasy / 1mg referral API
- [ ] "Send to pharmacy" button after prescription
- [ ] Order status tracking webhook
- [ ] Commission tracking in metering table

#### Multi-branch (Pro feature)

- [ ] `branches` table linked to clinic
- [ ] Branch-level admin role
- [ ] Cross-branch reporting dashboard
- [ ] Central billing for all branches

#### API & webhooks (Pro/Enterprise)

- [ ] Generate API keys per clinic
- [ ] Rate-limited public API (appointments, patients, queue status)
- [ ] Webhook event dispatcher (Celery async)
- [ ] Webhook management UI (register URL, test payload, view logs)

#### Scale infrastructure

- [ ] Set up load balancer (Nginx + 2 app instances)
- [ ] PostgreSQL read replica for report queries
- [ ] Prometheus + Grafana for metrics
- [ ] Sentry for error tracking (already in Phase 0)
- [ ] CloudFlare CDN for Flutter web assets

**Deliverable:** Full marketplace, Pro features live, infrastructure handles 100+ clinics.

---

### Phase 4 — Enterprise & White-label — Ongoing

- [ ] White-label option (custom domain, logo, colour scheme per clinic)
- [ ] HIPAA/DPDP compliance audit and documentation
- [ ] On-premise deployment option (Docker Compose + setup guide)
- [ ] SSO integration (SAML 2.0 / Google Workspace)
- [ ] Custom roles and permissions editor
- [ ] BI export (connect clinic data to their own analytics tools)
- [ ] Dedicated infrastructure per enterprise client

---

## 11. Database Migration Plan

### Migration order (do this in order, no skipping)

```
Step 1: Add clinics table
Step 2: Add clinic_id column (nullable) to all tables
Step 3: Create one default clinic, assign all existing data to it
Step 4: Make clinic_id NOT NULL
Step 5: Add indexes on clinic_id for all tables
Step 6: Enable RLS
Step 7: Test all existing endpoints still work (regression)
Step 8: Deploy tenant middleware
```

### Migration script skeleton

```python
# alembic/versions/0002_add_multitenancy.py

def upgrade():
    # Step 1
    op.create_table('clinics',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('plan', sa.String(), nullable=False, server_default='free'),
        sa.Column('plan_status', sa.String(), nullable=False, server_default='active'),
        sa.Column('billing_email', sa.String()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
    )
    
    # Step 2: Add clinic_id nullable first
    op.add_column('appointments', sa.Column('clinic_id', sa.UUID(), nullable=True))
    op.add_column('patients', sa.Column('clinic_id', sa.UUID(), nullable=True))
    # ... all tables
    
    # Step 3: Create default clinic and assign data
    op.execute("""
        INSERT INTO clinics (id, name, plan) 
        VALUES ('00000000-0000-0000-0000-000000000001', 'Default Clinic', 'starter');
        
        UPDATE appointments SET clinic_id = '00000000-0000-0000-0000-000000000001';
        UPDATE patients SET clinic_id = '00000000-0000-0000-0000-000000000001';
    """)
    
    # Step 4: Make NOT NULL
    op.alter_column('appointments', 'clinic_id', nullable=False)
    op.alter_column('patients', 'clinic_id', nullable=False)
    
    # Step 5: Indexes
    op.create_index('idx_appointments_clinic', 'appointments', ['clinic_id'])
    op.create_index('idx_patients_clinic', 'patients', ['clinic_id'])
```

---

## 12. Revenue Projections

### Conservative scenario (12 months)

| Month | Free | Starter | Clinic | Pro | MRR |
|-------|------|---------|--------|-----|-----|
| 1 | 20 | 5 | 1 | 0 | ₹7,994 |
| 3 | 60 | 20 | 5 | 1 | ₹38,974 |
| 6 | 150 | 60 | 20 | 5 | ₹1,39,880 |
| 9 | 300 | 120 | 50 | 15 | ₹3,47,850 |
| 12 | 500 | 200 | 100 | 30 | ₹6,39,700 |

Add-ons and marketplace add ~25–40% on top of subscription MRR by month 6.

### Revenue per customer (lifetime)

| Segment | ARPU/month | Avg. retention | LTV |
|---------|-----------|----------------|-----|
| Starter | ₹1,300 | 18 months | ₹23,400 |
| Clinic | ₹4,800 | 30 months | ₹1,44,000 |
| Pro | ₹14,000 | 48 months | ₹6,72,000 |

---

## 13. Growth & GTM Strategy

### Acquisition channels (priority order)

1. **Doctor WhatsApp groups** — Demo videos (60 seconds), free trial link. High density, zero cost.
2. **IMA (Indian Medical Association) chapter partnerships** — Bulk deals, co-branded webinars.
3. **Medical equipment dealers** — They visit clinics weekly. Referral commission ₹500–2,000 per sign-up.
4. **Content SEO** — "clinic management software India", "appointment booking system for doctors"
5. **Google Ads** — Target "clinic software", "OPD management system" (Phase 2+)

### Referral program

- Existing clinic refers a new clinic → ₹500 credit on next invoice
- Referred clinic gets first month 50% off
- Track via referral code in sign-up URL

### Upgrade triggers (automated)

- Email at 80% of free quota used
- In-app banner at 90% of quota used
- Block at 100% with upgrade CTA (not silent failure)
- Monthly value summary email ("You served 487 patients this month")

---

## 14. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Multi-tenancy data leak (wrong clinic_id) | Low | Critical | RLS at DB level + integration tests per tenant |
| Razorpay payment failure cascade | Medium | High | Grace period + retry logic + manual override |
| SMS provider downtime | Medium | Medium | Multi-provider fallback (MSG91 → Twilio) |
| DPDP (India data protection law) compliance | High | High | Data residency in India (Mumbai region), consent logging |
| Free tier abuse (fake clinics) | High | Low | Phone verification on signup, rate limit API |
| Key doctor churns (takes clinic with them) | Medium | Medium | Clinic-level account ownership, not doctor-level |
| Competition (Practo, ClinicSpots) | High | Medium | Focus on small clinics they ignore, local support |
| Lab partner API changes | Low | Medium | Adapter pattern — swap provider without core changes |

---

## Appendix: Quick Reference

### Environment variables needed

```bash
# Core
DATABASE_URL=postgresql+asyncpg://user:pass@host/dbname
REDIS_URL=redis://localhost:6379/0
SECRET_KEY=your-jwt-secret
ENVIRONMENT=production

# Billing
RAZORPAY_KEY_ID=rzp_live_xxx
RAZORPAY_KEY_SECRET=xxx
RAZORPAY_WEBHOOK_SECRET=xxx

# SMS
MSG91_AUTH_KEY=xxx
MSG91_SENDER_ID=CACMS

# WhatsApp
WATI_API_ENDPOINT=https://live-server.wati.io
WATI_ACCESS_TOKEN=xxx

# Storage
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx
AWS_S3_BUCKET=cacms-files
AWS_REGION=ap-south-1

# Monitoring
SENTRY_DSN=https://xxx@sentry.io/xxx
```

### Celery task schedule

```python
# config/celery_schedule.py

CELERYBEAT_SCHEDULE = {
    "appointment-reminders": {
        "task": "tasks.send_appointment_reminders",
        "schedule": crontab(hour=8, minute=0),  # Daily 8 AM
    },
    "usage-billing-sync": {
        "task": "tasks.sync_usage_to_billing",
        "schedule": crontab(day_of_month=1, hour=2),  # Monthly, 2 AM
    },
    "free-tier-nudge": {
        "task": "tasks.send_upgrade_nudges",
        "schedule": crontab(hour=10, minute=0),  # Daily 10 AM
    },
}
```

### Key API endpoints to build (new)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/auth/clinic/register` | New clinic signup |
| GET | `/billing/plans` | List available plans |
| POST | `/billing/subscribe` | Start subscription |
| POST | `/billing/webhook` | Razorpay webhook receiver |
| GET | `/billing/usage` | Current month usage summary |
| GET | `/admin/clinics` | Super-admin: list all clinics |
| POST | `/admin/clinics/{id}/plan` | Super-admin: change plan |
| POST | `/notifications/otp` | Send OTP (metered) |
| POST | `/prescriptions/{id}/pdf` | Generate Rx PDF (metered) |
| POST | `/labs/book` | Book lab test |
| GET | `/marketplace/labs` | Available lab partners |

---

*Last updated: based on CACMS v1 README. Update this document as the platform evolves.*
