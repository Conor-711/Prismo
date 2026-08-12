from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import NAMESPACE_URL, UUID, uuid4, uuid5

from services.client_api.config import REPO_ROOT
from services.client_api.daily_digest_planner import DailyDigestPlanner
from services.client_api.read_models import FixtureReadModelRepository
from services.client_api.schemas import (
    DeviceRegistrationInput,
    InstallationRegistration,
    NotificationPreferences,
    PortfolioEntryInput,
)
from services.client_api.state_store import ClientStateStore


def test_daily_digest_queues_once_for_local_day() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'daily-digest.db'}")
        try:
            _installation(store, ticker="HOOD", digest_minutes=8 * 60)
            signals = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()
            planner = DailyDigestPlanner(store)
            now = _digest_time(signals, "HOOD")

            first = planner.plan(signals, now=now)
            second = planner.plan(signals, now=now)
            delivery = store.notification_deliveries()[0]
            digest = store.latest_daily_digest(delivery.installation_id)

            assert first.queued == 1
            assert second.existing == 1
            assert digest is not None
            assert digest.digest_id == delivery.signal_id
            assert digest.local_date == now.date().isoformat()
            assert digest.generated_at == now
            assert digest.period_start == now - timedelta(hours=24)
            assert digest.period_end == now
            assert digest.summary == delivery.body
            assert [signal["ticker"] for signal in digest.signals] == ["HOOD"]
            assert delivery.ticker == "PORTFOLIO"
            assert delivery.status == "pending"
            assert delivery.reason == "daily_digest"
            assert delivery.deep_link == "bsmart://today/digest"
            assert "1 changes across HOOD" in delivery.body
            assert "1 need attention" in delivery.body
        finally:
            store.dispose()


def test_daily_digest_respects_schedule_disabled_state_and_muted_ticker() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'digest-policy.db'}")
        try:
            _installation(store, ticker="HOOD", digest_minutes=9 * 60, token="not-due")
            _installation(
                store,
                ticker="HOOD",
                digest_minutes=8 * 60,
                token="disabled",
                daily_digest_enabled=False,
            )
            _installation(
                store,
                ticker="HOOD",
                digest_minutes=8 * 60,
                token="muted",
                muted_tickers=["HOOD"],
            )
            signals = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()

            result = DailyDigestPlanner(store).plan(
                signals,
                now=_digest_time(signals, "HOOD"),
            )

            assert result.not_due == 1
            assert result.disabled == 1
            assert result.no_changes == 1
            assert store.notification_deliveries() == []
        finally:
            store.dispose()


def test_daily_digest_defers_during_quiet_hours() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'digest-quiet.db'}")
        try:
            _installation(
                store,
                ticker="HOOD",
                digest_minutes=8 * 60,
                quiet_hours_enabled=True,
                quiet_start_minutes=8 * 60,
                quiet_end_minutes=9 * 60,
            )
            signals = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()

            now = _digest_time(signals, "HOOD")
            result = DailyDigestPlanner(store).plan(signals, now=now)
            delivery = store.notification_deliveries()[0]

            assert result.queued == 1
            assert delivery.reason == "quiet_hours"
            assert delivery.scheduled_at == now.replace(hour=9, minute=0)
        finally:
            store.dispose()


def test_daily_digest_delivery_reuses_an_existing_immutable_snapshot() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'digest-recovery.db'}")
        try:
            installation_id = _installation(store, ticker="HOOD", digest_minutes=8 * 60)
            signals = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()
            now = _digest_time(signals, "HOOD")
            digest_id = uuid5(
                NAMESPACE_URL,
                f"bsmart:daily-digest:{installation_id}:{now.date().isoformat()}",
            )
            store.put_daily_digest(
                installation_id=installation_id,
                digest_id=digest_id,
                local_date=now.date().isoformat(),
                generated_at=now,
                period_start=now - timedelta(hours=24),
                period_end=now,
                data_as_of=now,
                title="Previously generated brief",
                summary="Original immutable summary",
                signals=[signals[0]],
            )

            result = DailyDigestPlanner(store).plan(signals, now=now)
            delivery = store.notification_deliveries()[0]

            assert result.queued == 1
            assert delivery.title == "Previously generated brief"
            assert delivery.body == "Original immutable summary"
        finally:
            store.dispose()


def _installation(
    store: ClientStateStore,
    *,
    ticker: str,
    digest_minutes: int,
    token: str = "digest-token",
    daily_digest_enabled: bool = True,
    muted_tickers: list[str] | None = None,
    quiet_hours_enabled: bool = False,
    quiet_start_minutes: int = 22 * 60,
    quiet_end_minutes: int = 7 * 60,
) -> UUID:
    installation_id = uuid4()
    store.register_installation(InstallationRegistration(
        installationId=installation_id,
        platform="ios",
        appVersion="1.0",
        locale="en_US",
        timeZone="UTC",
    ))
    store.upsert_portfolio(
        installation_id,
        uuid4(),
        PortfolioEntryInput(ticker=ticker, companyName=ticker, entryKind="watchlist"),
    )
    store.put_notification_preferences(installation_id, NotificationPreferences(
        instantAlertsEnabled=True,
        dailyDigestEnabled=daily_digest_enabled,
        dailyDigestMinutes=digest_minutes,
        quietHoursEnabled=quiet_hours_enabled,
        quietHoursStartMinutes=quiet_start_minutes,
        quietHoursEndMinutes=quiet_end_minutes,
        mutedTickers=muted_tickers or [],
    ))
    store.put_device(installation_id, DeviceRegistrationInput(
        apnsToken=f"{token}-{installation_id}",
        environment="development",
        appVersion="1.0",
        locale="en_US",
        timeZone="UTC",
    ))
    return installation_id


def _digest_time(signals: list[dict], ticker: str) -> datetime:
    signal = next(row for row in signals if row["ticker"] == ticker)
    occurred_at = datetime.fromisoformat(signal["occurredAt"].replace("Z", "+00:00")).astimezone(UTC)
    candidate = occurred_at.replace(hour=8, minute=5, second=0, microsecond=0)
    return candidate if candidate >= occurred_at else candidate + timedelta(days=1)
