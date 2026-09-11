import copy
from datetime import datetime, timezone

from pipeline.domain.smart_voice.representative_intro import enrich_representative_intros
from pipeline.domain.smart_voice.client_read_model import build_representative_evidence, build_smart_account_client_collections
from pipeline.tests.test_smart_account_client_read_model import _database

NOW = datetime(2026, 9, 9, tzinfo=timezone.utc)


def _documents():
    profile = {"id": "author-1", "platform": "X", "score": 107}
    work = {"id": "work-id", "authorId": "author-1", "platform": "X", "ticker": "NVDA",
            "direction": "bullish", "publishedAt": "2026-08-04T12:00:00Z",
            "evidenceRole": "representative", "representativeTickerContribution": 2,
            "representativeTickerRank": 1,
            "settlement": {"status": "settled", "horizon": "20D", "tickerReturnPercent": 12}}
    return [profile], [work]


def test_first_view_uses_full_history_not_only_positive_markers_and_never_future_close():
    db = _database()
    db.execute("UPDATE sv_call SET created_at='2026-08-03T15:00:00Z'")
    db.execute("INSERT INTO price_daily VALUES ('NVDA', '2026-07-31', 100, 110, 90, 105, 10, 'test')")
    profiles, evidence = _documents()
    original = copy.deepcopy(evidence)
    report = enrich_representative_intros(db, profiles, evidence, as_of=NOW)
    first = profiles[0]["representativeWork"]["firstOpinion"]
    assert first["publishedAt"] == "2026-08-03T15:00:00Z"
    assert first["price"] == 105
    assert first["priceDay"] == "2026-07-31"
    assert report["withFirstPrice"] == 1
    assert evidence[0] == original[0] | {"firstOpinion": first}
    assert profiles[0]["score"] == 107
    assert profiles[0]["representativeWork"]["stockReturnPercent"] == 3.3
    assert profiles[0]["representativeWork"]["publishedAt"] == first["publishedAt"]


def test_work_order_not_return_and_platform_direction_scope():
    db = _database()
    profiles, evidence = _documents()
    second = evidence[0] | {"id": "other", "ticker": "MU", "representativeTickerRank": 2,
                            "settlement": {"status": "settled", "horizon": "5D", "tickerReturnPercent": 999}}
    evidence.insert(0, second)
    db.execute("UPDATE sv_call SET source='youtube'")
    enrich_representative_intros(db, profiles, evidence, as_of=NOW)
    assert profiles[0]["representativeWork"]["ticker"] == "NVDA"
    assert "firstOpinion" not in profiles[0]["representativeWork"]
    db.execute("UPDATE sv_call SET source='x', direction='bear'")
    enrich_representative_intros(db, profiles, evidence, as_of=NOW)
    assert profiles[0]["representativeWork"]["direction"] == "bearish"
    assert profiles[0]["representativeWork"]["firstOpinion"]["direction"] == "bearish"


def test_unavailable_price_stays_null_and_does_not_use_later_price():
    db = _database()
    db.execute("DELETE FROM price_daily")
    db.execute("INSERT INTO price_daily VALUES ('NVDA', '2026-08-05', 100, 110, 90, 105, 10, 'test')")
    profiles, evidence = _documents()
    enrich_representative_intros(db, profiles, evidence, as_of=NOW)
    first = profiles[0]["representativeWork"]["firstOpinion"]
    assert first["price"] is None and first["priceDay"] is None


def test_post_close_can_use_same_day_close_but_missing_or_future_work_is_not_fabricated():
    db = _database()
    db.execute("UPDATE sv_call SET created_at='2026-08-04T21:00:00Z'")
    profiles, evidence = _documents()
    evidence[0]["publishedAt"] = "2026-08-04T21:00:00Z"
    enrich_representative_intros(db, profiles, evidence, as_of=NOW)
    assert profiles[0]["representativeWork"]["firstOpinion"]["priceDay"] == "2026-08-04"
    evidence[0]["publishedAt"] = "2099-01-01T00:00:00Z"
    assert enrich_representative_intros(db, profiles, evidence, as_of=NOW)["withRepresentative"] == 0
    assert "representativeWork" not in profiles[0]


def test_earliest_positive_anchor_survives_top_ten_limit_and_returns_same_call():
    db = _database()
    db.row_factory = __import__("sqlite3").Row
    original_call = dict(db.execute("SELECT * FROM sv_call LIMIT 1").fetchone())
    original_settlement = dict(db.execute("SELECT * FROM sv_call_settlement LIMIT 1").fetchone())
    for index in range(12):
        call = original_call | {"candidate_id": f"history-{index}", "tweet_id": f"post-{index}",
                                "created_at": f"2026-07-{index + 1:02}T12:00:00Z"}
        settlement = original_settlement | {"candidate_id": call["candidate_id"],
            "contribution": -10 if index == 0 else index / 100, "return_pct": index / 100,
            "entry_day": f"2026-07-{index + 1:02}", "exit_day": "2026-08-05"}
        for table, document in (("sv_call", call), ("sv_call_settlement", settlement)):
            db.execute(f"INSERT INTO {table} ({','.join(document)}) VALUES ({','.join('?' for _ in document)})", tuple(document.values()))
    works = build_representative_evidence(db)
    assert works[0]["publishedAt"] == "2026-07-02T12:00:00Z"
    assert works[0]["settlement"]["tickerReturnPercent"] == 1
    markers = works[0]["priceEvidence"]["opinionMarkers"]
    assert len(markers) == 10
    assert markers[0]["id"] == works[0]["id"]
    assert markers[0]["contribution"] == 0.01
    result = build_smart_account_client_collections(db, as_of=NOW)
    summary = result["smart-accounts"][0]["representativeWork"]
    assert summary["evidenceId"] == works[0]["id"]
    assert summary["publishedAt"] == summary["firstOpinion"]["publishedAt"]
    assert summary["stockReturnPercent"] == works[0]["settlement"]["tickerReturnPercent"]
