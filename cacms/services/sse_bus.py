"""
SSE Event Bus — in-process async fan-out with persistence.

Maintains one asyncio.Queue per subscriber. On publish, persists the event
to the `sse_events` table (for Last-Event-ID replay) and pushes to all
active subscriber queues on that channel.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any, AsyncGenerator

import cacms.database as _db_module
from cacms.models.sse_event import SseEvent
from cacms.schemas.common import SSEEvent

logger = logging.getLogger(__name__)

# _subscribers[channel][subscriber_id] = asyncio.Queue[SSEEvent]
_subscribers: dict[str, dict[str, asyncio.Queue]] = {}
_lock = asyncio.Lock()


class SSEBus:
    """Singleton in-process SSE event bus."""

    async def publish(
        self,
        channel: str,
        event_type: str,
        data: Any,
        event_id: str | None = None,
    ) -> None:
        """
        Persist an SSE event to the DB, then push to all active subscribers.

        Args:
            channel: Target channel, e.g. ``doctor:{doctor_id}``.
            event_type: Event name, e.g. ``appointment_created``.
            data: JSON-serialisable payload dict.
            event_id: Optional explicit event ID (UUID string). Generated if omitted.
        """
        if event_id is None:
            event_id = str(uuid.uuid4())

        # 1. Persist to DB using a fresh session (publish is called from many contexts)
        # Look up AsyncSessionLocal dynamically so test fixtures can override it.
        db_event: SseEvent | None = None
        try:
            async with _db_module.AsyncSessionLocal() as session:
                db_event = SseEvent(
                    event_id=uuid.UUID(event_id),
                    channel=channel,
                    event_type=event_type,
                    payload=data,
                )
                session.add(db_event)
                await session.commit()
                await session.refresh(db_event)
        except Exception:
            logger.exception("SSEBus: failed to persist event to DB")
            # Still push to live subscribers even if DB write fails
            db_event = None

        # Build the SSEEvent schema object to push to queues
        sse_event = SSEEvent(
            event_id=event_id,
            event_type=event_type,
            channel=channel,
            data=data if isinstance(data, dict) else {"value": data},
        )

        # 2. Push to all active subscriber queues for this channel
        async with _lock:
            channel_subs = _subscribers.get(channel, {})
            dead: list[str] = []
            for sub_id, queue in channel_subs.items():
                try:
                    queue.put_nowait(sse_event)
                except asyncio.QueueFull:
                    logger.warning("SSEBus: queue full for subscriber %s, dropping event", sub_id)
                    dead.append(sub_id)

            # Clean up any full/dead queues
            for sub_id in dead:
                channel_subs.pop(sub_id, None)

    async def subscribe(self, channel: str) -> AsyncGenerator[SSEEvent, None]:
        """
        Register a subscriber queue for *channel* and yield events as they arrive.

        Cleans up the queue on generator close (disconnect / CancelledError).
        """
        subscriber_id = str(uuid.uuid4())
        queue: asyncio.Queue[SSEEvent] = asyncio.Queue(maxsize=256)

        async with _lock:
            if channel not in _subscribers:
                _subscribers[channel] = {}
            _subscribers[channel][subscriber_id] = queue

        logger.debug("SSEBus: subscriber %s registered on channel %s", subscriber_id, channel)

        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=30.0)
                    yield event
                except asyncio.TimeoutError:
                    # Keep-alive: yield a comment-style heartbeat by re-looping.
                    # The caller (SSE endpoint) is responsible for sending keep-alives;
                    # we simply continue waiting.
                    continue
        except (GeneratorExit, asyncio.CancelledError):
            logger.debug("SSEBus: subscriber %s disconnected from channel %s", subscriber_id, channel)
        finally:
            await self.unsubscribe(channel, subscriber_id)

    async def unsubscribe(self, channel: str, subscriber_id: str) -> None:
        """
        Remove a subscriber queue and release its resources.

        Per requirements, resources are released within 30 seconds of disconnect.
        This method is synchronous in effect — the queue is removed immediately.
        """
        async with _lock:
            channel_subs = _subscribers.get(channel)
            if channel_subs is not None:
                channel_subs.pop(subscriber_id, None)
                if not channel_subs:
                    _subscribers.pop(channel, None)
        logger.debug("SSEBus: subscriber %s unsubscribed from channel %s", subscriber_id, channel)


# Singleton instance
sse_bus = SSEBus()
