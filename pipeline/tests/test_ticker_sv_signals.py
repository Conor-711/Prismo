from __future__ import annotations

import sqlite3

from pipeline.domain.smart_voice.ticker_signal_scoring import rebuild_point_in_time_scores
from pipeline.domain.smart_voice.ticker_signals import _aggregate_daily, _cohort_matches


def test_cohort_boundaries_overlap_as_expected() -> None:
    assert _cohort_matches(5) == ("top10", "top25")
    assert _cohort_matches(20) == ("top25",)
    assert _cohort_matches(80) == ("bottom25",)
    assert _cohort_matches(95) == ("bottom25", "bottom10")
    assert _cohort_matches(50) == ()


def test_cluster_requires_independent_effective_voices() -> None:
    calls = [
        {
            "direction": "bull",
            "cohorts": ("top25",),
            "call_weight": 1.0,
            "confidence": "high",
            "target_price": None,
            "source": "x",
            "call_type": "single_ticker_call",
            "candidate_id": f"call-{index}",
            "investor_id": f"investor-{index}",
            "sv": 130,
            "horizon_explicit": 1,
        }
        for index in range(3)
    ]
    result = _aggregate_daily(calls, "top25", 3, 0.65, 2.5)
    assert result is not None
    assert result["cluster_flag"] == 1
    assert result["n_authors"] == 3
    assert result["dominant_direction"] == "bull"


def test_point_in_time_score_uses_only_previously_exited_settlements() -> None:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE sv_call (
          candidate_id TEXT PRIMARY KEY,
          source TEXT,
          author_handle TEXT,
          language TEXT,
          direction TEXT,
          investor_style TEXT,
          call_structure TEXT
        );
        CREATE TABLE sv_call_settlement (
          candidate_id TEXT,
          horizon TEXT,
          ticker TEXT,
          investor_id TEXT,
          created_at TEXT,
          exit_day TEXT,
          status TEXT,
          actual_hit INTEGER,
          contribution REAL,
          score_weight REAL,
          expected_hit REAL
        );
        INSERT INTO sv_call VALUES ('call-1','x','alpha','en','bull','fundamental','thesis');
        INSERT INTO sv_call_settlement VALUES
          ('call-1','5D','MU','x:alpha','2026-01-01','2026-01-10','settled',1,0.5,1.0,0.5);
        """
    )
    rebuild_point_in_time_scores(con, ["2026-01-10", "2026-01-11"])
    days = [row[0] for row in con.execute("SELECT DISTINCT asof_day FROM sv_investor_score_asof ORDER BY asof_day")]
    assert days == ["2026-01-11"]
