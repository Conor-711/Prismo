from __future__ import annotations

from fastapi.testclient import TestClient

from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from services.x_ingest.config import XIngestSettings
from services.x_ingest.main import create_app


def _settings(tmp_path, *, enabled=True):
    database_url = f"sqlite:///{tmp_path / 'x.db'}"
    return XIngestSettings(
        environment="test",
        enabled=enabled,
        database_url=database_url,
        read_model_database_url=f"sqlite:///{tmp_path / 'read.db'}",
        priority_database_url=None,
        twitterapi_io_key="test-key",
        twitterapi_io_base_url="https://example.invalid",
        webhook_token="secret-token",
        tickers=("NVDA",),
        priority_tickers=(),
        pool_limit=0,
        process_batch_size=25,
        process_workers=1,
        process_interval_seconds=10,
        reconcile_interval_seconds=900,
        publish_interval_seconds=60,
        rule_interval_seconds=60,
        reconciliation_max_pages=20,
        monthly_cost_limit_usd=100,
    )


def _payload():
    return {
        "tag": "rule-a",
        "tweet": {
            "id": "100",
            "url": "https://x.com/alpha/status/100",
            "text": "I think $NVDA will rally.",
            "createdAt": "Wed Aug 05 12:00:00 +0000 2026",
            "lang": "en",
            "author": {"id": "author-1", "userName": "alpha", "name": "Alpha"},
        },
    }


def test_webhook_auth_switch_and_idempotency(tmp_path):
    settings = _settings(tmp_path)
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    with repository.sessions() as session, session.begin():
        from pipeline.common.models import XRealtimeSubscription

        session.add(
            XRealtimeSubscription(
                author_id="author-1",
                handle="alpha",
                display_name="Alpha",
                author_score=120,
                platform_percentile=0.1,
                pool_version="test",
                active=True,
            )
        )
    client = TestClient(create_app(settings, repository))

    assert client.post("/webhooks/twitterapi-io/wrong", json=_payload()).status_code == 404
    first = client.post("/webhooks/twitterapi-io/secret-token", json=_payload())
    second = client.post("/webhooks/twitterapi-io/secret-token", json=_payload())
    assert first.status_code == 202
    assert first.json()["inserted"] == 1
    assert second.json()["duplicates"] == 1

    disabled = TestClient(create_app(_settings(tmp_path, enabled=False), repository))
    assert disabled.post("/webhooks/twitterapi-io/secret-token", json=_payload()).status_code == 503
