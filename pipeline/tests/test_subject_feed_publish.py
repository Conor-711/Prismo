import copy
import json
from urllib.error import HTTPError

import pytest

from pipeline.jobs.congress_capture import subject_feed_publish
from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot


def snapshot():
    return {"schemaVersion": 1, "subjects": [{"id": "celebrity:1", "kind": "celebrity",
             "name": "Example", "avatarURL": None, "metrics": None}],
            "events": [{"id": "event:1", "subjectID": "celebrity:1", "ticker": "AAPL",
                        "type": "trade", "action": "buy", "occurredDay": "2026-09-27", "displayDay": "2026-09-28",
                        "amountRange": None, "assetDescription": None, "isSample": False}]}


def test_real_subject_snapshot_validates():
    validate_snapshot(snapshot())


def test_samples_need_explicit_opt_in():
    data = snapshot()
    data["events"][0]["isSample"] = True
    with pytest.raises(ValueError, match="Sample events"):
        validate_snapshot(data)
    validate_snapshot(data, allow_samples=True)


def test_unknown_subject_and_invalid_metrics_are_rejected():
    data = snapshot()
    data["events"][0]["subjectID"] = "institution:other"
    with pytest.raises(ValueError):
        validate_snapshot(data)
    data = copy.deepcopy(snapshot())
    data["subjects"][0]["metrics"] = {"wins": -1, "losses": 2, "trackedReturn": 0.1}
    with pytest.raises(ValueError):
        validate_snapshot(data)


def test_opinion_requires_direction_and_summary():
    data = snapshot()
    event = data["events"][0]
    event.update(type="opinion", action=None, direction="bullish", summary="A sample view")
    validate_snapshot(data)
    event["summary"] = ""
    with pytest.raises(ValueError, match="Invalid opinion"):
        validate_snapshot(data)


def test_holding_accepts_issuer_without_ticker_but_requires_source():
    data = snapshot()
    event = data["events"][0]
    event.update(type="holding", ticker=None, action="held", assetName="EXAMPLE INC",
                 sourceURL="https://www.sec.gov/Archives/example")
    validate_snapshot(data)
    event["sourceURL"] = None
    with pytest.raises(ValueError, match="Invalid holding"):
        validate_snapshot(data)


def test_management_publisher_stages_large_snapshot_after_413(monkeypatch):
    monkeypatch.setattr(subject_feed_publish, "MANAGEMENT_CHUNK_SIZE", 40)
    data = snapshot()
    calls = []

    def query(sql, parameters):
        calls.append((sql, parameters))
        if "insert into public.bsmart_subject_activity_snapshots" in sql and "with assembled" not in sql:
            raise HTTPError("https://api.supabase.com", 413, "Payload Too Large", None, None)
        if "select count(*) as promoted" in sql:
            return [{"promoted": 1}]
        return []

    subject_feed_publish.publish_management_snapshot(data, query)
    chunks = [parameters[2] for sql, parameters in calls if "payload_text) values" in sql]
    assert len(chunks) > 1
    assert json.loads("".join(chunks)) == data
    assert "string_agg" in calls[-2][0] and "md5" in calls[-2][0]
    assert "delete from public.bsmart_subject_activity_publish_chunks" in calls[-1][0]


def test_management_publisher_preserves_non_size_errors():
    def query(sql, parameters):
        raise HTTPError("https://api.supabase.com", 401, "Unauthorized", None, None)

    with pytest.raises(HTTPError) as error:
        subject_feed_publish.publish_management_snapshot(snapshot(), query)
    assert error.value.code == 401


def test_price_merge_preserves_live_events_and_rejects_identity_changes():
    current = snapshot()
    current["events"][0]["summary"] = "Keep live editorial text"
    incoming = copy.deepcopy(current)
    incoming["events"][0].update(eventDayAdjustedClose=100, latestAdjustedClose=110,
                                   latestPriceDay="2026-09-28", priceBasis="adjusted")

    merged, changed = subject_feed_publish.merge_price_observations(current, incoming)
    assert changed == 1
    assert merged["events"][0]["summary"] == "Keep live editorial text"
    assert merged["events"][0]["latestAdjustedClose"] == 110
    assert "latestAdjustedClose" not in current["events"][0]
    assert subject_feed_publish.merge_price_observations(merged, incoming)[1] == 0

    incoming["events"][0]["ticker"] = "MSFT"
    with pytest.raises(ValueError, match="changed since local export"):
        subject_feed_publish.merge_price_observations(current, incoming)


def test_holding_enrichment_only_changes_verified_matching_events():
    current = snapshot()
    holding = {**current["events"][0], "id": "13f:example", "type": "holding",
               "ticker": None, "action": "held", "assetName": "ALPHABET INC",
               "sourceURL": "https://www.sec.gov/Archives/example"}
    current["events"].append(holding)
    incoming = copy.deepcopy(current)
    incoming["events"][1].update(ticker="GOOGL", cusip="02079K305",
                                  eventDayAdjustedClose=100, latestAdjustedClose=110,
                                  latestPriceDay="2026-09-28", priceBasis="adjusted")

    merged, mapped, identified, priced = subject_feed_publish.merge_holding_enrichment(current, incoming)
    assert (mapped, identified, priced) == (1, 0, 1)
    assert merged["events"][0] == current["events"][0]
    assert merged["events"][1]["ticker"] == "GOOGL"
    assert merged["events"][1]["cusip"] == "02079K305"
    assert current["events"][1]["ticker"] is None
    assert subject_feed_publish.merge_holding_enrichment(merged, incoming)[1:] == (0, 0, 0)

    incoming["events"][1]["assetName"] = "OTHER ISSUER"
    with pytest.raises(ValueError, match="changed since local export"):
        subject_feed_publish.merge_holding_enrichment(current, incoming)


def test_option_underlying_is_identified_without_inventing_option_price():
    current = snapshot()
    current["events"][0].update(type="holding", ticker=None, action="new",
                                  assetName="INVESCO QQQ TRUST", summary="CALL option",
                                  sourceURL="https://www.sec.gov/Archives/example")
    incoming = copy.deepcopy(current)
    incoming["events"][0].update(cusip="46090E103", underlyingTicker="QQQ")
    merged, mapped, identified, priced = subject_feed_publish.merge_holding_enrichment(current, incoming)
    assert (mapped, identified, priced) == (0, 1, 0)
    assert merged["events"][0]["ticker"] is None
    assert merged["events"][0]["underlyingTicker"] == "QQQ"
    assert subject_feed_publish.merge_holding_enrichment(merged, incoming)[1:] == (0, 0, 0)
