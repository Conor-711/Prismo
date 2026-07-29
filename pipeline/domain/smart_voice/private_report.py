"""Calibrate and export a one-channel Private Smart Voice report."""
from __future__ import annotations

import datetime as dt
import json
import sqlite3
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from .integral_scoring import INTEGRAL_SCORING_VERSION
from .private_portfolio import build_private_portfolio_backtest
from .private_report_export import write_report_exports
from .v0_impl import (
    PLATFORM_QUALIFICATION,
    SV_RANKING_VERSION,
    aggregate_stats,
    blend_dual_ability_scores,
    concentration_cap,
    confidence,
    global_sv_from_platform,
    investor_key,
    reliability_cap,
    robust_scores,
)


REPORT_VERSION = "private-sv-mvp-v1"


def _json(value: object, fallback: object) -> object:
    try:
        parsed = json.loads(str(value or ""))
        return parsed
    except (TypeError, ValueError, json.JSONDecodeError):
        return fallback


def _qualified_public_references(
    reference_db_path: str | Path,
) -> tuple[dict[str, float], dict[str, float], dict[str, Any]]:
    con = sqlite3.connect(str(reference_db_path))
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """
        SELECT investor_id,source,raw_z,n_eff,settled_calls,ability_scores_json
          FROM sv_investor_score
         WHERE raw_z IS NOT NULL
        """
    ).fetchall()
    market: dict[str, float] = {}
    industry: dict[str, float] = {}
    source_counts: Counter[str] = Counter()
    for row in rows:
        source = str(row["source"] or "x")
        rule = PLATFORM_QUALIFICATION.get(source, PLATFORM_QUALIFICATION["x"])
        if (
            float(row["n_eff"] or 0) < float(rule["n_eff"])
            or int(row["settled_calls"] or 0) < int(rule["settled_calls"])
        ):
            continue
        ability = _json(row["ability_scores_json"], {})
        if not isinstance(ability, dict):
            ability = {}
        market_selection = ability.get("marketSelection") or {}
        industry_selection = ability.get("industrySelection") or {}
        key = f"public:{source}:{row['investor_id']}"
        market[key] = float(market_selection.get("rawZ", row["raw_z"]))
        if industry_selection.get("rawZ") is not None:
            industry[key] = float(industry_selection["rawZ"])
        source_counts[source] += 1
    con.close()
    if len(market) < 30:
        raise RuntimeError("public SV reference population is too small for calibration")
    return market, industry, {
        "population": len(market),
        "industry_population": len(industry),
        "sources": dict(sorted(source_counts.items())),
    }


def _settled_rows(con: sqlite3.Connection, investor_id: str) -> list[sqlite3.Row]:
    return con.execute(
        """
        SELECT s.*,c.source,c.author_handle,c.language,c.direction,
               c.investor_style,c.call_structure,c.summary_zh,c.summary_en,
               c.evidence_span,c.target_price,cc.text,cc.url
          FROM sv_call_settlement s
          JOIN sv_call c ON c.candidate_id=s.candidate_id
          JOIN sv_call_candidate cc ON cc.candidate_id=s.candidate_id
         WHERE c.source='telegram' AND c.investor_id=?
           AND s.status='settled'
        """,
        (investor_id,),
    ).fetchall()


def _primary_cases(con: sqlite3.Connection, investor_id: str) -> list[dict[str, Any]]:
    rows = con.execute(
        """
        SELECT s.*,c.direction,c.horizon_bucket,c.investor_style,
               c.summary_zh,c.summary_en,c.evidence_span,c.target_price,
               cc.text,cc.url,cc.view_count,cc.like_count AS reaction_count,cc.created_at
          FROM sv_call_settlement s
          JOIN sv_call c ON c.candidate_id=s.candidate_id
          JOIN sv_call_candidate cc ON cc.candidate_id=s.candidate_id
         WHERE c.source='telegram' AND c.investor_id=?
           AND s.status='settled' AND s.is_primary_horizon=1
         ORDER BY cc.created_at,s.candidate_id
        """,
        (investor_id,),
    ).fetchall()
    output = []
    for row in rows:
        direction = str(row["direction"])
        directional_excess = float(row["excess_return_pct"] or 0) * (
            1 if direction == "bull" else -1
        )
        output.append(
            {
                "candidate_id": str(row["candidate_id"]),
                "ticker": str(row["ticker"]),
                "direction": direction,
                "published_at": str(row["created_at"]),
                "horizon": str(row["horizon"]),
                "entry_day": str(row["entry_day"] or ""),
                "exit_day": str(row["exit_day"] or ""),
                "stock_return_pct": round(float(row["return_pct"] or 0) * 100, 2),
                "spy_return_pct": round(
                    float(row["benchmark_return_pct"] or 0) * 100, 2
                ),
                "directional_spy_excess_pct": round(directional_excess * 100, 2),
                "hit": bool(row["actual_hit"]),
                "score_contribution": round(float(row["contribution"] or 0), 5),
                "industry_benchmark": str(
                    row["industry_benchmark_ticker"] or ""
                ),
                "industry_directional_excess_pct": (
                    round(
                        float(row["industry_excess_return_pct"] or 0)
                        * (1 if direction == "bull" else -1)
                        * 100,
                        2,
                    )
                    if row["industry_status"] == "settled"
                    else None
                ),
                "summary_zh": str(row["summary_zh"] or ""),
                "summary_en": str(row["summary_en"] or ""),
                "evidence": str(row["evidence_span"] or ""),
                "original_text": str(row["text"] or ""),
                "url": str(row["url"] or ""),
                "target_price": row["target_price"],
                "style": str(row["investor_style"] or "unknown"),
                "views": int(row["view_count"] or 0),
                "reactions": int(row["reaction_count"] or 0),
            }
        )
    return output


def _ticker_report(cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case in cases:
        grouped[case["ticker"]].append(case)
    output = []
    for ticker, items in grouped.items():
        hits = sum(bool(item["hit"]) for item in items)
        bull = sum(item["direction"] == "bull" for item in items)
        bear = sum(item["direction"] == "bear" for item in items)
        latest = max(items, key=lambda item: item["published_at"])
        output.append(
            {
                "ticker": ticker,
                "settled_calls": len(items),
                "bull_calls": bull,
                "bear_calls": bear,
                "hit_rate": round(hits / len(items), 4),
                "mean_directional_spy_excess_pct": round(
                    sum(item["directional_spy_excess_pct"] for item in items)
                    / len(items),
                    2,
                ),
                "score_contribution": round(
                    sum(item["score_contribution"] for item in items), 5
                ),
                "latest_direction": latest["direction"],
                "latest_at": latest["published_at"],
                "latest_url": latest["url"],
            }
        )
    return sorted(
        output,
        key=lambda item: (-item["settled_calls"], -abs(item["score_contribution"]), item["ticker"]),
    )


def _performance_summary(cases: list[dict[str, Any]]) -> dict[str, Any]:
    excess = [float(case["directional_spy_excess_pct"]) for case in cases]
    positive = [value for value in excess if value > 0]
    negative = [value for value in excess if value < 0]
    industry = [
        float(case["industry_directional_excess_pct"])
        for case in cases
        if case["industry_directional_excess_pct"] is not None
    ]
    by_year = Counter(str(case["published_at"])[:4] for case in cases)
    payoff_ratio = (
        statistics.mean(positive) / abs(statistics.mean(negative))
        if positive and negative
        else None
    )
    profit_factor = (
        sum(positive) / abs(sum(negative))
        if positive and negative
        else None
    )
    return {
        "calls": len(cases),
        "bull_calls": sum(case["direction"] == "bull" for case in cases),
        "bear_calls": sum(case["direction"] == "bear" for case in cases),
        "spy_excess_hit_rate": round(len(positive) / len(excess), 4) if excess else None,
        "mean_directional_spy_excess_pct": (
            round(statistics.mean(excess), 2) if excess else None
        ),
        "median_directional_spy_excess_pct": (
            round(statistics.median(excess), 2) if excess else None
        ),
        "average_positive_excess_pct": (
            round(statistics.mean(positive), 2) if positive else None
        ),
        "average_negative_excess_pct": (
            round(statistics.mean(negative), 2) if negative else None
        ),
        "payoff_ratio": round(payoff_ratio, 3) if payoff_ratio is not None else None,
        "profit_factor": (
            round(profit_factor, 3) if profit_factor is not None else None
        ),
        "industry_calls": len(industry),
        "industry_excess_hit_rate": (
            round(sum(value > 0 for value in industry) / len(industry), 4)
            if industry
            else None
        ),
        "mean_directional_industry_excess_pct": (
            round(statistics.mean(industry), 2) if industry else None
        ),
        "calls_by_year": dict(sorted(by_year.items())),
    }


def build_private_report(
    con: sqlite3.Connection,
    *,
    reference_db_path: str | Path,
    handle: str,
    output_dir: str | Path,
) -> dict[str, Any]:
    normalized_handle = handle.strip().lstrip("@").lower()
    investor_id = investor_key("telegram", normalized_handle)
    settled = _settled_rows(con, investor_id)
    market_stats = aggregate_stats(
        settled,
        30.0,
        as_of_day=dt.datetime.now(dt.timezone.utc).date(),
    )
    if not market_stats:
        raise RuntimeError("no settled Telegram calls are available for scoring")
    industry_stats = aggregate_stats(
        settled,
        20.0,
        as_of_day=dt.datetime.now(dt.timezone.utc).date(),
        ability="industry",
    )
    market_reference, industry_reference, calibration = (
        _qualified_public_references(reference_db_path)
    )
    private_market_key = f"private:{investor_id}"
    market_scores = robust_scores(
        {**market_reference, private_market_key: float(market_stats["raw_z"])}
    )
    market_platform_sv = market_scores[private_market_key]
    industry_platform_sv = None
    if industry_stats:
        industry_scores = robust_scores(
            {
                **industry_reference,
                private_market_key: float(industry_stats["raw_z"]),
            }
        )
        industry_platform_sv = industry_scores[private_market_key]
    ability = blend_dual_ability_scores(
        market_stats,
        industry_stats,
        market_platform_sv,
        industry_platform_sv,
    )
    level = confidence(
        float(market_stats["n_eff"]),
        int(market_stats["settled_calls"]),
    )
    raw_platform_sv = float(ability["compositePlatformSv"])
    score_cap = min(reliability_cap(level), concentration_cap(market_stats))
    platform_sv = int(round(min(raw_platform_sv, score_cap)))
    sv, _ = global_sv_from_platform(platform_sv, level)
    better = sum(
        raw > float(market_stats["raw_z"]) for raw in market_reference.values()
    )
    reference_percentile = 100.0 * (better + 1) / (len(market_reference) + 1)

    channel = con.execute(
        "SELECT * FROM telegram_public_channel WHERE handle=?",
        (normalized_handle,),
    ).fetchone()
    if not channel:
        raise RuntimeError(f"missing Telegram channel metadata for @{normalized_handle}")
    counts = con.execute(
        """
        SELECT
          (SELECT COUNT(*) FROM telegram_public_message WHERE channel_handle=?) AS messages,
          (SELECT COUNT(*) FROM telegram_public_message WHERE channel_handle=? AND is_forwarded=1) AS forwarded,
          (SELECT COUNT(*) FROM sv_call_candidate WHERE source='telegram' AND author_id=?) AS candidates,
          (SELECT COUNT(*) FROM sv_call WHERE source='telegram' AND investor_id=?) AS extracted,
          (SELECT COUNT(*) FROM sv_call WHERE source='telegram' AND investor_id=? AND is_actionable_call=1) AS actionable
        """,
        (
            normalized_handle,
            normalized_handle,
            investor_id,
            investor_id,
            investor_id,
        ),
    ).fetchone()
    cases = _primary_cases(con, investor_id)
    performance = _performance_summary(cases)
    styles = Counter(case["style"] for case in cases)
    cases_by_result = sorted(
        cases,
        key=lambda item: item["directional_spy_excess_pct"],
        reverse=True,
    )
    report = {
        "report_version": REPORT_VERSION,
        "scoring_version": SV_RANKING_VERSION,
        "settlement_version": INTEGRAL_SCORING_VERSION,
        "generated_at": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat(),
        "channel": {
            "handle": normalized_handle,
            "title": str(channel["title"] or normalized_handle),
            "description": str(channel["description"] or ""),
            "public_url": str(channel["public_url"] or ""),
            "subscriber_count": int(channel["subscriber_count"] or 0),
            "message_count": int(channel["message_count"] or 0),
            "first_message_at": str(channel["first_message_at"] or ""),
            "last_message_at": str(channel["last_message_at"] or ""),
        },
        "score": {
            "sv": sv,
            "sv_platform_calibrated": platform_sv,
            "raw_sv_before_caps": round(raw_platform_sv, 2),
            "raw_z": round(float(ability["compositeRawZ"]), 4),
            "confidence": level,
            "n_eff": round(float(market_stats["n_eff"]), 2),
            "settled_calls": int(market_stats["settled_calls"]),
            "active_days": int(market_stats["active_days"]),
            "covered_tickers": int(market_stats["covered_tickers"]),
            "reference_percentile": round(reference_percentile, 2),
            "calibration": calibration,
            "ability": ability,
            "concentration": market_stats["concentration"],
            "caps": {
                "reliability": reliability_cap(level),
                "concentration": concentration_cap(market_stats),
                "applied": score_cap,
            },
            "explanation_zh": (
                f"基于 {market_stats['settled_calls']} 个已结算 Call，按相对 SPY 与行业 ETF "
                f"的完整持有期积分路径计算；时间衰减后的有效样本为 "
                f"{market_stats['n_eff']:.2f}。由于本次只有一位 Telegram 作者，"
                f"使用 {calibration['population']} 位现有公域合格作者的同算法 raw-z "
                f"分布校准，再应用样本置信度和标的集中度上限，得到 Private SE/SV={sv}。"
            ),
        },
        "style": {
            "dominant": styles.most_common(1)[0][0] if styles else "unknown",
            "distribution": dict(styles),
        },
        "performance": performance,
        "data_quality": {
            "messages": int(counts["messages"] or 0),
            "forwarded_excluded": int(counts["forwarded"] or 0),
            "candidate_ticker_pairs": int(counts["candidates"] or 0),
            "extracted_pairs": int(counts["extracted"] or 0),
            "actionable_calls": int(counts["actionable"] or 0),
            "settled_primary_calls": len(cases),
        },
        "ticker_report": _ticker_report(cases),
        "best_cases": cases_by_result[:5],
        "weak_cases": list(reversed(cases_by_result[-5:])),
        "calls": cases,
    }
    report["portfolio_backtest"] = build_private_portfolio_backtest(con, cases)

    write_report_exports(report, output_dir)
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS private_sv_report (
          report_id TEXT PRIMARY KEY,
          channel_handle TEXT NOT NULL,
          report_version TEXT NOT NULL,
          report_json TEXT NOT NULL,
          generated_at TEXT NOT NULL
        )
        """
    )
    report_id = f"{normalized_handle}:{report['generated_at']}"
    con.execute(
        """
        INSERT OR REPLACE INTO private_sv_report
          (report_id,channel_handle,report_version,report_json,generated_at)
        VALUES (?,?,?,?,?)
        """,
        (
            report_id,
            normalized_handle,
            REPORT_VERSION,
            json.dumps(report, ensure_ascii=False),
            report["generated_at"],
        ),
    )
    con.commit()
    return report
