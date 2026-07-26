"""Point-in-time Smart Voice scores used by ticker signal backtests."""
from __future__ import annotations

import collections
import sqlite3
from typing import Any, Iterable

from .ticker_signal_schema import ensure_ticker_signal_tables
from .v0_impl import (
    aggregate_stats,
    concentration_cap,
    confidence,
    global_sv_from_platform,
    primary_source_for_rows,
    qualifies_for_platform,
    reliability_cap,
    robust_scores,
)


def _score_pool(
    rows_by_investor: dict[str, list[sqlite3.Row]],
    as_of_day: str,
) -> list[dict[str, Any]]:
    stats = {
        investor: aggregate_stats(rows, 30.0, as_of_day=as_of_day)
        for investor, rows in rows_by_investor.items()
    }
    stats = {investor: value for investor, value in stats.items() if value}
    sources = {
        investor: primary_source_for_rows(rows_by_investor[investor])
        for investor in stats
    }
    raw_by_platform: dict[str, dict[str, float]] = collections.defaultdict(dict)
    for investor, value in stats.items():
        raw_by_platform[sources[investor]][investor] = float(value["raw_z"])

    platform_scores: dict[str, dict[str, int]] = {}
    fallback_scores: dict[str, dict[str, int]] = {}
    for source, raw_map in raw_by_platform.items():
        qualified = {
            investor: raw
            for investor, raw in raw_map.items()
            if qualifies_for_platform(source, stats[investor])
        }
        if len(qualified) < 8:
            qualified = raw_map
        platform_scores[source] = robust_scores(qualified)
        fallback_scores[source] = robust_scores(raw_map)

    scored: list[dict[str, Any]] = []
    for investor, value in stats.items():
        source = sources[investor]
        level = confidence(float(value["n_eff"]), int(value["settled_calls"]))
        raw_platform_sv = platform_scores.get(source, {}).get(
            investor,
            fallback_scores.get(source, {}).get(investor, 100),
        )
        platform_sv = min(
            raw_platform_sv,
            reliability_cap(level),
            concentration_cap(value),
        )
        global_sv, _ = global_sv_from_platform(platform_sv, level)
        scored.append(
            {
                "investor_id": investor,
                "source": source,
                "sv": float(global_sv),
                "platform_sv": float(platform_sv),
                "raw_z": float(value["raw_z"]),
                "confidence": level,
                "n_eff": float(value["n_eff"]),
                "settled_calls": int(value["settled_calls"]),
                "platform_qualified": qualifies_for_platform(source, value),
            }
        )

    scored.sort(
        key=lambda row: (
            -row["sv"],
            -row["raw_z"],
            -row["n_eff"],
            -row["settled_calls"],
            row["investor_id"],
        )
    )
    denominator = max(1, len(scored) - 1)
    for index, row in enumerate(scored):
        row["rank_no"] = index + 1
        row["percentile"] = index / denominator * 100.0

    for source in sorted({str(row["source"]) for row in scored}):
        platform_rows = [
            row for row in scored
            if row["source"] == source and row["platform_qualified"]
        ]
        platform_rows.sort(
            key=lambda row: (
                -row["platform_sv"],
                -row["raw_z"],
                -row["n_eff"],
                -row["settled_calls"],
                row["investor_id"],
            )
        )
        population = len(platform_rows)
        platform_denominator = max(1, population - 1)
        for index, row in enumerate(platform_rows):
            row["platform_rank_no"] = index + 1
            row["platform_population"] = population
            row["platform_percentile"] = index / platform_denominator * 100.0
        for row in scored:
            if row["source"] == source and not row["platform_qualified"]:
                row["platform_rank_no"] = None
                row["platform_population"] = population
                row["platform_percentile"] = None
    return scored


def rebuild_point_in_time_scores(con: sqlite3.Connection, call_days: Iterable[str]) -> int:
    """Rebuild scores using only settlements whose exit date precedes each call day."""
    ensure_ticker_signal_tables(con)
    days = sorted({day for day in call_days if day})
    con.execute("DELETE FROM sv_investor_score_asof")
    if not days:
        con.commit()
        return 0

    settlement_rows = con.execute(
        """SELECT s.*, c.source, c.author_handle, c.language, c.direction,
                  c.investor_style, c.call_structure
             FROM sv_call_settlement s
             JOIN sv_call c ON c.candidate_id = s.candidate_id
            WHERE s.status = 'settled'
              AND s.actual_hit IS NOT NULL
              AND s.exit_day IS NOT NULL
              AND s.investor_id IS NOT NULL
            ORDER BY s.exit_day, s.candidate_id, s.horizon"""
    ).fetchall()

    rows_by_investor: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    cursor = 0
    inserted = 0
    for day in days:
        while cursor < len(settlement_rows) and str(settlement_rows[cursor]["exit_day"]) < day:
            row = settlement_rows[cursor]
            rows_by_investor[str(row["investor_id"])].append(row)
            cursor += 1
        scored = _score_pool(rows_by_investor, day)
        con.executemany(
            """INSERT INTO sv_investor_score_asof
               (asof_day,investor_id,source,sv,raw_z,rank_no,percentile,confidence,n_eff,settled_calls,
                platform_sv,platform_rank_no,platform_population,platform_percentile,platform_qualified)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            [
                (
                    day,
                    row["investor_id"],
                    row["source"],
                    row["sv"],
                    row["raw_z"],
                    row["rank_no"],
                    row["percentile"],
                    row["confidence"],
                    row["n_eff"],
                    row["settled_calls"],
                    row["platform_sv"],
                    row["platform_rank_no"],
                    row["platform_population"],
                    row["platform_percentile"],
                    int(row["platform_qualified"]),
                )
                for row in scored
            ],
        )
        inserted += len(scored)
    con.commit()
    return inserted
