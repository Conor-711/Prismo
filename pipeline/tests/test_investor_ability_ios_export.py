import json
import sqlite3

from pipeline.jobs.investor_ability import export_ios_snapshot


def test_sparse_research_and_missing_metrics_remain_distinct(tmp_path, monkeypatch):
    report = tmp_path / "report"
    report.mkdir()
    (report / "summary.json").write_text(json.dumps({
        "window_end": "2026-09-29", "observed_calendar_days": 365,
    }))
    (report / "subjects.json").write_text(json.dumps([
        {
            "actor_id": "x:one", "actor_kind": "platform", "source": "x", "name": "One",
            "research_score": -0.1, "win_rate": 1.0, "win_rate_method": "closed_trade_30d",
            "win_rate_observations": 1, "win_rate_wins": 1, "win_rate_losses": 0,
            "follow_return": 0.02, "independent_decision_days": 1, "price_coverage": 1.0,
        },
        {
            "actor_id": "x:none", "actor_kind": "platform", "source": "x", "name": "None",
            "research_score": None, "win_rate": None, "follow_return": None,
            "independent_decision_days": 0, "price_coverage": 0,
        },
        {
            "actor_id": "x:sell", "actor_kind": "platform", "source": "x", "name": "Sell",
            "research_score": None, "win_rate": 1.0, "win_rate_method": "latest_directional_price",
            "win_rate_observations": 1, "win_rate_wins": 1, "win_rate_losses": 0,
            "follow_return": None, "directional_follow_return_proxy": 0.04,
            "independent_decision_days": 0, "price_coverage": 0,
        },
    ]))
    subjects = tmp_path / "subject-activity.json"
    subjects.write_text('{"subjects":[]}')
    output = tmp_path / "ability-research-snapshot.json"
    monkeypatch.setattr(export_ios_snapshot, "REPORT_DIR", report)
    monkeypatch.setattr(export_ios_snapshot, "SUBJECTS_PATH", subjects)
    monkeypatch.setattr(export_ios_snapshot, "OUTPUT", output)
    monkeypatch.setattr(export_ios_snapshot, "DB_PATH", tmp_path / "missing.db")

    export_ios_snapshot.main()
    snapshot = json.loads(output.read_text())
    assert snapshot["asOf"] == "2026-09-29T00:00:00Z"
    rows = snapshot["items"]
    assert len(rows) == 3
    assert (rows[0]["winRateWins"], rows[0]["winRateLosses"]) == (1, 0)
    assert rows[0]["followReturn"] == 0.02
    assert rows[1]["status"] == "no_observable_trade"
    assert rows[1]["followReturn"] is None
    assert rows[2]["followReturn"] == 0.04
    assert rows[2]["followReturnMethod"] == "directional_30d_proxy"


def test_platform_avatars_use_local_author_identity(tmp_path, monkeypatch):
    path = tmp_path / "authors.db"
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE author_profile (source TEXT, author_id TEXT, avatar_url TEXT)")
        db.execute("CREATE TABLE author_avatar (source TEXT, handle TEXT, url TEXT)")
        db.execute("INSERT INTO author_profile VALUES ('x', '123', 'https://example.com/x.jpg')")
        db.execute("INSERT INTO author_avatar VALUES ('youtube', 'UCAbC', 'https://example.com/yt.jpg')")
    monkeypatch.setattr(export_ios_snapshot, "DB_PATH", path)
    x_by_id, by_handle = export_ios_snapshot.platform_avatars()
    assert x_by_id["123"] == "https://example.com/x.jpg"
    assert by_handle[("youtube", "ucabc")] == "https://example.com/yt.jpg"
