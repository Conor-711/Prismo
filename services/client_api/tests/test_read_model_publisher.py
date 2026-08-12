from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import pytest

from services.client_api.config import REPO_ROOT
from services.client_api.publish_realtime_smart_money import _load as load_realtime_checkpoint
from services.client_api.read_models import (
    DatabaseReadModelRepository,
    ReadModelPublisher,
    RealtimeReadModelPublisher,
    load_read_model_directory,
)


def test_publisher_atomically_activates_and_rolls_back_immutable_releases() -> None:
    with TemporaryDirectory() as directory:
        database_url = f"sqlite:///{Path(directory) / 'read-model.db'}"
        collections = load_read_model_directory(REPO_ROOT / "contracts" / "fixtures")
        publisher = ReadModelPublisher(database_url)
        repository = DatabaseReadModelRepository(database_url)
        try:
            first = publisher.publish(collections, source_version="pipeline-run-1")
            first_title = repository.portfolio_signals()[0]["title"]
            first_etag = repository.etag("portfolio-signals")

            changed = deepcopy(collections)
            changed["portfolio-signals"][0]["title"] = "Updated immutable signal"
            second = publisher.publish(changed, source_version="pipeline-run-2")

            assert first.release_id != second.release_id
            assert repository.portfolio_signals()[0]["title"] == "Updated immutable signal"
            assert repository.etag("portfolio-signals") != first_etag

            publisher.activate(first.release_id)

            assert repository.portfolio_signals()[0]["title"] == first_title
            assert repository.etag("portfolio-signals") == first_etag

            repeated = publisher.publish(collections, source_version="pipeline-run-1-repeat")
            assert repeated.existing is True
            assert repeated.release_id == first.release_id
        finally:
            repository.dispose()
            publisher.dispose()


def test_publisher_rejects_partial_or_duplicate_snapshots() -> None:
    with TemporaryDirectory() as directory:
        database_url = f"sqlite:///{Path(directory) / 'invalid-read-model.db'}"
        collections = load_read_model_directory(REPO_ROOT / "contracts" / "fixtures")
        publisher = ReadModelPublisher(database_url)
        try:
            partial = dict(collections)
            partial.pop("smart-money")
            with pytest.raises(ValueError, match="collections mismatch"):
                publisher.publish(partial, source_version="partial")

            duplicate = deepcopy(collections)
            duplicate["portfolio-signals"].append(duplicate["portfolio-signals"][0])
            with pytest.raises(ValueError, match="duplicate document IDs"):
                publisher.publish(duplicate, source_version="duplicate")
        finally:
            publisher.dispose()


def test_realtime_collections_atomically_override_money_and_derived_intelligence() -> None:
    with TemporaryDirectory() as directory:
        database_url = f"sqlite:///{Path(directory) / 'realtime-read-model.db'}"
        collections = load_read_model_directory(REPO_ROOT / "contracts" / "fixtures")
        publisher = ReadModelPublisher(database_url)
        realtime = RealtimeReadModelPublisher(database_url)
        repository = DatabaseReadModelRepository(database_url)
        try:
            publisher.publish(collections, source_version="base")
            portfolio_etag = repository.etag("portfolio-signals")
            original_money_etag = repository.etag("smart-money")
            live_wallet = deepcopy(collections["smart-money"][0])
            live_wallet["score"] = 99
            live_movement = deepcopy(collections["smart-money-movements"][0])
            live_movement["notionalAfter"] = 123_456
            live_signal = deepcopy(collections["portfolio-signals"][0])
            live_signal["title"] = "Realtime capital relationship"
            live_intelligence = deepcopy(collections["ticker-intelligence"][0])
            live_intelligence["conclusion"] = "Realtime capital state"

            result = realtime.publish(
                {
                    "smart-money": [live_wallet],
                    "smart-money-movements": [live_movement],
                    "portfolio-signals": [live_signal],
                    "ticker-intelligence": [live_intelligence],
                },
                source_version="hyperliquid-live:test",
            )

            assert result.counts == {
                "smart-money": 1,
                "smart-money-movements": 1,
                "portfolio-signals": 1,
                "ticker-intelligence": 1,
            }
            assert repository.smart_money()[0]["score"] == 99
            assert repository.smart_money_movements()[0]["notionalAfter"] == 123_456
            assert repository.portfolio_signals()[0]["title"] == "Realtime capital relationship"
            assert repository.ticker_intelligence()[0]["conclusion"] == "Realtime capital state"
            assert repository.etag("smart-money") != original_money_etag
            assert repository.etag("portfolio-signals") != portfolio_etag

            realtime.clear(
                "smart-money",
                "smart-money-movements",
                "portfolio-signals",
                "ticker-intelligence",
            )
            assert len(repository.smart_money()) == len(collections["smart-money"])
            assert repository.etag("smart-money") == original_money_etag
        finally:
            repository.dispose()
            realtime.dispose()
            publisher.dispose()


def test_live_checkpoint_rejects_partially_written_collection() -> None:
    with TemporaryDirectory() as directory:
        root = Path(directory)
        payloads = {
            "smart-money": [{"id": "wallet"}],
            "smart-money-movements": [{"id": "movement"}],
            "portfolio-signals": [{"id": "signal"}],
            "ticker-intelligence": [{"ticker": "NVDA"}],
        }
        manifest = {"generatedAt": "2026-08-06T00:00:00Z", "collections": {}}
        for name, payload in payloads.items():
            raw = (json.dumps(payload) + "\n").encode()
            (root / f"{name}.json").write_bytes(raw)
            manifest["collections"][name] = {
                "count": len(payload),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
        (root / "smart-money-live-manifest.json").write_text(json.dumps(manifest))

        loaded, _ = load_realtime_checkpoint(root)
        assert set(loaded) == set(payloads)

        (root / "portfolio-signals.json").write_text("[]\n")
        with pytest.raises(RuntimeError, match="committed manifest"):
            load_realtime_checkpoint(root)


def test_partitioned_publishers_retain_each_others_documents_and_replace_own_partition() -> None:
    with TemporaryDirectory() as directory:
        database_url = f"sqlite:///{Path(directory) / 'partitioned-read-model.db'}"
        collections = load_read_model_directory(REPO_ROOT / "contracts" / "fixtures")
        base_youtube = deepcopy(collections["smart-account-updates"][0])
        base_youtube["platform"] = "YouTube"
        base_youtube["id"] = "10000000-0000-4000-8000-000000000001"
        base_x = deepcopy(base_youtube)
        base_x["platform"] = "X"
        base_x["id"] = "10000000-0000-4000-8000-000000000002"
        collections["smart-account-updates"] = [base_youtube, base_x]
        base_publisher = ReadModelPublisher(database_url)
        realtime = RealtimeReadModelPublisher(database_url)
        repository = DatabaseReadModelRepository(database_url)
        try:
            base_publisher.publish(collections, source_version="base")
            x_update = deepcopy(base_x)
            x_update["id"] = "20000000-0000-4000-8000-000000000001"
            x_signal = deepcopy(collections["portfolio-signals"][0])
            x_signal["id"] = "20000000-0000-4000-8000-000000000002"
            x_signal["title"] = "Live X signal"
            realtime.publish_partitioned(
                {
                    "smart-account-updates": [x_update],
                    "portfolio-signals": [x_signal],
                },
                producer="x-realtime",
                source_version="x-realtime:test",
                owns_document=lambda collection, item: (
                    collection == "smart-account-updates" and item.get("platform") == "X"
                ),
            )

            updates = repository.smart_account_updates()
            assert {item["platform"] for item in updates} == {"YouTube", "X"}
            assert base_x["id"] not in {item["id"] for item in updates}

            money_signal = deepcopy(collections["portfolio-signals"][0])
            money_signal["id"] = "30000000-0000-4000-8000-000000000001"
            money_signal["title"] = "Live money signal"
            realtime.publish_partitioned(
                {"portfolio-signals": [money_signal]},
                producer="hyperliquid-live",
                source_version="hyperliquid-live:test",
            )
            signal_titles = {item["title"] for item in repository.portfolio_signals()}
            assert "Live X signal" in signal_titles
            assert "Live money signal" in signal_titles
            assert repository.signal(x_signal["id"])["title"] == "Live X signal"

            replacement = deepcopy(x_signal)
            replacement["id"] = "20000000-0000-4000-8000-000000000003"
            replacement["title"] = "Replacement X signal"
            realtime.publish_partitioned(
                {"portfolio-signals": [replacement]},
                producer="x-realtime",
                source_version="x-realtime:replacement",
            )
            signal_titles = {item["title"] for item in repository.portfolio_signals()}
            assert "Live X signal" not in signal_titles
            assert "Replacement X signal" in signal_titles
            assert "Live money signal" in signal_titles
        finally:
            repository.dispose()
            realtime.dispose()
            base_publisher.dispose()
