from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from services.client_api.schemas import NotificationPreferences
from services.client_api.state_store import ClientStateStore


@dataclass(frozen=True)
class NotificationPlanResult:
    queued: int = 0
    deferred: int = 0
    skipped: int = 0
    existing: int = 0


class NotificationPlanner:
    def __init__(
        self,
        state_store: ClientStateStore,
        *,
        ticker_cooldown: timedelta = timedelta(hours=6),
        installation_daily_cap: int = 8,
    ):
        self.state_store = state_store
        self.ticker_cooldown = ticker_cooldown
        self.installation_daily_cap = installation_daily_cap

    def plan_signal(
        self,
        signal: dict[str, Any],
        *,
        now: datetime | None = None,
    ) -> NotificationPlanResult:
        current_time = (now or datetime.now(UTC)).astimezone(UTC)
        signal_id = UUID(str(signal["id"]))
        ticker = str(signal["ticker"]).upper()
        priority = signal.get("priority")
        data_status = signal.get("dataStatus")
        totals = {"queued": 0, "deferred": 0, "skipped": 0, "existing": 0}

        for target in self.state_store.notification_targets(ticker):
            status_value = "pending"
            reason: str | None = None
            scheduled_at = current_time

            if priority not in {"critical", "important"}:
                status_value, reason = "skipped", "daily_digest_priority"
            elif data_status != "current":
                status_value, reason = "skipped", "delayed_data"
            elif not target.preferences.instant_alerts_enabled:
                status_value, reason = "skipped", "instant_alerts_disabled"
            elif ticker in target.preferences.muted_tickers:
                status_value, reason = "skipped", "ticker_muted"
            elif self.state_store.has_active_notification_since(
                target.installation_id,
                ticker=ticker,
                since=current_time - self.ticker_cooldown,
            ):
                status_value, reason = "skipped", "ticker_cooldown"
            elif self.state_store.active_notification_count_since(
                target.installation_id,
                since=current_time - timedelta(hours=24),
            ) >= self.installation_daily_cap:
                status_value, reason = "skipped", "installation_daily_cap"
            else:
                scheduled_at = next_allowed_delivery_at(
                    target.time_zone,
                    target.preferences,
                    current_time,
                )
                if scheduled_at > current_time:
                    reason = "quiet_hours"

            inserted = self.state_store.enqueue_notification(
                installation_id=target.installation_id,
                signal_id=signal_id,
                ticker=ticker,
                title=str(signal["title"]),
                body=str(signal["summary"]),
                deep_link=f"bsmart://signals/{signal_id}",
                status_value=status_value,
                reason=reason,
                scheduled_at=scheduled_at,
            )
            if not inserted:
                totals["existing"] += 1
            elif status_value == "skipped":
                totals["skipped"] += 1
            elif scheduled_at > current_time:
                totals["deferred"] += 1
            else:
                totals["queued"] += 1

        return NotificationPlanResult(**totals)


def next_allowed_delivery_at(
    time_zone: str,
    preferences: NotificationPreferences,
    now: datetime,
) -> datetime:
    if not preferences.quiet_hours_enabled:
        return now
    start = preferences.quiet_hours_start_minutes
    end = preferences.quiet_hours_end_minutes
    if start == end:
        return now

    zone = _time_zone(time_zone)
    local_now = now.astimezone(zone)
    minute = local_now.hour * 60 + local_now.minute
    if start < end:
        is_quiet = start <= minute < end
        end_date = local_now.date()
    else:
        is_quiet = minute >= start or minute < end
        end_date = local_now.date() + (timedelta(days=1) if minute >= start else timedelta())
    if not is_quiet:
        return now

    local_end = datetime.combine(end_date, _minutes_to_time(end), tzinfo=zone)
    return local_end.astimezone(UTC)


def _minutes_to_time(minutes: int) -> time:
    return time(hour=minutes // 60, minute=minutes % 60)


def _time_zone(identifier: str) -> ZoneInfo:
    try:
        return ZoneInfo(identifier)
    except ZoneInfoNotFoundError:
        return ZoneInfo("UTC")
