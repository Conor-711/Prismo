from __future__ import annotations

import json
from datetime import UTC, datetime

from sqlalchemy import func, select

from pipeline.common.models import XRealtimePost, XRealtimeSubscription
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from services.x_ingest.stream import TwitterAPIIOStreamConsumer
from services.x_ingest.tests.test_api import _settings


def test_stream_ignores_housekeeping_and_ingests_rule_matches(tmp_path):
    settings = _settings(tmp_path)
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    with repository.sessions() as session, session.begin():
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
    consumer = TwitterAPIIOStreamConsumer(settings, repository)

    consumer.handle_message(json.dumps({"event_type": "connected"}))
    consumer.handle_message(json.dumps({"event_type": "ping", "timestamp": 1}))
    consumer.handle_message(
        json.dumps(
            {
                "event_type": "tweet",
                "rule_id": "rule-1",
                "rule_tag": "x-top25",
                "tweets": [
                    {
                        "id": "100",
                        "url": "https://x.com/alpha/status/100",
                        "text": "I think $NVDA will rally.",
                        "createdAt": "Wed Aug 05 12:00:00 +0000 2026",
                        "lang": "en",
                        "author": {
                            "id": "author-1",
                            "userName": "alpha",
                            "name": "Alpha",
                        },
                    }
                ],
            }
        )
    )
    consumer.handle_message(
        json.dumps(
            {
                "event_type": "tweet",
                "rule_id": "rule-1",
                "rule_tag": "x-top25",
                "tweets": [
                    {
                        "id": "100",
                        "url": "https://x.com/alpha/status/100",
                        "text": "I think $NVDA will rally.",
                        "createdAt": "Wed Aug 05 12:00:00 +0000 2026",
                        "lang": "en",
                        "author": {
                            "id": "author-1",
                            "userName": "alpha",
                            "name": "Alpha",
                        },
                    }
                ],
            }
        )
    )

    with repository.sessions() as session:
        assert session.scalar(select(func.count()).select_from(XRealtimePost)) == 1
    with repository.sessions() as session:
        post = session.get(XRealtimePost, "100")
        assert post is not None
        assert post.delivery_source == "websocket"
        assert post.delivery_tag == "x-top25"


def test_stream_ignores_fast_tweet_and_malformed_messages(tmp_path):
    settings = _settings(tmp_path)
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    consumer = TwitterAPIIOStreamConsumer(settings, repository)

    consumer.handle_message("not-json")
    consumer.handle_message(json.dumps({"event_type": "fast_tweet", "tweet": {"id": "1"}}))

    with repository.sessions() as session:
        assert session.scalar(select(func.count()).select_from(XRealtimePost)) == 0


def test_stream_marks_posts_from_before_connection_as_backfill(tmp_path):
    settings = _settings(tmp_path)
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    with repository.sessions() as session, session.begin():
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
    consumer = TwitterAPIIOStreamConsumer(settings, repository)
    consumer._connected_at = datetime(2026, 8, 5, 12, 1, tzinfo=UTC)

    consumer.handle_message(
        json.dumps(
            {
                "event_type": "tweet",
                "rule_tag": "x-top25",
                "tweets": [
                    {
                        "id": "backfill-1",
                        "url": "https://x.com/alpha/status/backfill-1",
                        "text": "I think $NVDA will rally.",
                        "createdAt": "Wed Aug 05 12:00:00 +0000 2026",
                        "lang": "en",
                        "author": {
                            "id": "author-1",
                            "userName": "alpha",
                            "name": "Alpha",
                        },
                    }
                ],
            }
        )
    )

    with repository.sessions() as session:
        post = session.get(XRealtimePost, "backfill-1")
        assert post is not None
        assert post.delivery_source == "websocket_backfill"
    assert repository.health_snapshot(
        now=datetime(2026, 8, 5, 12, 2, tzinfo=UTC)
    )["streamRecoveredPosts24h"] == 1


def test_stream_callbacks_persist_connection_and_disconnect_state(tmp_path):
    settings = _settings(tmp_path)
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    consumer = TwitterAPIIOStreamConsumer(settings, repository)

    consumer._handle_open(None)
    consumer.handle_message(json.dumps({"event_type": "ping"}))
    connected = repository.health_snapshot()
    assert connected["streamConnected"] is True
    assert connected["lastStreamHeartbeatAt"] is not None

    consumer._handle_close(None, 1001, "provider restart")
    disconnected = repository.health_snapshot()
    assert disconnected["streamConnected"] is False
    assert "provider restart" in disconnected["streamLastError"]
