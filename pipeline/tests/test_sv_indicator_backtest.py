from __future__ import annotations

from pipeline.domain.smart_voice.indicator_backtest import _signal_rows
from pipeline.domain.smart_voice.indicator_backtest_casebook import _select_distinct_tickers
from pipeline.domain.smart_voice.indicator_backtest_reporting import _audit_flags, _band, _stats
from pipeline.domain.smart_voice.indicator_backtest_outcomes import _trade_stats


def _call(author: str, direction: str, *, band: str = "top", day: str = "2026-07-10", weight: float = 1.0):
    return {
        "author_key": author,
        "direction": direction,
        "band": band,
        "created_at": f"{day}T12:00:00Z",
        "candidate_id": f"{author}:{day}:{direction}:{band}",
        "weight": weight,
    }


def test_signal_rows_match_product_gates() -> None:
    current = [
        _call("x:a", "bull"),
        _call("x:b", "bull"),
        _call("x:c", "bull"),
        _call("x:d", "bear", band="bottom"),
        _call("x:e", "bear", band="bottom"),
    ]
    previous = [
        _call("x:a", "bear", day="2026-07-03"),
        _call("x:b", "bear", day="2026-07-03"),
        _call("x:c", "bear", day="2026-07-03"),
    ]

    signals = {indicator: direction for indicator, direction, _, _ in _signal_rows(current, previous)}

    assert signals == {
        "weighted_net": "bull",
        "author_net": "bull",
        "author_net_shift": "bull",
        "high_low_divergence": "bull",
    }


def test_trade_stats_report_payoff_and_profit_factor() -> None:
    avg_win, avg_loss, payoff, profit_factor = _trade_stats([0.10, 0.20, -0.05, -0.10])

    assert round(avg_win or 0, 4) == 0.15
    assert round(avg_loss or 0, 4) == -0.075
    assert round(payoff or 0, 4) == 2.0
    assert round(profit_factor or 0, 4) == 2.0


def test_evidence_audit_flags_bearish_short_put_conflict() -> None:
    flags = _audit_flags(
        {
            "direction": "bear",
            "raw_text": "Sold MU short put; will buy the shares if assigned.",
            "summary_zh": "",
            "summary_en": "",
            "original_evidence": "",
            "underlying_direction": "unknown",
            "entry_status": "",
        }
    )

    assert "bear_short_put_conflict" in flags
    assert "option_direction_unresolved" in flags


def test_report_band_and_cost_adjustment() -> None:
    assert _band(2, 20) == "top"
    assert _band(19, 20) == "bottom"
    assert _band(10, 20) is None
    rows = [{"directional_return_pct": 0.002, "directional_excess_pct": 0.001}]

    result = _stats(rows, cost=0.0025)

    assert result["raw_hit_rate"] == 0
    assert round(result["avg_directional_return_pct"] or 0, 6) == -0.0005


def test_casebook_selects_best_and_worst_distinct_tickers() -> None:
    rows = [
        {"ticker": "AAA", "directional_excess_pct": "0.40"},
        {"ticker": "AAA", "directional_excess_pct": "0.35"},
        {"ticker": "BBB", "directional_excess_pct": "0.30"},
        {"ticker": "CCC", "directional_excess_pct": "-0.20"},
        {"ticker": "DDD", "directional_excess_pct": "-0.50"},
    ]

    successes = _select_distinct_tickers(rows, success=True, limit=2)
    failures = _select_distinct_tickers(rows, success=False, limit=2)

    assert [row["ticker"] for row in successes] == ["AAA", "BBB"]
    assert [row["ticker"] for row in failures] == ["DDD", "CCC"]
