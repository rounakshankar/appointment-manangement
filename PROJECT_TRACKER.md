# CACMS Project Tracker

Last updated: 2026-05-09

## Current Project Status

CACMS is currently in **beta/MVP stage**. The core clinic workflow is functional: admin/reception can register patients and create appointments, doctors can manage queues and record consultations, patients can check live appointment status, and payments/services are connected at a basic level.

The next major goal is to move from **working beta** to **sellable clinic pilot**, then from pilot to **production SaaS/local deployment**.

## Product Direction

CACMS is being built as a clinic management system for:

- Appointment booking
- Live queue management
- Doctor consultation workflow
- Patient status tracking
- Basic billing and services
- Local, cloud, and future hybrid deployment
- Later EMR/module-based clinic packages

## What Has Been Done

### Backend Core

| Area | Status | Notes |
|---|---|---|
| FastAPI backend setup | Done | Main API app is available through `cacms.main`. |
| PostgreSQL integration | Done | Uses async SQLAlchemy and asyncpg. |
| Alembic migrations | Done | Initial schema and later clinic/user-related migration exists. |
| Health endpoint | Done | `/health` returns server status. |
| Environment config | Partial | `.env` support exists, but production config needs hardening. |
| API version prefix | Done | Routes are mounted under `/v1`. |

### Authentication

| Area | Status | Notes |
|---|---|---|
| JWT token creation | Done | Backend issues JWT tokens. |
| Admin login | Beta Done | Works, but beta setup mentions hardcoded/default credentials. |
| Doctor login | Beta Done | Works, but password enforcement is MVP-grade. |
| Patient OTP login | Beta Done | OTP flow exists. OTP is currently printed/stubbed, not sent by SMS. |
| Role foundation | Partial | Admin, doctor, patient roles are used. Full RBAC is not finished. |

### Patient And Appointment Workflow

| Area | Status | Notes |
|---|---|---|
| Patient registration | Done | API and Flutter UI are wired. |
| Patient lookup | Done | Lookup by phone/details exists. |
| Appointment creation | Done | Supports normal, follow-up, and emergency. |
| Queue number assignment | Done | Queue logic has integration/property tests. |
| Emergency priority | Done | Emergency appointment can move to front of queue. |
| Follow-up conflict handling | Done | Prevents duplicate follow-up for same patient/doctor/date. |
| Appointment cancellation | Done | API and UI support cancellation. |
| No-show marking | Done | API and UI support no-show. |

### Queue And Live Status

| Area | Status | Notes |
|---|---|---|
| Doctor queue dashboard | Done | Flutter screen and backend API exist. |
| Admin/reception queue dashboard | Done | Admin queue screen exists. |
| Call next patient | Done | Atomic queue advancement is implemented. |
| Live queue updates | Done | Uses server-sent events. |
| Patient live status | Done | Patient can see status and queue info. |
| SSE reconnect/replay | Done | Last-Event-ID replay support exists. |
| Multi-server event scaling | Not Done | Current SSE bus is in-process and should move to Redis for horizontal scaling. |

### Consultation And Billing

| Area | Status | Notes |
|---|---|---|
| Consultation recording | Done | Doctor can record diagnosis/notes. |
| Consultation services | Done | Services/tests/procedures can be attached. |
| Follow-up prompt | Done | Follow-up booking flow exists after consultation. |
| Payment recording | Done | Payment can be recorded against consultation. |
| Payment modes | Done | Supports cash, UPI, card. |
| Payment statuses | Done | Supports pending, paid, partial. |
| Receipt/print workflow | Not Done | Needed for real clinic operations. |

### Admin Management

| Area | Status | Notes |
|---|---|---|
| Doctor management | Done | Add/edit/activate/deactivate doctors. |
| Service management | Done | Add/edit/activate/deactivate services. |
| Patient management | Done | Patient lookup and registration screens exist. |
| User/staff management | Not Done | Real owner/admin/staff user management is still needed. |
| Clinic settings | Not Done | Needed before multi-clinic deployment. |

### Flutter App

| Area | Status | Notes |
|---|---|---|
| Admin login screen | Done | Uses API. |
| Admin shell/navigation | Done | Queue, doctors, services, patients tabs. |
| Doctor login screen | Done | Uses API. |
| Doctor queue screen | Done | Includes SSE live updates. |
| Consultation screen | Done | Supports diagnosis, notes, services. |
| Patient phone/OTP screens | Done | Uses OTP API. |
| Patient live status screen | Done | Includes live status and visit summary. |
| Token storage | Done | Uses secure storage. |
| Configurable backend URL | Partial | Supports dart define, but production setup needs smoother configuration. |

### Testing

| Area | Status | Notes |
|---|---|---|
| Backend integration tests | Done | Queue, follow-up, appointment flow tests exist. |
| Property tests | Done | Queue and business rules have property-style coverage. |
| Flutter tests | Partial | Some Flutter tests exist, but production UI coverage should grow. |
| Load testing | Not Done | Needed before claiming scale. |
| Security testing | Not Done | Needed before production clinics. |

### Business And Planning Docs

| Area | Status | Notes |
|---|---|---|
| Deployment spec | Done | `DEPLOYMENT_SPEC_SHEET.md` exists. |
| Beta setup guide | Done | `BETA_SETUP.md` exists. |
| Sales document | Done | `CACMS_SALES_POINT_DOCUMENT.md` exists. |
| Project tracker | Done | This document. |

## What Is Going On Now

The project is moving from **technical beta** to **clinic pilot readiness**. The first production-readiness sprint has started and the backend now has a stronger foundation for staff authentication, staff management, clinic isolation, reports, backup status, basic exports, and cloud deployment preparation.

Current focus should be:

- Make the app safe enough for 3-4 real clinic pilots.
- Remove beta-grade authentication shortcuts.
- Decide first deployment mode: cloud-first, local-first, or both.
- Prepare backup and restore strategy.
- Create a simple pricing/package model.
- Collect workflow feedback from early clinics.

## What Needs To Be Done Next

### Priority 1 - Must Do Before Real Clinic Pilot

| Task | Status | Why It Matters |
|---|---|---|
| Replace hardcoded admin credential | Pending | Real clinics need secure login. |
| Enforce doctor password login | Backend Done | Doctor users now authenticate through the users table and must be linked to a doctor record. Flutter login wiring should be rechecked. |
| Add real users/staff management | Backend Done | `/v1/users` supports owner/admin staff listing, creation, and update. |
| Add backend-enforced RBAC | Partial | Role dependencies exist and key routes were tightened. Fine-grained permissions are still needed. |
| Add clinic_id to all business data | Partial | Existing core models have `clinic_id`; tenant-aware constraints were added for patients and queue numbers. |
| Ensure every query filters by clinic_id | Partial | Core patient, doctor, service, appointment, consultation, payment, report, and export paths now scope by clinic. A full audit is still recommended before production. |
| Add production CORS config | Pending | Needed for safe cloud deployment. |
| Add backup and restore process | Backend Done | `scripts/backup_postgres.py`, `scripts/restore_postgres.py`, and `/v1/ops/backup-status` were added. Encryption/cloud upload still needs implementation. |
| Add logs export / error visibility | Pending | Makes after-sales support possible. |
| Add database seed/setup flow | Partial | `scripts/create_owner.py` can bootstrap or reset an owner account. |

### Priority 2 - Sellable Product Improvements

| Task | Status | Why It Matters |
|---|---|---|
| SMS/WhatsApp OTP integration | Pending | Real patient login cannot rely on console OTP. |
| Prescription module | Pending | High-value doctor-facing feature. |
| Print prescription/receipt | Backend Foundation | Plain-text receipt and consultation summary export endpoints exist. PDF/print templates still need work. |
| Daily reports | Backend Done | `/v1/reports/daily` returns appointment counts and collection totals. |
| Payment reports | Pending | Helps clinic reconcile cash/UPI/card. |
| Appointment reminder | Pending | Reduces no-shows. |
| Patient visit history | Partial | Last visit is shown, but full searchable history is needed. |
| File upload/attachments | Pending | Needed for reports, scans, diagnostics. |
| Owner dashboard | Pending | Useful for sales and retention. |

### Priority 3 - Scaling And SaaS Readiness

| Task | Status | Why It Matters |
|---|---|---|
| Move SSE fan-out to Redis | Pending | Needed for multiple API servers. |
| Add PgBouncer | Pending | Protects PostgreSQL under growing traffic. |
| Add monitoring and alerts | Pending | Required for cloud reliability. |
| Add deployment pipeline | Pending | Reduces risky manual deploys. |
| Add object storage abstraction | Pending | Needed for attachments and cloud backup. |
| Add tenant/module subscription system | Pending | Supports package-based SaaS pricing. |
| Add license/subscription enforcement | Pending | Important for commercial rollout. |
| Add load tests | Pending | Needed before scaling claims. |

### Priority 4 - Future Modules

| Module | Status | Notes |
|---|---|---|
| Diagnostics/lab orders | Planned | Useful for specialty clinics. |
| Pharmacy | Planned | Add-on package. |
| Inventory | Planned | Add-on package. |
| Advanced EMR | Planned | Specialty-specific templates. |
| Neuro/EEG module | Planned | Mentioned in deployment direction. |
| Multi-branch | Planned | Needed for larger clinic groups. |
| Hybrid sync | Future | Local-first plus cloud backup/sync. |

## Suggested Roadmap

### Phase 1 - Pilot Ready

Target: 3-4 clinics.

- Secure login and staff users.
- Clinic isolation with `clinic_id`.
- Backup and restore.
- Production deployment setup.
- Basic reports.
- Print prescription/receipt.
- SMS/WhatsApp OTP or at least production OTP provider.

### Phase 2 - Early SaaS

Target: 10-20 clinics.

- Managed PostgreSQL or separated DB server.
- Monitoring and alerts.
- Owner dashboard.
- Better reports.
- Module/package controls.
- Cloud backup.
- Support tools: logs export, health page, version info.

### Phase 3 - Scale

Target: 50+ clinics / 10k registered users.

- Multiple API servers.
- Redis event bus.
- PgBouncer.
- Object storage.
- Automated CI/CD.
- Load testing.
- Advanced RBAC.
- Audit reports.
- Subscription/licensing system.

## Current Technical Risks

| Risk | Severity | Notes |
|---|---|---|
| Beta authentication shortcuts | High | Must be fixed before real production use. |
| Missing full multi-clinic isolation | High | Critical for cloud SaaS. |
| No production backup/restore flow | High | Clinics will blame vendor if data is lost. |
| In-process SSE event bus | Medium | Fine for one server, not for horizontal scaling. |
| No load testing yet | Medium | Need real numbers before scale promises. |
| Limited reporting | Medium | Owners will expect reports quickly. |
| No print workflow | Medium | Clinic operations often depend on printing. |

## Recommended Immediate Next Sprint

1. Wire Flutter admin UI to staff management and daily reports.
2. Replace beta login assumptions in Flutter with real user-table authentication.
3. Add PDF templates for receipt and consultation/prescription output.
4. Add backup encryption and optional cloud upload.
5. Add logs export and health dashboard in admin.
6. Complete full tenant-isolation audit across all backend queries and tests.
7. Add production CORS/domain configuration and deployment automation.

## Definition Of Sellable Pilot

CACMS is ready for paid pilot when:

- A clinic can log in securely.
- Reception can register/search patients and book appointments.
- Doctor can run daily queue and record consultation.
- Patient can see queue/status.
- Payment can be recorded.
- Clinic data is backed up daily.
- Admin can restore data if needed.
- Basic reports are available.
- Support can debug issues using logs.
- Data from one clinic cannot be accessed by another clinic.
