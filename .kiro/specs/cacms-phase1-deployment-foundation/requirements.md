# Requirements Document

## Introduction

Phase 1 of the CACMS Deployment Foundation upgrade hardens the existing FastAPI + PostgreSQL backend
and Flutter frontend for real clinic use. The current system has critical security gaps that block
production deployment: hardcoded credentials, no real user table, no data isolation per clinic,
a build-time-hardcoded backend URL in the Flutter app, no backup system, and an insecure production
configuration. Phase 1 closes all of these gaps while keeping the existing queue, consultation, and
payment workflows intact.

Source sections: DEPLOYMENT-SPEC-SHEET.md §3 (Auth), §4 (Roles), §7 (clinic_id isolation),
§8 (Flutter server config), §17 (Backup/Restore), §21 (Production config).

---

## Glossary

- **Auth_Service**: The FastAPI module responsible for authenticating users and issuing JWTs
  (`cacms/routers/auth.py` and `cacms/services/jwt_service.py`).
- **User**: A record in the new `users` table representing a human operator of the system
  (Owner, Admin, Doctor, or Receptionist). Distinct from the `doctors` table, which holds
  clinical profile data.
- **Role**: One of four string values stored in `users.role`: `owner`, `admin`, `doctor`,
  `receptionist`. Enforced by the backend on every protected endpoint.
- **Clinic**: A record in the `clinics` table. Phase 1 operates with exactly one clinic;
  the schema is designed to support multiple clinics in a future phase.
- **clinic_id**: A UUID foreign key column added to every business table to scope records to
  a specific clinic.
- **Business_Table**: Any of the following existing tables: `patients`, `doctors`,
  `appointments`, `consultations`, `services`, `payments`, `audit_logs`.
- **JWT_Service**: `cacms/services/jwt_service.py` — creates and verifies signed JWTs.
- **Config**: `cacms/config.py` — Pydantic `BaseSettings` that reads environment variables.
- **Server_Config_Screen**: A new Flutter screen shown on first launch (or when no server URL
  is stored) that lets the user enter, test, and save the backend URL.
- **Server_Config_Storage**: Persistent, secure local storage for the backend URL on the
  Flutter client, implemented via `flutter_secure_storage`.
- **Backup_Service**: A new FastAPI service that runs `pg_dump`, compresses the output, and
  encrypts it with AES-256-GCM before writing to disk.
- **Backup_Screen**: A new Flutter admin screen for triggering a backup and viewing backup
  history/status.
- **Rate_Limiter**: A per-IP request throttle applied to authentication endpoints, implemented
  via `slowapi`.
- **CORS_Origins**: The list of allowed origins read from the `CORS_ORIGINS` environment
  variable, used to replace the current wildcard CORS policy.
- **Password_Hash**: A bcrypt hash (cost factor ≥ 12) stored in `users.password_hash`.

---

## Requirements

### Requirement 1: Real Users Table with Bcrypt Authentication

**User Story:** As a clinic owner, I want all system users to authenticate with individually
managed credentials stored securely in the database, so that hardcoded passwords can never
grant access to the system.

#### Acceptance Criteria

1. THE Auth_Service SHALL store all operator credentials in a `users` table with columns:
   `user_id` (UUID PK), `username` (TEXT UNIQUE NOT NULL), `password_hash` (TEXT NOT NULL),
   `role` (TEXT NOT NULL), `linked_doctor_id` (UUID FK → doctors.doctor_id, nullable),
   `active` (BOOLEAN NOT NULL DEFAULT true), `created_at` (TIMESTAMPTZ NOT NULL DEFAULT now()).

2. WHEN a `users` record is created or updated with a plaintext password, THE Auth_Service
   SHALL hash the password using bcrypt with a cost factor of at least 12 before storing it.

3. WHEN a login request is received, THE Auth_Service SHALL verify the submitted password
   against `users.password_hash` using `bcrypt.checkpw` and SHALL reject the request if
   verification fails.

4. THE Auth_Service SHALL NOT contain any hardcoded username or password value; the admin
   account SHALL be seeded via a one-time migration script that reads credentials from
   environment variables `SEED_ADMIN_USERNAME` and `SEED_ADMIN_PASSWORD`.

5. IF `SEED_ADMIN_PASSWORD` is fewer than 12 characters, THEN THE Auth_Service SHALL refuse
   to seed the account and SHALL exit with a non-zero status code and a descriptive error
   message.

6. THE Auth_Service SHALL remove the `_get_admin_password_hash` function and the
   `ADMIN_USERNAME` / `_ADMIN_PASSWORD_HASH` module-level variables from `cacms/routers/auth.py`.

7. WHEN a doctor user logs in, THE Auth_Service SHALL look up the user by `users.username`,
   verify the password hash, and SHALL NOT accept any non-empty password as valid.

---

### Requirement 2: Role-Based Access Control

**User Story:** As a clinic owner, I want each user account to carry a role that the backend
enforces on every API call, so that receptionists cannot access doctor-only endpoints and
doctors cannot access admin-only endpoints.

#### Acceptance Criteria

1. THE Auth_Service SHALL issue JWTs that include a `role` claim containing exactly one of:
   `owner`, `admin`, `doctor`, `receptionist`.

2. WHEN a JWT is decoded, THE Auth_Service SHALL validate that the `role` claim is one of the
   four permitted values and SHALL reject tokens with any other role value with HTTP 401.

3. THE Auth_Service SHALL enforce the following access matrix on all existing and new
   protected endpoints:
   - `owner`: full access to all endpoints.
   - `admin`: access to patient, appointment, service, payment, consultation, backup, and
     audit endpoints; no access to user management endpoints.
   - `doctor`: access to queue, consultation, and own-profile endpoints only.
   - `receptionist`: access to patient registration, appointment creation, and payment
     recording endpoints only.

4. WHEN a request is made to an endpoint that the caller's role is not permitted to access,
   THE Auth_Service SHALL return HTTP 403 with `error_code: "FORBIDDEN"`.

5. THE Auth_Service SHALL update `cacms/middleware/auth_middleware.py` to add
   `require_owner`, `require_receptionist`, and `require_owner_or_admin` dependency
   factories alongside the existing ones.

6. THE Auth_Service SHALL store the role in the `users` table and SHALL NOT derive the role
   from the presence of a record in the `doctors` table.

---

### Requirement 3: clinic_id Isolation on All Business Tables

**User Story:** As a clinic owner, I want every record in the system to be tagged with a
clinic identifier, so that the schema is ready for multi-clinic deployment without requiring
a future data migration.

#### Acceptance Criteria

1. THE Auth_Service SHALL create a `clinics` table with columns: `clinic_id` (UUID PK),
   `name` (TEXT NOT NULL), `created_at` (TIMESTAMPTZ NOT NULL DEFAULT now()).

2. THE Auth_Service SHALL add a `clinic_id` (UUID NOT NULL, FK → clinics.clinic_id) column
   to each of the following existing tables via an Alembic migration:
   `patients`, `doctors`, `appointments`, `consultations`, `services`, `payments`,
   `audit_logs`.

3. THE Auth_Service SHALL seed exactly one clinic record during the initial migration; all
   existing rows in the Business_Tables SHALL be back-filled with that clinic's `clinic_id`.

4. WHEN a new record is created in any Business_Table, THE Auth_Service SHALL set
   `clinic_id` from the authenticated user's clinic context; the API SHALL NOT accept
   `clinic_id` as a client-supplied field in request bodies.

5. WHEN a read or write request targets a record in any Business_Table, THE Auth_Service
   SHALL verify that the record's `clinic_id` matches the requesting user's clinic context
   and SHALL return HTTP 404 if it does not match.

6. THE Auth_Service SHALL add a non-unique index on `clinic_id` to each Business_Table to
   support efficient filtered queries.

7. THE Auth_Service SHALL update all SQLAlchemy model files (`cacms/models/*.py`) to include
   the `clinic_id` mapped column and the FK relationship.

---

### Requirement 4: Flutter Server Setup Screen

**User Story:** As a clinic technician deploying the app, I want to enter the backend URL
once on the device and have it saved securely, so that the app does not need to be rebuilt
for each deployment.

#### Acceptance Criteria

1. WHEN the Flutter app launches and no backend URL is found in Server_Config_Storage, THE
   Server_Config_Screen SHALL be displayed before the role-selection screen.

2. THE Server_Config_Screen SHALL provide a text input field for the backend URL and a
   "Test Connection" button.

3. WHEN the user taps "Test Connection", THE Server_Config_Screen SHALL send an HTTP GET
   request to `{entered_url}/health` and SHALL display a success indicator if the response
   is HTTP 200 with `{"status": "ok"}`, or an error message otherwise.

4. WHEN the connection test succeeds and the user taps "Save", THE Server_Config_Screen
   SHALL persist the URL to Server_Config_Storage using `flutter_secure_storage` and SHALL
   navigate to the role-selection screen.

5. THE Server_Config_Screen SHALL validate that the entered URL is a well-formed HTTP or
   HTTPS URL before sending the test request; IF the URL is malformed, THEN THE
   Server_Config_Screen SHALL display an inline validation error and SHALL NOT send the
   request.

6. THE ApiClient SHALL read the backend base URL from Server_Config_Storage at startup
   instead of from the compile-time `String.fromEnvironment('BACKEND_URL')` constant.

7. THE Server_Config_Screen SHALL be accessible from the app settings so that the URL can
   be changed after initial setup without reinstalling the app.

8. THE Server_Config_Screen SHALL store the URL under the key `cacms_server_url` in
   Server_Config_Storage.

---

### Requirement 5: Encrypted Backup System

**User Story:** As a clinic admin, I want to create an encrypted backup of the database on
demand and download it, so that clinic data can be recovered after hardware failure or
accidental deletion.

#### Acceptance Criteria

1. THE Backup_Service SHALL expose a `POST /v1/admin/backup` endpoint, accessible only to
   users with role `owner` or `admin`, that triggers a `pg_dump` of the CACMS database.

2. WHEN a backup is triggered, THE Backup_Service SHALL compress the `pg_dump` output using
   gzip and encrypt the compressed stream using AES-256-GCM with a key derived from the
   `BACKUP_ENCRYPTION_KEY` environment variable via PBKDF2-HMAC-SHA256 with at least
   100,000 iterations.

3. THE Backup_Service SHALL write the encrypted backup file to the directory specified by
   the `BACKUP_DIR` environment variable with a filename of the form
   `cacms_backup_YYYYMMDD_HHMMSS.enc`.

4. THE Backup_Service SHALL expose a `GET /v1/admin/backups` endpoint that returns a list
   of available backup files with their filenames, sizes in bytes, and creation timestamps.

5. THE Backup_Service SHALL expose a `GET /v1/admin/backup/{filename}` endpoint that
   streams the encrypted backup file as a binary download to the caller.

6. IF `BACKUP_ENCRYPTION_KEY` is not set or is empty, THEN THE Backup_Service SHALL return
   HTTP 503 with `error_code: "BACKUP_NOT_CONFIGURED"` on any backup endpoint call.

7. IF the `pg_dump` process exits with a non-zero code, THEN THE Backup_Service SHALL
   return HTTP 500 with `error_code: "BACKUP_FAILED"` and SHALL NOT write a partial file
   to disk.

8. THE Backup_Screen SHALL display a "Create Backup" button and a list of existing backups
   with filename, size, and timestamp; each entry SHALL have a "Download" action.

9. WHEN a backup is in progress, THE Backup_Screen SHALL display a loading indicator and
   SHALL disable the "Create Backup" button until the operation completes or fails.

---

### Requirement 6: Production Configuration

**User Story:** As a system administrator, I want the backend to refuse to start with
insecure defaults, so that a misconfigured production deployment cannot be exploited.

#### Acceptance Criteria

1. THE Config SHALL require `JWT_SECRET` to be set via the environment with no default
   value; IF `JWT_SECRET` is absent or empty at startup, THEN THE Config SHALL raise a
   `ValueError` and the application SHALL not start.

2. THE Config SHALL read `CORS_ORIGINS` from the environment as a comma-separated list of
   allowed origins; IF `CORS_ORIGINS` is absent or empty, THEN THE Config SHALL default to
   an empty list and THE application SHALL log a warning that CORS is unconfigured.

3. THE application SHALL replace the current `allow_origins=["*"]` in `cacms/main.py` with
   the list read from `Config.CORS_ORIGINS`; THE application SHALL NOT use a wildcard
   origin in any environment.

4. THE application SHALL apply rate limiting to the `POST /v1/auth/login` and
   `POST /v1/auth/request-otp` endpoints using `slowapi`, with a default limit of
   10 requests per minute per IP address, configurable via the `AUTH_RATE_LIMIT`
   environment variable.

5. IF a client exceeds the rate limit on an auth endpoint, THEN THE Rate_Limiter SHALL
   return HTTP 429 with `error_code: "RATE_LIMIT_EXCEEDED"`.

6. THE Config SHALL expose a `BACKUP_ENCRYPTION_KEY` field (no default) and a `BACKUP_DIR`
   field (default: `/var/backups/cacms`) read from environment variables.

7. THE Config SHALL expose a `CORS_ORIGINS` field parsed from the `CORS_ORIGINS`
   environment variable as a `list[str]`.

8. THE application SHALL update `.env.example` to document all new required and optional
   environment variables introduced in Phase 1: `JWT_SECRET`, `CORS_ORIGINS`,
   `BACKUP_ENCRYPTION_KEY`, `BACKUP_DIR`, `AUTH_RATE_LIMIT`, `SEED_ADMIN_USERNAME`,
   `SEED_ADMIN_PASSWORD`.
