"""Point-in-time Smart Account scores used by ticker signal backtests."""
from __future__ import annotations

import collections
import sqlite3
from typing import Any, Iterable

from .ticker_signal_schema import ensure_ticker_signal_tables
from .v0_impl import (
    aggregate_stats,
    blend_dual_ability_scores,
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
    market_stats = {
        investor: aggregate_stats(rows, 30.0, as_of_day=as_of_day)
        for investor, rows in rows_by_investor.items()
    }
    market_stats = {
        investor: value for investor, value in market_stats.items() if value
    }
    industry_stats = {
        investor: aggregate_stats(
            rows,
            20.0,
            as_of_day=as_of_day,
            ability="industry",
        )
        for investor, rows in rows_by_investor.items()
        if investor in market_stats
    }
    industry_stats = {
        investor: value for investor, value in industry_stats.items() if value
    }
    sources = {
        investor: primary_source_for_rows(rows_by_investor[investor])
        for investor in market_stats
    }
    market_raw_by_platform: dict[str, dict[str, float]] = collections.defaultdict(dict)
    industry_raw_by_platform: dict[str, dict[str, float]] = collections.defaultdict(dict)
    for investor, value in market_stats.items():
        source = sources[investor]
        market_raw_by_platform[source][investor] = float(value["raw_z"])
        if investor in industry_stats:
            industry_raw_by_platform[source][investor] = float(
                industry_stats[investor]["raw_z"]
            )

    market_platform_scores: dict[str, dict[str, int]] = {}
    market_fallback_scores: dict[str, dict[str, int]] = {}
    industry_platform_scores: dict[str, dict[str, int]] = {}
    industry_fallback_scores: dict[str, dict[str, int]] = {}
    for source, raw_map in market_raw_by_platform.items():
        qualified = {
            investor: raw
            for investor, raw in raw_map.items()
            if qualifies_for_platform(source, market_stats[investor])
        }
        if len(qualified) < 8:
            qualified = raw_map
        market_platform_scores[source] = robust_scores(qualified)
        market_fallback_scores[source] = robust_scores(raw_map)
        industry_raw = industry_raw_by_platform.get(source, {})
        industry_qualified = {
            investor: raw
            for investor, raw in industry_raw.items()
            if float(industry_stats[investor]["n_eff"]) >= 4.0
            and int(industry_stats[investor]["settled_calls"]) >= 5
        }
        if len(industry_qualified) < 8:
            industry_qualified = industry_raw
        industry_platform_scores[source] = robust_scores(industry_qualified)
        industry_fallback_scores[source] = robust_scores(industry_raw)

    scored: list[dict[str, Any]] = []
    for investor, value in market_stats.items():
        source = sources[investor]
        level = confidence(float(value["n_eff"]), int(value["settled_calls"]))
        market_platform_sv = market_platform_scores.get(source, {}).get(
            investor,
            market_fallback_scores.get(source, {}).get(investor, 100),
        )
        industry_value = industry_stats.get(investor)
        industry_platform_sv = (
            industry_platform_scores.get(source, {}).get(
                investor,
                industry_fallback_scores.get(source, {}).get(investor, 100),
            )
            if industry_value
            else None
        )
        abilities = blend_dual_ability_scores(
            value,
            industry_value,
            market_platform_sv,
            industry_platform_sv,
        )
        raw_platform_sv = float(abilities["compositePlatformSv"])
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
                "raw_z": float(abilities["compositeRawZ"]),
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

    settlement_columns = {
        str(row["name"])
        for row in con.execute("PRAGMA table_info(sv_call_settlement)").fetchall()
    }
    primary_horizon_filter = (
        "AND (COALESCE(s.settlement_version, '') = '' OR s.is_primary_horizon = 1)"
        if {"settlement_version", "is_primary_horizon"} <= settlement_columns
        else ""
    )
    settlement_rows = con.execute(
        f"""SELECT s.*, c.source, c.author_handle, c.language, c.direction,
                  c.investor_style, c.call_structure
             FROM sv_call_settlement s
             JOIN sv_call c ON c.candidate_id = s.candidate_id
            WHERE s.status = 'settled'
              AND s.actual_hit IS NOT NULL
              {primary_horizon_filter}
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
