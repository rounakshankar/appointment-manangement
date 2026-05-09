# Design Document: CACMS Phase 1 Deployment Foundation

## Overview

This document describes the technical design for hardening the CACMS FastAPI + PostgreSQL backend
and Flutter frontend for real clinic deployment. The changes address six areas: a real users table
with bcrypt authentication, role-based access control, per-clinic data isolation via `clinic_id`,
a Flutter server setup screen, an encrypted backup system, and production configuration hardening.

All changes are backward-compatible: existing queue, consultation, and payment workflows continue
to function. The Alembic migration back-fills all existing rows so no data is lost.

---

## Architecture

```mermaid
graph TD
    subgraph Flutter Client
        A[main.dart startup] -->|no cacms_server_url| B[ServerSetupScreen]
        A -->|url exists| C[RoleSelectionScreen]
        B -->|GET /health OK + Save| C
        C --> D[AdminShell]
        D --> E[BackupScreen tab 5]
    end

    subgraph FastAPI Backend
        F[POST /v1/auth/login] -->|slowapi 10/min| G[users table lookup]
        G -->|bcrypt.checkpw| H[create_token sub=user_id role clinic_id]
        I[All business endpoints] --> J[get_current_user → UserContext]
        J --> K[clinic_id filter on every query]
        L[POST /v1/admin/backup] --> M[pg_dump subprocess]
        M --> N[gzip | AES-256-GCM]
        N --> O[BACKUP_DIR/*.enc]
    end

    subgraph PostgreSQL
        P[clinics] --> Q[users]
        P --> R[patients / doctors / appointments / consultations / services / payments / audit_logs]
    end

    Flutter Client -->|JWT Bearer| FastAPI Backend
    FastAPI Backend --> PostgreSQL
```

### Migration sequence

```
0001_initial_schema  (existing)
        ↓
0002_clinic_id_and_users  (new)
  - creates clinics table
  - creates users table
  - adds clinic_id FK to all business tables
  - back-fills existing rows
  - adds indexes
```

---

## Components and Interfaces

### Backend components

#### `cacms/models/user.py` (new)

SQLAlchemy ORM model for the `users` table.

#### `cacms/models/clinic.py` (new)

SQLAlchemy ORM model for the `clinics` table.

#### `cacms/routers/auth.py` (modified)

- Remove `ADMIN_USERNAME`, `_ADMIN_PASSWORD_HASH`, `_get_admin_password_hash`.
- Login now queries `users` table by `username`, calls `bcrypt.checkpw`, issues JWT with
  `sub=user_id`, `role=role`, `clinic_id=clinic_id`.
- Apply `slowapi` `@limiter.limit(settings.AUTH_RATE_LIMIT)` to `/login` and `/request-otp`.

#### `cacms/routers/backup.py` (new)

Three endpoints under `/v1/admin/backup`:
- `POST /v1/admin/backup` — trigger backup (owner/admin only)
- `GET /v1/admin/backups` — list backup files
- `GET /v1/admin/backup/{filename}` — stream download

#### `cacms/middleware/auth_middleware.py` (modified)

- `UserContext` gains `clinic_id: uuid.UUID` field.
- New dependency factories: `require_owner`, `require_receptionist`, `require_owner_or_admin`.
- `get_current_user` validates `role` is one of `{owner, admin, doctor, receptionist}`.

#### `cacms/services/backup_service.py` (new)

- `trigger_backup()` — runs `pg_dump` via `subprocess`, pipes through gzip + AES-256-GCM,
  writes to `BACKUP_DIR`.
- `list_backups()` — scans `BACKUP_DIR` for `*.enc` files, returns metadata.
- `get_backup_path(filename)` — validates filename and returns path.

#### `cacms/config.py` (modified)

```python
class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://..."
    JWT_SECRET: str  # no default — raises ValidationError if absent
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60
    OTP_TTL_SECONDS: int = 300
    CORS_ORIGINS: list[str] = []          # parsed from comma-separated env var
    BACKUP_ENCRYPTION_KEY: str = ""       # empty = backup disabled
    BACKUP_DIR: str = "/var/backups/cacms"
    AUTH_RATE_LIMIT: str = "10/minute"
    SEED_ADMIN_USERNAME: str = ""
    SEED_ADMIN_PASSWORD: str = ""

    @field_validator("JWT_SECRET")
    @classmethod
    def jwt_secret_must_be_set(cls, v: str) -> str:
        if not v:
            raise ValueError("JWT_SECRET must be set")
        return v

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def parse_cors(cls, v):
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v
```

#### `cacms/main.py` (modified)

- Replace `allow_origins=["*"]` with `allow_origins=settings.CORS_ORIGINS`.
- Add `slowapi` `Limiter` and `_rate_limit_exceeded_handler`.
- Register `backup.router`.

#### `seed_admin.py` (new)

Standalone script (not a migration) that reads `SEED_ADMIN_USERNAME` / `SEED_ADMIN_PASSWORD`
from env, validates password length ≥ 12, hashes with bcrypt cost 12, inserts into `users`
with `role="owner"`.

### Flutter components

#### `cacms_flutter/lib/features/setup/server_setup_screen.dart` (new)

- Text field for URL, "Test Connection" button, "Save" button.
- Validates URL format before sending request.
- Sends `GET {url}/health`, checks for `{"status": "ok"}`.
- On success + Save: writes to `flutter_secure_storage` under key `cacms_server_url`,
  navigates to `_RoleSelectionScreen`.

#### `cacms_flutter/lib/core/api/api_client.dart` (modified)

- Remove compile-time `kBackendBaseUrl` constant dependency.
- `ApiClient.create()` static async factory reads `cacms_server_url` from
  `flutter_secure_storage` before constructing `Dio`.

#### `cacms_flutter/lib/main.dart` (modified)

- `main()` becomes `async`; reads `cacms_server_url` from secure storage.
- If absent → show `ServerSetupScreen` as home.
- If present → construct `ApiClient` with stored URL, show `_RoleSelectionScreen`.
- Add settings gear `IconButton` on `_RoleSelectionScreen` AppBar → pushes `ServerSetupScreen`.

#### `cacms_flutter/lib/features/admin/backup/backup_screen.dart` (new)

- "Create Backup" button → `POST /v1/admin/backup`.
- List of backups from `GET /v1/admin/backups`.
- Each row has filename, size, timestamp, and "Download" button → `GET /v1/admin/backup/{filename}`.
- Loading state disables button during in-progress backup.

#### `cacms_flutter/lib/features/admin/admin_shell.dart` (modified)

- Add tab 4: `BackupScreen`.

---

## Data Models

### `clinics` table (new)

| Column | Type | Constraints |
|---|---|---|
| `clinic_id` | UUID | PK, default gen_random_uuid() |
| `name` | TEXT | NOT NULL |
| `created_at` | TIMESTAMPTZ | NOT NULL, default now() |

### `users` table (new)

| Column | Type | Constraints |
|---|---|---|
| `user_id` | UUID | PK, default gen_random_uuid() |
| `username` | TEXT | UNIQUE NOT NULL |
| `password_hash` | TEXT | NOT NULL |
| `role` | TEXT | NOT NULL, CHECK role IN ('owner','admin','doctor','receptionist') |
| `linked_doctor_id` | UUID | FK → doctors.doctor_id, nullable |
| `active` | BOOLEAN | NOT NULL, default true |
| `clinic_id` | UUID | NOT NULL, FK → clinics.clinic_id |
| `created_at` | TIMESTAMPTZ | NOT NULL, default now() |

### Business tables — `clinic_id` column added

Each of `patients`, `doctors`, `appointments`, `consultations`, `services`, `payments`,
`audit_logs` gains:

| Column | Type | Constraints |
|---|---|---|
| `clinic_id` | UUID | NOT NULL, FK → clinics.clinic_id |

Plus a non-unique index `idx_{table}_clinic_id`.

### `UserContext` dataclass (modified)

```python
@dataclass
class UserContext:
    sub: str           # user_id UUID str
    role: str          # owner | admin | doctor | receptionist
    clinic_id: uuid.UUID
```

### JWT payload (modified)

```json
{
  "sub": "<user_id>",
  "role": "admin",
  "clinic_id": "<clinic_id>",
  "exp": 1234567890
}
```

### Backup file format

```
[12-byte nonce][salt 16 bytes][ciphertext + 16-byte GCM tag]
```

The key derivation uses PBKDF2-HMAC-SHA256 with the `BACKUP_ENCRYPTION_KEY` env var as
password, a random 16-byte salt, and 100,000 iterations to produce a 32-byte AES key.
The nonce and salt are prepended to the file so decryption is self-contained.

---

## Alembic Migration 0002: `clinic_id_and_users`

```python
# revision: 0002
# down_revision: 0001

def upgrade():
    # 1. Create clinics table
    op.create_table("clinics", ...)

    # 2. Seed one clinic, capture its UUID
    clinic_id = op.get_bind().execute(
        text("INSERT INTO clinics (name) VALUES ('Default Clinic') RETURNING clinic_id")
    ).scalar()

    # 3. Add clinic_id column to each business table (nullable first for back-fill)
    for table in ["patients", "doctors", "appointments", "consultations",
                  "services", "payments", "audit_logs"]:
        op.add_column(table, sa.Column("clinic_id", UUID, nullable=True))
        op.execute(f"UPDATE {table} SET clinic_id = '{clinic_id}'")
        op.alter_column(table, "clinic_id", nullable=False)
        op.create_foreign_key(f"fk_{table}_clinic", table, "clinics", ["clinic_id"], ["clinic_id"])
        op.create_index(f"idx_{table}_clinic_id", table, ["clinic_id"])

    # 4. Create users table
    op.create_table("users", ...)
    op.create_index("idx_users_clinic_id", "users", ["clinic_id"])

def downgrade():
    op.drop_table("users")
    for table in [...]:
        op.drop_index(f"idx_{table}_clinic_id", table_name=table)
        op.drop_constraint(f"fk_{table}_clinic", table, type_="foreignkey")
        op.drop_column(table, "clinic_id")
    op.drop_table("clinics")
```

**Backward compatibility**: The migration uses a nullable-then-NOT NULL pattern so the
back-fill runs before the constraint is enforced. Existing rows are preserved with the
seeded clinic's UUID. The `0001` migration is untouched.

---

## Exact Changes to Existing Files

| File | Change |
|---|---|
| `cacms/config.py` | Add `JWT_SECRET` (no default), `CORS_ORIGINS`, `BACKUP_ENCRYPTION_KEY`, `BACKUP_DIR`, `AUTH_RATE_LIMIT`, validators |
| `cacms/main.py` | Replace wildcard CORS; add slowapi limiter + handler; register backup router |
| `cacms/routers/auth.py` | Remove hardcoded credentials; query `users` table; add rate limit decorators; include `clinic_id` in JWT |
| `cacms/middleware/auth_middleware.py` | Add `clinic_id` to `UserContext`; add `require_owner`, `require_receptionist`, `require_owner_or_admin`; validate role enum |
| `cacms/models/patient.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/doctor.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/appointment.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/consultation.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/service.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/payment.py` | Add `clinic_id` mapped column + FK |
| `cacms/models/audit_log.py` | Add `clinic_id` mapped column + FK |
| `cacms_flutter/lib/main.dart` | Async startup; check secure storage for URL; conditional routing; settings gear icon |
| `cacms_flutter/lib/core/api/api_client.dart` | Read base URL from secure storage instead of compile-time constant |
| `cacms_flutter/lib/features/admin/admin_shell.dart` | Add BackupScreen as tab 4 |
| `.env.example` | Document all new env vars |

New files:

| File | Purpose |
|---|---|
| `cacms/models/clinic.py` | Clinic ORM model |
| `cacms/models/user.py` | User ORM model |
| `cacms/routers/backup.py` | Backup endpoints |
| `cacms/services/backup_service.py` | pg_dump + gzip + AES-256-GCM logic |
| `cacms/migrations/versions/0002_clinic_id_and_users.py` | Alembic migration |
| `seed_admin.py` | One-time owner account seeder |
| `cacms_flutter/lib/features/setup/server_setup_screen.dart` | Server URL setup screen |
| `cacms_flutter/lib/features/admin/backup/backup_screen.dart` | Backup management screen |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions
of a system — essentially, a formal statement about what the system should do. Properties serve
as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Bcrypt hash round-trip

*For any* non-empty password string, hashing it with the auth service's hash function should
produce a bcrypt hash with cost factor ≥ 12 that passes `bcrypt.checkpw` with the original
password, and fails `bcrypt.checkpw` with any different password.

**Validates: Requirements 1.2, 1.3**

### Property 2: Seed script rejects short passwords

*For any* password string with length < 12, the seed admin script SHALL raise an error and
exit without writing any record to the `users` table. *For any* password string with length
≥ 12, the script SHALL succeed and the resulting `users` row SHALL have a valid bcrypt hash.

**Validates: Requirements 1.5**

### Property 3: JWT role claim round-trip

*For any* user record with a role in `{owner, admin, doctor, receptionist}`, calling
`create_token` and then `decode_token` on the result should return a payload whose `role`
claim equals the original role exactly.

**Validates: Requirements 2.1**

### Property 4: Invalid role tokens are rejected

*For any* JWT whose `role` claim is a string not in `{owner, admin, doctor, receptionist}`,
`get_current_user` SHALL raise HTTP 401.

**Validates: Requirements 2.2**

### Property 5: Unauthorized role returns 403

*For any* protected endpoint and *for any* user whose role is not in that endpoint's allowed
set, the request SHALL return HTTP 403 with `error_code: "FORBIDDEN"`.

**Validates: Requirements 2.4**

### Property 6: clinic_id is always set from user context on create

*For any* authenticated user with a `clinic_id` and *for any* business record creation
request, the persisted record's `clinic_id` SHALL equal the user's `clinic_id`, regardless
of any `clinic_id` value supplied in the request body.

**Validates: Requirements 3.4**

### Property 7: Cross-clinic access returns 404

*For any* business record belonging to clinic A and *for any* user whose `clinic_id` is B
where A ≠ B, any read or write request targeting that record SHALL return HTTP 404.

**Validates: Requirements 3.5**

### Property 8: Backup encryption round-trip

*For any* byte stream representing pg_dump output, encrypting it with `backup_service.encrypt`
and then decrypting with `backup_service.decrypt` using the same key SHALL return the original
byte stream exactly.

**Validates: Requirements 5.2**

### Property 9: Failed pg_dump leaves no partial file

*For any* pg_dump invocation that exits with a non-zero code, the `BACKUP_DIR` SHALL contain
no new files after the failed attempt (the backup directory state is unchanged).

**Validates: Requirements 5.7**

### Property 10: CORS_ORIGINS parses comma-separated strings correctly

*For any* non-empty comma-separated string of origin values, `Settings.CORS_ORIGINS` SHALL
equal the list of trimmed, non-empty origin strings produced by splitting on commas.

**Validates: Requirements 6.2**

### Property 11: Rate limiter blocks excess auth requests

*For any* IP address that sends more than the configured limit of requests to
`POST /v1/auth/login` within a 60-second window, every request beyond the limit SHALL
return HTTP 429 with `error_code: "RATE_LIMIT_EXCEEDED"`.

**Validates: Requirements 6.4, 6.5**

---

## Error Handling

| Scenario | HTTP | `error_code` |
|---|---|---|
| Missing or invalid JWT | 401 | `UNAUTHORIZED` |
| Role not in permitted set for endpoint | 403 | `FORBIDDEN` |
| Record belongs to different clinic | 404 | (standard not found) |
| `BACKUP_ENCRYPTION_KEY` not set | 503 | `BACKUP_NOT_CONFIGURED` |
| `pg_dump` exits non-zero | 500 | `BACKUP_FAILED` |
| Rate limit exceeded on auth endpoint | 429 | `RATE_LIMIT_EXCEEDED` |
| `JWT_SECRET` absent at startup | — | `ValueError` (app refuses to start) |
| Seed password < 12 chars | — | non-zero exit + stderr message |
| Malformed URL in ServerSetupScreen | — | inline validation error, no request sent |
| Health check returns non-200 or wrong body | — | inline error message in setup screen |

---

## Testing Strategy

### Unit tests (example-based)

- `test_config.py`: verify `Settings` raises `ValueError` when `JWT_SECRET` is absent;
  verify `CORS_ORIGINS` defaults to `[]` with a warning when env var is absent.
- `test_auth_router.py`: login with correct credentials returns 200 + JWT; login with wrong
  password returns 401; login with unknown username returns 401; doctor login no longer
  accepts any non-empty password.
- `test_backup_router.py`: owner and admin can trigger backup; doctor and receptionist get
  403; missing `BACKUP_ENCRYPTION_KEY` returns 503; download endpoint streams file bytes.
- `test_seed_admin.py`: seeding with valid credentials creates a `users` row with bcrypt hash.
- Flutter widget tests: `ServerSetupScreen` shows on first launch; settings gear navigates
  back to setup; `BackupScreen` shows button and list.

### Property-based tests (Hypothesis)

The project already uses Hypothesis. Each property below maps to a single `@given` test
running ≥ 100 iterations.

- **Feature: cacms-phase1-deployment-foundation, Property 1**: `st.text(min_size=1)` →
  hash → checkpw round-trip + cost factor check.
- **Feature: cacms-phase1-deployment-foundation, Property 2**: `st.text()` filtered by
  length → seed script accept/reject boundary.
- **Feature: cacms-phase1-deployment-foundation, Property 3**: `st.sampled_from(VALID_ROLES)`
  → create_token → decode_token → role preserved.
- **Feature: cacms-phase1-deployment-foundation, Property 4**: `st.text()` filtered to
  exclude valid roles → decode raises 401.
- **Feature: cacms-phase1-deployment-foundation, Property 5**: `st.sampled_from(endpoints)`
  × `st.sampled_from(roles)` → 403 when role not permitted.
- **Feature: cacms-phase1-deployment-foundation, Property 6**: `st.uuids()` for clinic_id
  → create record → verify persisted clinic_id matches.
- **Feature: cacms-phase1-deployment-foundation, Property 7**: two distinct `st.uuids()` →
  cross-clinic access returns 404.
- **Feature: cacms-phase1-deployment-foundation, Property 8**: `st.binary()` → encrypt →
  decrypt → identity.
- **Feature: cacms-phase1-deployment-foundation, Property 9**: mock pg_dump to fail →
  assert no new files in BACKUP_DIR.
- **Feature: cacms-phase1-deployment-foundation, Property 10**: `st.lists(st.text(...))` →
  join with commas → parse → list equality.
- **Feature: cacms-phase1-deployment-foundation, Property 11**: `st.integers(min_value=11)`
  requests → assert all beyond limit return 429.

### Integration tests

- Full login → JWT → protected endpoint flow with a real test database.
- Migration 0002 applied to a database with existing rows: verify all rows have non-null
  `clinic_id` after migration.
- Backup trigger → file written to temp dir → decrypt + decompress → valid SQL dump header.
