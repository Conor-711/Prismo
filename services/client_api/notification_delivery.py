from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol

from services.client_api.state_store import ClaimedNotification, ClientStateStore


@dataclass(frozen=True)
class PushResult:
    success: bool
    status_code: int | None = None
    reason: str | None = None
    permanent: bool = False
    invalidate_device: bool = False
    retry_after_seconds: int | None = None


class PushProvider(Protocol):
    async def send(self, delivery: ClaimedNotification) -> PushResult: ...

    async def close(self) -> None: ...


@dataclass(frozen=True)
class DispatchResult:
    sent: int = 0
    retried: int = 0
    failed: int = 0


class NotificationDispatcher:
    def __init__(
        self,
        state_store: ClientStateStore,
        provider: PushProvider,
        *,
        default_retry_delay: timedelta = timedelta(minutes=15),
    ):
        self.state_store = state_store
        self.provider = provider
        self.default_retry_delay = default_retry_delay

    async def dispatch_due(
        self,
        *,
        now: datetime | None = None,
        limit: int = 100,
    ) -> DispatchResult:
        current_time = (now or datetime.now(UTC)).astimezone(UTC)
        totals = {"sent": 0, "retried": 0, "failed": 0}
        deliveries = self.state_store.claim_due_notifications(now=current_time, limit=limit)
        for delivery in deliveries:
            try:
                result = await self.provider.send(delivery)
            except Exception as error:
                result = PushResult(success=False, reason=type(error).__name__)

            if result.success:
                totals["sent"] += 1
                self.state_store.finish_notification_attempt(
                    delivery,
                    outcome="sent",
                    status_code=result.status_code,
                    reason=None,
                )
            elif result.permanent:
                totals["failed"] += 1
                self.state_store.finish_notification_attempt(
                    delivery,
                    outcome="failed",
                    status_code=result.status_code,
                    reason=result.reason,
                    invalidate_device=result.invalidate_device,
                )
            else:
                totals["retried"] += 1
                delay = (
                    timedelta(seconds=result.retry_after_seconds)
                    if result.retry_after_seconds is not None
                    else self.default_retry_delay
                )
                self.state_store.finish_notification_attempt(
                    delivery,
                    outcome="retry",
                    status_code=result.status_code,
                    reason=result.reason,
                    retry_at=current_time + delay,
                )
        return DispatchResult(**totals)

    async def close(self) -> None:
        await self.provider.close()
