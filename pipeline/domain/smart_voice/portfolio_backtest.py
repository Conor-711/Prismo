"""Annualized portfolio backtests for X Smart Voice signals and authors."""
from __future__ import annotations

import bisect
import collections
import sqlite3
from pathlib import Path
from typing import Any

from .portfolio_backtest_engine import (
    PortfolioStats,
    Position,
    PriceBar,
    PriceSeries,
    make_price_series,
    simulate_portfolio_costs,
)
from .portfolio_backtest_reporting import write_portfolio_backtest_reports
from .rank_event_backtest import RankSignalEvent, build_rank_signal_events

DEFAULT_WINDOWS = (1, 3, 7, 14, 30)
DEFAULT_HOLDING_DAYS = (1, 5, 20, 60, 90, 180)
DEFAULT_POSITION_MODES = ("long_short", "long_only", "short_only")
DEFAULT_COSTS_BPS = (0, 10, 25)


def _load_price_book(con: sqlite3.Connection) -> dict[str, PriceSeries]:
    grouped: dict[str, list[PriceBar]] = collections.defaultdict(list)
    rows = con.execute(
        """SELECT upper(ticker) AS ticker,day,
                  CASE WHEN close>0 AND adj_close>0 THEN open*adj_close/close ELSE open END AS open,
                  COALESCE(NULLIF(adj_close,0),close) AS close,
                  COALESCE(volume,0) AS volume
             FROM price_daily
            WHERE open>0 AND COALESCE(NULLIF(adj_close,0),close)>0
            ORDER BY ticker,day"""
    ).fetchall()
    for row in rows:
        grouped[str(row["ticker"])].append(
            PriceBar(
                str(row["day"]),
                float(row["open"]),
                float(row["close"]),
                float(row["volume"] or 0.0),
            )
        )
    return {
        ticker: make_price_series(bars)
        for ticker, bars in grouped.items()
    }


def _entry_exit_days(
    series: PriceSeries,
    signal_day: str,
    holding_days: int,
) -> tuple[str, str] | None:
    entry_index = bisect.bisect_right(series.days, signal_day)
    exit_index = entry_index + holding_days - 1
    if entry_index >= len(series.days) or exit_index >= len(series.days):
        return None
    return series.days[entry_index], series.days[exit_index]


def _mode_allows(mode: str, direction: str) -> bool:
    if mode == "long_short":
        return direction in {"bull", "bear"}
    if mode == "long_only":
        return direction == "bull"
    if mode == "short_only":
        return direction == "bear"
    return False


def _stats_fields(
    simulations: dict[int, PortfolioStats],
) -> dict[str, Any]:
    if 10 not in simulations:
        return {}
    base = simulations[10]
    zero = simulations.get(0, base)
    high = simulations.get(25, base)
    return {
        "start_day": base.start_day,
        "end_day": base.end_day,
        "trading_days": base.trading_days,
        "active_days": base.active_days,
        "n_trades": base.n_trades,
        "overlap_skipped": base.overlap_skipped,
        "exposure_pct": base.exposure_pct,
        "average_positions": base.average_positions,
        "total_return_0bps": zero.total_return,
        "annualized_return_0bps": zero.annualized_return,
        "total_return_10bps": base.total_return,
        "annualized_return_10bps": base.annualized_return,
        "annualized_volatility_10bps": base.annualized_volatility,
        "sharpe_10bps": base.sharpe,
        "max_drawdown_10bps": base.max_drawdown,
        "trade_hit_rate_10bps": base.trade_hit_rate,
        "average_trade_return_10bps": base.average_trade_return,
        "profit_factor_10bps": base.profit_factor,
        "total_return_25bps": high.total_return,
        "annualized_return_25bps": high.annualized_return,
        "benchmark_annualized_return": base.benchmark_annualized_return,
    }


def _collective_rows(
    con: sqlite3.Connection,
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    windows: tuple[int, ...],
    holding_days: tuple[int, ...],
    position_modes: tuple[str, ...],
) -> list[dict[str, Any]]:
    slots = ",".join("?" for _ in windows)
    events = [
        dict(row)
        for row in con.execute(
            f"""SELECT event_id,upper(ticker) AS ticker,indicator,window_days,direction,
                       signal_day,signal_value
                  FROM sv_indicator_event
                 WHERE source_scope='x'
                   AND window_days IN ({slots})
                 ORDER BY indicator,window_days,signal_day,ticker,event_id""",
            list(windows),
        )
    ]
    if not events:
        raise RuntimeError(
            "No X indicator events found. Run sv-indicator-backtest before the portfolio backtest."
        )

    grouped: dict[tuple[str, int], list[dict[str, Any]]] = collections.defaultdict(list)
    for event in events:
        grouped[(str(event["indicator"]), int(event["window_days"]))].append(event)

    rows: list[dict[str, Any]] = []
    for (indicator, window), group in sorted(grouped.items()):
        for hold in holding_days:
            base_positions: list[tuple[dict[str, Any], Position]] = []
            for event in group:
                ticker = str(event["ticker"])
                series = price_book.get(ticker)
                if not series:
                    continue
                dates = _entry_exit_days(series, str(event["signal_day"]), hold)
                if not dates:
                    continue
                entry_day, exit_day = dates
                direction = 1 if event["direction"] == "bull" else -1
                position = Position(
                    position_id=str(event["event_id"]),
                    ticker=ticker,
                    direction=direction,
                    entry_day=entry_day,
                    exit_day=exit_day,
                )
                base_positions.append((event, position))
            for mode in position_modes:
                positions = [
                    position
                    for event, position in base_positions
                    if _mode_allows(mode, str(event["direction"]))
                ]
                simulations = simulate_portfolio_costs(
                    positions,
                    price_book,
                    benchmark,
                    DEFAULT_COSTS_BPS,
                )
                fields = _stats_fields(simulations)
                if not fields:
                    continue
                rows.append(
                    {
                        "source": "x",
                        "indicator": indicator,
                        "signal_window_days": window,
                        "holding_days": hold,
                        "position_mode": mode,
                        "n_input_signals": len(positions),
                        **fields,
                    }
                )
    return rows


def _rank_strategy_rows(
    events: list[RankSignalEvent],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    holding_days: tuple[int, ...],
    position_modes: tuple[str, ...],
) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, int, int], list[RankSignalEvent]] = (
        collections.defaultdict(list)
    )
    for event in events:
        grouped[
            (event.strategy, event.rank_band_pct, event.window_days)
        ].append(event)

    rows: list[dict[str, Any]] = []
    for (strategy, rank_band, window), group in sorted(grouped.items()):
        for hold in holding_days:
            base_positions: list[tuple[RankSignalEvent, Position]] = []
            for event in group:
                series = price_book.get(event.ticker)
                if not series:
                    continue
                dates = _entry_exit_days(series, event.signal_day, hold)
                if not dates:
                    continue
                entry_day, exit_day = dates
                base_positions.append(
                    (
                        event,
                        Position(
                            position_id=event.event_id,
                            ticker=event.ticker,
                            direction=1 if event.direction == "bull" else -1,
                            entry_day=entry_day,
                            exit_day=exit_day,
                        ),
                    )
                )
            for mode in position_modes:
                selected = [
                    (event, position)
                    for event, position in base_positions
                    if _mode_allows(mode, event.direction)
                ]
                positions = [position for _, position in selected]
                simulations = simulate_portfolio_costs(
                    positions,
                    price_book,
                    benchmark,
                    DEFAULT_COSTS_BPS,
                )
                fields = _stats_fields(simulations)
                if not fields:
                    continue
                rows.append(
                    {
                        "source": "x",
                        "strategy": strategy,
                        "rank_band_pct": rank_band,
                        "signal_window_days": window,
                        "holding_days": hold,
                        "position_mode": mode,
                        "n_input_events": len(positions),
                        "average_top_authors": (
                            sum(event.top_authors for event, _ in selected)
                            / len(selected)
                        ),
                        "average_bottom_authors": (
                            sum(event.bottom_authors for event, _ in selected)
                            / len(selected)
                        ),
                        "average_top_consensus": (
                            sum(event.top_consensus for event, _ in selected)
                            / len(selected)
                        ),
                        "average_bottom_consensus": (
                            sum(event.bottom_consensus for event, _ in selected)
                            / len(selected)
                        ),
                        **fields,
                    }
                )
    return rows


def _current_author_scores(con: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    output: dict[str, dict[str, Any]] = {}
    for row in con.execute(
        """SELECT investor_id,name,handle,sv,confidence,n_eff,settled_calls
             FROM sv_investor_score WHERE source='x'"""
    ):
        item = dict(row)
        item["formal"] = (
            float(item.get("n_eff") or 0.0) >= 8.0
            and int(item.get("settled_calls") or 0) >= 10
        )
        output[str(row["investor_id"])] = item
    return output


def _author_rows(
    con: sqlite3.Connection,
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    holding_days: tuple[int, ...],
) -> list[dict[str, Any]]:
    slots = ",".join("?" for _ in holding_days)
    raw_rows = [
        dict(row)
        for row in con.execute(
            f"""SELECT c.candidate_id,c.investor_id,c.author_handle,upper(c.ticker) AS ticker,
                       c.direction,c.call_weight,c.horizon_bucket,s.horizon,s.entry_day,s.exit_day,
                       COALESCE(a.platform_qualified,0) AS was_platform_qualified
                  FROM sv_call c
                  JOIN sv_call_settlement s ON s.candidate_id=c.candidate_id
             LEFT JOIN sv_investor_score_asof a
                    ON a.asof_day=substr(c.created_at,1,10)
                   AND a.investor_id=c.investor_id
                   AND a.source='x'
                 WHERE c.source='x'
                   AND c.is_actionable_call=1
                   AND c.direction IN ('bull','bear')
                   AND s.status='settled'
                   AND s.entry_day IS NOT NULL
                   AND s.exit_day IS NOT NULL
                   AND s.horizon IN ({slots})
                 ORDER BY s.horizon,c.investor_id,s.entry_day,s.exit_day,c.candidate_id""",
            [f"{value}D" for value in holding_days],
        )
    ]
    grouped: dict[tuple[str, int, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    handles: dict[str, str] = {}
    for row in raw_rows:
        investor_id = str(row["investor_id"])
        horizon = int(str(row["horizon"]).removesuffix("D"))
        handles.setdefault(investor_id, str(row.get("author_handle") or ""))
        grouped[(investor_id, horizon, "fixed", "all_actionable")].append(row)
        if int(row["was_platform_qualified"] or 0):
            grouped[(investor_id, horizon, "fixed", "point_in_time_qualified")].append(row)
        declared = str(row.get("horizon_bucket") or "").upper()
        canonical_horizon = (
            int(declared.removesuffix("D"))
            if declared in {"1D", "5D", "20D", "60D", "90D", "180D"}
            else 20
        )
        if horizon == canonical_horizon:
            grouped[
                (investor_id, 0, "call_horizon_or_20D", "all_actionable")
            ].append(row)
            if int(row["was_platform_qualified"] or 0):
                grouped[
                    (
                        investor_id,
                        0,
                        "call_horizon_or_20D",
                        "point_in_time_qualified",
                    )
                ].append(row)

    scores = _current_author_scores(con)
    output: list[dict[str, Any]] = []
    for (investor_id, horizon, holding_policy, eligibility_mode), rows in sorted(grouped.items()):
        positions = [
            Position(
                position_id=str(row["candidate_id"]),
                ticker=str(row["ticker"]),
                direction=1 if row["direction"] == "bull" else -1,
                entry_day=str(row["entry_day"]),
                exit_day=str(row["exit_day"]),
            )
            for row in rows
        ]
        simulations = simulate_portfolio_costs(
            positions,
            price_book,
            benchmark,
            DEFAULT_COSTS_BPS,
        )
        fields = _stats_fields(simulations)
        if not fields:
            continue
        score = scores.get(investor_id, {})
        formal = bool(score.get("formal"))
        rank_eligible = (
            formal
            and int(fields["n_trades"]) >= 10
            and int(fields["trading_days"]) >= 126
        )
        output.append(
            {
                "source": "x",
                "eligibility_mode": eligibility_mode,
                "investor_id": investor_id,
                "name": score.get("name") or handles.get(investor_id) or investor_id,
                "handle": score.get("handle") or handles.get(investor_id) or "",
                "current_sv": score.get("sv"),
                "current_confidence": score.get("confidence") or "",
                "current_n_eff": score.get("n_eff"),
                "current_settled_calls": score.get("settled_calls"),
                "current_formal": formal,
                "rank_eligible": rank_eligible,
                "holding_policy": holding_policy,
                "holding_days": horizon if holding_policy == "fixed" else "",
                "n_input_calls": len(rows),
                **fields,
            }
        )
    return output


def _data_profile(con: sqlite3.Connection) -> dict[str, Any]:
    call = con.execute(
        """SELECT COUNT(*) AS calls,COUNT(DISTINCT investor_id) AS authors
             FROM sv_call
            WHERE source='x' AND is_actionable_call=1
              AND direction IN ('bull','bear')"""
    ).fetchone()
    settlement = con.execute(
        """SELECT COUNT(*) AS rows
             FROM sv_call_settlement s
             JOIN sv_call c ON c.candidate_id=s.candidate_id
            WHERE c.source='x' AND s.status='settled'"""
    ).fetchone()
    asof = con.execute(
        """SELECT COUNT(DISTINCT investor_id) AS authors
             FROM sv_investor_score_asof
            WHERE source='x' AND platform_qualified=1"""
    ).fetchone()
    price = con.execute(
        """SELECT MIN(day) AS min_day,MAX(day) AS max_day,
                  COUNT(DISTINCT ticker) AS tickers
             FROM price_daily"""
    ).fetchone()
    return {
        "actionable_calls": int(call["calls"]),
        "call_authors": int(call["authors"]),
        "settled_rows": int(settlement["rows"]),
        "asof_authors": int(asof["authors"]),
        "price_min_day": str(price["min_day"]),
        "price_max_day": str(price["max_day"]),
        "price_tickers": int(price["tickers"]),
    }


def build_x_sv_portfolio_backtest(
    *,
    db_path: str | Path,
    report_dir: str | Path,
    windows: tuple[int, ...] = DEFAULT_WINDOWS,
    holding_days: tuple[int, ...] = DEFAULT_HOLDING_DAYS,
    position_modes: tuple[str, ...] = DEFAULT_POSITION_MODES,
) -> dict[str, int]:
    """Build annualized X-only collective-signal and per-author portfolios."""
    invalid_modes = sorted(set(position_modes) - set(DEFAULT_POSITION_MODES))
    if invalid_modes:
        raise ValueError(f"Unsupported position modes: {','.join(invalid_modes)}")
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    try:
        price_book = _load_price_book(con)
        benchmark = price_book.get("SPY")
        if not benchmark:
            raise RuntimeError("SPY price history is required for the annualized backtest.")
        collective = _collective_rows(
            con,
            price_book,
            benchmark,
            windows,
            holding_days,
            position_modes,
        )
        rank_events, rank_diagnostics = build_rank_signal_events(
            con,
            price_book,
            windows=windows,
        )
        rank_strategies = _rank_strategy_rows(
            rank_events,
            price_book,
            benchmark,
            holding_days,
            position_modes,
        )
        authors = _author_rows(
            con,
            price_book,
            benchmark,
            holding_days,
        )
        profile = _data_profile(con)
    finally:
        con.close()

    result = write_portfolio_backtest_reports(
        Path(report_dir),
        collective,
        authors,
        rank_strategies,
        profile,
    )
    return {
        **result,
        **rank_diagnostics,
        "price_tickers": len(price_book),
        "collective_scenarios": len(collective),
        "author_scenarios": len(authors),
        "rank_strategy_scenarios": len(rank_strategies),
    }
