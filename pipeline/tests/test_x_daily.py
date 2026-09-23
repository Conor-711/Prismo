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


def test_delivery_zip_accepts_tweets_jsonl_and_ignores_sidecars(tmp_path):
    original = tmp_path / "tweets_day.jsonl"
    package(original)
    archive = tmp_path / "delivery.zip"
    with zipfile.ZipFile(archive, "w") as output:
        output.write(original, "tweets.jsonl")
        output.writestr("roster.json", "{}")
        output.writestr("README.md", "metadata")
    result = stage_package(archive, tmp_path / "out")
    assert result["rows"] == 1
    assert len(list((tmp_path / "out").glob("tweets_*.jsonl"))) == 1


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


@pytest.mark.parametrize("target,module", [("supabase", "services.client_api.content_release"),
                                          ("legacy", "services.client_api.publish_daily_x")])
def test_publication_routes_to_explicit_target_without_reprocessing_real_data(tmp_path, monkeypatch, target, module):
    from pipeline.jobs.x_daily import write_json
    monkeypatch.setenv("BSMART_CONTENT_PUBLISH_TARGET", target)
    original = tmp_path / "tweets_day.jsonl"
    package(original)
    db = tmp_path / "source.db"
    db.write_bytes(b"never opened")
    commands = []
    def fake_run(command, **kwargs):
        commands.append(command)
        if command[2] == "pipeline.jobs.x_daily.worker":
            state_path = Path(command[3])
            state = json.loads(state_path.read_text())
            state["status"] = "ready"
            write_json(state_path, state)
    monkeypatch.setattr("pipeline.jobs.x_daily.subprocess.run", fake_run)
    result = run(package=str(original), database=str(db), output=str(tmp_path / "runs"), apply=True, publish=True)
    assert commands[-1][2] == module
    assert result["status"] == "published" and result["publicationTarget"] == target
    assert db.read_bytes() == b"never opened"


def test_invalid_publication_target_fails_before_processing(monkeypatch):
    monkeypatch.setenv("BSMART_CONTENT_PUBLISH_TARGET", "typo")
    with pytest.raises(ValueError, match="PUBLISH_TARGET"):
        run(package="not-read", database="not-opened", output="not-created", apply=True, publish=True)


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


def test_translation_accepts_exact_localized_numeric_equivalents_only():
    source = "Repay $325M in '28s after phase 2, then $408M over 4 quarters."
    en = source
    zh = "在2028年偿还3.25亿美元，完成第二阶段后，四个季度内再偿还4.08亿美元。"
    assert validate_translation(source, {"zh": zh, "en": en})
    assert not validate_translation(source, {"zh": zh.replace("3.25亿", "3.24亿"), "en": en})
    assert not validate_translation(source, {"zh": zh.replace("4.08亿", ""), "en": en})
    assert not validate_translation("NVDA target $200", {"zh": "NVDA 目标 2亿美元", "en": "NVDA target $200"})
    assert validate_translation("20K, 16.4K, 44.2K shares", {
        "zh": "成交量分别为2万股、1.64万股和4.42万股", "en": "20K, 16.4K, 44.2K shares"})
    assert not validate_translation("20K shares", {"zh": "成交量为3万股", "en": "20K shares"})
    assert validate_translation("2nd tranche in 9月", {
        "zh": "9月的第二笔交易", "en": "Second tranche in September"})
    assert validate_translation("About .5% remains to target +30%", {
        "zh": "距+30%目标还差0.5%", "en": "About 0.5% remains to target +30%"})
    assert validate_translation("q3/q4 results", {"zh": "第三季度和第四季度的业绩", "en": "q3/q4 results"})
    assert not validate_translation("q4 results", {"zh": "第三季度的业绩", "en": "q4 results"})
    assert validate_translation("At $16-18M per MW on 9.17", {
        "zh": "9月17日每兆瓦约1600万至1800万美元", "en": "At $16-18M per MW on Sept 17"})
    assert not validate_translation("At $16-18M per MW on 9.17", {
        "zh": "9月17日每兆瓦约1500万至1800万美元", "en": "At $16-18M per MW on Sept 17"})
    assert not validate_translation("At $16-18M per MW on 9.17", {
        "zh": "9月18日每兆瓦约1600万至1800万美元", "en": "At $16-18M per MW on Sept 17"})


def test_daily_translation_repairs_missing_numeric_tokens(monkeypatch):
    from pipeline.domain.opinions import kol_translate

    replies = iter([
        {"zh": "股价上涨，现报$110", "en": "Up 2% at $110"},
        {"zh": "股价上涨2%，现报$110", "en": "Up 2% at $110"},
    ])
    prompts = []

    def fake_translation(provider, system, user, *, max_tokens):
        prompts.append(user)
        assert provider == "qwen" and max_tokens == 16000
        return next(replies)

    monkeypatch.setattr(kol_translate, "_messages_json_with", fake_translation)
    result = kol_translate._complete_translation("Up 2% at $110", ["qwen"])
    assert result == {"zh": "股价上涨2%，现报$110", "en": "Up 2% at $110"}
    assert len(prompts) == 2
    assert "2" in prompts[1] and "110" in prompts[1]


def test_long_daily_translation_checks_each_chunk_and_joined_result(monkeypatch):
    from pipeline.domain.opinions import kol_translate

    source = ("A long investment thesis about $CLMT at $325M. " * 12
              + "\n\nThe second point forecasts $200M in debt payments. " * 8)
    chunks = kol_translate._translation_chunks(source)
    assert len(chunks) >= 2
    assert "325" in " ".join(chunks) and "200" in " ".join(chunks)
    calls = []

    def fake_whole(value, _providers):
        calls.append(value)
        return None if value == source else {"zh": value, "en": value}

    monkeypatch.setattr(kol_translate, "_translate_whole", fake_whole)
    result = kol_translate._complete_translation(source, ["qwen"])
    assert result is not None
    assert validate_translation(source, result)
    assert calls == chunks


def test_text_translation_bounds_gemini_rate_limit_wait(monkeypatch):
    from pipeline.domain.opinions import kol_translate

    seen = {}
    monkeypatch.setattr(kol_translate, "_provider_available", lambda provider: True)
    monkeypatch.setattr(kol_translate.gemini, "messages_json",
                        lambda *_args, **kwargs: seen.update(kwargs) or {"zh": "中文", "en": "English"})
    kol_translate._messages_json_with("gemini", "system", "text", max_tokens=16000)
    assert seen["max_rate_waits"] == 1


def test_daily_full_text_prompts_keep_late_ticker_without_changing_legacy_defaults():
    from pipeline.domain.opinions.kol_refine import _user
    body = "Background. " * 300 + "NVDA target $200"
    row = {"source": "x", "ticker": "NVDA", "created_at": "2026-09-16",
           "tweet_type": "tweet", "lang": "en", "reason": "target", "text": body}
    assert "target $200" not in daily_x.score.user_prompt(row)
    assert daily_x.score.user_prompt(row, complete_x_text=True).endswith(body)
    assert "target $200" not in _user("x", "NVDA", body, None)
    assert _user("x", "NVDA", body, None, complete_text=True).endswith(body)


@pytest.mark.parametrize("skip_translation", [False, True])
@pytest.mark.parametrize("reading_package_only", [False, True])
def test_failed_stage_resumes_without_reimporting_and_only_then_writes_ready_manifest(tmp_path, monkeypatch, skip_translation, reading_package_only):
    monkeypatch.setenv("BSMART_RANKINGS_FROZEN", "false")
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
    monkeypatch.setattr(daily_x, "reading_rows", lambda *a: [{"item_id": "100"}, {"item_id": "outside-package"}])
    def validate(*args, require_translation):
        assert require_translation is not skip_translation
        assert [r["item_id"] for r in args[1]] == (["100"] if reading_package_only else ["100", "outside-package"])
        return {"readyViews": 0}
    monkeypatch.setattr(daily_x, "validate_readings", validate)
    def refine(**kwargs):
        assert [r["item_id"] for r in kwargs["rows"]] == (["100"] if reading_package_only else ["100", "outside-package"])
        assert kwargs["complete_text"] is True
        stages.append("refine")
    monkeypatch.setattr(kol_refine, "refine", refine)
    monkeypatch.setattr(kol_translate, "translate", lambda **kw: stages.append("translate"))
    def export(**kwargs):
        destination = Path(kwargs["output_dir"])
        destination.mkdir()
        for name in ("smart-accounts", "smart-account-updates", "smart-account-evidence"):
            write_json(destination / f"{name}.json", [{"id": "x:a", "platform": "X"}] if name == "smart-accounts" else [])
    monkeypatch.setattr(client_read_model, "export_smart_account_client_read_model", export)
    state = {"database": str(Path(engine.url.database).resolve()), "postIds": ["100"],
             "asOf": datetime.now(timezone.utc).isoformat(), "packageHash": "abc", "sourceFrom": "start",
             "sourceThrough": "end", "steps": {}, "status": "running", "skipTranslation": skip_translation,
             "readingPackageOnly": reading_package_only}
    journal = tmp_path / "run.json"
    with pytest.raises(RuntimeError, match="timed out"):
        _process(state, journal, tmp_path, tmp_path, 1, 10)
    assert json.loads(journal.read_text())["status"] == "failed"
    assert not (tmp_path / "release/daily-x-manifest.json").exists()
    _process(json.loads(journal.read_text()), journal, tmp_path, tmp_path, 1, 10)
    assert stages == ["import", "candidates", "extract", "extract", "prices", "settle", "score", "refine"] + ([] if skip_translation else ["translate"])
    assert json.loads(journal.read_text())["status"] == "ready"
    assert json.loads((tmp_path / "release/daily-x-manifest.json").read_text())["status"] == "ready"


def test_daily_rankings_are_frozen_by_default(tmp_path, monkeypatch):
    from pipeline.jobs.x_daily import _process, write_json
    from pipeline.common.db import engine
    from pipeline.domain.opinions import kol_refine, kol_translate
    from pipeline.platforms.x import archive
    from pipeline.platforms.market_data import daily_prices
    from pipeline.jobs.smart_voice import client_read_model
    from types import SimpleNamespace
    monkeypatch.delenv("BSMART_RANKINGS_FROZEN", raising=False)
    monkeypatch.setattr(daily_x, "connect", lambda _: SimpleNamespace(close=lambda: None))
    monkeypatch.setattr(archive, "import_archives", lambda *a: None)
    monkeypatch.setattr(daily_x.score, "build_candidates", lambda *a, **kw: None)
    monkeypatch.setattr(daily_x, "extract", lambda *a: None)
    monkeypatch.setattr(daily_x, "price_scope", lambda _: [])
    monkeypatch.setattr(daily_prices, "refresh", lambda *a: None)
    monkeypatch.setattr(daily_x.score, "settle_calls", lambda *a, **kw: None)
    monkeypatch.setattr(daily_x.score, "score_investors", lambda *a, **kw: pytest.fail("scoring must stay frozen"))
    monkeypatch.setattr(daily_x, "collections", lambda *a: {})
    monkeypatch.setattr(daily_x, "reading_rows", lambda *a: [])
    monkeypatch.setattr(daily_x, "validate_readings", lambda *a, **kw: {})
    monkeypatch.setattr(kol_refine, "refine", lambda **kw: None)
    monkeypatch.setattr(kol_translate, "translate", lambda **kw: None)
    def export(**kwargs):
        destination = Path(kwargs["output_dir"])
        destination.mkdir()
        write_json(destination / "smart-accounts.json", [{"id": "x:a", "platform": "X"}])
        for name in ("smart-account-updates", "smart-account-evidence"):
            write_json(destination / f"{name}.json", [])
    monkeypatch.setattr(client_read_model, "export_smart_account_client_read_model", export)
    state = {"database": str(Path(engine.url.database).resolve()), "postIds": [],
             "asOf": datetime.now(timezone.utc).isoformat(), "packageHash": "abc", "sourceFrom": "start",
             "sourceThrough": "end", "steps": {}, "status": "running"}
    _process(state, tmp_path / "run.json", tmp_path, tmp_path, 1, 10)
    assert state["steps"]["score"]["result"] == {"status": "frozen"}


def test_original_only_still_requires_original_and_summaries():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.execute("CREATE TABLE kol_refined(source, item_id, ticker, reason_zh, reason_en, trans_zh, trans_en)")
    con.execute("INSERT INTO kol_refined VALUES ('x', '1', 'NVDA', 'summary zh', 'summary en', NULL, NULL)")
    rows = [{"item_id": "1", "ticker": "NVDA", "txt": "NVDA target $200"}]
    assert daily_x.validate_readings(con, rows, require_translation=False)["translationMode"] == "skipped"
    with pytest.raises(RuntimeError, match="Incomplete"):
        daily_x.validate_readings(con, rows)
    con.execute("UPDATE kol_refined SET reason_en=''")
    with pytest.raises(RuntimeError, match="Incomplete"):
        daily_x.validate_readings(con, rows, require_translation=False)
    con.execute("UPDATE kol_refined SET reason_en='summary en'")
    rows[0]["txt"] = " "
    with pytest.raises(RuntimeError, match="Incomplete"):
        daily_x.validate_readings(con, rows, require_translation=False)
    con.close()


def test_resume_rejects_changed_translation_mode_before_worker(tmp_path, monkeypatch):
    from pipeline.jobs.x_daily import write_json
    original = tmp_path / "tweets_day.jsonl"
    package(original)
    db = tmp_path / "source.db"
    db.write_bytes(b"not opened")
    output = tmp_path / "runs"
    inspection = run(package=str(original), database=str(db), output=str(output), skip_translation=True)
    assert inspection["skipTranslation"] is True
    write_json(Path(inspection["output"]) / "run.json", {
        "database": str(db), "skipTranslation": True, "steps": {}})
    def unexpected_worker(*args, **kwargs):
        pytest.fail("worker must not run after a mode change")
    monkeypatch.setattr("pipeline.jobs.x_daily.subprocess.run", unexpected_worker)
    with pytest.raises(ValueError, match="Translation mode changed"):
        run(package=str(original), database=str(db), output=str(output), apply=True)
