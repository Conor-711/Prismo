"""Cross-platform orchestration for per-Smart-Account follow backtests."""
from __future__ import annotations

import sqlite3
from collections import defaultdict
from dataclasses import asdict
from pathlib import Path
from typing import Any, Iterable

from .account_follow_backtest_engine import simulate_account_follow
from .account_follow_backtest_types import FollowCall, FollowStats, FollowTrade
from .client_read_model import QUALIFIED_FILTER
from .portfolio_backtest import _load_price_book
from .portfolio_backtest_engine import PriceSeries


FOLLOW_LIFECYCLES = (
    "open_call",
    "reinforce_call",
    "close_prior_call",
    "invalidate_prior_call",
    "reverse_call",
)
HORIZON_SESSIONS = {
    "1D": 1,
    "5D": 5,
    "20D": 20,
    "60D": 60,
    "90D": 90,
    "180D": 180,
}


def _current_accounts(connection: sqlite3.Connection) -> list[dict[str, Any]]:
    rows = [
        dict(row)
        for row in connection.execute(
            f"""SELECT investor_id,source,name,handle,sv,confidence,n_eff,
                       settled_calls,active_days,covered_tickers
                  FROM sv_investor_score
                 WHERE {QUALIFIED_FILTER}
                 ORDER BY source,sv DESC,investor_id"""
        )
    ]
    by_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_source[str(row["source"])].append(row)
    for source_rows in by_source.values():
        population = len(source_rows)
        for rank, row in enumerate(source_rows, start=1):
            row["current_platform_rank"] = rank
            row["current_platform_population"] = population
            row["current_platform_top_pct"] = rank / population if population else None
    return rows


def _load_calls(
    connection: sqlite3.Connection,
    accounts: Iterable[dict[str, Any]],
) -> dict[tuple[str, str], list[tuple[FollowCall, bool]]]:
    account_rows = list(accounts)
    if not account_rows:
        return {}
    investor_ids = [str(row["investor_id"]) for row in account_rows]
    sources = sorted({str(row["source"]) for row in account_rows})
    investor_slots = ",".join("?" for _ in investor_ids)
    source_slots = ",".join("?" for _ in sources)
    lifecycle_slots = ",".join("?" for _ in FOLLOW_LIFECYCLES)
    rows = connection.execute(
        f"""
        SELECT c.candidate_id,c.source,c.investor_id,upper(c.ticker) AS ticker,
               c.created_at,c.direction,
               COALESCE(NULLIF(c.lifecycle_action,''),'open_call') AS lifecycle_action,
               COALESCE(NULLIF(c.affected_direction,''),'unknown') AS affected_direction,
               COALESCE(NULLIF(c.horizon_bucket,''),'unknown') AS horizon_bucket,
               COALESCE(NULLIF(c.summary_zh,''),NULLIF(c.summary_en,''),
                        substr(candidate.text,1,320),'') AS thesis,
               COALESCE(candidate.url,'') AS evidence_url,
               COALESCE((
                   SELECT a.platform_qualified
                     FROM sv_investor_score_asof a
                    WHERE a.investor_id=c.investor_id
                      AND a.source=c.source
                      AND a.asof_day < substr(c.created_at,1,10)
                    ORDER BY a.asof_day DESC
                    LIMIT 1
               ),0) AS was_platform_qualified
          FROM sv_call c
     LEFT JOIN sv_call_candidate candidate
            ON candidate.candidate_id=c.candidate_id
         WHERE c.investor_id IN ({investor_slots})
           AND c.source IN ({source_slots})
           AND c.is_actionable_call=1
           AND c.direction IN ('bull','bear')
           AND c.lifecycle_action IN ({lifecycle_slots})
           AND c.created_at IS NOT NULL
         ORDER BY c.source,c.investor_id,c.created_at,c.candidate_id
        """,
        [*investor_ids, *sources, *FOLLOW_LIFECYCLES],
    ).fetchall()
    allowed_keys = {
        (str(row["source"]), str(row["investor_id"]))
        for row in account_rows
    }
    grouped: dict[tuple[str, str], list[tuple[FollowCall, bool]]] = defaultdict(list)
    for row in rows:
        key = (str(row["source"]), str(row["investor_id"]))
        if key not in allowed_keys:
            continue
        horizon = str(row["horizon_bucket"] or "unknown").upper()
        grouped[key].append(
            (
                FollowCall(
                    candidate_id=str(row["candidate_id"]),
                    source=key[0],
                    investor_id=key[1],
                    ticker=str(row["ticker"]),
                    created_at=str(row["created_at"]),
                    direction=str(row["direction"]),
                    lifecycle=str(row["lifecycle_action"]),
                    affected_direction=str(row["affected_direction"]),
                    horizon_sessions=HORIZON_SESSIONS.get(horizon, 20),
                    thesis=str(row["thesis"] or ""),
                    evidence_url=str(row["evidence_url"] or ""),
                ),
                bool(row["was_platform_qualified"]),
            )
        )
    return grouped


def _stats_row(stats: FollowStats | None) -> dict[str, Any]:
    if stats is None:
        return {
            "start_day": "",
            "end_day": "",
            "trading_days": 0,
            "active_days": 0,
            "signal_count": 0,
            "trade_count": 0,
            "long_trades": 0,
            "short_trades": 0,
            "exposure_pct": None,
            "average_active_positions": None,
            "turnover_sides": 0,
            "total_return": None,
            "annualized_return": None,
            "benchmark_total_return": None,
            "benchmark_annualized_return": None,
            "annualized_excess_return": None,
            "annualized_volatility": None,
            "sharpe": None,
            "max_drawdown": None,
            "trade_hit_rate": None,
            "average_trade_return": None,
            "same_direction_updates": 0,
            "reversals": 0,
            "explicit_exits": 0,
            "price_history_end_exits": 0,
            "skipped_no_price": 0,
        }
    return asdict(stats)


def _coverage_status(stats: FollowStats | None) -> str:
    if stats is None or stats.trade_count == 0:
        return "no_executable_calls"
    if stats.trading_days < 63 or stats.trade_count < 5:
        return "insufficient"
    if stats.trading_days < 126 or stats.trade_count < 10:
        return "limited"
    return "rank_eligible"


def _trade_rows(
    trades: Iterable[FollowTrade],
    account: dict[str, Any],
    eligibility_mode: str,
) -> list[dict[str, Any]]:
    return [
        {
            "eligibility_mode": eligibility_mode,
            "name": account.get("name") or account.get("handle") or account["investor_id"],
            "handle": account.get("handle") or "",
            "current_sv": account.get("sv"),
            **asdict(trade),
        }
        for trade in trades
    ]


def _simulate_mode(
    calls: list[FollowCall],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    *,
    evaluation_end: str,
    long_only: bool,
) -> tuple[FollowStats | None, list[FollowTrade]]:
    return simulate_account_follow(
        calls,
        price_book,
        benchmark,
        round_trip_cost_bps=10,
        long_only=long_only,
        evaluation_end=evaluation_end,
    )


def build_account_follow_backtest(
    *,
    db_path: str | Path,
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    dict[str, Any],
]:
    """Calculate executable and descriptive returns for every formal account."""
    connection = sqlite3.connect(str(db_path))
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA busy_timeout=8000")
    try:
        accounts = _current_accounts(connection)
        calls_by_account = _load_calls(connection, accounts)
        price_book = _load_price_book(connection)
    finally:
        connection.close()

    benchmark = price_book.get("SPY")
    if benchmark is None:
        raise RuntimeError("SPY price history is required for account follow backtests.")
    evaluation_end = max(
        series.days[-1]
        for ticker, series in price_book.items()
        if ticker != "SPY" and series.days
    )

    executable_rows: list[dict[str, Any]] = []
    descriptive_rows: list[dict[str, Any]] = []
    trade_rows: list[dict[str, Any]] = []
    for account in accounts:
        key = (str(account["source"]), str(account["investor_id"]))
        pairs = calls_by_account.get(key, [])
        all_calls = [call for call, _ in pairs]
        qualified_calls = [call for call, qualified in pairs if qualified]

        executable_stats, executable_trades = _simulate_mode(
            qualified_calls,
            price_book,
            benchmark,
            evaluation_end=evaluation_end,
            long_only=False,
        )
        long_only_stats, _ = _simulate_mode(
            qualified_calls,
            price_book,
            benchmark,
            evaluation_end=evaluation_end,
            long_only=True,
        )
        descriptive_stats, _ = _simulate_mode(
            all_calls,
            price_book,
            benchmark,
            evaluation_end=evaluation_end,
            long_only=False,
        )

        base = {
            "source": account["source"],
            "investor_id": account["investor_id"],
            "name": account.get("name") or account.get("handle") or account["investor_id"],
            "handle": account.get("handle") or "",
            "current_sv": account.get("sv"),
            "current_confidence": account.get("confidence") or "",
            "current_n_eff": account.get("n_eff"),
            "current_settled_calls": account.get("settled_calls"),
            "current_platform_rank": account.get("current_platform_rank"),
            "current_platform_population": account.get("current_platform_population"),
            "current_platform_top_pct": account.get("current_platform_top_pct"),
            "all_actionable_calls": len(all_calls),
            "point_in_time_qualified_calls": len(qualified_calls),
        }
        executable_rows.append(
            {
                **base,
                "eligibility_mode": "point_in_time_qualified",
                "position_mode": "long_short",
                "coverage_status": _coverage_status(executable_stats),
                **_stats_row(executable_stats),
                "long_only_total_return": (
                    long_only_stats.total_return if long_only_stats else None
                ),
                "long_only_annualized_return": (
                    long_only_stats.annualized_return if long_only_stats else None
                ),
                "long_only_max_drawdown": (
                    long_only_stats.max_drawdown if long_only_stats else None
                ),
                "long_only_trade_count": (
                    long_only_stats.trade_count if long_only_stats else 0
                ),
            }
        )
        descriptive_rows.append(
            {
                **base,
                "eligibility_mode": "current_pool_full_history_descriptive",
                "position_mode": "long_short",
                "coverage_status": _coverage_status(descriptive_stats),
                **_stats_row(descriptive_stats),
            }
        )
        trade_rows.extend(
            _trade_rows(
                executable_trades,
                account,
                "point_in_time_qualified",
            )
        )

    profile = {
        "account_count": len(accounts),
        "accounts_by_source": {
            source: sum(row["source"] == source for row in accounts)
            for source in sorted({str(row["source"]) for row in accounts})
        },
        "price_tickers": len(price_book),
        "price_start_day": benchmark.days[0],
        "price_end_day": evaluation_end,
        "executable_accounts": sum(row["trade_count"] > 0 for row in executable_rows),
        "rank_eligible_accounts": sum(
            row["coverage_status"] == "rank_eligible" for row in executable_rows
        ),
    }
    return executable_rows, descriptive_rows, trade_rows, profile
