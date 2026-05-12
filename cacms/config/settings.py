import logging
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/cacms"

    # --- Runtime ---
    ENVIRONMENT: str = "development"

    # --- Redis (optional; health check and future metering / Celery) ---
    REDIS_URL: str = ""

    # --- Monitoring ---
    SENTRY_DSN: str = ""
    SENTRY_TRACES_SAMPLE_RATE: float = 0.0

    # --- Auth (required, no defaults) ---
    JWT_SECRET: str = ""
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60

    # --- OTP ---
    OTP_TTL_SECONDS: int = 300

    # --- CORS: stored as raw comma-separated string, exposed as list via property ---
    CORS_ORIGINS: str = ""

    # --- Backup ---
    BACKUP_ENCRYPTION_KEY: str = ""
    BACKUP_DIR: str = "/var/backups/cacms"

    # --- Rate limiting ---
    AUTH_RATE_LIMIT: str = "10/minute"

    # --- Seeding (used by seed_admin.py only) ---
    SEED_ADMIN_USERNAME: str = ""
    SEED_ADMIN_PASSWORD: str = ""

    # --- Super-admin (static token auth, not JWT) ---
    SUPERADMIN_TOKEN: str = ""

    # --- Email (SMTP — optional; when not configured, emails are logged only) ---
    EMAIL_FROM: str = ""
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""

    @field_validator("JWT_SECRET")
    @classmethod
    def jwt_secret_must_be_set(cls, v: str) -> str:
        if not v:
            raise ValueError(
                "JWT_SECRET must be set in the environment. "
                "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        return v

    @property
    def cors_origins_list(self) -> list[str]:
        """Parse CORS_ORIGINS from comma-separated string."""
        if not self.CORS_ORIGINS:
            return []
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @model_validator(mode="after")
    def validate_production_settings(self) -> "Settings":
        if self.ENVIRONMENT == "production" and not self.SUPERADMIN_TOKEN:
            raise ValueError(
                "SUPERADMIN_TOKEN must be set in production. "
                "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        if not self.cors_origins_list:
            logger.warning(
                "CORS_ORIGINS is not configured — all cross-origin requests will be blocked. "
                "Set CORS_ORIGINS in your .env file (comma-separated list of allowed origins)."
            )
        return self


settings = Settings()
