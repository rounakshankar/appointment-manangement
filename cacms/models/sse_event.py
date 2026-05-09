import uuid
from datetime import datetime
from typing import Any
from sqlalchemy import Text, BigInteger, text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID, JSONB
from cacms.database import Base


class SseEvent(Base):
    __tablename__ = "sse_events"

    event_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    channel: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    event_type: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[Any] = mapped_column(JSONB, nullable=False)
    sequence: Mapped[int] = mapped_column(
        BigInteger, nullable=True, server_default=text("nextval('sse_events_sequence_seq')")
    )
    created_at: Mapped[datetime] = mapped_column(nullable=False, server_default=text("now()"))
