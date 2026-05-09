import uuid
from dataclasses import dataclass
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from cacms.services.jwt_service import decode_token

bearer_scheme = HTTPBearer(auto_error=False)

VALID_STAFF_ROLES = {"owner", "admin", "doctor", "receptionist"}


@dataclass
class UserContext:
    sub: str                        # user_id UUID str (or patient_id for patient tokens)
    role: str                       # owner | admin | doctor | receptionist | patient
    clinic_id: Optional[uuid.UUID]
    linked_doctor_id: Optional[uuid.UUID] = None

    @property
    def is_owner(self) -> bool:
        return self.role == "owner"

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"

    @property
    def is_doctor(self) -> bool:
        return self.role == "doctor"

    @property
    def is_receptionist(self) -> bool:
        return self.role == "receptionist"

    @property
    def is_patient(self) -> bool:
        return self.role == "patient"

    @property
    def doctor_id(self) -> Optional[uuid.UUID]:
        if self.role == "doctor":
            return self.linked_doctor_id
        return None

    @property
    def patient_id(self) -> Optional[uuid.UUID]:
        if self.role == "patient":
            return uuid.UUID(self.sub)
        return None


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> UserContext:
    """Extract and validate JWT from Authorization header. Returns UserContext."""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Authorization header missing"},
        )
    payload = decode_token(credentials.credentials)
    sub = payload.get("sub")
    role = payload.get("role")
    clinic_id_str = payload.get("clinic_id")
    linked_doctor_id_str = payload.get("linked_doctor_id")

    if not sub or not role:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Invalid token claims"},
        )

    # Validate role for staff tokens; patient tokens are allowed through
    if role not in VALID_STAFF_ROLES and role != "patient":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": f"Invalid role: {role}"},
        )

    # Parse clinic_id for staff and patient tokens.
    clinic_id: Optional[uuid.UUID] = None
    if not clinic_id_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Missing clinic_id claim"},
        )
    try:
        clinic_id = uuid.UUID(clinic_id_str)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "UNAUTHORIZED", "message": "Invalid clinic_id claim"},
        )

    linked_doctor_id: Optional[uuid.UUID] = None
    if role == "doctor":
        if not linked_doctor_id_str:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"error_code": "UNAUTHORIZED", "message": "Missing linked_doctor_id claim"},
            )
        try:
            linked_doctor_id = uuid.UUID(linked_doctor_id_str)
        except (ValueError, AttributeError):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"error_code": "UNAUTHORIZED", "message": "Invalid linked_doctor_id claim"},
            )

    return UserContext(
        sub=sub,
        role=role,
        clinic_id=clinic_id,
        linked_doctor_id=linked_doctor_id,
    )


def require_roles(*roles: str):
    """Dependency factory that restricts access to specific roles."""
    async def _check(user: UserContext = Depends(get_current_user)) -> UserContext:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"error_code": "FORBIDDEN", "message": "Insufficient permissions"},
            )
        return user
    return _check


# Pre-built role dependencies for use in routers
require_owner = require_roles("owner")
require_admin = require_roles("admin")
require_doctor = require_roles("doctor")
require_receptionist = require_roles("receptionist")
require_patient = require_roles("patient")
require_owner_or_admin = require_roles("owner", "admin")
require_owner_or_admin_or_receptionist = require_roles("owner", "admin", "receptionist")
require_staff = require_roles("owner", "admin", "doctor", "receptionist")
require_admin_or_doctor = require_roles("admin", "doctor")
require_owner_or_admin_or_doctor = require_roles("owner", "admin", "doctor")
require_owner_or_admin_or_doctor_or_receptionist = require_roles("owner", "admin", "doctor", "receptionist")
