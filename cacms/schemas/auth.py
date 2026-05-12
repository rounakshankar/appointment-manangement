from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: str | None = None
    clinic_id: str | None = None
    linked_doctor_id: str | None = None


class OtpRequest(BaseModel):
    phone: str


class OtpVerifyRequest(BaseModel):
    phone: str
    otp: str


class ClinicRegistrationRequest(BaseModel):
    clinic_name: str
    owner_username: str
    owner_password: str
    owner_name: str | None = None
    owner_email: str | None = None
    owner_phone: str | None = None


class ClinicRegistrationResponse(BaseModel):
    clinic_id: str
    clinic_name: str
    owner_user_id: str
    access_token: str
    token_type: str = "bearer"
