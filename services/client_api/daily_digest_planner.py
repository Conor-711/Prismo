from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import NAMESPACE_URL, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from services.client_api.notification_planner import next_allowed_delivery_at
from services.client_api.state_store import ClientStateStore, DailyDigestTarget


@dataclass(frozen=True)
class DailyDigestPlanResult:
    queued: int = 0
    existing: int = 0
    disabled: int = 0
    not_due: int = 0
    no_changes: int = 0


class DailyDigestPlanner:
    def __init__(self, state_store: ClientStateStore):
        self.state_store = state_store

    def plan(
        self,
        signals: list[dict[str, Any]],
        *,
        now: datetime | None = None,
    ) -> DailyDigestPlanResult:
        current_time = (now or datetime.now(UTC)).astimezone(UTC)
        totals = {"queued": 0, "existing": 0, "disabled": 0, "not_due": 0, "no_changes": 0}
        for target in self.state_store.daily_digest_targets():
            preferences = target.preferences
            if not preferences.daily_digest_enabled:
                totals["disabled"] += 1
                continue

            zone = _time_zone(target.time_zone)
            local_now = current_time.astimezone(zone)
            local_minutes = local_now.hour * 60 + local_now.minute
            if local_minutes < preferences.daily_digest_minutes:
                totals["not_due"] += 1
                continue

            selected = _signals_for_target(signals, target, current_time)
            if not selected:
                totals["no_changes"] += 1
                continue

            digest_id = uuid5(
                NAMESPACE_URL,
                f"bsmart:daily-digest:{target.installation_id}:{local_now.date().isoformat()}",
            )
            title = "Your bSmart daily brief"
            body = _digest_body(selected)
            data_as_of = max(
                (_parse_time(signal.get("dataAsOf")) for signal in selected),
                default=current_time,
            )
            if data_as_of == datetime.min.replace(tzinfo=UTC):
                data_as_of = current_time
            digest = self.state_store.put_daily_digest(
                installation_id=target.installation_id,
                digest_id=digest_id,
                local_date=local_now.date().isoformat(),
                generated_at=current_time,
                period_start=current_time - timedelta(hours=24),
                period_end=current_time,
                data_as_of=data_as_of,
                title=title,
                summary=body,
                signals=selected,
            )
            title = digest.title
            body = digest.summary
            scheduled_at = next_allowed_delivery_at(
                target.time_zone,
                preferences,
                current_time,
            )
            inserted = self.state_store.enqueue_notification(
                installation_id=target.installation_id,
                signal_id=digest_id,
                ticker="PORTFOLIO",
                title=title,
                body=body,
                deep_link="bsmart://today/digest",
                status_value="pending",
                reason="quiet_hours" if scheduled_at > current_time else "daily_digest",
                scheduled_at=scheduled_at,
            )
            totals["queued" if inserted else "existing"] += 1
        return DailyDigestPlanResult(**totals)


def _signals_for_target(
    signals: list[dict[str, Any]],
    target: DailyDigestTarget,
    now: datetime,
) -> list[dict[str, Any]]:
    cutoff = now - timedelta(hours=24)
    muted = set(target.preferences.muted_tickers)
    selected = [
        signal
        for signal in signals
        if str(signal.get("ticker", "")).upper() in target.tickers
        and str(signal.get("ticker", "")).upper() not in muted
        and signal.get("dataStatus") == "current"
        and _parse_time(signal.get("occurredAt")) >= cutoff
        and _parse_time(signal.get("occurredAt")) <= now
    ]
    priority = {"critical": 0, "important": 1, "notable": 2}
    return sorted(
        selected,
        key=lambda signal: (
            priority.get(str(signal.get("priority")), 3),
            -_parse_time(signal.get("occurredAt")).timestamp(),
        ),
    )


def _digest_body(signals: list[dict[str, Any]]) -> str:
    tickers = list(dict.fromkeys(str(signal["ticker"]).upper() for signal in signals))
    attention = sum(
        signal.get("priority") == "critical" or signal.get("kind") == "divergence"
        for signal in signals
    )
    confirmations = sum(signal.get("kind") == "confirmation" for signal in signals)
    ticker_label = ", ".join(tickers[:3])
    if len(tickers) > 3:
        ticker_label += f" +{len(tickers) - 3}"
    parts = [f"{len(signals)} changes across {ticker_label}"]
    if attention:
        parts.append(f"{attention} need attention")
    if confirmations:
        parts.append(f"{confirmations} confirmed")
    return " · ".join(parts)


def _parse_time(value: Any) -> datetime:
    if not isinstance(value, str):
        return datetime.min.replace(tzinfo=UTC)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return datetime.min.replace(tzinfo=UTC)


def _time_zone(identifier: str) -> ZoneInfo:
    try:
        return ZoneInfo(identifier)
    except ZoneInfoNotFoundError:
        return ZoneInfo("UTC")
