"""Event construction and forward performance for vertical sub-Score signals."""
from __future__ import annotations

import bisect
import collections
import itertools
import math
import sqlite3
import statistics
from datetime import datetime, timezone
from typing import Any

from .v0_impl import HORIZONS


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _price_series(con: sqlite3.Connection, ticker: str) -> list[dict[str, Any]]:
    return [
        dict(row)
        for row in con.execute(
            """SELECT day,
                      CASE WHEN close>0 AND adj_close>0 THEN open*adj_close/close ELSE open END AS open,
                      COALESCE(NULLIF(adj_close,0),close) AS close
                 FROM price_daily WHERE upper(ticker)=? ORDER BY day""",
            (ticker,),
        )
    ]


def build_segment_events(con: sqlite3.Connection) -> int:
    rows = con.execute(
        """SELECT * FROM sv_segment_signal_daily
           ORDER BY ticker,source_scope,segment_type,segment_key,window_days,rank_band,day"""
    ).fetchall()
    day_index: dict[str, dict[str, int]] = collections.defaultdict(dict)
    for row in con.execute("SELECT upper(ticker) AS ticker,day FROM price_daily ORDER BY ticker,day"):
        ticker = str(row["ticker"])
        day_index[ticker][str(row["day"])] = len(day_index[ticker])
    events: list[dict[str, Any]] = []
    key_fn = lambda row: (
        row["ticker"],row["source_scope"],row["segment_type"],row["segment_key"],
        row["window_days"],row["rank_band"],
    )
    for _, group_iter in itertools.groupby(rows, key=key_fn):
        current: dict[str, Any] | None = None
        for row in group_iter:
            ticker = str(row["ticker"])
            index = day_index[ticker].get(str(row["day"]), -99)
            consecutive = (
                current is not None
                and str(row["direction"]) == current["direction"]
                and index == current["last_index"] + 1
            )
            if not consecutive:
                if current:
                    events.append(current)
                current = {
                    "row": row,
                    "direction": str(row["direction"]),
                    "start_day": str(row["day"]),
                    "end_day": str(row["day"]),
                    "last_index": index,
                }
            else:
                current["end_day"] = str(row["day"])
                current["last_index"] = index
        if current:
            events.append(current)
    now = _utc_now()
    output: list[tuple[object, ...]] = []
    for event in events:
        row = event["row"]
        event_id = ":".join(
            (
                str(row["ticker"]),str(row["source_scope"]),str(row["segment_type"]),
                str(row["segment_key"]),str(row["window_days"]),str(row["rank_band"]),
                event["start_day"],event["direction"],
            )
        )
        output.append(
            (
                event_id,row["ticker"],row["source_scope"],row["segment_type"],row["segment_key"],
                row["window_days"],row["rank_band"],event["direction"],event["start_day"],
                event["end_day"],event["start_day"],row["signal_value"],row["weighted_net"],
                row["bull_authors"],row["bear_authors"],row["total_authors"],row["consensus"],
                row["effective_voices"],row["authors_json"],None,None,now,
            )
        )
    con.executemany(
        """INSERT OR REPLACE INTO sv_segment_event
           (event_id,ticker,source_scope,segment_type,segment_key,window_days,rank_band,direction,
            start_day,end_day,signal_day,signal_value,weighted_net,bull_authors,bear_authors,
            total_authors,consensus,effective_voices,authors_json,entry_day,entry_price,created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def build_segment_outcomes(con: sqlite3.Connection) -> int:
    events = con.execute("SELECT * FROM sv_segment_event ORDER BY ticker,signal_day").fetchall()
    spy = _price_series(con, "SPY")
    spy_by_day = {str(row["day"]): row for row in spy}
    by_ticker: dict[str, list[dict[str, Any]]] = {}
    days_by_ticker: dict[str, list[str]] = {}
    output: list[tuple[object, ...]] = []
    for event in events:
        ticker = str(event["ticker"])
        if ticker not in by_ticker:
            by_ticker[ticker] = _price_series(con, ticker)
            days_by_ticker[ticker] = [str(row["day"]) for row in by_ticker[ticker]]
        series = by_ticker[ticker]
        days = days_by_ticker[ticker]
        entry_index = bisect.bisect_right(days, str(event["signal_day"]))
        if entry_index >= len(series):
            for horizon in HORIZONS:
                output.append((event["event_id"],horizon,None,None,None,None,None,None,None,None,"pending"))
            continue
        entry = series[entry_index]
        entry_price = float(entry["open"] or entry["close"] or 0.0)
        con.execute(
            "UPDATE sv_segment_event SET entry_day=?,entry_price=? WHERE event_id=?",
            (entry["day"],entry_price,event["event_id"]),
        )
        for horizon, trading_days in HORIZONS.items():
            exit_index = entry_index + trading_days - 1
            if not entry_price or exit_index >= len(series):
                output.append((event["event_id"],horizon,None,None,None,None,None,None,None,None,"pending"))
                continue
            exit_row = series[exit_index]
            exit_price = float(exit_row["close"] or 0.0)
            raw_return = exit_price / entry_price - 1.0 if exit_price else None
            spy_entry = spy_by_day.get(str(entry["day"]))
            spy_exit = spy_by_day.get(str(exit_row["day"]))
            benchmark_return = None
            if spy_entry and spy_exit:
                benchmark_entry = float(spy_entry["open"] or spy_entry["close"] or 0.0)
                benchmark_exit = float(spy_exit["close"] or 0.0)
                if benchmark_entry and benchmark_exit:
                    benchmark_return = benchmark_exit / benchmark_entry - 1.0
            sign = 1.0 if event["direction"] == "bull" else -1.0
            directional_return = sign * raw_return if raw_return is not None else None
            excess = raw_return - benchmark_return if raw_return is not None and benchmark_return is not None else None
            directional_excess = sign * excess if excess is not None else None
            path: list[float] = []
            for point in series[entry_index:exit_index + 1]:
                close = float(point["close"] or 0.0)
                if not close:
                    continue
                point_return = close / entry_price - 1.0
                spy_point = spy_by_day.get(str(point["day"]))
                point_benchmark = None
                if spy_entry and spy_point:
                    benchmark_open = float(spy_entry["open"] or spy_entry["close"] or 0.0)
                    benchmark_close = float(spy_point["close"] or 0.0)
                    if benchmark_open and benchmark_close:
                        point_benchmark = benchmark_close / benchmark_open - 1.0
                if point_benchmark is not None:
                    path.append(sign * (point_return - point_benchmark))
            output.append(
                (
                    event["event_id"],horizon,exit_row["day"],exit_price,directional_return,
                    directional_excess,int(directional_return > 0) if directional_return is not None else None,
                    int(directional_excess > 0) if directional_excess is not None else None,
                    max(path) if path else directional_excess,min(path) if path else directional_excess,"settled",
                )
            )
    con.executemany(
        """INSERT OR REPLACE INTO sv_segment_outcome
           (event_id,outcome_horizon,exit_day,exit_price,directional_return_pct,directional_excess_pct,
            raw_hit,excess_hit,max_favorable_excess,max_adverse_excess,status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def _mean(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def _ratio(numerator: float | None, denominator: float | None) -> float | None:
    if numerator is None or denominator is None or denominator == 0:
        return None
    return numerator / abs(denominator)


def _wilson(hits: int, total: int, z: float = 1.959963984540054) -> tuple[float | None, float | None]:
    if total <= 0:
        return None, None
    rate = hits / total
    denominator = 1.0 + z * z / total
    center = (rate + z * z / (2.0 * total)) / denominator
    margin = z * math.sqrt(rate * (1.0 - rate) / total + z * z / (4.0 * total * total)) / denominator
    return max(0.0, center - margin), min(1.0, center + margin)


def _trade_stats(values: list[float]) -> tuple[float | None, float | None, float | None, float | None]:
    wins = [value for value in values if value > 0]
    losses = [value for value in values if value < 0]
    avg_win = _mean(wins)
    avg_loss = _mean(losses)
    payoff = _ratio(avg_win, avg_loss)
    profit_factor = _ratio(sum(wins) if wins else None, sum(losses) if losses else None)
    return avg_win, avg_loss, payoff, profit_factor


def build_segment_stats(con: sqlite3.Connection) -> int:
    rows = con.execute(
        """SELECT e.source_scope,e.segment_type,e.segment_key,e.window_days,e.rank_band,e.direction,o.*
             FROM sv_segment_event e JOIN sv_segment_outcome o ON o.event_id=e.event_id
            WHERE o.status='settled'"""
    ).fetchall()
    groups: dict[tuple[str, str, str, int, str, str, str], list[sqlite3.Row]] = collections.defaultdict(list)
    for row in rows:
        base = (
            str(row["source_scope"]),str(row["segment_type"]),str(row["segment_key"]),
            int(row["window_days"]),str(row["rank_band"]),str(row["outcome_horizon"]),
        )
        groups[(*base,str(row["direction"]))].append(row)
        groups[(*base,"all")].append(row)
    now = _utc_now()
    output: list[tuple[object, ...]] = []
    for key, group in groups.items():
        directional = [float(row["directional_return_pct"]) for row in group if row["directional_return_pct"] is not None]
        excess = [float(row["directional_excess_pct"]) for row in group if row["directional_excess_pct"] is not None]
        if not excess:
            continue
        raw_hits = sum(value > 0 for value in directional)
        excess_hits = sum(value > 0 for value in excess)
        ci_low, ci_high = _wilson(excess_hits, len(excess))
        avg_win, avg_loss, payoff, profit_factor = _trade_stats(directional)
        _, _, excess_payoff, excess_profit_factor = _trade_stats(excess)
        favorable = [float(row["max_favorable_excess"]) for row in group if row["max_favorable_excess"] is not None]
        adverse = [float(row["max_adverse_excess"]) for row in group if row["max_adverse_excess"] is not None]
        output.append(
            (
                *key,len(excess),raw_hits / len(directional) if directional else None,
                excess_hits / len(excess) if excess else None,ci_low,ci_high,_mean(directional),
                statistics.median(directional) if directional else None,avg_win,avg_loss,payoff,
                profit_factor,_mean(excess),statistics.median(excess) if excess else None,
                excess_payoff,excess_profit_factor,_mean(favorable),_mean(adverse),now,
            )
        )
    con.executemany(
        """INSERT OR REPLACE INTO sv_segment_stat
           (source_scope,segment_type,segment_key,window_days,rank_band,outcome_horizon,direction,
            n_events,raw_hit_rate,excess_hit_rate,excess_hit_ci_low,excess_hit_ci_high,
            avg_directional_return_pct,median_directional_return_pct,avg_win_pct,avg_loss_pct,
            payoff_ratio,profit_factor,avg_directional_excess_pct,median_directional_excess_pct,
            excess_payoff_ratio,excess_profit_factor,avg_max_favorable_excess,avg_max_adverse_excess,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)
