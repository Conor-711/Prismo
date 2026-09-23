from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from services.client_api.content_release import push, publisher, push_queue
from services.client_api.content_release.models import Active, Release
from services.client_api.tests.test_supabase_content import baseline, engine
from services.client_api.tests.test_daily_x_publisher import make_release


def test_only_new_daily_content_enqueues(monkeypatch):
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "true")
    old = SimpleNamespace(manifest={"collections": {"a": {"sha256": "one"}}})
    assert not push.should_enqueue(True, old, {"a": {"sha256": "two"}})
    assert not push.should_enqueue(False, old, {"a": {"sha256": "one"}})
    assert push.should_enqueue(False, old, {"a": {"sha256": "two"}})
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "false")
    assert not push.should_enqueue(False, old, {"a": {"sha256": "two"}})


def test_publication_enqueue_is_atomic_and_idempotent(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "true")
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    calls = []
    monkeypatch.setattr(publisher, "enqueue", lambda session, revision, events: calls.append((revision, events)) or 2)
    first = publisher.publish(engine, baseline(tmp_path), baseline=True, apply=True)
    assert calls == []
    daily = make_release(tmp_path / "daily", name="Changed")
    assert publisher.publish(engine, daily)["status"] == "validated"
    assert calls == []
    result = publisher.publish(engine, daily, apply=True)
    assert result["notificationsQueued"] == 2 and len(calls) == 1
    assert calls[0][0] == result["revision"]
    publisher.publish(engine, daily, apply=True)
    publisher.rollback(engine, first["revision"], apply=True)
    assert len(calls) == 1


def test_queue_failure_rolls_back_pointer(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "true")
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    first = publisher.publish(engine, baseline(tmp_path), baseline=True, apply=True)
    def fail(*args):
        raise RuntimeError("queue unavailable")
    monkeypatch.setattr(publisher, "enqueue", fail)
    with pytest.raises(RuntimeError):
        publisher.publish(engine, make_release(tmp_path / "daily", name="Changed"), apply=True)
    with Session(engine) as session:
        assert session.get(Active, "production").revision == first["revision"]
        assert len(session.scalars(select(Release)).all()) == 1


@pytest.mark.parametrize("status,reason,state,invalid", [
    (200, None, "accepted", False), (429, None, "failed", False),
    (503, None, "failed", False), (None, None, "failed", False),
    (403, "InvalidProviderToken", "failed", False), (410, "Unregistered", "failed", True),
    (400, "BadDeviceToken", "failed", True), (413, "PayloadTooLarge", "failed", False)])
def test_delivery_classification(status, reason, state, invalid):
    assert push.outcome(status, reason, 1) == (state, invalid)


def test_new_events_ignore_rescores_and_reintroduced_opinions():
    old = {"smart-account-updates": [{"id": "a"}], "smart-account-evidence": [{"id": "b"}],
           "smart-money-movements": [{"id": "m"}]}
    current = {"smart-account-updates": [
        {"id": "a", "score": 99}, {"id": "b", "score": 100},
        {"id": "c", "authorId": "x:author", "ticker": "gme", "authorName": "Author"}],
        "smart-money-movements": [
            {"id": "m", "score": 1},
            {"id": "n", "accountId": "wallet", "ticker": "mstr", "accountLabel": "Wallet"}]}
    assert push.new_events(old, current) == [
        {"event_kind": "opinion", "event_id": "c", "actor_id": "x:author", "ticker": "GME", "actor_name": "Author"},
        {"event_kind": "movement", "event_id": "n", "actor_id": "wallet", "ticker": "MSTR", "actor_name": "Wallet"}]


def test_same_author_source_post_and_ticker_has_stable_notice_identity():
    original = {"id": "00000000-0000-0000-0000-000000000001", "platform": "X",
                "authorId": "x:alice", "sourcePostId": "post-7", "ticker": "GME",
                "authorName": "Alice"}
    changed = {**original, "id": "00000000-0000-0000-0000-000000000002", "score": 99}
    old = {"smart-account-updates": [original], "smart-account-evidence": [], "smart-money-movements": []}
    current = {"smart-account-updates": [changed], "smart-money-movements": []}
    assert push.new_events(old, current) == []
    unseen = {"smart-account-updates": [], "smart-account-evidence": [], "smart-money-movements": []}
    first = push.new_events(unseen, {**current, "smart-account-updates": [original]})[0]
    second = push.new_events(unseen, current)[0]
    assert first["event_id"] == second["event_id"]


def test_only_three_shanghai_digest_slots():
    for local_hour, utc_hour in [(8, 0), (18, 10), (22, 14)]:
        at = datetime(2026, 9, 23, utc_hour, 0, tzinfo=timezone.utc)
        assert push_queue.due_slot(at) == at
        assert push_queue.due_slot(at + timedelta(minutes=29)) == at
        assert push_queue.due_slot(at + timedelta(minutes=30)) is None
    assert push_queue.due_slot(datetime(2026, 9, 23, 8, tzinfo=timezone.utc)) is None


def test_apns_headers_payload_and_receipt(monkeypatch):
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "true")
    delivery = {"user_id": uuid4(), "slot_at": datetime.now(timezone.utc), "item_count": 4,
                "locale": "zh-Hans", "apns_token": "b" * 64,
                "environment": "production", "apns_id": uuid4(), "attempts": 1,
                }
    claims = iter([delivery, None])
    monkeypatch.setattr(push.push_queue, "due_slot", lambda: delivery["slot_at"])
    monkeypatch.setattr(push.push_queue, "prepare_slot", lambda *args: 1)
    monkeypatch.setattr(push.push_queue, "claim", lambda _: next(claims))
    receipts = []
    monkeypatch.setattr(push.push_queue, "complete", lambda *args: receipts.append(args))
    def handler(request):
        assert request.url.host == "api.push.apple.com"
        assert request.headers["apns-id"] == str(delivery["apns_id"])
        assert str(delivery["user_id"]) in request.headers["apns-collapse-id"]
        assert request.headers["apns-topic"] == "today.bsmart.ios"
        assert b'content_digest' in request.content
        return httpx.Response(200)
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = push.drain(None, client=client, settings=SimpleNamespace(topic="today.bsmart.ios"),
                            token=SimpleNamespace(value=lambda: "private"))
    assert result["accepted"] == 1 and receipts[0][2:4] == ("accepted", 200)
    assert "4 条" in push.payload(delivery)["aps"]["alert"]["body"]
    assert push.payload({**delivery, "locale": "en"})["aps"]["alert"]["title"] == "New on bSmart"


def test_disabled_worker_does_not_access_credentials_or_database(monkeypatch):
    monkeypatch.setenv("BSMART_UPDATE_PUSH_ENABLED", "false")
    assert push.drain(None) == {"status": "disabled", "attempted": 0}
