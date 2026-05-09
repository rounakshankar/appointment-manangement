from typing import Any, Optional
from pydantic import BaseModel


class ErrorResponse(BaseModel):
    error_code: str
    message: str
    detail: Optional[Any] = None


class SSEEvent(BaseModel):
    event_id: str
    event_type: str
    channel: str
    data: dict
