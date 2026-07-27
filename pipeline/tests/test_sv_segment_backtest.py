from __future__ import annotations

import sqlite3

from pipeline.domain.smart_voice.segment_backtest import _cluster
from pipeline.domain.smart_voice.segment_backtest_schema import ensure_segment_backtest_tables
from pipeline.domain.smart_voice.segment_backtest_scoring import rebuild_segment_scores_asof


def _ranked_call(author: str, direction: str, created_at: str, weight: float = 1.0) -> dict:
    return {
        "author_key": f"x:{author}",
        "investor_id": author,
        "author_handle": author,
        "source": "x",
        "candidate_id": f"{author}:{created_at}",
        "direction": direction,
        "created_at": created_at,
        "segment_sv": 110.0,
        "segment_rank_no": 1,
        "segment_population": 20,
        "weight": weight,
        "url": f"https://x.com/{author}/status/1",
    }


def test_segment_cluster_uses_latest_call_per_author() -> None:
    calls = [
        _ranked_call("a", "bear", "2026-01-01T10:00:00Z"),
        _ranked_call("a", "bull", "2026-01-02T10:00:00Z"),
        _ranked_call("b", "bull", "2026-01-02T11:00:00Z"),
        _ranked_call("c", "bull", "2026-01-02T12:00:00Z"),
    ]

    signal = _cluster(calls, min_authors=3, consensus_threshold=0.65, effective_threshold=2.5)

    assert signal is not None
    assert signal["direction"] == "bull"
    assert signal["bull_authors"] == 3
    assert signal["bear_authors"] == 0


def test_segment_scores_exclude_same_day_settlements() -> None:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE sv_call (
          candidate_id TEXT PRIMARY KEY, source TEXT, investor_id TEXT,
          investor_style TEXT, is_actionable_call INTEGER, direction TEXT
        );
        CREATE TABLE sv_call_candidate (
          candidate_id TEXT PRIMARY KEY, text TEXT
        );
        CREATE TABLE sv_call_settlement (
          candidate_id TEXT, horizon TEXT, ticker TEXT, investor_id TEXT,
          exit_day TEXT, status TEXT, score_weight REAL, expected_hit REAL,
          contribution REAL
        );
        """
    )
    ensure_segment_backtest_tables(con)
    for investor_index in range(10):
        investor_id = f"x:{investor_index}"
        for call_index in range(5):
            candidate_id = f"c:{investor_index}:{call_index}"
            con.execute(
                "INSERT INTO sv_call VALUES (?,?,?,?,?,?)",
                (candidate_id,"x",investor_id,"technical",1,"bull"),
            )
            con.execute("INSERT INTO sv_call_candidate VALUES (?,?)", (candidate_id,"technical setup"))
            con.execute(
                "INSERT INTO sv_call_settlement VALUES (?,?,?,?,?,?,?,?,?)",
                (candidate_id,"1D","NVDA",investor_id,"2026-01-02","settled",1.0,0.5,investor_index / 100.0),
            )
    rebuild_segment_scores_asof(
        con,
        asof_days=("2026-01-02","2026-01-03"),
        sources=("x",),
        segment_types=("horizon",),
        min_n_eff=4.0,
        min_settled_calls=5,
    )

    assert con.execute("SELECT COUNT(*) FROM sv_segment_score_asof WHERE asof_day='2026-01-02'").fetchone()[0] == 0
    assert con.execute("SELECT COUNT(*) FROM sv_segment_score_asof WHERE asof_day='2026-01-03'").fetchone()[0] == 10
    top = con.execute(
        "SELECT investor_id FROM sv_segment_score_asof WHERE asof_day='2026-01-03' ORDER BY rank_no LIMIT 1"
    ).fetchone()[0]
    assert top == "x:9"

