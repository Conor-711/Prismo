from datetime import datetime, timedelta, timezone
import hashlib
import json

import pytest

from services.client_api.publish_daily_x import COLLECTIONS, publish, load_release
from services.client_api.read_models import (DatabaseReadModelRepository, RealtimeReadModelPublisher,
                                             ReadModelPublisher, READ_MODEL_COLLECTIONS)
from services.client_api.smart_account_signals import build_portfolio_signals


def make_release(path, *, name="New author", as_of=None):
    path.mkdir(exist_ok=True)
    documents = {
        "smart-accounts": [{"id": "x:a", "platform": "X", "name": name, "handle": "@a",
                            "score": 110, "scoreChange": 0, "specialty": "Mixed", "horizon": "20D"}],
        "smart-account-updates": [view("00000000-0000-0000-0000-000000000001")],
        "smart-account-evidence": [view("00000000-0000-0000-0000-000000000002")],
    }
    entries = {}
    for key, items in documents.items():
        raw = json.dumps(items).encode()
        (path / f"{key}.json").write_bytes(raw)
        entries[key] = {"count": len(items), "sha256": hashlib.sha256(raw).hexdigest()}
    (path / "daily-x-manifest.json").write_text(json.dumps({"version": 1, "status": "ready", "collections": entries,
        "asOf": (as_of or datetime.now(timezone.utc)).isoformat(),
        "sourceThrough": datetime.now(timezone.utc).isoformat()}))
    return path


def view(identity):
    return {"id": identity, "ticker": "NVDA", "companyName": "NVIDIA", "authorId": "x:a",
            "authorName": "Author", "platform": "X", "score": 110, "platformPercentile": 0.1,
            "direction": "bullish", "lifecycle": "new", "horizon": "20D", "thesis": "Example",
            "publishedAt": datetime.now(timezone.utc).isoformat()}


def test_delayed_smart_account_signal_discloses_processing_delay():
    published = datetime.now(timezone.utc) - timedelta(hours=1)
    update = view("00000000-0000-0000-0000-000000000003")
    update.update(publishedAt=published.isoformat(), processedAt=datetime.now(timezone.utc).isoformat())

    signal = build_portfolio_signals([update])[0]

    assert signal["dataStatus"] == "delayed"
    assert any("delay" in limitation.lower() for limitation in signal["limitations"])


def seed(url):
    publisher = ReadModelPublisher(url)
    base = {name: [] for name in READ_MODEL_COLLECTIONS}
    base["smart-accounts"] = [{"id": "x:a", "platform": "X", "name": "Old author"},
                              {"id": "reddit:b", "platform": "Reddit"}]
    base["smart-account-updates"] = [{"id": "old", "platform": "X", "authorId": "x:a"},
                                     {"id": "reddit-view", "platform": "Reddit", "authorId": "reddit:b"}]
    base["smart-money"] = [{"id": "wallet"}]
    publisher.publish(base, source_version="base")
    publisher.dispose()


def test_daily_publish_preserves_other_platforms_and_money_and_is_idempotent(tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    url = f"sqlite:///{tmp_path / 'api.db'}"
    seed(url)
    live = RealtimeReadModelPublisher(url)
    live.publish({"smart-accounts": [{"id": "reddit:live", "platform": "Reddit"}]}, source_version="unlabelled")
    live.dispose()
    repository = DatabaseReadModelRepository(url)
    before = repository.etag("smart-account-updates")
    release = make_release(tmp_path / "release")
    assert publish(release, url)["status"] == "validated"
    assert repository.etag("smart-account-updates") == before
    result = publish(release, url, apply=True)
    assert result["status"] == "published"
    assert repository.etag("smart-account-updates") != before
    assert {p["id"] for p in repository.smart_accounts()} == {"x:a", "reddit:b", "reddit:live"}
    assert {p["id"] for p in repository.smart_account_updates()} == {"00000000-0000-0000-0000-000000000001", "reddit-view"}
    assert repository.smart_money() == [{"id": "wallet"}]
    assert publish(release, url, apply=True)["status"] == "already-published"
    repository.dispose()


def test_tampered_release_does_not_publish(tmp_path):
    release = make_release(tmp_path / "release")
    (release / "smart-accounts.json").write_text("[]")
    with pytest.raises(ValueError, match="Checksum"):
        load_release(release)


def test_partial_publication_rolls_back_on_concurrent_change(tmp_path):
    url = f"sqlite:///{tmp_path / 'api.db'}"
    seed(url)
    publisher = RealtimeReadModelPublisher(url, initialize_schema=False)
    with pytest.raises(ValueError, match="changed"):
        publisher.publish_partitioned({"smart-accounts": [], "smart-account-updates": []},
            producer="x-daily", source_version="test", expected_hashes={"smart-accounts": "changed", "smart-account-updates": None})
    repository = DatabaseReadModelRepository(url)
    assert len(repository.smart_accounts()) == 2
    assert len(repository.smart_account_updates()) == 2
    repository.dispose()
    publisher.dispose()


def test_newer_release_cannot_be_overwritten_without_explicit_rollback(tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    url = f"sqlite:///{tmp_path / 'api.db'}"
    seed(url)
    now = datetime.now(timezone.utc)
    new = make_release(tmp_path / "new", as_of=now)
    old = make_release(tmp_path / "old", as_of=now - timedelta(hours=1))
    publish(new, url, apply=True)
    with pytest.raises(ValueError, match="newer"):
        publish(old, url, apply=True)
    assert publish(old, url, apply=True, rollback=True)["status"] == "published"


def test_missing_database_schema_is_not_created(tmp_path):
    url = f"sqlite:///{tmp_path / 'missing.db'}"
    release = make_release(tmp_path / "release")
    from sqlalchemy.exc import OperationalError
    with pytest.raises(OperationalError):
        publish(release, url)
    import sqlite3
    with sqlite3.connect(tmp_path / "missing.db") as con:
        assert con.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall() == []


def test_actual_rollback_package_restores_author_and_generated_signals(tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    url = f"sqlite:///{tmp_path / 'api.db'}"
    seed(url)
    publish(make_release(tmp_path / "one", name="One"), url, apply=True)
    result = publish(make_release(tmp_path / "two", name="Two"), url, apply=True)
    from pathlib import Path
    restored = publish(Path(result["rollbackDirectory"]), url, apply=True, rollback=True)
    assert restored["status"] == "published"
    repository = DatabaseReadModelRepository(url)
    assert next(item for item in repository.smart_accounts() if item["id"] == "x:a")["name"] == "One"
    assert len(repository.portfolio_signals()) == 1
    repository.dispose()


def test_invalid_required_ios_fields_and_stale_source_block_publication(tmp_path):
    release = make_release(tmp_path / "release")
    path = release / "smart-accounts.json"
    data = json.loads(path.read_text())
    data[0]["score"] = "not-a-number"
    path.write_text(json.dumps(data))
    manifest_path = release / "daily-x-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["collections"]["smart-accounts"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest_path.write_text(json.dumps(manifest))
    with pytest.raises(ValueError):
        load_release(release)
    make_release(release)
    manifest = json.loads(manifest_path.read_text())
    manifest["sourceThrough"] = "2020-01-01T00:00:00+00:00"
    manifest_path.write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="not current"):
        publish(release, "sqlite:///:memory:")
