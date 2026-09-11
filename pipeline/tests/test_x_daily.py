from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import zipfile

import pytest

from pipeline.platforms.x.daily_package import stage_package
from pipeline.domain.smart_voice import daily_x
from pipeline.domain.opinions.translation_completeness import validate_translation
from pipeline.jobs.x_daily import run


def package(path, **changes):
    post = {"tweet_id": "100", "text": "NVDA target $200", "created_at": "2026-09-01T01:00:00Z",
            "author_handle": "author", "cashtags": ["NVDA"], **changes}
    path.write_text(json.dumps(post) + "\n")


def test_nested_zip_and_plain_file_have_same_identity(tmp_path):
    original = tmp_path / "tweets_day.jsonl"
    package(original)
    archive = tmp_path / "day.zip"
    with zipfile.ZipFile(archive, "w") as output:
        output.write(original, "nested/tweets_day.jsonl")
    a = stage_package(original, tmp_path / "a")
    b = stage_package(archive, tmp_path / "b")
    assert a == b
    assert a["uniquePosts"] == 1


@pytest.mark.parametrize("name", ["../tweets_a.jsonl", "/tweets_a.jsonl", "bad\\tweets_a.jsonl"])
def test_unsafe_zip_paths_rejected(tmp_path, name):
    archive = tmp_path / "bad.zip"
    with zipfile.ZipFile(archive, "w") as output:
        output.writestr(name, "{}")
    with pytest.raises(ValueError, match="Unsafe"):
        stage_package(archive, tmp_path / "out")


@pytest.mark.parametrize("changes", [{"created_at": "2100-01-01T00:00:00Z"}, {"author_handle": ""},
                                     {"created_at": "2026-09-01"}, {"cashtags": "NVDA"}])
def test_malformed_rows_rejected_before_import(tmp_path, changes):
    original = tmp_path / "tweets_day.jsonl"
    package(original, **changes)
    with pytest.raises(ValueError, match="Invalid package row"):
        stage_package(original, tmp_path / "out")


def test_inspection_does_not_touch_database_or_call_models(tmp_path):
    original = tmp_path / "tweets_day.jsonl"
    package(original)
    db = tmp_path / "source.db"
    db.write_bytes(b"not opened by inspection")
    result = run(package=str(original), database=str(db), output=str(tmp_path / "runs"))
    assert result["status"] == "inspected"
    assert db.read_bytes() == b"not opened by inspection"


def test_extraction_is_limited_to_this_package_and_partial_results_block(tmp_path, monkeypatch):
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript("CREATE TABLE sv_call_candidate(candidate_id TEXT, tweet_id TEXT, source TEXT);"
                      "CREATE TABLE sv_call(candidate_id TEXT);"
                      "INSERT INTO sv_call_candidate VALUES ('a','100','x'),('b','101','x'),('c','100','reddit');")
    received = []
    monkeypatch.setattr(daily_x.score, "extract_calls", lambda *a, **kw: received.append(kw["candidate_ids"]))
    with pytest.raises(RuntimeError, match="unprocessed"):
        daily_x.extract(con, {"100"}, 1, 5)
    assert received == [{"a"}]
    con.execute("INSERT INTO sv_call VALUES ('a')")
    assert daily_x.extract(con, {"100"}, 1, 5)["processed"] == 0
    con.close()


def test_translation_cannot_be_empty_or_drop_price_numbers():
    assert validate_translation("NVDA $200", {"zh": "NVDA 目标 $200", "en": "NVDA $200"})
    assert not validate_translation("NVDA $200", {"zh": "NVDA 上涨", "en": "NVDA $200"})
    assert not validate_translation("Long detailed original. " * 30, {"zh": "看多", "en": "Bullish"})
    assert validate_translation("NVDA $10,000 https://t.co/123", {"zh": "NVDA $10000", "en": "NVDA $10,000"})


def test_failed_stage_resumes_without_reimporting_and_only_then_writes_ready_manifest(tmp_path, monkeypatch):
    from pipeline.jobs.x_daily import _process, write_json
    from pipeline.common.db import engine
    from pipeline.domain.opinions import kol_refine, kol_translate
    from pipeline.platforms.x import archive
    from pipeline.platforms.market_data import daily_prices
    from pipeline.jobs.smart_voice import client_read_model
    from types import SimpleNamespace
    stages = []
    monkeypatch.setattr(daily_x, "connect", lambda _: SimpleNamespace(close=lambda: None))
    monkeypatch.setattr(archive, "import_archives", lambda *a: stages.append("import"))
    monkeypatch.setattr(daily_x.score, "build_candidates", lambda *a, **kw: stages.append("candidates"))
    failures = [True, False]
    def extract(*args):
        stages.append("extract")
        if failures.pop(0):
            raise RuntimeError("model timed out")
        return {"processed": 1}
    monkeypatch.setattr(daily_x, "extract", extract)
    monkeypatch.setattr(daily_x, "price_scope", lambda _: ["NVDA"])
    monkeypatch.setattr(daily_prices, "refresh", lambda *a: stages.append("prices"))
    monkeypatch.setattr(daily_x.score, "settle_calls", lambda *a, **kw: stages.append("settle"))
    monkeypatch.setattr(daily_x.score, "score_investors", lambda *a, **kw: stages.append("score"))
    monkeypatch.setattr(daily_x, "collections", lambda *a: {})
    monkeypatch.setattr(daily_x, "reading_rows", lambda *a: [])
    monkeypatch.setattr(daily_x, "validate_readings", lambda *a: {"readyViews": 0})
    monkeypatch.setattr(kol_refine, "refine", lambda **kw: stages.append("refine"))
    monkeypatch.setattr(kol_translate, "translate", lambda **kw: stages.append("translate"))
    def export(**kwargs):
        destination = Path(kwargs["output_dir"])
        destination.mkdir()
        for name in ("smart-accounts", "smart-account-updates", "smart-account-evidence"):
            write_json(destination / f"{name}.json", [{"id": "x:a", "platform": "X"}] if name == "smart-accounts" else [])
    monkeypatch.setattr(client_read_model, "export_smart_account_client_read_model", export)
    state = {"database": str(Path(engine.url.database).resolve()), "postIds": ["100"],
             "asOf": datetime.now(timezone.utc).isoformat(), "packageHash": "abc", "sourceFrom": "start",
             "sourceThrough": "end", "steps": {}, "status": "running"}
    journal = tmp_path / "run.json"
    with pytest.raises(RuntimeError, match="timed out"):
        _process(state, journal, tmp_path, tmp_path, 1, 10)
    assert json.loads(journal.read_text())["status"] == "failed"
    assert not (tmp_path / "release/daily-x-manifest.json").exists()
    _process(json.loads(journal.read_text()), journal, tmp_path, tmp_path, 1, 10)
    assert stages == ["import", "candidates", "extract", "extract", "prices", "settle", "score", "refine", "translate"]
    assert json.loads(journal.read_text())["status"] == "ready"
    assert json.loads((tmp_path / "release/daily-x-manifest.json").read_text())["status"] == "ready"
