from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

import httpx
import pytest
import yaml

from services.client_api.config import ClientAPISettings, REPO_ROOT
from services.client_api.daily_digest_planner import DailyDigestPlanner
from services.client_api.main import create_app
from services.client_api.read_models import materialize_fixture_read_models


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@asynccontextmanager
async def make_client(directory: str):
    settings = ClientAPISettings(
        environment="test",
        database_url=f"sqlite:///{Path(directory) / 'client-api-test.db'}",
        read_model_mode="fixture",
        fixture_root=REPO_ROOT / "contracts" / "fixtures",
        session_lifetime_days=1,
    )
    app = create_app(settings)
    transport = httpx.ASGITransport(app=app)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


async def register(client: httpx.AsyncClient) -> tuple[str, str]:
    installation_id = str(uuid4())
    response = await client.post(
        "/v1/installations",
        json={
            "installationId": installation_id,
            "platform": "ios",
            "appVersion": "1.0",
            "locale": "en_US",
            "timeZone": "UTC",
        },
    )
    assert response.status_code == 201
    assert response.json()["installationId"] == installation_id
    return installation_id, response.json()["accessToken"]


@pytest.mark.anyio
async def test_protected_read_models_require_session_and_return_contract_fixtures() -> None:
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            assert (await client.get("/v1/feed")).status_code == 401
            _, token = await register(client)
            headers = {"Authorization": f"Bearer {token}"}

            feed = await client.get("/v1/feed", headers=headers)
            portfolio_history = await client.get("/v1/portfolio/history", headers=headers)
            intelligence = await client.get("/v1/intelligence", headers=headers)
            updates = await client.get("/v1/smart-account-updates", headers=headers)
            accounts = await client.get("/v1/smart-accounts", headers=headers)
            money = await client.get("/v1/smart-money", headers=headers)

            assert feed.status_code == 200
            assert portfolio_history.status_code == 200
            assert portfolio_history.json() == []
            assert len(feed.json()) == 5
            assert feed.headers["etag"].startswith('"')
            assert feed.headers["cache-control"] == "private, max-age=0, must-revalidate"
            assert intelligence.status_code == 200
            assert len(intelligence.json()) == 5
            assert updates.headers["x-bsmart-source-item-count"] == str(len(updates.json()))
            assert updates.headers["x-bsmart-latest-content-at"]
            account_id = accounts.json()[0]["id"]
            evidence = await client.get(
                f"/v1/smart-accounts/{account_id}/evidence",
                headers=headers,
            )
            assert evidence.status_code == 200
            assert all(item["authorId"] == account_id for item in evidence.json())
            assert evidence.headers["x-bsmart-source-item-count"] == str(len(evidence.json()))
            assert money.headers["x-bsmart-source-item-count"] == str(len(money.json()))
            assert money.headers["x-bsmart-latest-content-at"]


@pytest.mark.anyio
async def test_smart_money_movements_support_bounded_filtered_history_replay() -> None:
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, token = await register(client)
            headers = {"Authorization": f"Bearer {token}"}
            all_response = await client.get(
                "/v1/smart-money-movements",
                headers=headers,
                params={"limit": 1000},
            )
            movements = all_response.json()
            assert movements
            first = movements[0]

            filtered = await client.get(
                "/v1/smart-money-movements",
                headers=headers,
                params={"ticker": first["ticker"], "account_id": first["accountId"], "limit": 1},
            )
            assert filtered.status_code == 200
            assert filtered.headers["x-bsmart-result-count"] == "1"
            assert filtered.json()[0]["ticker"] == first["ticker"]
            assert filtered.json()[0]["accountId"] == first["accountId"]

            older = await client.get(
                "/v1/smart-money-movements",
                headers=headers,
                params={"before": first["observedAt"], "limit": 1000},
            )
            assert all(row["observedAt"] < first["observedAt"] for row in older.json())
            invalid = await client.get(
                "/v1/smart-money-movements",
                headers=headers,
                params={"limit": 1001},
            )
            assert invalid.status_code == 422


@pytest.mark.anyio
async def test_portfolio_state_is_scoped_and_idempotent() -> None:
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, first_token = await register(client)
            _, second_token = await register(client)
            first_headers = {"Authorization": f"Bearer {first_token}"}
            second_headers = {"Authorization": f"Bearer {second_token}"}
            entry_id = str(uuid4())
            payload = {
                "ticker": "nvda",
                "companyName": "NVIDIA",
                "entryKind": "position",
                "shares": 2,
                "averageCost": 100,
                "portfolioWeight": 0.4,
            }

            first_put = await client.put(
                f"/v1/portfolio/{entry_id}",
                headers=first_headers,
                json=payload,
            )
            second_put = await client.put(
                f"/v1/portfolio/{entry_id}",
                headers=first_headers,
                json={**payload, "shares": 3},
            )

            assert first_put.status_code == 200
            assert second_put.status_code == 200
            assert second_put.json()["id"] == entry_id
            assert second_put.json()["shares"] == 3
            assert len((await client.get("/v1/portfolio", headers=first_headers)).json()) == 1
            assert (await client.get("/v1/portfolio", headers=second_headers)).json() == []

            deleted = await client.delete(f"/v1/portfolio/{entry_id}", headers=first_headers)
            assert deleted.status_code == 204
            assert (await client.get("/v1/portfolio", headers=first_headers)).json() == []


@pytest.mark.anyio
async def test_signal_preferences_and_device_mutations_round_trip() -> None:
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, token = await register(client)
            headers = {"Authorization": f"Bearer {token}"}
            signal_id = str(uuid4())

            signal_state = await client.put(
                f"/v1/signals/{signal_id}/state",
                headers=headers,
                json={"isRead": True, "isSaved": True, "isIgnored": False, "feedback": "useful"},
            )
            preferences_payload = {
                "instantAlertsEnabled": True,
                "dailyDigestEnabled": True,
                "dailyDigestMinutes": 510,
                "quietHoursEnabled": True,
                "quietHoursStartMinutes": 1320,
                "quietHoursEndMinutes": 420,
                "mutedTickers": ["nvda", "NVDA", "mu"],
            }
            preferences = await client.put(
                "/v1/notification-preferences",
                headers=headers,
                json=preferences_payload,
            )
            device = await client.put(
                "/v1/devices",
                headers=headers,
                json={
                    "apnsToken": "a1b2c3",
                    "environment": "development",
                    "appVersion": "1.0",
                    "locale": "en_US",
                    "timeZone": "UTC",
                },
            )

            assert signal_state.status_code == 200
            assert signal_state.json()["isSaved"] is True
            assert preferences.status_code == 200
            assert preferences.json()["mutedTickers"] == ["MU", "NVDA"]
            current_preferences = await client.get("/v1/notification-preferences", headers=headers)
            assert current_preferences.json() == preferences.json()
            assert device.status_code == 204


@pytest.mark.anyio
async def test_daily_digest_returns_the_persisted_signal_snapshot() -> None:
    with TemporaryDirectory() as directory:
        settings = ClientAPISettings(
            environment="test",
            database_url=f"sqlite:///{Path(directory) / 'daily-digest-api.db'}",
            read_model_mode="fixture",
            fixture_root=REPO_ROOT / "contracts" / "fixtures",
        )
        app = create_app(settings)
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                installation_id, token = await register(client)
                headers = {"Authorization": f"Bearer {token}"}
                assert (await client.get("/v1/daily-digest", headers=headers)).status_code == 404

                entry_id = str(uuid4())
                assert (await client.put(
                    f"/v1/portfolio/{entry_id}",
                    headers=headers,
                    json={
                        "ticker": "HOOD",
                        "companyName": "Robinhood Markets",
                        "entryKind": "watchlist",
                    },
                )).status_code == 200
                assert (await client.put(
                    "/v1/devices",
                    headers=headers,
                    json={
                        "apnsToken": f"digest-{installation_id}",
                        "environment": "development",
                        "appVersion": "1.0",
                        "locale": "en_US",
                        "timeZone": "UTC",
                    },
                )).status_code == 204

                result = DailyDigestPlanner(app.state.state_store).plan(
                    app.state.read_models.portfolio_signals(),
                    now=(digest_time := _fixture_digest_time(app.state.read_models.portfolio_signals(), "HOOD")),
                )
                response = await client.get("/v1/daily-digest", headers=headers)
                body = response.json()

                assert result.queued == 1
                assert response.status_code == 200
                assert body["title"] == "Your bSmart daily brief"
                assert body["summary"].startswith("1 changes across HOOD")
                assert [signal["ticker"] for signal in body["signals"]] == ["HOOD"]
                assert body["generatedAt"] == digest_time.isoformat().replace("+00:00", "Z")


@pytest.mark.anyio
async def test_telemetry_is_installation_scoped_and_idempotent() -> None:
    with TemporaryDirectory() as directory:
        settings = ClientAPISettings(
            environment="test",
            database_url=f"sqlite:///{Path(directory) / 'telemetry.db'}",
            read_model_mode="fixture",
            fixture_root=REPO_ROOT / "contracts" / "fixtures",
        )
        app = create_app(settings)
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                installation_id, token = await register(client)
                event_id = str(uuid4())
                payload = {
                    "events": [{
                        "id": event_id,
                        "name": "evidence_opened",
                        "occurredAt": "2026-08-04T16:00:00Z",
                        "signalId": str(uuid4()),
                        "ticker": "nvda",
                        "evidenceId": str(uuid4()),
                        "source": "smart_account",
                        "context": "signal_detail",
                    }]
                }
                headers = {"Authorization": f"Bearer {token}"}

                first = await client.post("/v1/telemetry/events", headers=headers, json=payload)
                second = await client.post("/v1/telemetry/events", headers=headers, json=payload)
                events = app.state.state_store.telemetry_events()

                assert first.status_code == 202
                assert second.status_code == 202
                assert len(events) == 1
                assert str(events[0].installation_id) == installation_id
                assert str(events[0].event_id) == event_id
                assert events[0].ticker == "NVDA"
                assert events[0].source == "smart_account"


def test_production_rejects_fixture_read_models() -> None:
    settings = ClientAPISettings(
        environment="production",
        database_url="sqlite:///:memory:",
        read_model_mode="fixture",
        fixture_root=REPO_ROOT / "contracts" / "fixtures",
    )

    try:
        settings.validate()
    except RuntimeError as error:
        assert "cannot run with fixture" in str(error)
    else:
        raise AssertionError("Production fixture mode must be rejected.")


@pytest.mark.anyio
async def test_database_read_model_serves_materialized_contract_documents() -> None:
    with TemporaryDirectory() as directory:
        database_url = f"sqlite:///{Path(directory) / 'client-api-production.db'}"
        first_counts = materialize_fixture_read_models(
            database_url,
            REPO_ROOT / "contracts" / "fixtures",
        )
        second_counts = materialize_fixture_read_models(
            database_url,
            REPO_ROOT / "contracts" / "fixtures",
        )
        assert first_counts == second_counts
        assert first_counts["portfolio-signals"] == 5

        app = create_app(ClientAPISettings(
            environment="production",
            database_url=database_url,
            read_model_mode="database",
            fixture_root=REPO_ROOT / "contracts" / "fixtures",
            read_model_database_url=database_url,
        ))
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                _, token = await register(client)
                headers = {"Authorization": f"Bearer {token}"}
                feed = await client.get("/v1/feed", headers=headers)
                signal = await client.get(
                    f"/v1/signals/{feed.json()[0]['id']}",
                    headers=headers,
                )
                entry_id = str(uuid4())
                portfolio = await client.put(
                    f"/v1/portfolio/{entry_id}",
                    headers=headers,
                    json={
                        "ticker": "NVDA",
                        "companyName": "NVIDIA",
                        "entryKind": "position",
                        "shares": 2,
                        "averageCost": 100,
                    },
                )

                assert len(feed.json()) == 5
                assert feed.headers["etag"].startswith('"')
                assert signal.status_code == 200
                assert signal.json()["id"] == feed.json()[0]["id"]
                assert portfolio.json()["currentPrice"] == 128.62


def test_service_covers_every_contract_operation() -> None:
    contract = yaml.safe_load((REPO_ROOT / "contracts" / "openapi" / "bsmart-v1.yaml").read_text())
    methods = {"get", "post", "put", "patch", "delete"}
    expected = {
        (normalize_path(path), method.upper())
        for path, path_item in contract["paths"].items()
        for method in path_item
        if method in methods
    }
    actual = {
        (normalize_path(route.path), method)
        for route in create_app(ClientAPISettings(
            environment="test",
            database_url="sqlite:///:memory:",
            read_model_mode="fixture",
            fixture_root=REPO_ROOT / "contracts" / "fixtures",
        )).routes
        for method in (route.methods or set())
        if route.path.startswith("/v1/")
    }

    assert actual == expected


def normalize_path(path: str) -> str:
    return "/".join("{}" if part.startswith("{") else part for part in path.split("/"))


def _fixture_digest_time(signals: list[dict], ticker: str) -> datetime:
    signal = next(row for row in signals if row["ticker"] == ticker)
    occurred_at = datetime.fromisoformat(signal["occurredAt"].replace("Z", "+00:00")).astimezone(UTC)
    candidate = occurred_at.replace(hour=8, minute=5, second=0, microsecond=0)
    return candidate if candidate >= occurred_at else candidate + timedelta(days=1)
