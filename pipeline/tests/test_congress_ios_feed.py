import json
import hashlib
from pathlib import Path
import sqlite3
from datetime import date

from PIL import Image
import pytest

from pipeline.jobs.congress_capture.ios_feed import attach_prices, build_feed, enrich_existing_holdings
from pipeline.jobs.congress_capture.portrait_assets import preserved_portraits


ROOT = Path(__file__).resolve().parents[2]


def test_user_selected_subject_images_are_exact_originals():
    sources = ROOT / "pipeline/jobs/congress_capture/subject_avatar_sources.json"
    assets = ROOT / "ios/BSmart/Assets.xcassets"
    overrides = json.loads(sources.read_text())["bundledOverrides"]
    assert {item["id"] for item in overrides} == {
        "institution:citadel", "politician:P000197", "celebrity:duan-yongping",
        "celebrity:ken-griffin", "celebrity:bill-ackman", "celebrity:warren-buffett",
    }
    for item in overrides:
        name = "SubjectAvatar_" + item["id"].replace(":", "_").replace("-", "_")
        directory = assets / f"{name}.imageset"
        contents = json.loads((directory / "Contents.json").read_text())
        assert contents["images"][0]["filename"] == item["filename"]
        image = directory / item["filename"]
        assert hashlib.sha256(image.read_bytes()).hexdigest() == item["sha256"]
        with Image.open(image) as decoded:
            decoded.verify()
    assert preserved_portraits(assets, sources) == {"politician:P000197"}


def test_changed_user_portrait_is_not_silently_overwritten(tmp_path):
    sources = tmp_path / "sources.json"
    sources.write_text(json.dumps({"bundledOverrides": [
        {"id": "politician:P000197", "filename": "avatar.png", "sha256": "0" * 64},
    ]}))
    with pytest.raises(ValueError, match="override changed"):
        preserved_portraits(ROOT / "ios/BSmart/Assets.xcassets", sources)


def test_current_subjects_use_verified_images_or_initials():
    feed = json.loads((ROOT / "ios/BSmart/Resources/subject-activity.json").read_text())
    sources = json.loads((ROOT / "pipeline/jobs/congress_capture/subject_avatar_sources.json").read_text())
    by_id = {subject["id"]: subject for subject in sources["subjects"]}
    for subject in feed["subjects"]:
        if subject["kind"] == "politician":
            assert subject["avatarURL"].startswith("https://")
            assert len(subject["id"].split(":")[1]) == 7
        else:
            source = by_id.get(subject["id"])
            if source is None:
                assert subject["avatarURL"] is None
                continue
            else:
                assert source["name"] == subject["name"]
                assert source.get("url") == subject["avatarURL"]
                assert source["credit"] and source["license"]
        asset = "SubjectAvatar_" + subject["id"].replace(":", "_").replace("-", "_")
        image_set = ROOT / "ios/BSmart/Assets.xcassets" / f"{asset}.imageset"
        if not image_set.exists():
            assert subject["avatarURL"] and subject["avatarURL"].startswith("https://")
            continue
        contents = json.loads((image_set / "Contents.json").read_text())
        image = image_set / contents["images"][0]["filename"]
        with Image.open(image) as decoded:
            decoded.verify()
        if subject["kind"] == "politician":
            assert image.stat().st_size > 2_000
        else:
            with Image.open(image) as decoded:
                assert decoded.width >= 100 and decoded.height >= 24



def test_ios_feed_keeps_valid_operations_and_disclosure_order():
    def trade(id, ticker, side, transaction_day, disclosure_day):
        return {"id": id, "politician_id": 7, "politician_name": "Example Member",
                "ticker": ticker, "trade_type": side, "transaction_date": transaction_day,
                "disclosure_date": disclosure_day, "amount_range": "$1,001 - $15,000"}

    snapshot = {"source": "disclosed_capitol", "fetched_at": "2026-09-28T12:00:00Z", "trades": [
        trade(1, "AAPL", "Buy", "2026-09-02", "2026-09-20"),
        trade(2, "MSFT", "Sell", "2026-09-01", "2026-09-22"),
        trade(2, "MSFT", "Sell", "2026-09-01", "2026-09-22"),
        trade(3, "N/A", "Buy", "2026-09-01", "2026-09-21"),
        trade(4, "NVDA", "Buy", "2026-09-30", "2026-09-20"),
    ]}
    feed = build_feed(snapshot)
    assert [row["id"] for row in feed["events"]] == ["politician:trade:2", "politician:trade:1"]
    assert feed["events"][0]["action"] == "sell"
    assert feed["events"][0]["type"] == "trade"
    assert feed["events"][0]["subjectID"] == "politician:7"
    assert feed["subjects"] == [{"id": "politician:7", "kind": "politician", "name": "Example Member",
                                 "avatarURL": None, "metrics": None}]


def test_price_change_uses_transaction_day_and_adjusted_closes():
    connection = sqlite3.connect(":memory:")
    connection.execute("CREATE TABLE price_daily (ticker TEXT, day TEXT, adj_close REAL)")
    connection.executemany("INSERT INTO price_daily VALUES (?, ?, ?)", [
        ("AAPL", "2026-09-02", 100.0),
        ("AAPL", "2026-09-20", 120.0),
        ("AAPL", "2026-09-28", 125.0),
    ])
    feed = {"events": [{"ticker": "AAPL", "type": "trade", "occurredDay": "2026-09-02",
                        "displayDay": "2026-09-20", "isSample": False}]}
    assert attach_prices(feed, connection, as_of=date(2026, 9, 29)) == 1
    assert feed["events"][0]["eventDayAdjustedClose"] == 100.0
    assert feed["events"][0]["latestAdjustedClose"] == 125.0
    assert feed["events"][0]["latestPriceDay"] == "2026-09-28"
    assert feed["events"][0]["priceBasis"] == "adjusted"
    assert attach_prices(feed, connection, as_of=date(2026, 10, 10)) == 0
    assert "latestAdjustedClose" not in feed["events"][0]


def test_price_change_does_not_mix_adjusted_and_raw_closes():
    connection = sqlite3.connect(":memory:")
    connection.execute("CREATE TABLE price_daily (ticker TEXT, day TEXT, adj_close REAL, source TEXT)")
    connection.executemany("INSERT INTO price_daily VALUES (?, ?, ?, ?)", [
        ("AAPL", "2026-09-23", 90.0, "yahoo"),
        ("AAPL", "2026-09-28", 120.0, "nasdaq_raw"),
    ])
    event = {"ticker": "AAPL", "type": "opinion", "occurredDay": "2026-09-23",
             "displayDay": "2026-09-23", "isSample": False}
    feed = {"events": [event]}
    assert attach_prices(feed, connection, as_of=date(2026, 9, 29)) == 0
    assert "eventDayAdjustedClose" not in event

    connection.execute("INSERT INTO price_daily VALUES (?, ?, ?, ?)",
                       ("AAPL", "2026-09-25", 110.0, "nasdaq_raw"))
    assert attach_prices(feed, connection, as_of=date(2026, 9, 29)) == 1
    assert event["eventDayAdjustedClose"] == 110.0
    assert event["latestAdjustedClose"] == 120.0
    assert event["priceBasis"] == "raw"


def test_real_13f_subjects_keep_report_period_and_do_not_invent_tickers_or_trades():
    snapshot = {"source": "disclosed_capitol", "fetched_at": "2026-09-28T12:00:00Z", "trades": []}
    filing = {
        "subjectId": "michael-burry", "kind": "celebrity", "title": "Michael Burry",
        "source": "SEC EDGAR Form 13F", "periodOfReport": "2025-09-30",
        "filedAt": "2025-11-03", "filingUrl": "https://www.sec.gov/Archives/example",
        "accession": "0000001-25-000001", "changes": [],
        "holdings": [{"issuer": "EXAMPLE INC", "cusip": "123456789", "securityClass": "COM",
                      "option": None, "shareType": "SH", "discretion": "SOLE",
                      "reportedValueUsd": 100_000}],
    }
    feed = build_feed(snapshot, institutional_snapshots=[filing])
    assert feed["subjects"][0]["name"] == "Michael Burry"
    assert feed["events"][0]["type"] == "holding"
    assert feed["events"][0]["action"] == "held"
    assert feed["events"][0]["ticker"] is None
    assert feed["events"][0]["cusip"] == "123456789"
    assert feed["events"][0]["assetName"] == "EXAMPLE INC"
    assert feed["events"][0]["occurredDay"] == "2025-09-30"
    assert feed["events"][0]["displayDay"] == "2025-11-03"
    assert feed["events"][0]["isSample"] is False

    filing["disclosureStatus"] = "stale"
    stale = build_feed(snapshot, institutional_snapshots=[filing])
    assert "Stale 13F; report period 2025-09-30" in stale["events"][0]["sourceNote"]

    filing["changes"] = [{"issuer": "EXAMPLE INC", "cusip": "123456789", "securityClass": "COM",
                          "option": None, "shareType": "SH", "reportedShareChange": "100",
                          "classification": "reported_shares_increased"}]
    changed = build_feed(snapshot, institutional_snapshots=[filing])
    assert changed["events"][0]["action"] == "increased"

    filing["changes"] = []
    mapped = build_feed(snapshot, institutional_snapshots=[filing],
                        cusip_tickers={"123456789": "EXM"})
    assert mapped["events"][0]["ticker"] == "EXM"
    assert enrich_existing_holdings(feed, mapped) == 1
    assert feed["events"][0]["ticker"] == "EXM"

    filing["holdings"][0]["option"] = "PUT"
    option = build_feed(snapshot, institutional_snapshots=[filing],
                        cusip_tickers={"123456789": "EXM"})
    assert option["events"][0]["ticker"] is None
    assert option["events"][0]["underlyingTicker"] == "EXM"
