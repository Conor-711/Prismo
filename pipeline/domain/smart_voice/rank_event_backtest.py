"""Point-in-time Top/Bottom X Score event construction."""
from __future__ import annotations

import bisect
import collections
import math
import sqlite3
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

from .indicator_backtest_logic import call_signal_weight
from .portfolio_backtest_engine import PriceSeries


@dataclass(frozen=True)
class RankSignalEvent:
    event_id: str
    ticker: str
    strategy: str
    rank_band_pct: int
    window_days: int
    direction: str
    signal_day: str
    end_day: str
    signal_value: float
    top_authors: int
    bottom_authors: int
    top_consensus: float
    bottom_consensus: float


def _load_point_in_time_calls(con: sqlite3.Connection) -> list[dict[str, Any]]:
    rows = con.execute(
        """SELECT c.candidate_id,upper(c.ticker) AS ticker,c.investor_id,c.created_at,
                  substr(c.created_at,1,10) AS day,c.direction,c.call_weight,
                  a.platform_sv,a.platform_rank_no,a.platform_population,
                  a.confidence,a.n_eff
             FROM sv_call c
             JOIN sv_investor_score_asof a
               ON a.asof_day=substr(c.created_at,1,10)
              AND a.investor_id=c.investor_id
              AND a.source='x'
            WHERE c.source='x'
              AND c.is_actionable_call=1
              AND c.direction IN ('bull','bear')
              AND c.created_at IS NOT NULL
              AND a.platform_qualified=1
              AND a.platform_rank_no IS NOT NULL
              AND a.platform_population>=10
            ORDER BY ticker,c.created_at,c.candidate_id"""
    ).fetchall()
    output: list[dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        item["weight"] = call_signal_weight(item)
        output.append(item)
    return output


def _latest_author_states(calls: list[dict[str, Any]]) -> list[dict[str, Any]]:
    states: dict[str, dict[str, Any]] = {}
    for call in calls:
        author = str(call["investor_id"])
        previous = states.get(author)
        marker = (str(call["created_at"]), str(call["candidate_id"]))
        if previous is None or marker > (
            str(previous["created_at"]),
            str(previous["candidate_id"]),
        ):
            states[author] = call
    return list(states.values())


def _band_states(
    states: list[dict[str, Any]],
    rank_band_pct: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    top: list[dict[str, Any]] = []
    bottom: list[dict[str, Any]] = []
    share = rank_band_pct / 100.0
    for state in states:
        population = int(state["platform_population"])
        rank = int(state["platform_rank_no"])
        cutoff = max(1, math.ceil(population * share))
        if rank <= cutoff:
            top.append(state)
        elif rank > population - cutoff:
            bottom.append(state)
    return top, bottom


def _group_signal(
    states: list[dict[str, Any]],
    min_authors: int,
    consensus_threshold: float,
) -> dict[str, Any] | None:
    if not states:
        return None
    bull = [state for state in states if state["direction"] == "bull"]
    bear = [state for state in states if state["direction"] == "bear"]
    direction = "bull" if len(bull) > len(bear) else "bear"
    dominant = bull if direction == "bull" else bear
    consensus = len(dominant) / len(states)
    if len(dominant) < min_authors or consensus < consensus_threshold:
        return None
    weighted_net = sum(
        (1.0 if state["direction"] == "bull" else -1.0) * float(state["weight"])
        for state in states
    )
    if (direction == "bull" and weighted_net <= 0) or (
        direction == "bear" and weighted_net >= 0
    ):
        return None
    return {
        "direction": direction,
        "consensus": consensus,
        "authors": len(states),
        "dominant_authors": len(dominant),
        "net": weighted_net,
    }


def _daily_rank_signals(
    calls: list[dict[str, Any]],
    price_book: dict[str, PriceSeries],
    windows: tuple[int, ...],
    rank_bands: tuple[int, ...],
    min_authors: int,
    consensus_threshold: float,
) -> list[dict[str, Any]]:
    calls_by_ticker: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for call in calls:
        calls_by_ticker[str(call["ticker"])].append(call)

    output: list[dict[str, Any]] = []
    for ticker, ticker_calls in calls_by_ticker.items():
        series = price_book.get(ticker)
        if not series:
            continue
        ticker_calls.sort(
            key=lambda call: (
                str(call["day"]),
                str(call["created_at"]),
                str(call["candidate_id"]),
            )
        )
        call_days = [str(call["day"]) for call in ticker_calls]
        first_day = call_days[0]
        last_day = call_days[-1]
        days = [bar.day for bar in series.bars if first_day <= bar.day <= last_day]
        for window in windows:
            for day in days:
                start = (date.fromisoformat(day) - timedelta(days=window - 1)).isoformat()
                current = ticker_calls[
                    bisect.bisect_left(call_days, start) : bisect.bisect_right(call_days, day)
                ]
                states = _latest_author_states(current)
                for rank_band in rank_bands:
                    top_states, bottom_states = _band_states(states, rank_band)
                    top = _group_signal(
                        top_states,
                        min_authors,
                        consensus_threshold,
                    )
                    bottom = _group_signal(
                        bottom_states,
                        min_authors,
                        consensus_threshold,
                    )
                    if top:
                        output.append(
                            {
                                "ticker": ticker,
                                "day": day,
                                "strategy": "top_follow",
                                "rank_band_pct": rank_band,
                                "window_days": window,
                                "direction": top["direction"],
                                "signal_value": abs(float(top["net"])),
                                "top_authors": int(top["authors"]),
                                "bottom_authors": int(bottom["authors"]) if bottom else 0,
                                "top_consensus": float(top["consensus"]),
                                "bottom_consensus": float(bottom["consensus"]) if bottom else 0.0,
                            }
                        )
                    if bottom:
                        inverse_direction = "bear" if bottom["direction"] == "bull" else "bull"
                        output.append(
                            {
                                "ticker": ticker,
                                "day": day,
                                "strategy": "bottom_contrarian",
                                "rank_band_pct": rank_band,
                                "window_days": window,
                                "direction": inverse_direction,
                                "signal_value": abs(float(bottom["net"])),
                                "top_authors": int(top["authors"]) if top else 0,
                                "bottom_authors": int(bottom["authors"]),
                                "top_consensus": float(top["consensus"]) if top else 0.0,
                                "bottom_consensus": float(bottom["consensus"]),
                            }
                        )
                    if top and bottom and top["direction"] != bottom["direction"]:
                        output.append(
                            {
                                "ticker": ticker,
                                "day": day,
                                "strategy": "top_bottom_divergence",
                                "rank_band_pct": rank_band,
                                "window_days": window,
                                "direction": top["direction"],
                                "signal_value": abs(float(top["net"]))
                                + abs(float(bottom["net"])),
                                "top_authors": int(top["authors"]),
                                "bottom_authors": int(bottom["authors"]),
                                "top_consensus": float(top["consensus"]),
                                "bottom_consensus": float(bottom["consensus"]),
                            }
                        )
    return output


def _eventize(
    signals: list[dict[str, Any]],
    price_book: dict[str, PriceSeries],
) -> list[RankSignalEvent]:
    grouped: dict[tuple[str, str, int, int], list[dict[str, Any]]] = (
        collections.defaultdict(list)
    )
    for signal in signals:
        grouped[
            (
                str(signal["ticker"]),
                str(signal["strategy"]),
                int(signal["rank_band_pct"]),
                int(signal["window_days"]),
            )
        ].append(signal)

    events: list[RankSignalEvent] = []
    for (ticker, strategy, rank_band, window), rows in sorted(grouped.items()):
        series = price_book[ticker]
        rows.sort(key=lambda row: str(row["day"]))
        current: dict[str, Any] | None = None
        last_index = -99
        for row in rows:
            day = str(row["day"])
            day_index = series.index_by_day.get(day, -99)
            consecutive = (
                current is not None
                and row["direction"] == current["direction"]
                and day_index == last_index + 1
            )
            if not consecutive:
                if current:
                    events.append(
                        _make_event(current, str(current["end_day"]))
                    )
                current = {**row, "start_day": day, "end_day": day}
            else:
                current["end_day"] = day
            last_index = day_index
        if current:
            events.append(_make_event(current, str(current["end_day"])))
    return events


def _make_event(row: dict[str, Any], end_day: str) -> RankSignalEvent:
    event_id = ":".join(
        (
            str(row["strategy"]),
            str(row["rank_band_pct"]),
            str(row["window_days"]),
            str(row["ticker"]),
            str(row["start_day"]),
            str(row["direction"]),
        )
    )
    return RankSignalEvent(
        event_id=event_id,
        ticker=str(row["ticker"]),
        strategy=str(row["strategy"]),
        rank_band_pct=int(row["rank_band_pct"]),
        window_days=int(row["window_days"]),
        direction=str(row["direction"]),
        signal_day=str(row["start_day"]),
        end_day=end_day,
        signal_value=float(row["signal_value"]),
        top_authors=int(row["top_authors"]),
        bottom_authors=int(row["bottom_authors"]),
        top_consensus=float(row["top_consensus"]),
        bottom_consensus=float(row["bottom_consensus"]),
    )


def build_rank_signal_events(
    con: sqlite3.Connection,
    price_book: dict[str, PriceSeries],
    *,
    windows: tuple[int, ...],
    rank_bands: tuple[int, ...] = (10, 25),
    min_authors: int = 2,
    consensus_threshold: float = 0.65,
) -> tuple[list[RankSignalEvent], dict[str, int]]:
    """Build leakage-free rank-band events without writing derived DB rows."""
    calls = _load_point_in_time_calls(con)
    daily = _daily_rank_signals(
        calls,
        price_book,
        windows,
        rank_bands,
        min_authors,
        consensus_threshold,
    )
    events = _eventize(daily, price_book)
    return events, {
        "ranked_calls": len(calls),
        "rank_daily_signals": len(daily),
        "rank_events": len(events),
    }
