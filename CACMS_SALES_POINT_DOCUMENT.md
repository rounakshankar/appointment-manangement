# CACMS Sales Point Document

## Product Name

CACMS - Clinic Appointment & Consultation Management System

## One-Line Pitch

CACMS helps clinics manage patients, appointments, live queues, doctor consultations, services, and payments from one simple digital system.

## Short Sales Pitch

CACMS is built for small and growing clinics that want to reduce manual register work, manage patient flow smoothly, and give doctors, reception staff, and patients a better daily experience. It supports appointment booking, live queue management, doctor consultation records, payment tracking, and patient status updates.

The system can run as a cloud-based SaaS or as a local clinic server, depending on the clinic's internet quality and data-control preference.

## Target Customers

- Single-doctor clinics
- Multi-doctor clinics
- Specialty clinics
- Small hospitals
- Diagnostic or procedure-based clinics
- Clinics currently using paper registers or Excel
- Clinics that want appointment, queue, consultation, and payment workflow in one place

## Problems Clinics Face

- Patient records are scattered across registers, files, and staff memory.
- Reception staff struggle to manage queues during busy hours.
- Doctors do not get a clean view of today's patient queue.
- Patients repeatedly ask, "Mera number kab aayega?"
- Billing and service charges are manually tracked.
- Follow-up appointments are easy to miss.
- Clinic owners cannot easily see daily patient flow.
- Paper-based systems make searching old patient data slow.

## How CACMS Solves These Problems

- Digitizes patient registration and lookup.
- Creates appointments with normal, follow-up, and emergency visit types.
- Gives reception/admin a live queue dashboard.
- Gives doctors their own queue dashboard.
- Allows doctors to record consultation details.
- Supports service/test/procedure selection during consultation.
- Records payment mode and payment status.
- Gives patients live appointment and queue status.
- Keeps structured data for future reports, backups, and growth.

## Core Features

### Admin And Reception

- Secure admin login
- Patient registration
- Patient lookup
- Patient consent capture
- Appointment creation
- Doctor selection
- Visit type selection: normal, follow-up, emergency
- Emergency queue priority
- Live daily queue dashboard
- Queue statistics: total, completed, remaining
- Cancel appointment
- Mark patient as no-show
- Record consultation payment
- Manage doctors
- Manage clinic services
- Manage patients

### Doctor Workflow

- Doctor login
- Doctor-specific queue dashboard
- View today's appointments
- See patient queue number and visit type
- Call next patient
- Mark no-show or cancel
- Start consultation
- Add diagnosis and notes
- Add services, tests, or procedures
- Create follow-up suggestion
- Receive real-time queue updates

### Patient Experience

- Patient OTP login
- View current appointment status
- View queue number
- View doctor name and appointment date
- Receive live status updates
- View completed visit summary
- View last visit diagnosis, notes, services, and next visit date

### Billing And Services

- Add billable services during consultation
- Payment mode support: cash, UPI, card
- Payment status support: pending, paid, partial
- Service-wise billing structure

### System And Security

- FastAPI backend
- PostgreSQL database
- JWT-based authentication
- Role-based access foundation
- Audit log foundation
- API rate limiting support
- Real-time updates through server-sent events
- Health check endpoint
- Database migration support

## Business Benefits For Clinics

- Reduces manual register dependency.
- Improves patient flow and queue clarity.
- Saves reception staff time.
- Gives doctors a clean consultation workflow.
- Reduces missed follow-ups.
- Helps clinics look more professional.
- Creates structured records for future reporting.
- Supports multi-doctor clinic growth.
- Can start small and scale later.

## Deployment Options

### Cloud Mode

Best for clinics that want remote access, easier updates, and automatic cloud backup.

Benefits:

- No clinic-side server maintenance
- Easier updates
- Remote access possible
- Centralized backups
- Good for multi-branch growth

Best fit:

- Urban clinics
- Clinics with stable internet
- Multi-doctor clinics
- Clinic owners who want remote monitoring

### Local Server Mode

Best for clinics with poor internet or strong local data-control preference.

Benefits:

- Works inside clinic over LAN
- Daily operations can continue without internet
- Data stays on clinic machine
- Cloud backup can be optional
- Lower recurring cloud compute cost

Best fit:

- Small clinics
- Clinics with unreliable internet
- Clinics that prefer local data storage

### Future Hybrid Mode

Best for advanced clinics that want local operation plus cloud sync and remote access.

Benefits:

- Local-first reliability
- Cloud backup
- Optional owner dashboard
- Better disaster recovery

## Suggested Packages

### Starter Clinic

For single-doctor or small clinics.

Includes:

- Patient registration
- Appointment booking
- Queue management
- Doctor dashboard
- Basic consultation
- Basic payment tracking

### Growth Clinic

For 2-10 doctors or busy specialty clinics.

Includes:

- Everything in Starter
- Doctor management
- Service management
- Follow-up flow
- Patient live status
- Daily backup
- Priority support

### Multi-Doctor / Premium Clinic

For large clinics, specialty centers, or future multi-branch customers.

Includes:

- Everything in Growth
- Advanced roles and permissions
- Reports
- Cloud backup
- Multi-branch support
- Custom modules
- Dedicated support

## Possible Future Add-On Modules

- Prescription module
- Lab/diagnostic orders
- Pharmacy module
- Inventory management
- Reports and analytics
- WhatsApp/SMS reminders
- Online appointment booking
- File uploads and attachments
- Insurance/TPA support
- Multi-branch dashboard
- Owner revenue dashboard
- Staff attendance
- Patient feedback

## Demo Flow For Sales Meeting

1. Show admin login.
2. Register a new patient.
3. Create an appointment with a doctor.
4. Show live queue dashboard.
5. Open doctor login.
6. Show doctor's queue.
7. Call next patient.
8. Record consultation diagnosis and services.
9. Create follow-up prompt.
10. Record payment.
11. Show patient live status screen.

## Strong Sales Talking Points

- "Your clinic can move from paper register to digital workflow without changing daily habits too much."
- "Reception, doctor, and patient all see the same queue status."
- "Emergency patients can be handled without disturbing the whole workflow."
- "Doctors get a clean list of today's patients."
- "The system can start small and grow with your clinic."
- "Cloud and local deployment options are both possible."
- "Your data becomes searchable, structured, and ready for future reports."

## Objection Handling

### "We already use registers."

Registers work, but they become slow when patient volume grows. CACMS does not remove your clinic workflow; it makes the same workflow faster, searchable, and easier to manage.

### "Our staff is not technical."

The system is designed around simple clinic roles: reception creates appointments, doctor sees queue and consultations, patient checks status. Training can be done workflow-wise, not technically.

### "Internet is unreliable."

CACMS can support local server mode where the clinic works over LAN. Cloud backup can be added separately.

### "Is our data safe?"

The system uses authenticated access and can be deployed with encrypted backups, controlled roles, and audit logs. For production clinics, stronger role-based permissions and backup policies should be enabled.

### "What if we grow?"

The system is designed to scale from one doctor to multi-doctor clinics, and later to multi-clinic or multi-branch setups.

## Ideal First Clients

- Clinics that currently use manual registers.
- Clinics with 2-5 staff members.
- Doctors who face queue confusion daily.
- Specialty clinics where follow-ups matter.
- Clinics open to digital improvement but not ready for expensive hospital ERP systems.

## Sales Positioning

CACMS should be positioned as a practical clinic workflow system, not a heavy hospital ERP.

Best positioning:

"A simple, affordable digital clinic management system for appointments, queue, consultation, and payments."

Avoid positioning it as:

- Full hospital ERP
- Complete EMR for all specialties
- Enterprise hospital system
- Insurance-grade medical platform

## Recommended First-Year Sales Strategy

- Start with 3-4 clinics.
- Offer assisted setup and training.
- Collect real workflow feedback.
- Improve reports, backup, and role permissions.
- Add WhatsApp/SMS reminders later as a paid add-on.
- Build case studies from early clinics.
- Expand to 10-20 clinics after support process is stable.

## Closing Pitch

CACMS gives clinics a practical way to digitize daily operations without jumping into a complex hospital ERP. It focuses on the most important clinic workflows first: patient registration, appointment booking, queue management, doctor consultation, services, payments, and patient status.

It is suitable for clinics that want to become more organized, reduce manual work, and prepare for future growth.
