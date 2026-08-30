"""CSV, JSON, and evidence-first Markdown output for Congress Score."""
from __future__ import annotations

import csv
import datetime as dt
import json
from dataclasses import asdict
from pathlib import Path

from .schema import MemberScore, TradeOutcome


def _round(value: float | None, digits: int = 2) -> float | None:
    return round(value, digits) if value is not None else None


def _pct(value: float | None) -> float | None:
    return _round(value * 100.0, 1) if value is not None else None


def score_row(row: MemberScore) -> dict[str, object]:
    return {
        "rank": row.rank,
        "score_percentile": _round(row.score, 1),
        "status": row.status,
        "confidence": _round(row.confidence, 1),
        "member_id": row.member.member_id,
        "name": row.member.name,
        "chamber": row.member.chamber,
        "party": row.member.party,
        "state": row.member.state,
        "office": row.member.office,
        "raw_disclosures": row.raw_disclosures,
        "eligible_events": row.eligible_events,
        "price_resolved_events": row.price_resolved_events,
        "purchase_events_20d": row.purchase_events_20d,
        "purchase_decision_days_20d": row.purchase_days_20d,
        "purchase_hit_rate_20d_pct": _pct(row.purchase_hit_rate_20d),
        "purchase_avg_excess_20d_pct": _round(row.purchase_avg_excess_20d),
        "purchase_median_excess_20d_pct": _round(row.purchase_median_excess_20d),
        "purchase_events_60d": row.purchase_events_60d,
        "purchase_decision_days_60d": row.purchase_days_60d,
        "purchase_hit_rate_60d_pct": _pct(row.purchase_hit_rate_60d),
        "purchase_avg_excess_60d_pct": _round(row.purchase_avg_excess_60d),
        "purchase_median_excess_60d_pct": _round(row.purchase_median_excess_60d),
        "sale_events_20d": row.sale_events_20d,
        "sale_decision_days_20d": row.sale_days_20d,
        "sale_avoidance_hit_rate_20d_pct": _pct(row.sale_avoidance_hit_rate_20d),
        "sale_avoidance_avg_excess_20d_pct": _round(row.sale_avoidance_avg_excess_20d),
        "median_disclosure_lag_days": _round(row.median_disclosure_lag_days, 1),
        "late_filing_rate_pct": _pct(row.late_filing_rate),
        "top_tickers": ",".join(row.top_tickers),
        "official_evidence_url": row.evidence_url,
    }


def write_scores_csv(path: Path, scores: list[MemberScore]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = [score_row(row) for row in scores]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else [])
        writer.writeheader()
        writer.writerows(rows)


def write_evidence_csv(
    path: Path,
    outcomes: list[TradeOutcome],
    scores: list[MemberScore],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    score_by_member = {row.member.member_id: row for row in scores}
    fieldnames = [
        "rank",
        "score_percentile",
        "member_id",
        "name",
        "chamber",
        "party",
        "state",
        "ticker",
        "direction",
        "transaction_date",
        "entry_date",
        "exit_date",
        "horizon_trading_days",
        "asset_return_pct",
        "spy_return_pct",
        "directional_excess_pct",
        "collapsed_line_items",
        "amount_range_midpoint_sum",
        "official_evidence_urls",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for outcome in sorted(
            outcomes,
            key=lambda row: (row.transaction_date, row.member.name, row.ticker, row.horizon),
        ):
            score = score_by_member[outcome.member.member_id]
            writer.writerow(
                {
                    "rank": score.rank,
                    "score_percentile": _round(score.score, 1),
                    "member_id": outcome.member.member_id,
                    "name": outcome.member.name,
                    "chamber": outcome.member.chamber,
                    "party": outcome.member.party,
                    "state": outcome.member.state,
                    "ticker": outcome.ticker,
                    "direction": outcome.direction,
                    "transaction_date": outcome.transaction_date.isoformat(),
                    "entry_date": outcome.entry_date.isoformat(),
                    "exit_date": outcome.exit_date.isoformat(),
                    "horizon_trading_days": outcome.horizon,
                    "asset_return_pct": _round(outcome.asset_return, 4),
                    "spy_return_pct": _round(outcome.benchmark_return, 4),
                    "directional_excess_pct": _round(outcome.directional_excess, 4),
                    "collapsed_line_items": outcome.trade_count,
                    "amount_range_midpoint_sum": _round(outcome.amount_midpoint, 2),
                    "official_evidence_urls": "|".join(outcome.evidence_urls),
                }
            )


def _table_score_row(row: MemberScore) -> str:
    score = f"{row.score:.1f}" if row.score is not None else "-"
    hit = f"{row.purchase_hit_rate_20d * 100:.1f}%" if row.purchase_hit_rate_20d is not None else "-"
    excess = f"{row.purchase_avg_excess_20d:+.2f}%" if row.purchase_avg_excess_20d is not None else "-"
    hit_60 = f"{row.purchase_hit_rate_60d * 100:.1f}%" if row.purchase_hit_rate_60d is not None else "-"
    excess_60 = f"{row.purchase_avg_excess_60d:+.2f}%" if row.purchase_avg_excess_60d is not None else "-"
    evidence = f"[PDF]({row.evidence_url})" if row.evidence_url else "-"
    return (
        f"| {row.rank or '-'} | {row.member.name} | {row.member.chamber.title()} | "
        f"{score} | {row.purchase_days_20d} | {hit} | {excess} | "
        f"{row.purchase_days_60d} | {hit_60} | {excess_60} | "
        f"{row.confidence:.1f} | {evidence} |"
    )


def _case_row(outcome: TradeOutcome) -> str:
    url = outcome.evidence_urls[0] if outcome.evidence_urls else ""
    evidence = f"[official filing]({url})" if url else "-"
    return (
        f"| {outcome.member.name} | {outcome.transaction_date.isoformat()} | "
        f"{outcome.direction} {outcome.ticker} | {outcome.asset_return:+.2f}% | "
        f"{outcome.benchmark_return:+.2f}% | {outcome.directional_excess:+.2f}% | {evidence} |"
    )


def write_markdown_report(
    path: Path,
    *,
    scores: list[MemberScore],
    outcomes: list[TradeOutcome],
    manifest: dict[str, object],
) -> None:
    ranked = [row for row in scores if row.status == "ranked"]
    observation = [row for row in scores if row.status == "observation"]
    unscored = [row for row in scores if row.status == "unscored"]
    top = ranked[:15]
    bottom = list(reversed(ranked[-10:]))
    ranked_ids = {row.member.member_id for row in ranked}
    purchase_20 = [
        outcome
        for outcome in outcomes
        if outcome.horizon == 20
        and outcome.direction == "purchase"
        and outcome.member.member_id in ranked_ids
    ]
    successes = sorted(purchase_20, key=lambda row: row.directional_excess, reverse=True)[:10]
    failures = sorted(purchase_20, key=lambda row: row.directional_excess)[:10]
    generated = str(manifest.get("generated_at") or dt.datetime.now(dt.timezone.utc).isoformat())
    lines = [
        "# U.S. Congress Investment Ability Score - 1 Year",
        "",
        f"Generated: `{generated}`",
        "",
        "## Scope and coverage",
        "",
        f"- Transaction window: `{manifest['window_start']}` through `{manifest['window_end']}` (inclusive).",
        f"- House + Senate members with disclosures: **{manifest['member_count']}**.",
        f"- Raw disclosed line items: **{manifest['disclosure_count']}**; priceable decision events after collapsing duplicates: **{manifest['eligible_event_count']}**.",
        f"- Official ranking: **{len(ranked)}** members; observation only: **{len(observation)}**; unscored: **{len(unscored)}**.",
        f"- Price-resolved decision events: **{manifest['price_resolved_event_count']}**; missing/immature events are never filled with future data.",
        "",
        "A score is a percentile among members with at least five independently dated, settled purchase decisions. "
        "It is not an estimate of account return or proof that the member personally selected the trade.",
        "",
        "## Method",
        "",
        "1. Preserve every official House Clerk or Senate eFD document URL from the normalized public dataset.",
        "2. Keep listed stocks/ETFs with a resolvable ticker; exclude options, bonds, municipal securities, crypto, and exchanges.",
        "3. Collapse repeated line items to one member + ticker + transaction date + direction event.",
        "4. Enter at the next trading-session adjusted close, then settle at 20 and 60 further trading sessions.",
        "5. Compute stock return minus SPY return for purchases. Sales are reported separately as avoidance timing and do not raise the core score.",
        "6. Average all tickers on the same member-day before scoring, cap each day at +/-50 percentage points, shrink small samples toward zero, and combine 20D/60D evidence at 65%/35%.",
        "7. Rank only members with at least five settled purchase decision days. Amount-range midpoints are evidence fields, not score weights.",
        "",
        "## Top ranked members",
        "",
        "| Rank | Member | Chamber | Score | 20D days | 20D hit | Avg 20D excess | 60D days | 60D hit | Avg 60D excess | Confidence | Evidence |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
        *[_table_score_row(row) for row in top],
        "",
        "## Bottom of the qualified ranking",
        "",
        "| Rank | Member | Chamber | Score | 20D days | 20D hit | Avg 20D excess | 60D days | 60D hit | Avg 60D excess | Confidence | Evidence |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
        *[_table_score_row(row) for row in bottom],
        "",
        "## Strongest settled purchase cases",
        "",
        "| Member | Trade date | Event | Stock return | SPY return | Excess | Source |",
        "|---|---|---|---:|---:|---:|---|",
        *[_case_row(row) for row in successes],
        "",
        "## Weakest settled purchase cases",
        "",
        "| Member | Trade date | Event | Stock return | SPY return | Excess | Source |",
        "|---|---|---|---:|---:|---:|---|",
        *[_case_row(row) for row in failures],
        "",
        "## Interpretation limits",
        "",
        "- PTRs disclose value ranges, not exact quantities or execution prices; this report therefore does not claim precise portfolio P&L or annualized return.",
        "- Disclosures may represent a spouse, dependent, joint account, or delegated manager. The score belongs to the filing household, not necessarily the member's personal stock-picking.",
        "- The legal filing lag can be up to 45 days. Transaction-date ability and disclosure-date followability are different questions; this report measures the former.",
        "- A one-year sample is short. Percentile rank is relative to this qualified cohort and should be read with the confidence and decision-day columns.",
        "- Sales are ambiguous portfolio actions, so sale timing is exported but intentionally excluded from the primary score.",
        "",
        "The complete member table is in `congress_member_scores_1y.csv`; every settled event and original filing link is in `congress_trade_evidence_1y.csv`.",
        "",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def write_manifest(path: Path, manifest: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
