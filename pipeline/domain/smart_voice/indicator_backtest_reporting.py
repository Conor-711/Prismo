"""Auditable event, evidence, and robustness exports for SV indicator backtests."""
from __future__ import annotations

import bisect
import collections
import csv
import math
import re
import sqlite3
import statistics
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Iterable

from .indicator_backtest_casebook import write_indicator_casebook
from .indicator_backtest_logic import call_signal_weight

SHORT_PUT_RE = re.compile(r"\b(?:sold|sell|selling|write|writing)\b.{0,50}\bputs?\b|\bshort puts?\b|卖出.{0,12}看跌", re.I)
OPTION_RE = re.compile(r"\b(?:puts?|calls?|\d+(?:\.\d+)?[pc])\b|看涨期权|看跌期权", re.I)


def _write_csv(path: Path, columns: list[str], rows: Iterable[dict[str, Any]]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
            count += 1
    return count


def _band(rank: int, population: int) -> str | None:
    cutoff = max(1, math.ceil(population * 0.10))
    if rank <= cutoff:
        return "top"
    if rank > population - cutoff:
        return "bottom"
    return None


def _audit_flags(row: dict[str, Any]) -> list[str]:
    text = " ".join(
        str(row.get(key) or "")
        for key in ("raw_text", "summary_zh", "summary_en", "original_evidence")
    )
    flags: list[str] = []
    if row["direction"] == "bear" and SHORT_PUT_RE.search(text):
        flags.append("bear_short_put_conflict")
    if OPTION_RE.search(text) and str(row.get("underlying_direction") or "unknown") == "unknown":
        flags.append("option_direction_unresolved")
    if str(row.get("entry_status") or "") == "conditional_setup":
        flags.append("conditional_entry")
    return flags


def _load_ranked_evidence(con: sqlite3.Connection) -> dict[str, list[dict[str, Any]]]:
    rows = con.execute(
        """SELECT c.candidate_id,upper(c.ticker) AS ticker,c.source,c.investor_id,
                  COALESCE(NULLIF(c.author_handle,''),NULLIF(cc.author_handle,''),c.investor_id) AS author,
                  c.created_at,substr(c.created_at,1,10) AS day,c.direction,c.horizon_bucket,
                  c.target_price,c.call_weight,c.evidence_score,c.specificity_score,
                  c.summary_zh,c.summary_en,c.evidence_span AS original_evidence,
                  c.call_structure,c.lifecycle_action,c.entry_status,c.option_strategy,c.underlying_direction,
                  a.platform_sv,a.platform_rank_no,a.platform_population,a.platform_percentile,
                  a.confidence,a.n_eff,a.settled_calls,cc.text AS raw_text,cc.url
             FROM sv_call c
             JOIN sv_investor_score_asof a
               ON a.asof_day=substr(c.created_at,1,10)
              AND a.investor_id=c.investor_id
              AND a.source=c.source
             LEFT JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
            WHERE c.is_actionable_call=1
              AND c.direction IN ('bull','bear')
              AND a.platform_qualified=1
              AND a.platform_rank_no IS NOT NULL
              AND a.platform_population>=10
            ORDER BY ticker,c.created_at,c.candidate_id"""
    ).fetchall()
    output: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for raw in rows:
        item = dict(raw)
        item["band"] = _band(int(item["platform_rank_no"]), int(item["platform_population"]))
        if item["band"] is None:
            continue
        item["author_key"] = f"{item['source']}:{item['investor_id']}"
        item["signal_weight"] = call_signal_weight(item)
        item["audit_flags"] = _audit_flags(item)
        output[str(item["ticker"])].append(item)
    return output


def _window_calls(
    calls: list[dict[str, Any]],
    source_scope: str,
    start_day: str,
    end_day: str,
) -> list[dict[str, Any]]:
    scoped = calls if source_scope == "all" else [call for call in calls if call["source"] == source_scope]
    days = [str(call["day"]) for call in scoped]
    return scoped[bisect.bisect_left(days, start_day):bisect.bisect_right(days, end_day)]


def _latest_markers(calls: list[dict[str, Any]]) -> set[tuple[str, str]]:
    latest: dict[tuple[str, str], dict[str, Any]] = {}
    for call in calls:
        key = (str(call["band"]), str(call["author_key"]))
        previous = latest.get(key)
        marker = (str(call["created_at"]), str(call["candidate_id"]))
        if previous is None or marker > (str(previous["created_at"]), str(previous["candidate_id"])):
            latest[key] = call
    return {(str(call["band"]), str(call["candidate_id"])) for call in latest.values()}


def export_indicator_evidence(
    con: sqlite3.Connection,
    path: Path,
) -> tuple[int, int, dict[str, set[str]]]:
    by_ticker = _load_ranked_evidence(con)
    events = con.execute("SELECT * FROM sv_indicator_event ORDER BY signal_day,event_id").fetchall()
    event_flags: dict[str, set[str]] = collections.defaultdict(set)
    columns = [
        "event_id", "ticker", "source_scope", "window_days", "indicator", "signal_direction",
        "signal_day", "evidence_window", "window_start", "window_end", "candidate_id", "source",
        "investor_id", "author", "created_at", "direction", "band", "platform_sv",
        "platform_rank_no", "platform_population", "platform_percentile", "confidence", "n_eff",
        "settled_calls", "call_weight", "signal_weight", "weighted_contribution", "is_latest_author_call",
        "author_vote", "used_by_indicator", "horizon_bucket", "target_price", "evidence_score",
        "specificity_score", "call_structure", "lifecycle_action", "entry_status", "option_strategy",
        "underlying_direction", "audit_flags", "summary_zh", "summary_en", "original_evidence", "raw_text", "url",
    ]
    output: list[dict[str, Any]] = []
    for event in events:
        ticker = str(event["ticker"])
        window = int(event["window_days"])
        signal_day = str(event["signal_day"])
        current_start = (date.fromisoformat(signal_day) - timedelta(days=window - 1)).isoformat()
        periods = [("current", current_start, signal_day)]
        if event["indicator"] == "author_net_shift":
            previous_start = (date.fromisoformat(signal_day) - timedelta(days=window * 2 - 1)).isoformat()
            previous_end = (date.fromisoformat(signal_day) - timedelta(days=window)).isoformat()
            periods.append(("previous", previous_start, previous_end))
        for period, start_day, end_day in periods:
            calls = _window_calls(by_ticker.get(ticker, []), str(event["source_scope"]), start_day, end_day)
            latest = _latest_markers(calls)
            for call in calls:
                is_latest = (str(call["band"]), str(call["candidate_id"])) in latest
                used = (
                    period == "current" and event["indicator"] == "weighted_net" and call["band"] == "top"
                ) or (
                    period == "current" and event["indicator"] == "high_low_divergence"
                ) or (
                    event["indicator"] in ("author_net", "author_net_shift")
                    and call["band"] == "top" and is_latest
                )
                sign = 1 if call["direction"] == "bull" else -1
                flags = list(call["audit_flags"])
                if used:
                    event_flags[str(event["event_id"])].update(flags)
                output.append(
                    {
                        **call,
                        "event_id": event["event_id"],
                        "source_scope": event["source_scope"],
                        "window_days": window,
                        "indicator": event["indicator"],
                        "signal_direction": event["direction"],
                        "signal_day": signal_day,
                        "evidence_window": period,
                        "window_start": start_day,
                        "window_end": end_day,
                        "weighted_contribution": sign * float(call["signal_weight"]),
                        "is_latest_author_call": int(is_latest),
                        "author_vote": sign if is_latest else 0,
                        "used_by_indicator": int(used),
                        "audit_flags": ";".join(flags),
                    }
                )
    compact_columns = [
        "event_id", "ticker", "source_scope", "window_days", "indicator", "signal_direction",
        "signal_day", "evidence_window", "candidate_id", "source", "author", "created_at", "direction",
        "band", "platform_sv", "platform_rank_no", "platform_population", "confidence", "signal_weight",
        "weighted_contribution", "is_latest_author_call", "author_vote", "used_by_indicator", "audit_flags",
        "summary_zh", "original_evidence", "url",
    ]
    full_rows = _write_csv(path, columns, output)
    compact_rows = _write_csv(path.with_name("sv_indicator_event_evidence_compact.csv"), compact_columns, output)
    return full_rows, compact_rows, event_flags


def _result_rows(con: sqlite3.Connection) -> list[dict[str, Any]]:
    return [
        dict(row)
        for row in con.execute(
            """SELECT e.*,o.outcome_horizon,o.exit_day,o.exit_price,o.directional_return_pct,
                      o.directional_excess_pct,o.raw_hit,o.excess_hit,o.max_favorable_excess,
                      o.max_adverse_excess,o.status
                 FROM sv_indicator_event e
                 JOIN sv_indicator_outcome o ON o.event_id=e.event_id
                ORDER BY e.signal_day,e.event_id,o.outcome_horizon"""
        )
    ]


def _overlap_counts(rows: list[dict[str, Any]]) -> dict[tuple[str, str], int]:
    groups: dict[tuple[str, str, int, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for row in rows:
        if row["status"] == "settled" and row["entry_day"] and row["exit_day"]:
            key = (row["ticker"], row["source_scope"], row["window_days"], row["indicator"], row["outcome_horizon"])
            groups[key].append(row)
    output: dict[tuple[str, str], int] = {}
    for group in groups.values():
        entries = sorted(str(row["entry_day"]) for row in group)
        exits = sorted(str(row["exit_day"]) for row in group)
        for row in group:
            day = str(row["entry_day"])
            output[(str(row["event_id"]), str(row["outcome_horizon"]))] = (
                bisect.bisect_right(entries, day) - bisect.bisect_left(exits, day)
            )
    return output


def export_indicator_events(
    con: sqlite3.Connection,
    path: Path,
    event_flags: dict[str, set[str]],
) -> tuple[int, list[dict[str, Any]]]:
    rows = _result_rows(con)
    overlaps = _overlap_counts(rows)
    columns = [
        "event_id", "ticker", "source_scope", "window_days", "indicator", "direction", "start_day", "end_day",
        "signal_day", "signal_value", "top_net", "bottom_net", "top_author_net", "previous_top_author_net",
        "author_net_delta", "author_net_shift_pct", "top_authors", "previous_top_authors", "bottom_authors",
        "entry_day", "entry_price", "outcome_horizon", "exit_day", "exit_price", "raw_ticker_return_pct",
        "benchmark_return_pct", "directional_return_pct", "directional_excess_pct", "raw_hit", "excess_hit",
        "max_favorable_excess", "max_adverse_excess", "same_strategy_active_at_entry", "audit_flags",
        "return_after_10bps_cost", "return_after_25bps_cost", "status",
    ]
    output: list[dict[str, Any]] = []
    for row in rows:
        sign = 1.0 if row["direction"] == "bull" else -1.0
        directional = row["directional_return_pct"]
        directional_excess = row["directional_excess_pct"]
        raw_return = sign * float(directional) if directional is not None else None
        benchmark = (
            raw_return - sign * float(directional_excess)
            if raw_return is not None and directional_excess is not None else None
        )
        detail = {
                **row,
                "raw_ticker_return_pct": raw_return,
                "benchmark_return_pct": benchmark,
                "same_strategy_active_at_entry": overlaps.get((str(row["event_id"]), str(row["outcome_horizon"])), 0),
                "audit_flags": ";".join(sorted(event_flags.get(str(row["event_id"]), set()))),
                "return_after_10bps_cost": float(directional) - 0.001 if directional is not None else None,
                "return_after_25bps_cost": float(directional) - 0.0025 if directional is not None else None,
            }
        output.append(detail)
    return _write_csv(path, columns, output), output


def _wilson(hits: int, total: int) -> tuple[float | None, float | None]:
    if not total:
        return None, None
    z = 1.959963984540054
    rate = hits / total
    denominator = 1.0 + z * z / total
    center = (rate + z * z / (2.0 * total)) / denominator
    margin = z * math.sqrt(rate * (1.0 - rate) / total + z * z / (4.0 * total * total)) / denominator
    return max(0.0, center - margin), min(1.0, center + margin)


def _stats(rows: list[dict[str, Any]], cost: float = 0.0) -> dict[str, Any]:
    raw = [float(row["directional_return_pct"]) - cost for row in rows if row["directional_return_pct"] is not None]
    excess = [float(row["directional_excess_pct"]) - cost for row in rows if row["directional_excess_pct"] is not None]
    wins = [value for value in raw if value > 0]
    losses = [value for value in raw if value < 0]
    excess_wins = [value for value in excess if value > 0]
    excess_losses = [value for value in excess if value < 0]
    ci_low, ci_high = _wilson(len(excess_wins), len(excess))
    ratio = lambda a, b: a / abs(b) if b else None
    return {
        "n_events": len(rows),
        "raw_hit_rate": len(wins) / len(raw) if raw else None,
        "excess_hit_rate": len(excess_wins) / len(excess) if excess else None,
        "excess_hit_ci_low": ci_low,
        "excess_hit_ci_high": ci_high,
        "avg_directional_return_pct": statistics.fmean(raw) if raw else None,
        "median_directional_return_pct": statistics.median(raw) if raw else None,
        "avg_win_pct": statistics.fmean(wins) if wins else None,
        "avg_loss_pct": statistics.fmean(losses) if losses else None,
        "payoff_ratio": ratio(statistics.fmean(wins), statistics.fmean(losses)) if wins and losses else None,
        "profit_factor": ratio(sum(wins), sum(losses)) if wins and losses else None,
        "avg_directional_excess_pct": statistics.fmean(excess) if excess else None,
        "median_directional_excess_pct": statistics.median(excess) if excess else None,
        "excess_profit_factor": ratio(sum(excess_wins), sum(excess_losses)) if excess_wins and excess_losses else None,
    }


def export_indicator_breakdowns(con: sqlite3.Connection, path: Path, rows: list[dict[str, Any]]) -> int:
    settled = [row for row in rows if row["status"] == "settled"]
    events = {str(row["event_id"]): row for row in settled if row["source_scope"] == "all"}
    days = sorted({str(row["signal_day"]) for row in events.values()})
    cutoff = days[max(0, math.ceil(len(days) * 0.70) - 1)] if days else ""
    strength_groups: dict[tuple[str, int], list[dict[str, Any]]] = collections.defaultdict(list)
    for event in events.values():
        strength_groups[(str(event["indicator"]), int(event["window_days"]))].append(event)
    strength_quartile: dict[str, str] = {}
    for group in strength_groups.values():
        ordered = sorted(group, key=lambda row: (float(row["signal_value"]), str(row["event_id"])))
        for index, row in enumerate(ordered):
            strength_quartile[str(row["event_id"])] = f"Q{min(4, index * 4 // max(1, len(ordered)) + 1)}"

    grouped: dict[tuple[str, str, str, str, int, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for row in settled:
        if row["source_scope"] != "all":
            continue
        base = (str(row["indicator"]), int(row["window_days"]), str(row["outcome_horizon"]))
        grouped[("ticker", str(row["ticker"]), "all", *base, "all")].append(row)
        grouped[("signal_month", str(row["signal_day"])[:7], "all", *base, "all")].append(row)
        split = f"early_through_{cutoff}" if str(row["signal_day"]) <= cutoff else f"late_after_{cutoff}"
        grouped[("time_split", split, "all", *base, "all")].append(row)
        grouped[("direction", str(row["direction"]), "all", *base, str(row["direction"]))].append(row)
        grouped[("strength_quartile", strength_quartile[str(row["event_id"])], "all", *base, "all")].append(row)
        flags = {flag for flag in str(row.get("audit_flags") or "").split(";") if flag}
        quality_group = "no_audit_flags" if not flags else "has_audit_flags"
        grouped[("evidence_quality", quality_group, "all", *base, "all")].append(row)
        for flag in flags:
            grouped[("evidence_quality", flag, "all", *base, "all")].append(row)

    columns = [
        "breakdown_type", "group_value", "source_scope", "indicator", "window_days", "outcome_horizon",
        "direction", "cost_bps", "n_events", "raw_hit_rate", "excess_hit_rate", "excess_hit_ci_low",
        "excess_hit_ci_high", "avg_directional_return_pct", "median_directional_return_pct", "avg_win_pct",
        "avg_loss_pct", "payoff_ratio", "profit_factor", "avg_directional_excess_pct",
        "median_directional_excess_pct", "excess_profit_factor",
    ]
    output: list[dict[str, Any]] = []
    for key, group in grouped.items():
        breakdown_type, group_value, source_scope, indicator, window, horizon, direction = key
        if breakdown_type == "ticker" and len(group) < 5:
            continue
        output.append(
            {
                "breakdown_type": breakdown_type,
                "group_value": group_value,
                "source_scope": source_scope,
                "indicator": indicator,
                "window_days": window,
                "outcome_horizon": horizon,
                "direction": direction,
                "cost_bps": 0,
                **_stats(group),
            }
        )
    cost_groups: dict[tuple[str, int, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for row in settled:
        if row["source_scope"] == "all":
            cost_groups[(str(row["indicator"]), int(row["window_days"]), str(row["outcome_horizon"]))].append(row)
    for (indicator, window, horizon), group in cost_groups.items():
        for bps in (10, 25):
            output.append(
                {
                    "breakdown_type": "transaction_cost",
                    "group_value": f"{bps}bps",
                    "source_scope": "all",
                    "indicator": indicator,
                    "window_days": window,
                    "outcome_horizon": horizon,
                    "direction": "all",
                    "cost_bps": bps,
                    **_stats(group, bps / 10_000.0),
                }
            )
    position_groups: dict[tuple[str, int, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for row in settled:
        if row["source_scope"] == "all" and row["entry_day"] and row["exit_day"]:
            key = (str(row["indicator"]), int(row["window_days"]), str(row["outcome_horizon"]), str(row["ticker"]))
            position_groups[key].append(row)
    non_overlapping: dict[tuple[str, int, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for (indicator, window, horizon, _), group in position_groups.items():
        last_exit = ""
        for row in sorted(group, key=lambda value: (str(value["entry_day"]), str(value["event_id"]))):
            if str(row["entry_day"]) <= last_exit:
                continue
            non_overlapping[(indicator, window, horizon)].append(row)
            last_exit = str(row["exit_day"])
    for (indicator, window, horizon), group in non_overlapping.items():
        output.append(
            {
                "breakdown_type": "position_policy",
                "group_value": "non_overlapping_same_ticker",
                "source_scope": "all",
                "indicator": indicator,
                "window_days": window,
                "outcome_horizon": horizon,
                "direction": "all",
                "cost_bps": 0,
                **_stats(group),
            }
        )
    output.sort(key=lambda row: tuple(str(row[column]) for column in columns[:8]))
    return _write_csv(path, columns, output)


def write_indicator_detail_reports(con: sqlite3.Connection, report_dir: Path) -> dict[str, int]:
    evidence_rows, compact_rows, event_flags = export_indicator_evidence(
        con, report_dir / "sv_indicator_event_evidence.csv"
    )
    event_rows, results = export_indicator_events(con, report_dir / "sv_indicator_event_results.csv", event_flags)
    breakdown_rows = export_indicator_breakdowns(con, report_dir / "sv_indicator_breakdowns.csv", results)
    casebook_cases = write_indicator_casebook(report_dir)
    return {
        "event_detail_rows": event_rows,
        "evidence_rows": evidence_rows,
        "compact_evidence_rows": compact_rows,
        "breakdown_rows": breakdown_rows,
        "casebook_cases": casebook_cases,
    }


def export_sv_indicator_backtest_reports(*, db_path: str | Path, report_dir: str | Path) -> dict[str, int]:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    result = write_indicator_detail_reports(con, Path(report_dir))
    con.close()
    return result
