# Requirements Document

## Introduction

A Real-Time Clinic Appointment & Consultation Management System (CACMS) designed as a SaaS product for high-throughput retail clinics. The system supports fast appointment creation, queue-based doctor workflows, real-time status updates via Server-Sent Events, consultation recording, service billing, and payment tracking. It serves three user roles: Admin, Doctor, and Patient, each with distinct workflows and access controls.

## Glossary

- **CACMS**: Clinic Appointment & Consultation Management System — the system being specified.
- **Admin**: A clinic staff member with full access to create appointments and manage patients.
- **Doctor**: A licensed medical practitioner who manages their own appointment queue and records consultations.
- **Patient**: A clinic visitor who books appointments and views their own visit status and history.
- **Queue_Number**: An integer assigned atomically to each appointment representing the patient's position in a doctor's daily queue.
- **Appointment**: A scheduled visit record linking a patient to a doctor on a specific date with a queue position and status.
- **Consultation**: A clinical record linked one-to-one with a completed appointment, containing symptoms, diagnosis, notes, and services rendered.
- **Service**: A billable item from the clinic's rate list (consultation, test, or procedure).
- **Payment**: A financial record linked to a consultation capturing total amount, mode, and status.
- **SSE**: Server-Sent Events — a unidirectional HTTP streaming protocol used for real-time updates.
- **OTP**: One-Time Password — a short-lived numeric code sent to a patient's phone for authentication.
- **JWT**: JSON Web Token — a signed token used for Admin and Doctor authentication.
- **Visit_Type**: The classification of an appointment: `normal`, `follow-up`, or `emergency`.
- **Appointment_Status**: The lifecycle state of an appointment: `scheduled`, `in-progress`, `completed`, `cancelled`, or `no-show`.
- **Call_Next**: The atomic doctor action that advances the queue by completing the current in-progress appointment and marking the next scheduled appointment as in-progress.
- **Follow_Up**: An appointment created in response to a `next_visit_date` set during a prior consultation.

---

## Requirements

### Requirement 1: Patient Registration and Lookup

**User Story:** As an Admin, I want to look up a patient by phone number and register new patients inline, so that appointment creation takes no longer than 30 seconds.

#### Acceptance Criteria

1. WHEN the Admin submits a phone number, THE CACMS SHALL return the matching patient record within 500ms if the phone number exists in the system.
2. WHEN the Admin submits a phone number that does not exist, THE CACMS SHALL present an inline registration form requesting name, age, and gender.
3. WHEN the Admin submits the inline registration form with valid data, THE CACMS SHALL create a new Patient record with a UUID primary key, record `consent_given` and `consent_date`, and return the new patient record within 500ms.
4. IF the Admin submits a registration form with a phone number that already exists, THEN THE CACMS SHALL return a conflict error indicating the phone number is already registered.
5. THE CACMS SHALL enforce uniqueness on the `phone` field across all Patient records.
6. THE CACMS SHALL index the `phone` field to support sub-500ms lookup under concurrent load.
7. THE CACMS SHALL NOT expose the patient's phone number as a URL path parameter in any API endpoint.
8. THE CACMS SHALL store `address` as an optional field on the Patient record; it is not required for appointment creation.

---

### Requirement 2: Appointment Creation

**User Story:** As an Admin, I want to create an appointment for a patient with a specific doctor and visit type, so that the patient is assigned a queue position atomically and the full process completes within 30 seconds.

#### Acceptance Criteria

1. WHEN the Admin submits a valid appointment creation request with `patient_id`, `doctor_id`, `scheduled_date`, and `visit_type`, THE CACMS SHALL assign a `queue_number` atomically and persist the Appointment record with `status = scheduled` within 1 second.
2. THE CACMS SHALL assign `queue_number` values as sequential integers starting from 1 for each unique `(doctor_id, scheduled_date)` combination.
3. WHEN `visit_type` is `emergency`, THE CACMS SHALL assign the lowest available `queue_number` ahead of all existing `scheduled` appointments for that doctor on that date.
4. THE CACMS SHALL enforce a database-level UNIQUE constraint on `(doctor_id, scheduled_date, queue_number)` to prevent duplicate queue positions under concurrent requests.
5. WHEN the number of `scheduled` and `in-progress` appointments for a doctor on a given date equals the doctor's `max_patients_per_day`, THE CACMS SHALL reject new appointment creation requests with an error indicating the doctor's daily capacity has been reached.
6. IF two concurrent requests attempt to create appointments for the same doctor on the same date, THEN THE CACMS SHALL serialize the queue number assignment so that each request receives a unique `queue_number` with no gaps or duplicates.
7. WHEN an appointment is successfully created, THE CACMS SHALL emit an `appointment_created` SSE event to the `/events/doctor/{doctor_id}` stream.

---

### Requirement 3: Doctor Queue Dashboard

**User Story:** As a Doctor, I want to view my daily appointment queue with counts and patient details, so that I can manage my workload efficiently.

#### Acceptance Criteria

1. WHEN a Doctor requests their daily dashboard for a given date, THE CACMS SHALL return the total number of appointments, the count of completed appointments, the count of remaining (scheduled) appointments, and the ordered queue list for that doctor and date.
2. THE CACMS SHALL return the queue list ordered ascending by `queue_number`.
3. THE CACMS SHALL include `patient name`, `visit_type`, `queue_number`, and `status` for each entry in the queue list.
4. THE CACMS SHALL restrict the Doctor's dashboard data to appointments belonging to that Doctor's `doctor_id` only.

---

### Requirement 4: Call Next — Atomic Queue Advancement

**User Story:** As a Doctor, I want to call the next patient atomically, so that queue integrity is maintained even under concurrent or duplicate requests.

#### Acceptance Criteria

1. WHEN a Doctor triggers Call_Next, THE CACMS SHALL execute the following steps within a single database transaction: mark the current `in-progress` appointment as `completed`, select the next `scheduled` appointment ordered by `queue_number`, and mark it as `in-progress`.
2. THE CACMS SHALL ensure that at most one Appointment per doctor per day holds `status = in-progress` at any point in time.
3. IF a Doctor triggers Call_Next when no `scheduled` appointments remain for that doctor on that date, THEN THE CACMS SHALL return a response indicating the queue is empty with no state changes applied.
4. IF two concurrent Call_Next requests are received for the same doctor, THEN THE CACMS SHALL process only one successfully and return a conflict or no-op response to the second request, leaving queue state consistent.
5. WHEN Call_Next completes successfully, THE CACMS SHALL emit a `queue_updated` SSE event to the `/events/doctor/{doctor_id}` stream and a `status_changed` SSE event to the `/events/patient/{patient_id}` stream for the newly in-progress patient.

---

### Requirement 5: Consultation Recording

**User Story:** As a Doctor, I want to record symptoms, diagnosis, notes, and services for a patient's consultation, so that a complete clinical record is created.

#### Acceptance Criteria

1. WHEN a Doctor submits a consultation record with a valid `appointment_id`, `symptoms`, and `diagnosis`, THE CACMS SHALL create a Consultation record linked one-to-one with the Appointment and return the created record within 1 second.
2. THE CACMS SHALL enforce a UNIQUE constraint on `consultation_id → appointment_id` so that each Appointment has at most one Consultation.
3. WHEN a Doctor adds one or more services to a consultation, THE CACMS SHALL create Consultation_Service records capturing `service_id`, `quantity`, `price_applied`, and `total` for each service.
4. WHERE a `next_visit_date` is provided in the consultation, THE CACMS SHALL persist the `next_visit_date` on the Consultation record.
5. THE CACMS SHALL restrict consultation creation and editing to the Doctor whose `doctor_id` matches the appointment's `doctor_id`.
6. WHEN a consultation is completed, THE CACMS SHALL emit a `consultation_completed` SSE event to the `/events/doctor/{doctor_id}` stream and to the `/events/patient/{patient_id}` stream.

---

### Requirement 6: Services Rate List

**User Story:** As a Doctor or Admin, I want to view the active services rate list, so that I can add billable services to a consultation accurately.

#### Acceptance Criteria

1. WHEN a request is made to retrieve the services list, THE CACMS SHALL return all Service records where `active = true`, including `service_id`, `name`, `category`, and `base_price`.
2. THE CACMS SHALL categorize each Service as one of: `consultation`, `test`, or `procedure`.
3. THE CACMS SHALL make the services list accessible to authenticated Admin and Doctor roles only.

---

### Requirement 7: Payment Recording

**User Story:** As an Admin, I want to record a payment against a completed consultation, so that the clinic's financial records are accurate.

#### Acceptance Criteria

1. WHEN an Admin submits a payment with a valid `consultation_id`, `total_amount`, and `payment_mode`, THE CACMS SHALL create a Payment record with `status = pending` and return the created record within 1 second.
2. THE CACMS SHALL accept `payment_mode` values of `cash`, `upi`, or `card` only.
3. THE CACMS SHALL accept `status` values of `pending`, `paid`, or `partial` only.
4. IF a payment submission references a `consultation_id` that does not exist, THEN THE CACMS SHALL return a not-found error.

---

### Requirement 8: Patient Live Status

**User Story:** As a Patient, I want to see my current appointment status and queue position in real time, so that I know when I will be seen.

#### Acceptance Criteria

1. WHEN a Patient requests their appointment status, THE CACMS SHALL return one of the following states based on the current appointment record: no active appointment (show last visit summary), `scheduled` (show queue position), `in-progress` (indicate the patient is currently being seen), or `completed` (show diagnosis, services rendered, and next visit date).
2. WHEN the Patient's appointment `status` changes, THE CACMS SHALL push a `status_changed` SSE event to the `/events/patient/{patient_id}` stream within 2 seconds of the state change.
3. WHILE a Patient is connected to the `/events/patient/{patient_id}` SSE stream, THE CACMS SHALL maintain the connection and deliver ordered events without duplication.
4. WHEN a Patient's SSE connection is interrupted, THE CACMS SHALL support client-initiated reconnection using the `Last-Event-ID` header to resume event delivery from the last received event.

---

### Requirement 9: Real-Time SSE Streams

**User Story:** As a system operator, I want all real-time updates delivered via authenticated SSE streams, so that clients receive ordered, reliable events without polling.

#### Acceptance Criteria

1. THE CACMS SHALL expose SSE streams at `/events/doctor/{doctor_id}` and `/events/patient/{patient_id}`.
2. THE CACMS SHALL require a valid JWT or OTP-issued token in the `Authorization` header to establish an SSE connection.
3. THE CACMS SHALL deliver events in the order they occur per doctor stream, with no out-of-order delivery for a given `doctor_id`.
4. THE CACMS SHALL support the following event types on the doctor stream: `appointment_created`, `queue_updated`, `consultation_completed`.
5. THE CACMS SHALL support the following event types on the patient stream: `status_changed`, `consultation_completed`.
6. IF an SSE client disconnects, THEN THE CACMS SHALL release the associated server-side connection resources within 30 seconds.

---

### Requirement 10: Authentication and Authorization

**User Story:** As a system operator, I want role-based access control enforced on all endpoints, so that Admins, Doctors, and Patients can only access data they are permitted to see.

#### Acceptance Criteria

1. WHEN an Admin or Doctor submits valid credentials to `POST /v1/auth/login`, THE CACMS SHALL return a signed JWT with role and identity claims.
2. WHEN a Patient submits a phone number to `POST /v1/auth/verify-otp`, THE CACMS SHALL send an OTP to that phone number and return a session token upon successful OTP verification.
3. THE CACMS SHALL enforce that Admin-role tokens have access to all patient, appointment, consultation, service, and payment endpoints.
4. THE CACMS SHALL enforce that Doctor-role tokens have access only to appointments, consultations, and services associated with that Doctor's `doctor_id`.
5. THE CACMS SHALL enforce that Patient-role tokens have access only to that Patient's own appointment status, consultation summary, and payment records.
6. IF a request is received without a valid token, THEN THE CACMS SHALL return a 401 Unauthorized response.
7. IF a request is received with a valid token but insufficient role permissions, THEN THE CACMS SHALL return a 403 Forbidden response.
8. THE CACMS SHALL record an audit log entry for every create, update, and delete operation, capturing the actor identity, role, action, affected resource ID, and timestamp.

---

### Requirement 11: Follow-Up Appointment Handling

**User Story:** As an Admin or Doctor, I want the system to prompt for a follow-up appointment when a next visit date is set, so that continuity of care is maintained without manual re-entry.

#### Acceptance Criteria

1. WHEN a Consultation record is saved with a non-null `next_visit_date`, THE CACMS SHALL return a follow-up prompt in the response containing the pre-filled `patient_id`, `doctor_id`, and `visit_type = follow-up`.
2. WHEN an Admin or Doctor confirms the follow-up prompt, THE CACMS SHALL create a new Appointment using the pre-filled data and the `next_visit_date` as `scheduled_date`, applying all standard queue assignment rules from Requirement 2.
3. IF a follow-up appointment already exists for the same `patient_id`, `doctor_id`, and `scheduled_date`, THEN THE CACMS SHALL return a conflict error rather than creating a duplicate.

---

### Requirement 12: No-Show and Cancellation Handling

**User Story:** As an Admin or Doctor, I want to mark appointments as no-show or cancelled, so that the queue reflects only active patients.

#### Acceptance Criteria

1. WHEN an Admin or Doctor updates an appointment `status` to `no-show` or `cancelled`, THE CACMS SHALL persist the status change and emit a `queue_updated` SSE event to the `/events/doctor/{doctor_id}` stream.
2. WHEN an appointment is marked `no-show` or `cancelled`, THE CACMS SHALL NOT reassign its `queue_number` to another appointment, preserving the original queue order for audit purposes.
3. THE CACMS SHALL exclude `no-show` and `cancelled` appointments from the remaining patient count on the Doctor's dashboard.

---

### Requirement 13: API Versioning and Structure

**User Story:** As a developer integrating with CACMS, I want all API endpoints versioned under `/v1/`, so that future breaking changes can be introduced without disrupting existing clients.

#### Acceptance Criteria

1. THE CACMS SHALL expose all API endpoints under the `/v1/` path prefix.
2. THE CACMS SHALL implement the following endpoint surface:
   - `POST /v1/auth/login`
   - `POST /v1/auth/verify-otp`
   - `POST /v1/patients`
   - `GET /v1/patients` (with `phone` query parameter)
   - `POST /v1/appointments`
   - `GET /v1/appointments/today` (with `doctor_id` and `date` query parameters)
   - `GET /v1/appointments/{id}`
   - `PATCH /v1/appointments/{id}/status`
   - `PATCH /v1/appointments/{id}/clinical`
   - `PATCH /v1/appointments/{id}/schedule`
   - `POST /v1/consultations`
   - `GET /v1/consultations/{appointment_id}`
   - `GET /v1/services`
   - `POST /v1/payments`
   - `POST /v1/patient/appointment-status`
3. THE CACMS SHALL return error responses in a consistent JSON structure containing at minimum an `error_code` and `message` field.

---

### Requirement 14: Database Integrity and Schema

**User Story:** As a system operator, I want the PostgreSQL schema to enforce all business rules at the database level, so that data integrity is maintained even if application-layer checks are bypassed.

#### Acceptance Criteria

1. THE CACMS SHALL use PostgreSQL as the sole relational database.
2. THE CACMS SHALL define all primary keys as UUID type.
3. THE CACMS SHALL enforce a UNIQUE constraint on `(doctor_id, scheduled_date, queue_number)` in the Appointments table.
4. THE CACMS SHALL enforce a CHECK constraint or application-level transaction guard ensuring at most one `in-progress` appointment exists per `(doctor_id, scheduled_date)` at any time.
5. THE CACMS SHALL enforce a UNIQUE constraint on `appointment_id` in the Consultations table.
6. THE CACMS SHALL define foreign key constraints between: Appointments → Patients, Appointments → Doctors, Consultations → Appointments, Consultation_Services → Consultations, Consultation_Services → Services, Payments → Consultations.
7. THE CACMS SHALL index `appointments(doctor_id, scheduled_date)` and `appointments(patient_id)` to support sub-500ms queue queries under concurrent load.
