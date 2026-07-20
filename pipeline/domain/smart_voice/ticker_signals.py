"""Build ticker-level Smart Voice cohorts, clustering events, and backtests."""
from __future__ import annotations

import bisect
import collections
import itertools
import json
import math
import sqlite3
import statistics
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .ticker_signal_schema import ensure_ticker_signal_tables
from .ticker_signal_scoring import rebuild_point_in_time_scores
from .v0_impl import confidence_factor

HORIZON_DAYS = {"1D": 1, "5D": 5, "20D": 20, "60D": 60, "90D": 90, "180D": 180}
COHORTS = ("top10", "top25", "bottom25", "bottom10")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _cohort_matches(percentile: float) -> tuple[str, ...]:
    matches: list[str] = []
    if percentile <= 10:
        matches.append("top10")
    if percentile <= 25:
        matches.append("top25")
    if percentile >= 75:
        matches.append("bottom25")
    if percentile >= 90:
        matches.append("bottom10")
    return tuple(matches)


def _where_tickers(tickers: list[str]) -> tuple[str, list[str]]:
    if not tickers:
        return "", []
    return f" AND upper(c.ticker) IN ({','.join('?' for _ in tickers)})", tickers


def _load_calls(con: sqlite3.Connection, tickers: list[str]) -> list[dict[str, Any]]:
    where, params = _where_tickers(tickers)
    rows = con.execute(
        f"""SELECT c.candidate_id, upper(c.ticker) AS ticker, c.source, c.investor_id,
                   c.created_at, substr(c.created_at,1,10) AS day, c.direction,
                   upper(c.horizon_bucket) AS horizon, c.horizon_explicit,
                   c.target_price, c.call_weight, c.call_type,
                   a.sv, a.percentile, a.confidence
              FROM sv_call c
              JOIN sv_investor_score_asof a
                ON a.asof_day = substr(c.created_at,1,10)
               AND a.investor_id = c.investor_id
             WHERE c.is_actionable_call = 1
               AND c.direction IN ('bull','bear')
               AND upper(c.horizon_bucket) IN ('1D','5D','20D','60D','90D','180D')
               AND c.investor_id IS NOT NULL{where}
             ORDER BY c.created_at, c.candidate_id""",
        params,
    ).fetchall()

    latest: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for raw in rows:
        item = dict(raw)
        key = (item["ticker"], item["day"], item["horizon"], item["investor_id"])
        previous = latest.get(key)
        if previous is None or (item["created_at"], float(item["call_weight"] or 0)) > (
            previous["created_at"],
            float(previous["call_weight"] or 0),
        ):
            item["cohorts"] = _cohort_matches(float(item["percentile"]))
            latest[key] = item
    return sorted(latest.values(), key=lambda row: (row["ticker"], row["horizon"], row["day"], row["investor_id"]))


def _aggregate_daily(
    calls: list[dict[str, Any]],
    cohort: str,
    min_authors: int,
    consensus_threshold: float,
    effective_voice_threshold: float,
) -> dict[str, Any] | None:
    selected = [call for call in calls if cohort in call["cohorts"]]
    if not selected:
        return None
    n_bull = sum(call["direction"] == "bull" for call in selected)
    n_bear = len(selected) - n_bull
    bull_share = n_bull / len(selected)
    bear_share = n_bear / len(selected)
    weights = [
        max(0.1, float(call["call_weight"] or 0.1)) * confidence_factor(str(call["confidence"]))
        for call in selected
    ]
    weight_sum = sum(weights)
    weighted_net = (
        sum((1 if call["direction"] == "bull" else -1) * weight for call, weight in zip(selected, weights)) / weight_sum
        if weight_sum
        else 0.0
    )
    effective_voices = weight_sum * weight_sum / sum(weight * weight for weight in weights) if weights else 0.0
    consensus = max(bull_share, bear_share)
    direction = "bull" if bull_share >= bear_share else "bear"
    targets = sorted(float(call["target_price"]) for call in selected if call["target_price"] is not None)
    sources = collections.Counter(str(call["source"]) for call in selected)
    call_types = collections.Counter(str(call["call_type"] or "unknown") for call in selected)
    return {
        "n_authors": len(selected),
        "n_bull": n_bull,
        "n_bear": n_bear,
        "bull_share": bull_share,
        "bear_share": bear_share,
        "weighted_net": weighted_net,
        "consensus_strength": consensus,
        "effective_voices": effective_voices,
        "dominant_direction": direction,
        "cluster_flag": int(
            len(selected) >= min_authors
            and consensus >= consensus_threshold
            and effective_voices >= effective_voice_threshold
        ),
        "avg_sv": statistics.fmean(float(call["sv"]) for call in selected),
        "target_count": len(targets),
        "target_median": statistics.median(targets) if targets else None,
        "explicit_horizon_count": sum(bool(call["horizon_explicit"]) for call in selected),
        "source_count": len(sources),
        "call_types_json": _json(dict(call_types.most_common())),
        "sources_json": _json(dict(sources.most_common())),
        "candidate_ids_json": _json([call["candidate_id"] for call in selected]),
        "investor_ids_json": _json([call["investor_id"] for call in selected]),
    }


def _build_daily_rows(
    con: sqlite3.Connection,
    calls: list[dict[str, Any]],
    tickers: list[str],
    window_days: int,
    min_authors: int,
    consensus_threshold: float,
    effective_voice_threshold: float,
) -> int:
    by_key: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for call in calls:
        by_key[(call["ticker"], call["horizon"])].append(call)
    where = "" if not tickers else f" WHERE upper(ticker) IN ({','.join('?' for _ in tickers)})"
    price_rows = con.execute(
        f"SELECT upper(ticker) AS ticker, day FROM price_daily{where} ORDER BY ticker, day",
        tickers,
    ).fetchall()
    price_days: dict[str, list[str]] = collections.defaultdict(list)
    for row in price_rows:
        price_days[str(row["ticker"])].append(str(row["day"]))

    now = _utc_now()
    output: list[tuple[Any, ...]] = []
    for (ticker, horizon), group in by_key.items():
        if not group or not price_days.get(ticker):
            continue
        first_day = group[0]["day"]
        for day in price_days[ticker]:
            if day < first_day:
                continue
            start = (date.fromisoformat(day) - timedelta(days=max(0, window_days - 1))).isoformat()
            latest_by_investor: dict[str, dict[str, Any]] = {}
            for call in group:
                if call["day"] < start or call["day"] > day:
                    continue
                previous = latest_by_investor.get(call["investor_id"])
                if previous is None or call["created_at"] > previous["created_at"]:
                    latest_by_investor[call["investor_id"]] = call
            window_calls = list(latest_by_investor.values())
            for cohort in COHORTS:
                aggregate = _aggregate_daily(
                    window_calls,
                    cohort,
                    min_authors,
                    consensus_threshold,
                    effective_voice_threshold,
                )
                if aggregate is None:
                    continue
                output.append(
                    (
                        ticker, day, horizon, cohort, int(cohort[-2:]),
                        aggregate["n_authors"], aggregate["n_bull"], aggregate["n_bear"],
                        aggregate["bull_share"], aggregate["bear_share"], aggregate["weighted_net"],
                        aggregate["consensus_strength"], aggregate["effective_voices"],
                        aggregate["dominant_direction"], aggregate["cluster_flag"], aggregate["avg_sv"],
                        aggregate["target_count"], aggregate["target_median"],
                        aggregate["explicit_horizon_count"], aggregate["source_count"],
                        aggregate["call_types_json"], aggregate["sources_json"],
                        aggregate["candidate_ids_json"], aggregate["investor_ids_json"], now,
                    )
                )
    con.executemany(
        """INSERT OR REPLACE INTO sv_ticker_signal_daily
           (ticker,day,horizon,cohort,percentile_cut,n_authors,n_bull,n_bear,bull_share,bear_share,
            weighted_net,consensus_strength,effective_voices,dominant_direction,cluster_flag,avg_sv,
            target_count,target_median,explicit_horizon_count,source_count,call_types_json,sources_json,
            candidate_ids_json,investor_ids_json,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def _build_events(con: sqlite3.Connection, tickers: list[str]) -> int:
    where = "" if not tickers else f" AND ticker IN ({','.join('?' for _ in tickers)})"
    rows = con.execute(
        f"""SELECT * FROM sv_ticker_signal_daily
             WHERE cluster_flag = 1{where}
             ORDER BY ticker, cohort, horizon, day""",
        tickers,
    ).fetchall()
    day_index: dict[str, dict[str, int]] = collections.defaultdict(dict)
    price_where = "" if not tickers else f" WHERE upper(ticker) IN ({','.join('?' for _ in tickers)})"
    for row in con.execute(f"SELECT upper(ticker) ticker, day FROM price_daily{price_where} ORDER BY ticker, day", tickers):
        ticker = str(row["ticker"])
        day_index[ticker][str(row["day"])] = len(day_index[ticker])

    events: list[dict[str, Any]] = []
    for _, group_iter in itertools.groupby(rows, key=lambda row: (row["ticker"], row["cohort"], row["horizon"])):
        group = list(group_iter)
        current: dict[str, Any] | None = None
        for row in group:
            ticker = str(row["ticker"])
            consecutive = current is not None and (
                row["dominant_direction"] == current["direction"]
                and day_index[ticker].get(str(row["day"]), -99) == current["last_index"] + 1
            )
            if not consecutive:
                if current:
                    events.append(current)
                current = {
                    "row": row,
                    "direction": str(row["dominant_direction"]),
                    "start_day": str(row["day"]),
                    "end_day": str(row["day"]),
                    "last_index": day_index[ticker].get(str(row["day"]), -99),
                }
            else:
                current["end_day"] = str(row["day"])
                current["last_index"] = day_index[ticker].get(str(row["day"]), -99)
        if current:
            events.append(current)

    now = _utc_now()
    output = []
    for event in events:
        row = event["row"]
        event_id = f"{row['ticker']}:{row['cohort']}:{row['horizon']}:{event['start_day']}:{event['direction']}"
        output.append(
            (
                event_id, row["ticker"], row["cohort"], row["percentile_cut"], row["horizon"],
                event["direction"], event["start_day"], event["end_day"], event["start_day"],
                row["n_authors"], row["n_bull"], row["n_bear"], row["consensus_strength"],
                row["effective_voices"], row["weighted_net"], row["avg_sv"], row["source_count"],
                row["target_median"], row["candidate_ids_json"], row["investor_ids_json"], None, None, now,
            )
        )
    con.executemany(
        """INSERT OR REPLACE INTO sv_ticker_signal_event
           (event_id,ticker,cohort,percentile_cut,horizon,direction,start_day,end_day,signal_day,
            n_authors,n_bull,n_bear,consensus_strength,effective_voices,weighted_net,avg_sv,source_count,
            target_median,candidate_ids_json,investor_ids_json,entry_day,entry_price,created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def _price_series(con: sqlite3.Connection, ticker: str) -> list[dict[str, Any]]:
    return [dict(row) for row in con.execute(
        "SELECT day, open, close FROM price_daily WHERE upper(ticker)=? ORDER BY day",
        (ticker,),
    ).fetchall()]


def _build_outcomes(con: sqlite3.Connection, tickers: list[str]) -> int:
    where = "" if not tickers else f" WHERE ticker IN ({','.join('?' for _ in tickers)})"
    events = con.execute(f"SELECT * FROM sv_ticker_signal_event{where} ORDER BY ticker, signal_day", tickers).fetchall()
    spy = _price_series(con, "SPY")
    spy_by_day = {row["day"]: row for row in spy}
    by_ticker: dict[str, list[dict[str, Any]]] = {}
    output: list[tuple[Any, ...]] = []
    for event in events:
        ticker = str(event["ticker"])
        series = by_ticker.setdefault(ticker, _price_series(con, ticker))
        days = [row["day"] for row in series]
        entry_index = bisect.bisect_right(days, str(event["signal_day"]))
        if entry_index >= len(series):
            for horizon in HORIZON_DAYS:
                output.append((event["event_id"], horizon, None, None, None, None, None, None, None, None, None, None, None, "pending"))
            continue
        entry_row = series[entry_index]
        entry_price = float(entry_row["open"] or entry_row["close"] or 0)
        con.execute(
            "UPDATE sv_ticker_signal_event SET entry_day=?, entry_price=? WHERE event_id=?",
            (entry_row["day"], entry_price, event["event_id"]),
        )
        for horizon, trading_days in HORIZON_DAYS.items():
            exit_index = entry_index + trading_days - 1
            if not entry_price or exit_index >= len(series):
                output.append((event["event_id"], horizon, None, None, None, None, None, None, None, None, None, None, None, "pending"))
                continue
            exit_row = series[exit_index]
            exit_price = float(exit_row["close"] or 0)
            raw_return = exit_price / entry_price - 1 if exit_price else None
            spy_entry = spy_by_day.get(entry_row["day"])
            spy_exit = spy_by_day.get(exit_row["day"])
            benchmark_return = None
            if spy_entry and spy_exit:
                benchmark_entry = float(spy_entry["open"] or spy_entry["close"] or 0)
                benchmark_exit = float(spy_exit["close"] or 0)
                if benchmark_entry and benchmark_exit:
                    benchmark_return = benchmark_exit / benchmark_entry - 1
            excess = raw_return - benchmark_return if raw_return is not None and benchmark_return is not None else None
            sign = 1 if event["direction"] == "bull" else -1
            directional_return = sign * raw_return if raw_return is not None else None
            directional_excess = sign * excess if excess is not None else None
            path: list[float] = []
            for point in series[entry_index:exit_index + 1]:
                close = float(point["close"] or 0)
                if not close:
                    continue
                point_return = close / entry_price - 1
                spy_point = spy_by_day.get(point["day"])
                point_benchmark = None
                if spy_entry and spy_point:
                    spy_open = float(spy_entry["open"] or spy_entry["close"] or 0)
                    spy_close = float(spy_point["close"] or 0)
                    if spy_open and spy_close:
                        point_benchmark = spy_close / spy_open - 1
                point_excess = point_return - point_benchmark if point_benchmark is not None else point_return
                path.append(sign * point_excess)
            max_favorable = max(path) if path else directional_excess
            max_adverse = min(path) if path else directional_excess
            time_to_peak = path.index(max_favorable) + 1 if path and max_favorable is not None else None
            hit = int(directional_excess > 0) if directional_excess is not None else None
            output.append(
                (
                    event["event_id"], horizon, exit_row["day"], exit_price, raw_return, benchmark_return,
                    excess, directional_return, directional_excess, hit, max_favorable, max_adverse,
                    time_to_peak, "settled",
                )
            )
    con.executemany(
        """INSERT OR REPLACE INTO sv_ticker_signal_outcome
           (event_id,outcome_horizon,exit_day,exit_price,return_pct,benchmark_return_pct,excess_return_pct,
            directional_return_pct,directional_excess_pct,actual_hit,max_favorable_excess,max_adverse_excess,
            time_to_peak_days,status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def _mean(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def _build_stats(con: sqlite3.Connection, tickers: list[str]) -> int:
    where = "" if not tickers else f" AND e.ticker IN ({','.join('?' for _ in tickers)})"
    rows = con.execute(
        f"""SELECT e.ticker,e.cohort,e.horizon AS signal_horizon,e.direction,o.*
              FROM sv_ticker_signal_event e
              JOIN sv_ticker_signal_outcome o ON o.event_id=e.event_id
             WHERE o.status='settled'{where}""",
        tickers,
    ).fetchall()
    groups: dict[tuple[str, str, str, str, str], list[sqlite3.Row]] = collections.defaultdict(list)
    for row in rows:
        base = (row["ticker"], row["cohort"], row["signal_horizon"], row["outcome_horizon"])
        groups[(*base, row["direction"])].append(row)
        groups[(*base, "all")].append(row)
    now = _utc_now()
    output = []
    for key, values in groups.items():
        hits = [float(row["actual_hit"]) for row in values if row["actual_hit"] is not None]
        directional_returns = [float(row["directional_return_pct"]) for row in values if row["directional_return_pct"] is not None]
        directional_excess = [float(row["directional_excess_pct"]) for row in values if row["directional_excess_pct"] is not None]
        favorable = [float(row["max_favorable_excess"]) for row in values if row["max_favorable_excess"] is not None]
        adverse = [float(row["max_adverse_excess"]) for row in values if row["max_adverse_excess"] is not None]
        peaks = [float(row["time_to_peak_days"]) for row in values if row["time_to_peak_days"] is not None]
        output.append(
            (
                *key, len(values), _mean(hits), _mean(directional_returns),
                statistics.median(directional_returns) if directional_returns else None,
                _mean(directional_excess), statistics.median(directional_excess) if directional_excess else None,
                _mean(favorable), _mean(adverse), _mean(peaks), now,
            )
        )
    con.executemany(
        """INSERT OR REPLACE INTO sv_ticker_signal_stat
           (ticker,cohort,signal_horizon,outcome_horizon,direction,n_events,hit_rate,
            avg_directional_return_pct,median_directional_return_pct,avg_directional_excess_pct,
            median_directional_excess_pct,avg_max_favorable_excess,avg_max_adverse_excess,
            avg_time_to_peak_days,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def build_ticker_sv_signals(
    *,
    db_path: str | Path,
    only: list[str] | None = None,
    window_days: int = 7,
    min_authors: int = 3,
    consensus_threshold: float = 0.65,
    effective_voice_threshold: float = 2.5,
) -> dict[str, int]:
    """Build point-in-time cohorts and ticker event backtests from local SV evidence."""
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    ensure_ticker_signal_tables(con)
    tickers = sorted({ticker.upper() for ticker in (only or []) if ticker})
    where, params = _where_tickers(tickers)
    call_days = [
        str(row["day"])
        for row in con.execute(
            f"""SELECT DISTINCT substr(c.created_at,1,10) AS day
                  FROM sv_call c
                 WHERE c.is_actionable_call=1{where}
                 ORDER BY day""",
            params,
        ).fetchall()
    ]
    score_rows = rebuild_point_in_time_scores(con, call_days)

    if tickers:
        placeholders = ",".join("?" for _ in tickers)
        event_ids = [
            row[0]
            for row in con.execute(
                f"SELECT event_id FROM sv_ticker_signal_event WHERE ticker IN ({placeholders})",
                tickers,
            ).fetchall()
        ]
        if event_ids:
            con.executemany("DELETE FROM sv_ticker_signal_outcome WHERE event_id=?", [(event_id,) for event_id in event_ids])
        for table in ("sv_ticker_signal_daily", "sv_ticker_signal_event", "sv_ticker_signal_stat"):
            con.execute(f"DELETE FROM {table} WHERE ticker IN ({placeholders})", tickers)
    else:
        con.execute("DELETE FROM sv_ticker_signal_outcome")
        con.execute("DELETE FROM sv_ticker_signal_event")
        con.execute("DELETE FROM sv_ticker_signal_daily")
        con.execute("DELETE FROM sv_ticker_signal_stat")
    con.commit()

    calls = _load_calls(con, tickers)
    daily_rows = _build_daily_rows(
        con, calls, tickers, window_days, min_authors, consensus_threshold, effective_voice_threshold,
    )
    event_rows = _build_events(con, tickers)
    outcome_rows = _build_outcomes(con, tickers)
    stat_rows = _build_stats(con, tickers)
    con.close()
    return {
        "asof_scores": score_rows,
        "calls": len(calls),
        "daily_rows": daily_rows,
        "events": event_rows,
        "outcomes": outcome_rows,
        "stats": stat_rows,
    }
