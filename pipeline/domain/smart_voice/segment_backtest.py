"""Leakage-free vertical backtests using historical sub-Score ranks."""
from __future__ import annotations

import bisect
import collections
import json
import math
import sqlite3
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .indicator_backtest_logic import call_signal_weight
from .segment_backtest_outcomes import build_segment_events, build_segment_outcomes, build_segment_stats
from .segment_backtest_reporting import write_segment_reports
from .segment_backtest_schema import ensure_segment_backtest_tables
from .segment_backtest_scoring import SEGMENT_TYPES, rebuild_segment_scores_asof
from .v0_impl import HORIZONS, TICKER_NARRATIVE, confidence, infer_analysis_type

DEFAULT_WINDOWS = (3, 7, 14, 30)
DEFAULT_RANK_BANDS = ("top10", "top25")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _band_fraction(rank_band: str) -> float:
    return {"top10": 0.10, "top25": 0.25}[rank_band]


def _load_rank_lookup(
    con: sqlite3.Connection,
    *,
    sources: tuple[str, ...],
) -> dict[tuple[str, str, str, str, str], dict[str, Any]]:
    slots = ",".join("?" for _ in sources)
    output: dict[tuple[str, str, str, str, str], dict[str, Any]] = {}
    for row in con.execute(
        f"""SELECT * FROM sv_segment_score_asof
              WHERE source IN ({slots}) AND qualified=1 AND population>=10""",
        sources,
    ):
        output[
            (
                str(row["asof_day"]),
                str(row["segment_type"]),
                str(row["segment_key"]),
                str(row["source"]),
                str(row["investor_id"]),
            )
        ] = dict(row)
    return output


def _call_segments(
    call: sqlite3.Row,
    segment_types: set[str],
) -> list[tuple[str, str]]:
    output: list[tuple[str, str]] = []
    if "horizon" in segment_types:
        output.extend(("horizon", horizon) for horizon in HORIZONS)
    if "narrative" in segment_types:
        narrative = TICKER_NARRATIVE.get(str(call["ticker"] or "").upper())
        if narrative:
            output.append(("narrative", narrative))
    if "investor_type" in segment_types:
        investor_type = infer_analysis_type(
            str(call["text"] or ""),
            str(call["investor_style"] or "unknown"),
        )
        if investor_type != "unknown":
            output.append(("investor_type", investor_type))
    return output


def _load_ranked_segment_calls(
    con: sqlite3.Connection,
    *,
    sources: tuple[str, ...],
    segment_types: tuple[str, ...],
    rank_bands: tuple[str, ...],
    tickers: tuple[str, ...],
) -> list[dict[str, Any]]:
    ranks = _load_rank_lookup(con, sources=sources)
    source_slots = ",".join("?" for _ in sources)
    params: list[str] = list(sources)
    ticker_filter = ""
    if tickers:
        ticker_filter = f" AND upper(c.ticker) IN ({','.join('?' for _ in tickers)})"
        params.extend(tickers)
    rows = con.execute(
        f"""SELECT c.candidate_id,c.tweet_id,upper(c.ticker) AS ticker,c.source,c.investor_id,
                   c.created_at,substr(c.created_at,1,10) AS day,c.direction,c.call_weight,
                   c.investor_style,c.author_handle,cc.text,cc.url
              FROM sv_call c
              JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
             WHERE c.is_actionable_call=1
               AND c.direction IN ('bull','bear')
               AND c.created_at IS NOT NULL
               AND c.source IN ({source_slots}){ticker_filter}
             ORDER BY c.created_at,c.candidate_id""",
        params,
    ).fetchall()
    wanted_segments = set(segment_types) & set(SEGMENT_TYPES)
    output: list[dict[str, Any]] = []
    for row in rows:
        source = str(row["source"])
        investor_id = str(row["investor_id"] or "")
        day = str(row["day"])
        if not investor_id:
            continue
        for segment_type, segment_key in _call_segments(row, wanted_segments):
            rank = ranks.get((day, segment_type, segment_key, source, investor_id))
            if not rank:
                continue
            population = int(rank["population"])
            rank_no = int(rank["rank_no"])
            for rank_band in rank_bands:
                cutoff = max(1, math.ceil(population * _band_fraction(rank_band)))
                if rank_no > cutoff:
                    continue
                level = confidence(float(rank["n_eff"]), int(rank["settled_calls"]))
                weight = call_signal_weight(
                    {
                        "platform_sv": rank["segment_sv"],
                        "call_weight": row["call_weight"],
                        "confidence": level,
                        "n_eff": rank["n_eff"],
                    }
                )
                output.append(
                    {
                        **dict(row),
                        "segment_type": segment_type,
                        "segment_key": segment_key,
                        "rank_band": rank_band,
                        "segment_sv": float(rank["segment_sv"]),
                        "segment_rank_no": rank_no,
                        "segment_population": population,
                        "segment_n_eff": float(rank["n_eff"]),
                        "segment_settled_calls": int(rank["settled_calls"]),
                        "author_key": f"{source}:{investor_id}",
                        "weight": weight,
                    }
                )
    return output


def _latest_by_author(calls: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    states: dict[str, dict[str, Any]] = {}
    for call in calls:
        key = str(call["author_key"])
        marker = (str(call["created_at"]), str(call["candidate_id"]))
        previous = states.get(key)
        if previous is None or marker > (str(previous["created_at"]), str(previous["candidate_id"])):
            states[key] = call
    return states


def _cluster(calls: list[dict[str, Any]], min_authors: int, consensus_threshold: float, effective_threshold: float) -> dict[str, Any] | None:
    states = _latest_by_author(calls)
    if len(states) < min_authors:
        return None
    bull = [call for call in states.values() if call["direction"] == "bull"]
    bear = [call for call in states.values() if call["direction"] == "bear"]
    dominant = bull if len(bull) >= len(bear) else bear
    direction = "bull" if dominant is bull else "bear"
    consensus = len(dominant) / len(states)
    if consensus < consensus_threshold:
        return None
    weights = [max(0.0, float(call["weight"])) for call in dominant]
    weight_sq = sum(weight * weight for weight in weights)
    effective_voices = sum(weights) ** 2 / weight_sq if weight_sq else 0.0
    if effective_voices < effective_threshold:
        return None
    weighted_net = sum(
        (1.0 if call["direction"] == "bull" else -1.0) * float(call["weight"])
        for call in states.values()
    )
    if (direction == "bull" and weighted_net <= 0) or (direction == "bear" and weighted_net >= 0):
        return None
    authors = [
        {
            "authorKey": call["author_key"],
            "investorId": call["investor_id"],
            "handle": call["author_handle"],
            "source": call["source"],
            "candidateId": call["candidate_id"],
            "direction": call["direction"],
            "createdAt": call["created_at"],
            "segmentSv": round(float(call["segment_sv"]), 3),
            "segmentRank": int(call["segment_rank_no"]),
            "segmentPopulation": int(call["segment_population"]),
            "weight": round(float(call["weight"]), 6),
            "url": call["url"],
        }
        for call in sorted(states.values(), key=lambda item: (-float(item["weight"]), str(item["author_key"])))
    ]
    return {
        "direction": direction,
        "signal_value": abs(weighted_net),
        "weighted_net": weighted_net,
        "bull_authors": len(bull),
        "bear_authors": len(bear),
        "total_authors": len(states),
        "consensus": consensus,
        "effective_voices": effective_voices,
        "authors_json": json.dumps(authors, ensure_ascii=False, separators=(",", ":")),
    }


def _build_daily_signals(
    con: sqlite3.Connection,
    *,
    calls: list[dict[str, Any]],
    source_scope: str,
    windows: tuple[int, ...],
    min_authors: int,
    consensus_threshold: float,
    effective_voice_threshold: float,
) -> int:
    groups: dict[tuple[str, str, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for call in calls:
        groups[(str(call["ticker"]), str(call["segment_type"]), str(call["segment_key"]), str(call["rank_band"]))].append(call)
    price_days: dict[str, list[str]] = collections.defaultdict(list)
    for row in con.execute("SELECT upper(ticker) AS ticker,day FROM price_daily ORDER BY ticker,day"):
        price_days[str(row["ticker"])].append(str(row["day"]))
    con.execute("DELETE FROM sv_segment_signal_daily")
    now = _utc_now()
    output: list[tuple[object, ...]] = []
    for (ticker, segment_type, segment_key, rank_band), group in groups.items():
        if not price_days.get(ticker):
            continue
        group.sort(key=lambda item: (str(item["day"]), str(item["created_at"]), str(item["candidate_id"])))
        call_days = [str(item["day"]) for item in group]
        days = [day for day in price_days[ticker] if call_days[0] <= day <= call_days[-1]]
        for window in windows:
            for day in days:
                start = (date.fromisoformat(day) - timedelta(days=window - 1)).isoformat()
                current = group[bisect.bisect_left(call_days, start):bisect.bisect_right(call_days, day)]
                signal = _cluster(current, min_authors, consensus_threshold, effective_voice_threshold)
                if not signal:
                    continue
                output.append(
                    (
                        ticker,day,source_scope,segment_type,segment_key,window,rank_band,
                        signal["direction"],signal["signal_value"],signal["weighted_net"],
                        signal["bull_authors"],signal["bear_authors"],signal["total_authors"],
                        signal["consensus"],signal["effective_voices"],signal["authors_json"],now,
                    )
                )
    con.executemany(
        """INSERT OR REPLACE INTO sv_segment_signal_daily
           (ticker,day,source_scope,segment_type,segment_key,window_days,rank_band,direction,
            signal_value,weighted_net,bull_authors,bear_authors,total_authors,consensus,
            effective_voices,authors_json,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        output,
    )
    con.commit()
    return len(output)


def build_sv_segment_backtest(
    *,
    db_path: str | Path,
    report_path: str | Path,
    only: list[str] | None = None,
    windows: tuple[int, ...] = DEFAULT_WINDOWS,
    sources: tuple[str, ...] = ("x",),
    segment_types: tuple[str, ...] = SEGMENT_TYPES,
    rank_bands: tuple[str, ...] = DEFAULT_RANK_BANDS,
    min_authors: int = 3,
    consensus_threshold: float = 0.65,
    effective_voice_threshold: float = 2.5,
    segment_min_n_eff: float = 4.0,
    segment_min_settled_calls: int = 5,
) -> dict[str, int]:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    ensure_segment_backtest_tables(con)
    tickers = tuple(sorted({ticker.upper() for ticker in (only or []) if ticker}))
    source_slots = ",".join("?" for _ in sources)
    ticker_filter = ""
    params: list[str] = list(sources)
    if tickers:
        ticker_filter = f" AND upper(ticker) IN ({','.join('?' for _ in tickers)})"
        params.extend(tickers)
    asof_days = [
        str(row["day"])
        for row in con.execute(
            f"""SELECT DISTINCT substr(created_at,1,10) AS day FROM sv_call
                 WHERE is_actionable_call=1 AND direction IN ('bull','bear')
                   AND source IN ({source_slots}) AND created_at IS NOT NULL{ticker_filter}
                 ORDER BY day""",
            params,
        )
    ]
    score_rows = rebuild_segment_scores_asof(
        con,
        asof_days=asof_days,
        sources=sources,
        segment_types=segment_types,
        min_n_eff=segment_min_n_eff,
        min_settled_calls=segment_min_settled_calls,
    )
    for table in ("sv_segment_outcome", "sv_segment_event", "sv_segment_signal_daily", "sv_segment_stat"):
        con.execute(f"DELETE FROM {table}")
    con.commit()
    ranked_calls = _load_ranked_segment_calls(
        con,
        sources=sources,
        segment_types=segment_types,
        rank_bands=rank_bands,
        tickers=tickers,
    )
    source_scope = "+".join(sorted(sources))
    daily_rows = _build_daily_signals(
        con,
        calls=ranked_calls,
        source_scope=source_scope,
        windows=windows,
        min_authors=min_authors,
        consensus_threshold=consensus_threshold,
        effective_voice_threshold=effective_voice_threshold,
    )
    events = build_segment_events(con)
    outcomes = build_segment_outcomes(con)
    stats = build_segment_stats(con)
    report_rows = write_segment_reports(con, Path(report_path))
    con.close()
    return {
        "asof_scores": score_rows,
        "ranked_calls": len(ranked_calls),
        "daily_signals": daily_rows,
        "events": events,
        "outcomes": outcomes,
        "stats": stats,
        **report_rows,
    }

