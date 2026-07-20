"""Build leakage-free historical signals for the Smart Voice discovery indicators."""
from __future__ import annotations

import bisect
import collections
import math
import sqlite3
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .indicator_backtest_outcomes import (
    build_indicator_events,
    build_indicator_outcomes,
    build_indicator_stats,
    write_indicator_report,
)
from .indicator_backtest_logic import call_signal_weight
from .indicator_backtest_reporting import write_indicator_detail_reports
from .indicator_backtest_schema import ensure_indicator_backtest_tables
from .ticker_signal_schema import ensure_ticker_signal_tables
from .ticker_signal_scoring import rebuild_point_in_time_scores

DEFAULT_WINDOWS = (1, 3, 7, 30, 90)
DEFAULT_SOURCES = ("x", "youtube", "reddit", "xueqiu")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _where_tickers(tickers: list[str], alias: str = "c") -> tuple[str, list[str]]:
    if not tickers:
        return "", []
    return f" AND upper({alias}.ticker) IN ({','.join('?' for _ in tickers)})", tickers


def _load_ranked_calls(
    con: sqlite3.Connection,
    tickers: list[str],
    sources: tuple[str, ...],
) -> list[dict[str, Any]]:
    where, params = _where_tickers(tickers)
    source_slots = ",".join("?" for _ in sources)
    rows = con.execute(
        f"""SELECT c.candidate_id, upper(c.ticker) AS ticker, c.source, c.investor_id,
                   c.created_at, substr(c.created_at,1,10) AS day, c.direction, c.call_weight,
                   a.platform_sv, a.platform_rank_no, a.platform_population,
                   a.confidence, a.n_eff
              FROM sv_call c
              JOIN sv_investor_score_asof a
                ON a.asof_day=substr(c.created_at,1,10)
               AND a.investor_id=c.investor_id
               AND a.source=c.source
             WHERE c.is_actionable_call=1
               AND c.direction IN ('bull','bear')
               AND c.source IN ({source_slots})
               AND a.platform_qualified=1
               AND a.platform_rank_no IS NOT NULL
               AND a.platform_population>=10
               AND c.created_at IS NOT NULL{where}
             ORDER BY ticker, c.created_at, c.candidate_id""",
        [*sources, *params],
    ).fetchall()
    output: list[dict[str, Any]] = []
    for raw in rows:
        item = dict(raw)
        cutoff = max(1, math.ceil(int(item["platform_population"]) * 0.10))
        rank = int(item["platform_rank_no"])
        population = int(item["platform_population"])
        if rank <= cutoff:
            item["band"] = "top"
        elif rank > population - cutoff:
            item["band"] = "bottom"
        else:
            continue
        item["author_key"] = f"{item['source']}:{item['investor_id']}"
        item["weight"] = call_signal_weight(item)
        output.append(item)
    return output


def _latest_states(calls: list[dict[str, Any]], band: str) -> dict[str, dict[str, Any]]:
    states: dict[str, dict[str, Any]] = {}
    for call in calls:
        if call["band"] != band:
            continue
        key = str(call["author_key"])
        previous = states.get(key)
        marker = (str(call["created_at"]), str(call["candidate_id"]))
        if previous is None or marker > (str(previous["created_at"]), str(previous["candidate_id"])):
            states[key] = call
    return states


def _signal_rows(
    current_calls: list[dict[str, Any]],
    previous_calls: list[dict[str, Any]],
) -> list[tuple[str, str, float, dict[str, Any]]]:
    top = [call for call in current_calls if call["band"] == "top"]
    bottom = [call for call in current_calls if call["band"] == "bottom"]
    top_net = sum((1 if call["direction"] == "bull" else -1) * call["weight"] for call in top)
    bottom_net = sum((1 if call["direction"] == "bull" else -1) * call["weight"] for call in bottom)
    top_bull_voices = {call["author_key"] for call in top if call["direction"] == "bull"}
    top_bear_voices = {call["author_key"] for call in top if call["direction"] == "bear"}
    bottom_voices = {call["author_key"] for call in bottom}
    top_states = _latest_states(current_calls, "top")
    previous_states = _latest_states(previous_calls, "top")
    top_bull_authors = sum(call["direction"] == "bull" for call in top_states.values())
    top_bear_authors = len(top_states) - top_bull_authors
    previous_bull_authors = sum(call["direction"] == "bull" for call in previous_states.values())
    previous_bear_authors = len(previous_states) - previous_bull_authors
    author_net = top_bull_authors - top_bear_authors
    previous_author_net = previous_bull_authors - previous_bear_authors
    author_delta = author_net - previous_author_net
    author_base = max(1, len(top_states), len(previous_states))
    author_shift_pct = author_delta / author_base * 100.0
    common = {
        "top_net": top_net,
        "bottom_net": bottom_net,
        "top_author_net": author_net,
        "previous_top_author_net": previous_author_net,
        "author_net_delta": author_delta,
        "author_net_shift_pct": author_shift_pct,
        "top_authors": len(top_states),
        "previous_top_authors": len(previous_states),
        "bottom_authors": len(_latest_states(current_calls, "bottom")),
        "top_calls": len(top),
        "bottom_calls": len(bottom),
    }
    signals: list[tuple[str, str, float, dict[str, Any]]] = []
    if top_net > 0 and sum(call["direction"] == "bull" for call in top) >= 2 and len(top_bull_voices) >= 2:
        signals.append(("weighted_net", "bull", abs(top_net), common))
    elif top_net < 0 and sum(call["direction"] == "bear" for call in top) >= 2 and len(top_bear_voices) >= 2:
        signals.append(("weighted_net", "bear", abs(top_net), common))
    dominant_authors = top_bull_authors if author_net > 0 else top_bear_authors
    if author_net and abs(author_net) >= 2 and dominant_authors >= 2:
        signals.append(("author_net", "bull" if author_net > 0 else "bear", float(abs(author_net)), common))
    abrupt = (
        abs(author_delta) >= 3
        and abs(author_shift_pct) >= 50.0
        and len(top_states) >= 3
        and len(previous_states) >= 3
    )
    if abrupt:
        signals.append(("author_net_shift", "bull" if author_delta > 0 else "bear", abs(author_shift_pct), common))
    contrast = abs(top_net - bottom_net)
    if top_net * bottom_net < 0 and contrast > 1.5 and len(top_bull_voices | top_bear_voices) >= 2 and len(bottom_voices) >= 2:
        signals.append(("high_low_divergence", "bull" if top_net > 0 else "bear", contrast, common))
    return signals


def _build_daily_signals(
    con: sqlite3.Connection,
    calls: list[dict[str, Any]],
    windows: tuple[int, ...],
    source_scopes: tuple[str, ...],
    sources: tuple[str, ...],
) -> int:
    calls_by_ticker: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for call in calls:
        calls_by_ticker[str(call["ticker"])].append(call)
    price_days: dict[str, list[str]] = collections.defaultdict(list)
    for row in con.execute("SELECT upper(ticker) AS ticker, day FROM price_daily ORDER BY ticker, day"):
        price_days[str(row["ticker"])].append(str(row["day"]))

    now = _utc_now()
    output: list[tuple[Any, ...]] = []
    for ticker, ticker_calls in calls_by_ticker.items():
        if not price_days.get(ticker):
            continue
        last_call_day = max(str(call["day"]) for call in ticker_calls)
        for scope in source_scopes:
            scope_sources = set(sources if scope == "all" else (scope,))
            scoped = [call for call in ticker_calls if call["source"] in scope_sources]
            if not scoped:
                continue
            scoped.sort(key=lambda call: (call["day"], call["created_at"], call["candidate_id"]))
            call_days = [str(call["day"]) for call in scoped]
            first_day = call_days[0]
            days = [day for day in price_days[ticker] if first_day <= day <= last_call_day]
            for window in windows:
                for day in days:
                    day_value = date.fromisoformat(day)
                    current_start = (day_value - timedelta(days=window - 1)).isoformat()
                    previous_start = (day_value - timedelta(days=window * 2 - 1)).isoformat()
                    previous_end = (day_value - timedelta(days=window)).isoformat()
                    current = scoped[bisect.bisect_left(call_days, current_start):bisect.bisect_right(call_days, day)]
                    previous = scoped[bisect.bisect_left(call_days, previous_start):bisect.bisect_right(call_days, previous_end)]
                    for indicator, direction, value, metrics in _signal_rows(current, previous):
                        output.append(
                            (
                                ticker, day, scope, window, indicator, direction, value,
                                metrics["top_net"], metrics["bottom_net"], metrics["top_author_net"],
                                metrics["previous_top_author_net"], metrics["author_net_delta"],
                                metrics["author_net_shift_pct"], metrics["top_authors"],
                                metrics["previous_top_authors"], metrics["bottom_authors"],
                                metrics["top_calls"], metrics["bottom_calls"], now,
                            )
                        )
    con.executemany(
        """INSERT OR REPLACE INTO sv_indicator_signal_daily
           (ticker,day,source_scope,window_days,indicator,direction,signal_value,top_net,bottom_net,
            top_author_net,previous_top_author_net,author_net_delta,author_net_shift_pct,top_authors,
            previous_top_authors,bottom_authors,top_calls,bottom_calls,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def build_sv_indicator_backtest(
    *,
    db_path: str | Path,
    report_path: str | Path,
    only: list[str] | None = None,
    windows: tuple[int, ...] = DEFAULT_WINDOWS,
    source_scopes: tuple[str, ...] = ("all", "x", "youtube", "reddit", "xueqiu"),
) -> dict[str, int]:
    """Rebuild indicator events and forward results from point-in-time platform ranks."""
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    ensure_ticker_signal_tables(con)
    ensure_indicator_backtest_tables(con)
    tickers = sorted({ticker.upper() for ticker in (only or []) if ticker})
    where, params = _where_tickers(tickers)
    call_days = [
        str(row["day"])
        for row in con.execute(
            f"""SELECT DISTINCT substr(c.created_at,1,10) AS day FROM sv_call c
                 WHERE c.is_actionable_call=1 AND c.created_at IS NOT NULL{where} ORDER BY day""",
            params,
        )
    ]
    score_rows = rebuild_point_in_time_scores(con, call_days)
    for table in ("sv_indicator_outcome", "sv_indicator_event", "sv_indicator_signal_daily", "sv_indicator_stat"):
        con.execute(f"DELETE FROM {table}")
    con.commit()
    calls = _load_ranked_calls(con, tickers, DEFAULT_SOURCES)
    daily_rows = _build_daily_signals(con, calls, windows, source_scopes, DEFAULT_SOURCES)
    events = build_indicator_events(con)
    outcomes = build_indicator_outcomes(con)
    stats = build_indicator_stats(con)
    report_rows = write_indicator_report(con, Path(report_path))
    detail_rows = write_indicator_detail_reports(con, Path(report_path).parent)
    con.close()
    return {
        "asof_scores": score_rows,
        "ranked_calls": len(calls),
        "daily_signals": daily_rows,
        "events": events,
        "outcomes": outcomes,
        "stats": stats,
        "report_rows": report_rows,
        **detail_rows,
    }
