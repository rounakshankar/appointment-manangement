# CACMS Deployment Spec Sheet

## 1. Product Goal

Build a modular clinic management and EMR system that can run in:

- Local Server Mode
- Cloud Server Mode
- Future Hybrid Mode

The system should support:

- Small clinics with appointment, queue, basic EMR, and billing.
- Medium or unorganized clinics with structured EMR, services, diagnostics, pharmacy, inventory, and reports.
- Specialty clinics such as neuro, ortho, dental, gynae, etc.
- Module-based packages where features can be switched on or off as per clinic need.

## 2. Deployment Modes

### Local Server Mode

Best for clinics with poor internet or strong data-control preference.

Must support:

- Backend running on clinic PC or mini server.
- PostgreSQL running locally.
- Flutter apps connecting over LAN/Wi-Fi.
- Daily operations without internet.
- Local encrypted backups.
- Optional cloud backup.

Required changes:

- Configurable backend URL in Flutter app.
- Local installer or setup script.
- Backend service installation.
- PostgreSQL setup automation.
- Backup and restore tool.
- Local HTTPS support where possible.

### Cloud Server Mode

Best for clinics needing remote access, multi-branch support, automatic backups, and easier updates.

Must support:

- Hosted FastAPI backend.
- PostgreSQL cloud or managed database.
- HTTPS domain.
- Automated backups.
- Cloud file storage.
- Monitoring.
- Secure deployment pipeline.

Required changes:

- Environment-based settings.
- Production CORS configuration.
- HTTPS-only deployment.
- Cloud backup policy.
- File storage abstraction.

### Future Hybrid Mode

Not required immediately.

Later support:

- Local-first daily operations.
- Cloud backup and sync.
- Remote owner dashboard.
- Conflict-safe sync.

## 3. Core Architecture Changes

The current app is single-clinic style. For deployment, convert it into a multi-clinic, module-controlled system.

Add these core concepts:

```text
clinics
branches
users
roles
permissions
modules
clinic_module_subscriptions
clinic_settings
```

Most business tables should include:

```text
clinic_id
branch_id
created_by
updated_by
created_at
updated_at
```

Tables that need `clinic_id`:

- patients
- doctors
- appointments
- consultations / visits
- services
- payments
- prescriptions
- diagnostic orders
- attachments
- audit logs
- inventory
- pharmacy
- users

## 4. Authentication And Users

Current auth is MVP-grade and must be replaced before real deployment.

Required:

- Real `users` table.
- Password hashes using bcrypt or Argon2id.
- No hardcoded admin password.
- No doctor login with any password.
- User active/inactive status.
- Password reset/change flow.
- Session timeout.
- Role-based access.

Suggested roles:

```text
Owner
Admin
Doctor
Receptionist
Cashier
EEG Technician
Lab Technician
Pharmacist
Auditor
```

Optional later:

- PIN login for quick clinic workflow.
- Two-factor authentication for owner/admin.
- Device/session management.

## 5. Role-Based Access Control

Access must be enforced from the backend, not only hidden in the UI.

Example permissions:

```text
patients.create
patients.view_basic
patients.view_emr
appointments.create
appointments.cancel
consultations.create
prescriptions.create
billing.create
billing.refund
reports.view
settings.manage
users.manage
audit.view
```

Role examples:

Receptionist:

- Register patient.
- Book appointment.
- View queue.
- View basic patient information.

Doctor:

- View EMR.
- Record consultation.
- Create prescription.
- Order diagnostics.
- View reports.

Cashier:

- View bill.
- Record payment.
- Print receipt.

EEG technician:

- View EEG orders.
- Update EEG status.
- Upload EEG report.

Owner/Admin:

- Manage users.
- Manage services.
- View reports.
- Configure modules.

## 6. Module And Package System

This is critical for the business model.

Add module control:

```text
appointments
queue
emr_core
prescription
billing
diagnostics
eeg
lab
pharmacy
inventory
attachments
followup_reminders
analytics
multi_branch
audit
cloud_backup
```

Example package: Starter Clinic

```text
appointments = on
queue = on
basic_consultation = on
basic_billing = on
prescription = off
diagnostics = off
```

Example package: Neuro Clinic

```text
appointments = on
queue = on
emr_core = on
prescription = on
billing = on
diagnostics = on
eeg = on
attachments = on
surgery_referral = on
```

Example package: Enterprise

```text
all core modules = on
multi_branch = on
analytics = on
advanced_audit = on
integrations = on
```

Backend must check module access before serving module APIs.

## 7. Data Security Requirements

This is the most important deployment requirement.

Must-have:

- Strong user login.
- Role-based access.
- HTTPS for cloud.
- Secure local network setup.
- Full disk encryption guidance for local server.
- Encrypted backups.
- Audit logs.
- Secure file storage.
- Database credentials not hardcoded.
- JWT secret generated per deployment.

For local deployment:

- Use BitLocker on Windows or LUKS on Linux.
- Randomize PostgreSQL password during install.
- Lock backend config file permissions.
- Create daily encrypted database backup.
- Create encrypted attachment backup.

For cloud deployment:

- HTTPS only.
- Database not publicly exposed.
- Firewall/security groups.
- Rate limiting.
- Managed backups.
- Object storage access control.
- Monitoring/logging.

## 8. Backup And Restore

This is mandatory before clinic deployment.

Required backup system:

- Daily automatic encrypted backup.
- Manual backup button.
- Backup status screen.
- Restore tool.
- Backup retention policy.
- Optional cloud backup upload.
- Alert if backup fails.

Backup should include:

```text
PostgreSQL database
uploaded reports/files
configuration
license/module settings
```

Backup files should be encrypted:

```text
clinic_backup_2026-04-19.dump.enc
attachments_backup_2026-04-19.zip.enc
```

Owner/admin screen should show:

```text
Last backup: Today 2:00 AM
Backup status: Successful
Cloud backup: Enabled/Disabled
Last restore test: date
```

## 9. Audit Logging

Current audit log exists, but it needs improvement.

Required audit events:

- Login/logout.
- Failed login.
- Patient created/viewed/updated.
- Appointment created/cancelled/no-show.
- Consultation created/viewed.
- Prescription created/printed.
- EEG/report uploaded/viewed/downloaded.
- Payment created/refunded/edited.
- User created/permission changed.
- Backup exported/restored.
- Settings changed.

Important:

- Do not store full sensitive request payloads without masking.
- Mask phone numbers where needed.
- Never log passwords, OTPs, tokens, or full medical notes unnecessarily.

## 10. EMR Core Upgrade

Current consultation schema is too basic for real EMR.

Add:

```text
patient_cases
visits / enhanced consultations
vitals
diagnoses
prescriptions
prescription_items
patient_allergies
patient_medical_history
patient_attachments
followup_plans
```

For long-term patients:

```text
case_id
patient_id
primary_diagnosis
case_start_date
condition_status
active
```

This is important for chronic neuro, diabetes, cardiac, ortho, and other long-term cases.

## 11. Prescription Module

Must-have for real clinic use.

Required:

- Create prescription.
- Repeat previous prescription.
- Continue/change/stop medicine.
- Dosage/frequency/duration/instructions.
- Print/share prescription.
- Medicine favorites/templates.
- Long-term medicine history.

Tables:

```text
prescriptions
prescription_items
medicine_catalog
doctor_favorite_medicines
```

## 12. Diagnostics And EEG Module

Required for neuro clinic and future specialty modules.

Required:

- Diagnostic order.
- Service selection: EEG, consultation, etc.
- Status: ordered, scheduled, in-progress, completed, reviewed.
- Report upload.
- Doctor review.
- Billing link.
- Patient report history.

Tables:

```text
diagnostic_orders
diagnostic_reports
```

For EEG:

```text
order_type = EEG
report_file
summary
technician_id
reviewed_by_doctor_id
```

## 13. Surgery And External Referral Tracking

For doctors who operate at another hospital/place.

Required:

- Surgery advised.
- Procedure name.
- Referred hospital/place.
- Planned date.
- Status.
- Completed date.
- Discharge summary upload.
- Post-op follow-up notes.

Tables:

```text
surgery_referrals
external_procedure_records
```

Statuses:

```text
advised
planned
completed
cancelled
followup_required
```

## 14. Billing Upgrade

Current payment is basic. For deployment, improve billing.

Required:

- Invoice number.
- Receipt number.
- Service line items.
- Discount.
- Paid amount.
- Due amount.
- Payment mode.
- Payment reference / UPI transaction ID.
- Partial payment.
- Refund/cancel bill.
- Daily cash report.

Tables:

```text
invoices
invoice_items
payments
payment_transactions
```

Billing should connect to:

- consultation
- EEG
- lab
- pharmacy
- packages

## 15. Appointment And Queue Improvements

Current queue is good. Improve it for high-volume clinics.

Required:

- Visit reason.
- New/follow-up/report review/diagnostic-only.
- Doctor schedule.
- Time slots optional.
- Token print/share.
- Queue filters.
- Multi-counter reception support.
- Queue display screen.
- No-show/cancel reason.
- Reschedule appointment.
- Follow-up reminder.

For 50+ patients/day:

- Fast patient search.
- One-click follow-up booking.
- Repeat previous visit/prescription.
- Queue category filters.

## 16. File And Attachment Storage

Required for EMR.

Files:

- EEG reports.
- MRI/CT reports.
- Lab reports.
- Discharge summaries.
- Consent forms.
- Old prescriptions.
- Referral letters.

Storage strategy:

- Local mode: encrypted local storage folder.
- Cloud mode: object storage like S3-compatible storage.
- Store metadata in DB, not raw files.

Table:

```text
patient_attachments
- attachment_id
- clinic_id
- patient_id
- case_id
- visit_id
- file_type
- storage_path
- encrypted
- checksum
- uploaded_by
- uploaded_at
```

## 17. Flutter App Deployment Changes

Current app hardcodes backend URL at build time. Change this.

Required:

- Server setup screen.
- Save backend URL securely.
- Test connection button.
- Local/cloud mode selection.
- Logout/session expiry handling.
- Role-based home screen.
- Module-based menus.
- App version display.
- Update notice.

Example setup:

```text
Server URL:
http://192.168.1.10:8000
or
https://clinic.yourdomain.com
```

## 18. Admin Settings

Add clinic admin settings:

```text
Clinic profile
Branch profile
Doctor management
User management
Role management
Service catalog
Module settings
Billing settings
Backup settings
Security settings
Printer settings
Prescription template
```

## 19. Reports And Analytics

For small clinics, basic reports are enough.

Required first:

- Daily appointments.
- Doctor-wise patients.
- Revenue report.
- Due payments.
- Service-wise revenue.
- New vs follow-up patients.
- EEG orders completed/pending.
- No-show/cancellation report.

Later:

- Diagnosis trends.
- Medicine usage.
- Doctor productivity.
- Monthly growth.
- Branch comparison.

## 20. License And Package Control

If local server deployment is supported, add licensing.

Required:

- Clinic license.
- Enabled modules.
- Max users/doctors.
- Expiry date.
- Local/cloud deployment type.
- Signed license file.
- Offline activation support.

License should control backend access to modules.

Do not rely only on Flutter UI hiding features.

## 21. Production Backend Requirements

Before deployment:

- Remove hardcoded credentials.
- Require strong `JWT_SECRET`.
- Use production `.env`.
- Restrict CORS.
- Add request rate limiting.
- Add proper logging.
- Keep health check endpoint.
- Test database migrations.
- Standardize error handling.
- Maintain API versioning.
- Add background jobs for backups/reminders.
- Secure file upload size/type validation.

## 22. Testing Requirements

Backend tests:

- Auth tests.
- Role permission tests.
- Module access tests.
- Queue concurrency tests.
- Backup/restore tests.
- Billing calculation tests.
- Prescription tests.
- EEG workflow tests.
- Patient privacy tests.

Flutter tests:

- Remove stale default counter test.
- Login tests.
- Admin workflow tests.
- Doctor queue tests.
- Patient status tests.
- Billing modal tests.
- Offline/server unavailable states.

Deployment tests:

- Fresh local install.
- Fresh cloud deploy.
- Backup restore.
- Server reboot recovery.
- Internet outage local mode.
- Multi-user same-day queue load.

## 23. Minimum Deployment Readiness Checklist

Before giving to a real clinic, complete at least:

```text
[ ] Real user auth
[ ] Role-based permissions
[ ] Remove hardcoded admin/doctor login
[ ] Configurable backend URL in Flutter
[ ] Clinic/user setup wizard
[ ] Encrypted database backups
[ ] Restore tool
[ ] Production environment config
[ ] Restricted CORS
[ ] Secure JWT secret
[ ] Audit log masking
[ ] Local server installer or Docker setup
[ ] Cloud deployment script
[ ] Billing receipt basics
[ ] Prescription basics
[ ] File upload basics
[ ] App/server health screen
```

## 24. Recommended Development Phases

### Phase 1: Deployment Foundation

- Real users/roles.
- Clinic settings.
- Backend URL setup.
- Local/cloud config.
- Backup/restore.
- Security cleanup.

### Phase 2: EMR Core

- Patient cases.
- Structured visits.
- Prescription.
- Attachments.
- Follow-up history.

### Phase 3: Billing And Services

- Invoices.
- Receipts.
- Service packages.
- Partial payments.
- Daily reports.

### Phase 4: Specialty Modules

- EEG.
- Surgery referral.
- Lab/diagnostics.
- Pharmacy if needed.

### Phase 5: Scale

- Multi-branch.
- Analytics.
- Cloud backup.
- Advanced audit.
- Enterprise deployment.

## 25. Immediate Next Steps

Upgrade the current app in this order:

1. Real auth and roles.
2. Clinic/module architecture.
3. Configurable local/cloud server setup.
4. Encrypted backup and restore.
5. Prescription and patient timeline.
6. Billing upgrade.
7. EEG module.

This path keeps the app usable for small clinics while preparing it for medium and specialty clinics.
