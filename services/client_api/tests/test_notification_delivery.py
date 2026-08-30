from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import UUID, uuid4

import pytest

from services.client_api.config import REPO_ROOT
from services.client_api.notification_delivery import NotificationDispatcher, PushResult
from services.client_api.notification_planner import NotificationPlanner
from services.client_api.read_models import FixtureReadModelRepository
from services.client_api.schemas import (
    DeviceRegistrationInput,
    InstallationRegistration,
    NotificationPreferences,
    PortfolioEntryInput,
)
from services.client_api.state_store import ClaimedNotification, ClientStateStore


@pytest.mark.anyio
async def test_dispatcher_retries_transient_failure_then_marks_delivery_sent() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'delivery.db'}")
        provider = SequenceProvider([
            PushResult(success=False, status_code=503, reason="ServiceUnavailable"),
            PushResult(success=True, status_code=200),
        ])
        try:
            _install_for_ticker(store, "HOOD", "active-token")
            signal = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()[0]
            start = datetime(2026, 8, 4, 12, tzinfo=UTC)
            NotificationPlanner(store).plan_signal(signal, now=start)
            dispatcher = NotificationDispatcher(
                store,
                provider,
                default_retry_delay=timedelta(minutes=1),
            )

            first = await dispatcher.dispatch_due(now=start)
            second = await dispatcher.dispatch_due(now=start + timedelta(minutes=2))
            delivery = store.notification_deliveries()[0]
            attempts = store.notification_attempts()

            assert first.retried == 1
            assert second.sent == 1
            assert delivery.status == "sent"
            assert [attempt.outcome for attempt in attempts] == ["retry", "sent"]
        finally:
            await provider.close()
            store.dispose()


@pytest.mark.anyio
async def test_dispatcher_fails_permanently_and_removes_invalid_device() -> None:
    with TemporaryDirectory() as directory:
        store = ClientStateStore(f"sqlite:///{Path(directory) / 'invalid-device.db'}")
        provider = SequenceProvider([
            PushResult(
                success=False,
                status_code=410,
                reason="Unregistered",
                permanent=True,
                invalidate_device=True,
            )
        ])
        try:
            _install_for_ticker(store, "NVDA", "invalid-token")
            signal = FixtureReadModelRepository(
                REPO_ROOT / "contracts" / "fixtures"
            ).portfolio_signals()[1]
            start = datetime(2026, 8, 4, 12, tzinfo=UTC)
            NotificationPlanner(store).plan_signal(signal, now=start)

            result = await NotificationDispatcher(store, provider).dispatch_due(now=start)
            delivery = store.notification_deliveries()[0]

            assert result.failed == 1
            assert delivery.status == "failed"
            assert delivery.reason == "Unregistered"
            assert store.notification_targets("NVDA") == []
        finally:
            await provider.close()
            store.dispose()


def _install_for_ticker(store: ClientStateStore, ticker: str, apns_token: str) -> UUID:
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
        dailyDigestEnabled=True,
        dailyDigestMinutes=480,
        quietHoursEnabled=False,
        quietHoursStartMinutes=1320,
        quietHoursEndMinutes=420,
        mutedTickers=[],
    ))
    store.put_device(installation_id, DeviceRegistrationInput(
        apnsToken=apns_token,
        environment="development",
        appVersion="1.0",
        locale="en_US",
        timeZone="UTC",
    ))
    return installation_id


class SequenceProvider:
    def __init__(self, results: list[PushResult]):
        self.results = results
        self.deliveries: list[ClaimedNotification] = []

    async def send(self, delivery: ClaimedNotification) -> PushResult:
        self.deliveries.append(delivery)
        return self.results.pop(0)

    async def close(self) -> None:
        return None
