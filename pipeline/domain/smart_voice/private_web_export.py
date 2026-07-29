"""Compact web export for the one-channel Private Smart Voice experiment."""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any


WEB_EXPORT_VERSION = "private-sv-experiment-v1"


def _call_payload(case: dict[str, Any]) -> dict[str, Any]:
    return {
        "candidateId": str(case["candidate_id"]),
        "ticker": str(case["ticker"]),
        "source": "telegram",
        "day": str(case["published_at"])[:10],
        "publishedAt": str(case["published_at"]),
        "direction": str(case["direction"]),
        "horizon": str(case["horizon"]),
        "summaryZh": str(case["summary_zh"] or ""),
        "summaryEn": str(case["summary_en"] or ""),
        "evidence": str(case["evidence"] or ""),
        "url": str(case["url"] or ""),
        "contribution": float(case["score_contribution"] or 0),
        "returnPct": float(case["stock_return_pct"] or 0) / 100,
        "excessReturnPct": float(case["directional_spy_excess_pct"] or 0)
        / 100,
        "actualHit": int(bool(case["hit"])),
        "entryDay": str(case["entry_day"] or ""),
        "exitDay": str(case["exit_day"] or ""),
        "entryPrice": None,
        "exitPrice": None,
        "industryBenchmark": str(case["industry_benchmark"] or ""),
        "industryDirectionalExcessPct": case[
            "industry_directional_excess_pct"
        ],
        "style": str(case["style"] or "unknown"),
        "views": int(case["views"] or 0),
        "reactions": int(case["reactions"] or 0),
    }


def _ticker_metadata(
    con: sqlite3.Connection,
    tickers: list[str],
) -> dict[str, dict[str, str]]:
    if not tickers:
        return {}
    placeholders = ",".join("?" for _ in tickers)
    try:
        rows = con.execute(
            f"""
            SELECT ticker,company_name,sector
              FROM ticker_meta
             WHERE ticker IN ({placeholders})
            """,
            tickers,
        ).fetchall()
    except sqlite3.OperationalError:
        return {}
    return {
        str(row["ticker"]).upper(): {
            "companyName": str(row["company_name"] or ""),
            "sector": str(row["sector"] or ""),
        }
        for row in rows
    }


def _price_points(
    con: sqlite3.Connection,
    ticker: str,
    calls: list[dict[str, Any]],
) -> list[list[Any]]:
    starts = [str(call["entryDay"] or call["day"]) for call in calls]
    ends = [str(call["exitDay"] or call["entryDay"] or call["day"]) for call in calls]
    if not starts or not ends:
        return []
    start = con.execute(
        "SELECT date(?, '-35 days') AS day",
        (min(starts),),
    ).fetchone()["day"]
    end = con.execute(
        "SELECT date(?, '+12 days') AS day",
        (max(ends),),
    ).fetchone()["day"]
    try:
        rows = con.execute(
            """
            SELECT day,COALESCE(adj_close,close) AS close
              FROM price_daily
             WHERE ticker=? AND day BETWEEN ? AND ?
               AND COALESCE(adj_close,close) IS NOT NULL
             ORDER BY day
            """,
            (ticker, start, end),
        ).fetchall()
    except sqlite3.OperationalError:
        rows = con.execute(
            """
            SELECT day,close
              FROM price_daily
             WHERE ticker=? AND day BETWEEN ? AND ? AND close IS NOT NULL
             ORDER BY day
            """,
            (ticker, start, end),
        ).fetchall()
    return [[str(row["day"]), round(float(row["close"]), 4)] for row in rows]


def write_private_web_export(
    con: sqlite3.Connection,
    report: dict[str, Any],
    output_path: str | Path,
    *,
    ticker_limit: int = 0,
) -> dict[str, Any]:
    """Write a bounded, public-evidence-only payload for the experiment page."""
    ticker_stats = (
        report["ticker_report"][:ticker_limit]
        if ticker_limit > 0
        else report["ticker_report"]
    )
    tickers = [str(item["ticker"]).upper() for item in ticker_stats]
    ticker_set = set(tickers)
    metadata = _ticker_metadata(con, tickers)
    calls_by_ticker: dict[str, list[dict[str, Any]]] = {
        ticker: [] for ticker in tickers
    }
    for case in report["calls"]:
        ticker = str(case["ticker"]).upper()
        if ticker in ticker_set:
            calls_by_ticker[ticker].append(_call_payload(case))

    ticker_payload = []
    price_points = 0
    for stats in ticker_stats:
        ticker = str(stats["ticker"]).upper()
        calls = sorted(
            calls_by_ticker[ticker],
            key=lambda item: (item["day"], item["candidateId"]),
        )
        prices = _price_points(con, ticker, calls)
        price_points += len(prices)
        ticker_payload.append(
            {
                **metadata.get(ticker, {"companyName": "", "sector": ""}),
                "ticker": ticker,
                "settledCalls": int(stats["settled_calls"]),
                "bullCalls": int(stats["bull_calls"]),
                "bearCalls": int(stats["bear_calls"]),
                "hitRate": float(stats["hit_rate"]),
                "meanDirectionalSpyExcessPct": float(
                    stats["mean_directional_spy_excess_pct"]
                ),
                "focusContribution": float(stats["score_contribution"]),
                "latestDirection": str(stats["latest_direction"]),
                "latestAt": str(stats["latest_at"]),
                "latestUrl": str(stats["latest_url"]),
                "calls": calls,
                "prices": prices,
            }
        )

    payload = {
        "version": WEB_EXPORT_VERSION,
        "generatedAt": str(report["generated_at"]),
        "reportVersion": str(report["report_version"]),
        "scoringVersion": str(report["scoring_version"]),
        "settlementVersion": str(report["settlement_version"]),
        "channel": {
            "handle": str(report["channel"]["handle"]),
            "title": str(report["channel"]["title"]),
            "description": str(report["channel"]["description"]),
            "publicUrl": str(report["channel"]["public_url"]),
            "subscriberCount": int(report["channel"]["subscriber_count"]),
            "messageCount": int(report["channel"]["message_count"]),
            "firstMessageAt": str(report["channel"]["first_message_at"]),
            "lastMessageAt": str(report["channel"]["last_message_at"]),
        },
        "score": {
            "sv": int(report["score"]["sv"]),
            "confidence": str(report["score"]["confidence"]),
            "nEff": float(report["score"]["n_eff"]),
            "settledCalls": int(report["score"]["settled_calls"]),
            "activeDays": int(report["score"]["active_days"]),
            "coveredTickers": int(report["score"]["covered_tickers"]),
            "referencePercentile": float(
                report["score"]["reference_percentile"]
            ),
            "referencePopulation": int(
                report["score"]["calibration"]["population"]
            ),
            "explanationZh": str(report["score"]["explanation_zh"]),
        },
        "style": report["style"],
        "performance": {
            "calls": int(report["performance"]["calls"]),
            "bullCalls": int(report["performance"]["bull_calls"]),
            "bearCalls": int(report["performance"]["bear_calls"]),
            "spyExcessHitRate": report["performance"]["spy_excess_hit_rate"],
            "meanDirectionalSpyExcessPct": report["performance"][
                "mean_directional_spy_excess_pct"
            ],
            "medianDirectionalSpyExcessPct": report["performance"][
                "median_directional_spy_excess_pct"
            ],
            "averagePositiveExcessPct": report["performance"][
                "average_positive_excess_pct"
            ],
            "averageNegativeExcessPct": report["performance"][
                "average_negative_excess_pct"
            ],
            "payoffRatio": report["performance"]["payoff_ratio"],
            "profitFactor": report["performance"]["profit_factor"],
            "industryCalls": int(report["performance"]["industry_calls"]),
            "industryExcessHitRate": report["performance"][
                "industry_excess_hit_rate"
            ],
            "meanDirectionalIndustryExcessPct": report["performance"][
                "mean_directional_industry_excess_pct"
            ],
            "callsByYear": report["performance"]["calls_by_year"],
        },
        "dataQuality": {
            "messages": int(report["data_quality"]["messages"]),
            "forwardedExcluded": int(
                report["data_quality"]["forwarded_excluded"]
            ),
            "candidateTickerPairs": int(
                report["data_quality"]["candidate_ticker_pairs"]
            ),
            "extractedPairs": int(report["data_quality"]["extracted_pairs"]),
            "actionableCalls": int(report["data_quality"]["actionable_calls"]),
            "settledPrimaryCalls": int(
                report["data_quality"]["settled_primary_calls"]
            ),
        },
        "portfolioBacktest": report["portfolio_backtest"],
        "bestCases": [_call_payload(case) for case in report["best_cases"]],
        "weakCases": [_call_payload(case) for case in report["weak_cases"]],
        "tickers": ticker_payload,
    }
    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    return {
        "path": str(destination),
        "tickers": len(ticker_payload),
        "calls": sum(len(item["calls"]) for item in ticker_payload),
        "price_points": price_points,
    }
