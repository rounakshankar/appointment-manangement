# Implementation Plan: CACMS Phase 1 Deployment Foundation

## Overview

Incremental implementation ordered by dependency: config hardening first (everything depends on it),
then the Alembic migration and ORM models, then real auth, then middleware and service-layer
clinic_id filtering, then backup system, then seed script, then Flutter screens, and finally
.env.example documentation.

## Tasks

- [x] 1. Harden `cacms/config.py`
  - Add `JWT_SECRET: str` with no default and a `@field_validator` that raises `ValueError` when absent or empty
  - Add `CORS_ORIGINS: list[str] = []` with a `@field_validator(mode="before")` that splits a comma-separated string
  - Add `BACKUP_ENCRYPTION_KEY: str = ""`, `BACKUP_DIR: str = "/var/backups/cacms"`, `AUTH_RATE_LIMIT: str = "10/minute"`, `SEED_ADMIN_USERNAME: str = ""`, `SEED_ADMIN_PASSWORD: str = ""`
  - Log a warning when `CORS_ORIGINS` is empty
  - _Requirements: 6.1, 6.2, 6.6, 6.7_

  - [ ]* 1.1 Write property test for CORS_ORIGINS parsing (Property 10)
    - **Property 10: CORS_ORIGINS parses comma-separated strings correctly**
    - **Validates: Requirements 6.2**

  - [ ]* 1.2 Write unit tests for config validation
    - Test `JWT_SECRET` absent → `ValueError`; test `CORS_ORIGINS` defaults to `[]`
    - _Requirements: 6.1, 6.2_

- [x] 2. Write Alembic migration `0002_clinic_id_and_users`
  - Create `cacms/migrations/versions/0002_clinic_id_and_users.py` with `down_revision = "0001"`
  - Create `clinics` table (`clinic_id` UUID PK, `name` TEXT NOT NULL, `created_at` TIMESTAMPTZ)
  - Seed one `Default Clinic` row and capture its UUID
  - For each business table (`patients`, `doctors`, `appointments`, `consultations`, `services`, `payments`, `audit_logs`): add nullable `clinic_id`, back-fill with seeded UUID, alter to NOT NULL, add FK constraint, add index
  - Create `users` table with all columns from the design; add `idx_users_clinic_id`
  - Implement `downgrade()` that reverses all steps
  - _Requirements: 3.1, 3.2, 3.3, 3.6, 1.1_

- [x] 3. Create new ORM models
  - [x] 3.1 Create `cacms/models/clinic.py`
    - `Clinic` mapped class with `clinic_id`, `name`, `created_at`
    - _Requirements: 3.1_

  - [x] 3.2 Create `cacms/models/user.py`
    - `User` mapped class with all columns from the design (`user_id`, `username`, `password_hash`, `role`, `linked_doctor_id`, `active`, `clinic_id`, `created_at`)
    - _Requirements: 1.1_

  - [x] 3.3 Add `clinic_id` mapped column to existing ORM models
    - Update `patient.py`, `doctor.py`, `appointment.py`, `consultation.py`, `service.py`, `payment.py`, `audit_log.py` — add `clinic_id: Mapped[uuid.UUID]` with FK to `clinics.clinic_id`
    - _Requirements: 3.7_

- [x] 4. Implement real bcrypt authentication in `cacms/routers/auth.py`
  - Remove `ADMIN_USERNAME`, `_ADMIN_PASSWORD_HASH`, `_get_admin_password_hash`
  - On `POST /v1/auth/login`: query `users` table by `username`, call `bcrypt.checkpw`, return 401 on failure
  - Issue JWT with `sub=user_id`, `role=role`, `clinic_id=clinic_id`
  - Apply `@limiter.limit(settings.AUTH_RATE_LIMIT)` to `/login` and `/request-otp`
  - _Requirements: 1.2, 1.3, 1.4, 1.6, 1.7, 2.1, 6.4_

  - [x] 4.1 Write property test for bcrypt hash round-trip (Property 1)
    - **Property 1: Bcrypt hash round-trip**
    - **Validates: Requirements 1.2, 1.3**

  - [x] 4.2 Write property test for JWT role claim round-trip (Property 3)
    - **Property 3: JWT role claim round-trip**
    - **Validates: Requirements 2.1**

  - [ ]* 4.3 Write property test for invalid role tokens rejected (Property 4)
    - **Property 4: Invalid role tokens are rejected**
    - **Validates: Requirements 2.2**

  - [x] 4.4 Write unit tests for auth router
    - Correct credentials → 200 + JWT; wrong password → 401; unknown username → 401
    - _Requirements: 1.3, 1.7_

- [x] 5. Update `cacms/middleware/auth_middleware.py`
  - Add `clinic_id: uuid.UUID` field to `UserContext` dataclass
  - Populate `clinic_id` from the decoded JWT `clinic_id` claim in `get_current_user`
  - Validate that `role` is one of `{owner, admin, doctor, receptionist}`; raise HTTP 401 otherwise
  - Add `require_owner`, `require_receptionist`, `require_owner_or_admin` dependency factories
  - _Requirements: 2.2, 2.4, 2.5_

  - [ ]* 5.1 Write property test for unauthorized role returns 403 (Property 5)
    - **Property 5: Unauthorized role returns 403**
    - **Validates: Requirements 2.4**

- [x] 6. Update `cacms/main.py`
  - Replace `allow_origins=["*"]` with `allow_origins=settings.CORS_ORIGINS`
  - Add `slowapi` `Limiter` instance and `_rate_limit_exceeded_handler` returning 429 with `error_code: "RATE_LIMIT_EXCEEDED"`
  - Register `backup.router`
  - _Requirements: 6.3, 6.4, 6.5_

  - [ ]* 6.1 Write property test for rate limiter blocks excess auth requests (Property 11)
    - **Property 11: Rate limiter blocks excess auth requests**
    - **Validates: Requirements 6.4, 6.5**

- [x] 7. Update all service functions to filter by `clinic_id`
  - In `patient_service.py`, `appointment_service.py`, `consultation_service.py`, `payment_service.py`, `service_catalog.py`: add `clinic_id` parameter to all query functions and apply `WHERE clinic_id = :clinic_id` filter
  - On record creation, set `clinic_id` from `UserContext.clinic_id`; do not accept it from request body
  - On record lookup, return 404 if `clinic_id` does not match
  - Update all router call sites to pass `current_user.clinic_id`
  - _Requirements: 3.4, 3.5_

  - [ ]* 7.1 Write property test for clinic_id always set from user context on create (Property 6)
    - **Property 6: clinic_id is always set from user context on create**
    - **Validates: Requirements 3.4**

  - [ ]* 7.2 Write property test for cross-clinic access returns 404 (Property 7)
    - **Property 7: Cross-clinic access returns 404**
    - **Validates: Requirements 3.5**

- [x] 8. Checkpoint — ensure all backend tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Create `cacms/services/backup_service.py`
  - `trigger_backup(db_url, backup_dir, encryption_key)` — runs `pg_dump` via `subprocess`, pipes through gzip, encrypts with AES-256-GCM (PBKDF2-HMAC-SHA256, ≥100k iterations, random 16-byte salt, 12-byte nonce), writes `cacms_backup_YYYYMMDD_HHMMSS.enc`; if `pg_dump` exits non-zero, delete any partial file and raise
  - `list_backups(backup_dir)` — scans for `*.enc` files, returns filename, size, mtime
  - `get_backup_path(backup_dir, filename)` — validates filename (no path traversal), returns `Path`
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.6, 5.7_

  - [ ]* 9.1 Write property test for backup encryption round-trip (Property 8)
    - **Property 8: Backup encryption round-trip**
    - **Validates: Requirements 5.2**

  - [ ]* 9.2 Write property test for failed pg_dump leaves no partial file (Property 9)
    - **Property 9: Failed pg_dump leaves no partial file**
    - **Validates: Requirements 5.7**

- [x] 10. Create `cacms/routers/backup.py`
  - `POST /v1/admin/backup` — `require_owner_or_admin` dependency; returns 503 if `BACKUP_ENCRYPTION_KEY` empty; calls `backup_service.trigger_backup`; returns filename on success
  - `GET /v1/admin/backups` — `require_owner_or_admin`; calls `backup_service.list_backups`
  - `GET /v1/admin/backup/{filename}` — `require_owner_or_admin`; calls `backup_service.get_backup_path`; streams file with `FileResponse`
  - _Requirements: 5.1, 5.4, 5.5, 5.6_

  - [ ]* 10.1 Write unit tests for backup router
    - Owner/admin can trigger backup; doctor/receptionist get 403; missing key → 503; download streams bytes
    - _Requirements: 5.1, 5.6_

- [x] 11. Create `seed_admin.py`
  - Standalone script (not a migration) that reads `SEED_ADMIN_USERNAME` and `SEED_ADMIN_PASSWORD` from env
  - Validates `SEED_ADMIN_PASSWORD` length ≥ 12; exits non-zero with descriptive stderr message if not
  - Hashes password with bcrypt cost 12; inserts into `users` with `role="owner"` and the seeded clinic's `clinic_id`
  - Idempotent: skip insert if username already exists
  - _Requirements: 1.4, 1.5_

  - [ ]* 11.1 Write property test for seed script rejects short passwords (Property 2)
    - **Property 2: Seed script rejects short passwords**
    - **Validates: Requirements 1.5**

  - [ ]* 11.2 Write unit tests for seed_admin.py
    - Valid credentials → `users` row with bcrypt hash; password < 12 chars → non-zero exit
    - _Requirements: 1.4, 1.5_

- [x] 12. Create Flutter server setup screen
  - Create `cacms_flutter/lib/features/setup/server_setup_screen.dart`
  - URL text field with inline validation (must be well-formed HTTP/HTTPS URL; no request sent if malformed)
  - "Test Connection" button: `GET {url}/health`, show success if `{"status": "ok"}` else show error
  - "Save" button (enabled after successful test): write URL to `flutter_secure_storage` under key `cacms_server_url`, navigate to role-selection screen
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.8_

- [x] 13. Update `cacms_flutter/lib/core/api/api_client.dart`
  - Remove compile-time `kBackendBaseUrl` / `String.fromEnvironment('BACKEND_URL')` constant
  - Add `ApiClient.create()` static async factory that reads `cacms_server_url` from `flutter_secure_storage` before constructing `Dio`
  - _Requirements: 4.6_

- [x] 14. Update `cacms_flutter/lib/main.dart`
  - Make `main()` async; read `cacms_server_url` from secure storage on startup
  - If absent → show `ServerSetupScreen` as home; if present → construct `ApiClient` with stored URL, show role-selection screen
  - Add settings gear `IconButton` on `_RoleSelectionScreen` AppBar that pushes `ServerSetupScreen`
  - _Requirements: 4.1, 4.7_

- [x] 15. Create Flutter backup screen and wire into admin shell
  - Create `cacms_flutter/lib/features/admin/backup/backup_screen.dart`
    - "Create Backup" button → `POST /v1/admin/backup`; loading indicator disables button during in-progress backup
    - List of backups from `GET /v1/admin/backups` showing filename, size, timestamp
    - "Download" button per row → `GET /v1/admin/backup/{filename}`
  - Update `cacms_flutter/lib/features/admin/admin_shell.dart` to add `BackupScreen` as tab 4
  - _Requirements: 5.8, 5.9_

- [x] 16. Update `.env.example`
  - Document all new variables: `JWT_SECRET`, `CORS_ORIGINS`, `BACKUP_ENCRYPTION_KEY`, `BACKUP_DIR`, `AUTH_RATE_LIMIT`, `SEED_ADMIN_USERNAME`, `SEED_ADMIN_PASSWORD`
  - Mark required vs optional; include example values and comments
  - _Requirements: 6.8_

- [x] 17. Final checkpoint — ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Tasks are ordered by dependency: config → migration → models → auth → middleware → services → backup → seed → Flutter → docs
- Property tests map 1-to-1 with the Correctness Properties in the design document
- The migration uses a nullable-then-NOT NULL back-fill pattern; existing rows are preserved
