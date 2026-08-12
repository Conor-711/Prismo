from __future__ import annotations

import argparse
from datetime import UTC, datetime
from uuid import uuid4

import httpx

from services.client_api.config import ClientAPISettings
from services.client_api.daily_digest_planner import DailyDigestPlanner
from services.client_api.read_models import DatabaseReadModelRepository
from services.client_api.state_store import ClientStateStore


FIXTURE_DIGEST_TIME = datetime(2026, 8, 4, 8, 5, tzinfo=UTC)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Exercise the database-backed Internal Alpha API end to end."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8082")
    args = parser.parse_args()

    settings = ClientAPISettings.from_environment()
    if settings.environment != "internal-alpha" or settings.read_model_mode != "database":
        raise RuntimeError("Internal Alpha smoke requires internal-alpha database mode.")

    with httpx.Client(base_url=args.base_url, timeout=15) as client:
        health = _expect(client.get("/health"), 200).json()
        expected_health = {
            "status": "ok",
            "environment": "internal-alpha",
            "readModelMode": "database",
        }
        if health != expected_health:
            raise AssertionError(f"Unexpected health payload: {health}")
        _expect(client.get("/v1/feed"), 401)

        installation_id = str(uuid4())
        session = _expect(
            client.post(
                "/v1/installations",
                json={
                    "installationId": installation_id,
                    "platform": "ios",
                    "appVersion": "internal-alpha-smoke",
                    "locale": "en_US",
                    "timeZone": "UTC",
                },
            ),
            201,
        ).json()
        headers = {"Authorization": f"Bearer {session['accessToken']}"}

        entries = (
            {
                "ticker": "HOOD",
                "companyName": "Robinhood Markets",
                "entryKind": "watchlist",
            },
            {
                "ticker": "NVDA",
                "companyName": "NVIDIA",
                "entryKind": "position",
                "shares": 4,
                "averageCost": 150,
                "portfolioWeight": 0.6,
            },
        )
        for payload in entries:
            _expect(
                client.put(f"/v1/portfolio/{uuid4()}", headers=headers, json=payload),
                200,
            )
        portfolio = _expect(client.get("/v1/portfolio", headers=headers), 200).json()
        if {item["ticker"] for item in portfolio} != {"HOOD", "NVDA"}:
            raise AssertionError(f"Unexpected portfolio: {portfolio}")

        _expect(
            client.put(
                "/v1/devices",
                headers=headers,
                json={
                    "apnsToken": f"internal-alpha-smoke-{installation_id}",
                    "environment": "development",
                    "appVersion": "internal-alpha-smoke",
                    "locale": "en_US",
                    "timeZone": "UTC",
                },
            ),
            204,
        )
        _expect(
            client.put(
                "/v1/notification-preferences",
                headers=headers,
                json={
                    "instantAlertsEnabled": True,
                    "dailyDigestEnabled": True,
                    "dailyDigestMinutes": 0,
                    "quietHoursEnabled": False,
                    "quietHoursStartMinutes": 1320,
                    "quietHoursEndMinutes": 420,
                    "mutedTickers": [],
                },
            ),
            200,
        )

        feed_response = _expect(client.get("/v1/feed", headers=headers), 200)
        repeated_feed = _expect(client.get("/v1/feed", headers=headers), 200)
        if not feed_response.headers.get("etag"):
            raise AssertionError("Feed response is missing its ETag.")
        if feed_response.headers["etag"] != repeated_feed.headers.get("etag"):
            raise AssertionError("Read-model ETag changed without a release change.")
        if feed_response.headers.get("cache-control") != "private, max-age=0, must-revalidate":
            raise AssertionError("Feed response has an unsafe cache policy.")

        counts = {
            "feed": len(feed_response.json()),
            "intelligence": len(_expect(client.get("/v1/intelligence", headers=headers), 200).json()),
            "smartAccounts": len(_expect(client.get("/v1/smart-accounts", headers=headers), 200).json()),
            "accountUpdates": len(
                _expect(client.get("/v1/smart-account-updates", headers=headers), 200).json()
            ),
            "moneyMovements": len(
                _expect(client.get("/v1/smart-money-movements", headers=headers), 200).json()
            ),
        }
        expected_counts = {
            "feed": 5,
            "intelligence": 5,
            "smartAccounts": 510,
            "accountUpdates": 127,
            "moneyMovements": 4,
        }
        if counts != expected_counts:
            raise AssertionError(f"Unexpected read-model counts: {counts}")
        _expect(client.get("/v1/daily-digest", headers=headers), 404)

        state_store = ClientStateStore(
            settings.database_url,
            session_lifetime_days=settings.session_lifetime_days,
            telemetry_retention_days=settings.telemetry_retention_days,
        )
        read_models = DatabaseReadModelRepository(
            settings.read_model_database_url or settings.database_url
        )
        try:
            result = DailyDigestPlanner(state_store).plan(
                read_models.portfolio_signals(),
                now=FIXTURE_DIGEST_TIME,
            )
        finally:
            read_models.dispose()
            state_store.dispose()
        if result.queued < 1:
            raise AssertionError(f"Daily digest was not queued: {result}")

        digest = _expect(client.get("/v1/daily-digest", headers=headers), 200).json()
        if {item["ticker"] for item in digest["signals"]} != {"HOOD", "NVDA"}:
            raise AssertionError(f"Unexpected daily digest evidence: {digest}")

    print("Internal Alpha API smoke passed:")
    print(f"installation: {installation_id}")
    for key, value in counts.items():
        print(f"{key}: {value}")
    print(f"digestSignals: {len(digest['signals'])}")


def _expect(response: httpx.Response, status_code: int) -> httpx.Response:
    if response.status_code != status_code:
        raise AssertionError(
            f"{response.request.method} {response.request.url.path} returned "
            f"{response.status_code}, expected {status_code}: {response.text}"
        )
    return response


if __name__ == "__main__":
    main()
