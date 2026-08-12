from __future__ import annotations

from copy import deepcopy
from datetime import UTC, datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import UUID, uuid4

from services.client_api.config import REPO_ROOT
from services.client_api.notification_planner import NotificationPlanner
from services.client_api.read_models import FixtureReadModelRepository
from services.client_api.schemas import (
    DeviceRegistrationInput,
    InstallationRegistration,
    NotificationPreferences,
    PortfolioEntryInput,
)
from services.client_api.state_store import ClientStateStore


def test_planner_queues_once_and_respects_muted_tickers() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'notifications.db'}")
        try:
            active = _installation(store, ticker="HOOD", apns_token="active")
            muted = _installation(store, ticker="HOOD", apns_token="muted")
            store.put_notification_preferences(active, _preferences(quiet_hours_enabled=False))
            store.put_notification_preferences(
                muted,
                _preferences(quiet_hours_enabled=False, muted_tickers=["HOOD"]),
            )
            signal = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()[0]
            planner = NotificationPlanner(store)

            first = planner.plan_signal(signal, now=datetime(2026, 8, 4, 12, tzinfo=UTC))
            second = planner.plan_signal(signal, now=datetime(2026, 8, 4, 12, tzinfo=UTC))
            deliveries = store.notification_deliveries()

            assert first.queued == 1
            assert first.skipped == 1
            assert second.existing == 2
            assert len(deliveries) == 2
            assert {item.status for item in deliveries} == {"pending", "skipped"}
            assert next(item for item in deliveries if item.status == "skipped").reason == "ticker_muted"
        finally:
            store.dispose()


def test_planner_defers_delivery_until_quiet_hours_end() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'quiet-hours.db'}")
        try:
            installation_id = _installation(store, ticker="NVDA", apns_token="quiet")
            store.put_notification_preferences(
                installation_id,
                _preferences(
                    quiet_hours_enabled=True,
                    quiet_hours_start_minutes=22 * 60,
                    quiet_hours_end_minutes=7 * 60,
                ),
            )
            signal = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()[1]

            result = NotificationPlanner(store).plan_signal(
                signal,
                now=datetime(2026, 8, 4, 23, 30, tzinfo=UTC),
            )
            delivery = store.notification_deliveries()[0]

            assert result.deferred == 1
            assert delivery.reason == "quiet_hours"
            assert delivery.scheduled_at == datetime(2026, 8, 5, 7, tzinfo=UTC)
        finally:
            store.dispose()


def test_planner_applies_ticker_cooldown_to_distinct_signals() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'cooldown.db'}")
        try:
            installation_id = _installation(store, ticker="HOOD", apns_token="cooldown")
            store.put_notification_preferences(
                installation_id,
                _preferences(quiet_hours_enabled=False),
            )
            signal = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()[0]
            second_signal = deepcopy(signal)
            second_signal["id"] = str(uuid4())
            second_signal["title"] = "A second important HOOD signal"
            planner = NotificationPlanner(store)
            now = datetime(2026, 8, 4, 12, tzinfo=UTC)

            first = planner.plan_signal(signal, now=now)
            second = planner.plan_signal(second_signal, now=now)
            deliveries = store.notification_deliveries()

            assert first.queued == 1
            assert second.skipped == 1
            assert len(deliveries) == 2
            assert deliveries[1].reason == "ticker_cooldown"
        finally:
            store.dispose()


def _installation(store: ClientStateStore, *, ticker: str, apns_token: str) -> UUID:
    installation_id = uuid4()
    token, _ = store.register_installation(InstallationRegistration(
        installationId=installation_id,
        platform="ios",
        appVersion="1.0",
        locale="en_US",
        timeZone="UTC",
    ))
    authenticated = store.authenticate(token)
    assert authenticated is not None
    store.upsert_portfolio(
        installation_id,
        uuid4(),
        PortfolioEntryInput(
            ticker=ticker,
            companyName=ticker,
            entryKind="watchlist",
        ),
    )
    store.put_device(installation_id, DeviceRegistrationInput(
        apnsToken=apns_token,
        environment="development",
        appVersion="1.0",
        locale="en_US",
        timeZone="UTC",
    ))
    return installation_id


def _preferences(
    *,
    quiet_hours_enabled: bool,
    quiet_hours_start_minutes: int = 22 * 60,
    quiet_hours_end_minutes: int = 7 * 60,
    muted_tickers: list[str] | None = None,
) -> NotificationPreferences:
    return NotificationPreferences(
        instantAlertsEnabled=True,
        dailyDigestEnabled=True,
        dailyDigestMinutes=8 * 60,
        quietHoursEnabled=quiet_hours_enabled,
        quietHoursStartMinutes=quiet_hours_start_minutes,
        quietHoursEndMinutes=quiet_hours_end_minutes,
        mutedTickers=muted_tickers or [],
    )
