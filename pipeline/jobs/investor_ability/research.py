"""Build a local, non-publishable one-year follow-ability research snapshot."""

from __future__ import annotations

import json
import sqlite3
from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.domain.investor_ability.backtest import PublicSignal, replay
from pipeline.domain.investor_ability.directional_win_rate import (
    latest_directional_win_rate,
)
from pipeline.domain.investor_ability.scoring import (
    VERSION,
    FollowPerformance,
    research_score_value,
    score_follow_performance,
)
from pipeline.domain.smart_voice.portfolio_backtest import _load_price_book
from pipeline.jobs.congress_capture.cusip_tickers import tickers as cached_cusip_tickers

ALLOWED_ACTIONS = (
    "open_call",
    "reinforce_call",
    "reverse_call",
    "close_prior_call",
    "invalidate_prior_call",
)
NEW_YORK = ZoneInfo("America/New_York")


def _parse_public_time(value: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def _read_signals(
    connection: sqlite3.Connection,
    start: date,
    end: date,
) -> tuple[dict[tuple[str, str], list[PublicSignal]], Counter[str]]:
    allowed_tickers = {
        str(row[0]).upper()
        for row in connection.execute(
            "SELECT ticker FROM ticker_meta WHERE market='us'"
        )
    }
    grouped: dict[tuple[str, str], list[PublicSignal]] = defaultdict(list)
    exclusions: Counter[str] = Counter()
    rows = connection.execute(
        """SELECT c.source,c.investor_id,c.candidate_id,upper(c.ticker),c.created_at,
                  c.direction,c.lifecycle_action,COALESCE(k.url,'')
             FROM sv_call c
        LEFT JOIN sv_call_candidate k ON k.candidate_id=c.candidate_id
            WHERE c.created_at>=? AND c.created_at<?
              AND c.is_actionable_call=1 AND c.direction IN ('bull','bear')
              AND c.source IN ('x','youtube','reddit','xueqiu')
            ORDER BY c.source,c.investor_id,c.created_at,c.candidate_id""",
        (start.isoformat(), (end + timedelta(days=1)).isoformat()),
    )
    for source, actor, event_id, ticker, created_at, direction, action, url in rows:
        if not actor or not url:
            exclusions["missing_actor_or_evidence"] += 1
            continue
        if ticker not in allowed_tickers:
            exclusions["unsupported_asset"] += 1
            continue
        if action not in ALLOWED_ACTIONS:
            exclusions["non_entry_lifecycle"] += 1
            continue
        published = _parse_public_time(str(created_at or ""))
        if published is None:
            exclusions["missing_explicit_timezone"] += 1
            continue
        grouped[(str(source), str(actor))].append(
            PublicSignal(
                actor_id=str(actor),
                source=str(source),
                event_id=str(event_id),
                ticker=str(ticker),
                published_at=published,
                direction=str(direction),
                evidence_url=str(url),
            )
        )
    return grouped, exclusions


def _read_congress_signals(
    file_path: Path,
    allowed_tickers: set[str],
    start: date,
    end: date,
) -> tuple[dict[tuple[str, str], list[PublicSignal]], dict[str, str], Counter[str]]:
    grouped: dict[tuple[str, str], list[PublicSignal]] = defaultdict(list)
    names: dict[str, str] = {}
    exclusions: Counter[str] = Counter()
    if not file_path.exists():
        exclusions["congress_file_missing"] += 1
        return grouped, names, exclusions
    with file_path.open() as handle:
        rows = [json.loads(line) for line in handle]
    known_ids = {
        (
            str(row.get("chamber") or ""),
            str(row.get("member_name") or "").casefold(),
        ): str(row["member_id"])
        for row in rows
        if row.get("member_id") and row.get("member_name")
    }
    for row in rows:
        actor = str(
            row.get("member_id")
            or known_ids.get(
                (
                    str(row.get("chamber") or ""),
                    str(row.get("member_name") or "").casefold(),
                ),
                "",
            )
        ).strip()
        if not actor:
            actor = "name:" + "-".join(
                str(row.get("member_name") or "").lower().split()
            )
        if actor == "house_johnjmr_mcguire_iii":
            actor = "house_john_mcguire"
        if actor == "name:":
            exclusions["congress_missing_actor"] += 1
            continue
        names[actor] = "John McGuire" if actor == "house_john_mcguire" else str(row.get("member_name") or actor)
        grouped[("congress", actor)]
        ticker = str(row.get("ticker") or "").upper()
        if ticker not in allowed_tickers:
            exclusions["congress_unsupported_asset"] += 1
            continue
        action = str(row.get("action") or "").lower()
        if action in {"purchase", "p"}:
            direction = "bull"
        elif action.startswith("sale") or action in {"s", "s (partial)"}:
            direction = "bear"
        else:
            exclusions["congress_non_market_action"] += 1
            continue
        filing = str(row.get("filing_date") or "")
        try:
            public_day = date.fromisoformat(filing)
        except ValueError:
            exclusions["congress_missing_filing_date"] += 1
            continue
        if not start <= public_day <= end:
            exclusions["congress_outside_window"] += 1
            continue
        evidence = str(row.get("evidence_url") or "")
        if not evidence:
            exclusions["congress_missing_evidence"] += 1
            continue
        # Only a filing date is available, so assume the last second of
        # that date locally. This is a research approximation, not audit.
        published = datetime.combine(public_day, time(23, 59, 59), NEW_YORK)
        grouped[("congress", actor)].append(
            PublicSignal(
                actor_id=actor,
                source="congress",
                event_id=str(row.get("trade_id") or ""),
                ticker=ticker,
                published_at=published,
                direction=direction,
                evidence_url=evidence,
            )
        )
    return grouped, names, exclusions


def _read_13f_signals(
    directory: Path,
    start: date,
    end: date,
) -> tuple[
    dict[tuple[str, str], list[PublicSignal]],
    dict[tuple[str, str], list[PublicSignal]],
    dict[tuple[str, str], dict[str, str | None]],
    Counter[str],
]:
    """Follow the five largest disclosed long holdings, after filing publication.

    A 13F position is not an inferred trade. The reported value only fixes a
    pre-committed selection order; the replay always buys after the filing.
    """
    grouped: dict[tuple[str, str], list[PublicSignal]] = {}
    directional: dict[tuple[str, str], list[PublicSignal]] = {}
    metadata: dict[tuple[str, str], dict[str, str | None]] = {}
    exclusions: Counter[str] = Counter()
    cusip_tickers = cached_cusip_tickers()
    for subject in SUBJECTS:
        key = (subject.kind, subject.id)
        grouped[key] = []
        directional[key] = []
        metadata[key] = {
            "disclosure_status": "snapshot_missing",
            "report_period": None,
            "filing_date": None,
            "filing_url": None,
            "filing_coverage": None,
        }
        path = directory / f"{subject.id}.json"
        if not path.is_file():
            exclusions["13f_snapshot_missing"] += 1
            continue
        filing = json.loads(path.read_text())
        if (
            filing.get("source") != "SEC EDGAR Form 13F"
            or filing.get("subjectId") != subject.id
            or filing.get("kind") != subject.kind
            or filing.get("filerCik") != subject.filer_cik
        ):
            exclusions["13f_identity_mismatch"] += 1
            metadata[key]["disclosure_status"] = "identity_mismatch"
            continue
        metadata[key] = {
            "disclosure_status": str(filing.get("disclosureStatus") or "unknown"),
            "report_period": str(filing.get("periodOfReport") or "") or None,
            "filing_date": str(filing.get("filedAt") or "")[:10] or None,
            "filing_url": str(filing.get("filingUrl") or "") or None,
            "filing_coverage": str(filing.get("coverage") or "") or None,
        }
        url = str(filing.get("filingUrl") or "")
        if not url.startswith("https://www.sec.gov/Archives/"):
            exclusions["13f_missing_evidence"] += 1
            continue
        try:
            public_day = date.fromisoformat(str(filing.get("filedAt") or "")[:10])
            report_day = date.fromisoformat(str(filing.get("periodOfReport") or ""))
        except ValueError:
            exclusions["13f_missing_filing_date"] += 1
            continue
        if report_day > public_day or not start <= public_day <= end:
            exclusions["13f_outside_window"] += 1
            continue
        if filing.get("coverage") != "complete":
            exclusions["13f_partial_report"] += 1
        values: Counter[str] = Counter()
        for row in filing.get("holdings", []):
            if row.get("shareType") != "SH" or row.get("option"):
                continue
            cusip = str(row.get("cusip") or "").upper()
            if cusip:
                values[cusip] += int(row.get("reportedValueUsd") or 0)
        ranked_cusips = sorted(values, key=lambda cusip: (-values[cusip], cusip))
        seen_tickers: set[str] = set()
        published = datetime.combine(public_day, time(23, 59, 59), NEW_YORK)
        for cusip in ranked_cusips[:5]:
            ticker = cusip_tickers.get(cusip)
            if not ticker:
                exclusions["13f_unmapped_cusip"] += 1
                continue
            if ticker in seen_tickers:
                exclusions["13f_duplicate_ticker"] += 1
                continue
            seen_tickers.add(ticker)
            grouped[key].append(PublicSignal(
                actor_id=subject.id,
                source=subject.kind,
                event_id=f"{filing.get('accession')}:{cusip}",
                ticker=ticker,
                published_at=published,
                direction="bull",
                evidence_url=url,
            ))
        changes: defaultdict[str, Decimal] = defaultdict(Decimal)
        for row in filing.get("changes", []):
            if row.get("shareType") != "SH" or row.get("option"):
                continue
            cusip = str(row.get("cusip") or "").upper()
            if not cusip:
                continue
            try:
                changes[cusip] += Decimal(str(row.get("reportedShareChange")))
            except InvalidOperation:
                exclusions["13f_invalid_share_change"] += 1
        for cusip, delta in sorted(changes.items()):
            if delta == 0:
                continue
            ticker = cusip_tickers.get(cusip)
            if not ticker:
                exclusions["13f_unmapped_change_cusip"] += 1
                continue
            directional[key].append(PublicSignal(
                actor_id=subject.id,
                source=subject.kind,
                event_id=f"{filing.get('accession')}:change:{cusip}",
                ticker=ticker,
                published_at=published,
                direction="bull" if delta > 0 else "bear",
                evidence_url=url,
            ))
    return grouped, directional, metadata, exclusions


def build_research_snapshot(
    db_path: str | Path,
    output_dir: str | Path,
    congress_file: str | Path | None = None,
    institutional_dir: str | Path | None = None,
) -> dict[str, Any]:
    """Read a local immutable SQLite snapshot; do not mutate app or cloud data."""
    uri = f"file:{Path(db_path).resolve()}?mode=ro&immutable=1"
    connection = sqlite3.connect(uri, uri=True)
    try:
        connection.row_factory = sqlite3.Row
        prices = _load_price_book(connection)
        benchmark = prices.get("SPY")
        if benchmark is None:
            raise RuntimeError("SPY daily price history is required")
        end = date.fromisoformat(benchmark.days[-1])
        start = end - timedelta(days=364)
        signals_by_actor, input_exclusions = _read_signals(connection, start, end)
        allowed_tickers = set(prices)
        platform_names = {
            (str(row[0]), str(row[1])): str(row[2] or row[3] or row[1])
            for row in connection.execute(
                "SELECT source,investor_id,name,handle FROM sv_investor_score"
            )
        }
    finally:
        connection.close()

    congress_path = (
        Path(congress_file)
        if congress_file
        else Path(db_path).resolve().parent
        / "exports"
        / "congress"
        / "congress_trades_1y_research.jsonl"
    )
    congress_signals, congress_names, congress_exclusions = _read_congress_signals(
        congress_path,
        allowed_tickers,
        start,
        end,
    )
    signals_by_actor.update(congress_signals)
    input_exclusions.update(congress_exclusions)
    holdings_path = (
        Path(institutional_dir)
        if institutional_dir
        else Path(db_path).resolve().parent / "exports" / "institutional_holdings"
    )
    holdings_signals, holdings_directions, holdings_metadata, holdings_exclusions = _read_13f_signals(
        holdings_path, start, end
    )
    signals_by_actor.update(holdings_signals)
    input_exclusions.update(holdings_exclusions)
    holdings_subjects = {(subject.kind, subject.id): subject for subject in SUBJECTS}

    observed = (end - start).days + 1
    results: list[dict[str, Any]] = []
    replay_exclusions: Counter[str] = Counter()
    for (source, actor_id), signals in sorted(signals_by_actor.items()):
        outcome = replay(signals, prices, benchmark, start=start, end=end)
        replay_exclusions.update(outcome.excluded)
        actor_kind = (
            "politician" if source == "congress"
            else source if source in {"celebrity", "institution"}
            else "platform"
        )
        performance = FollowPerformance(
            actor_id=f"{source}:{actor_id}",
            actor_kind=actor_kind,
            as_of=end.isoformat(),
            observed_calendar_days=observed,
            independent_decision_days=outcome.independent_decision_days,
            settled_decisions=outcome.settled_decisions,
            executable_decisions=outcome.executable_decisions,
            priced_decisions=outcome.priced_decisions,
            annualized_net_return=outcome.annualized_net_return,
            annualized_matched_benchmark_return=outcome.annualized_benchmark_return,
            annualized_volatility=outcome.annualized_volatility,
            max_drawdown=outcome.max_drawdown,
            source_verified=False,
            point_in_time_verified=False,
            execution_costs_included=True,
            benchmark_aligned=True,
        )
        score = score_follow_performance(performance)
        directional_result = (
            latest_directional_win_rate(
                holdings_directions[(source, actor_id)]
                if source in {"celebrity", "institution"} else signals,
                prices,
                benchmark,
                as_of=end,
            )
            if actor_kind in {"politician", "celebrity", "institution"}
            else None
        )
        coverage = score.priced_coverage
        has_result = outcome.settled_decisions > 0 and outcome.priced_decisions > 0
        directional_available = directional_result is not None and directional_result.rate is not None
        # Sparse samples are still observable research results; publication
        # thresholds remain enforced separately by score_follow_performance.
        cohort_ready = has_result
        sensitivity = (
            {
                "10bps": replay(
                    signals,
                    prices,
                    benchmark,
                    start=start,
                    end=end,
                    round_trip_cost_bps=10,
                ).follow_return,
                "50bps": replay(
                    signals,
                    prices,
                    benchmark,
                    start=start,
                    end=end,
                    round_trip_cost_bps=50,
                ).follow_return,
            }
            if cohort_ready and outcome.settled_decisions >= 10
            else None
        )
        results.append(
            {
                "actor_id": performance.actor_id,
                "actor_kind": actor_kind,
                "source": source,
                "name": (
                    congress_names.get(actor_id, actor_id)
                    if source == "congress" else
                    holdings_subjects[(source, actor_id)].title
                    if (source, actor_id) in holdings_subjects else
                    platform_names.get((source, actor_id), actor_id)
                ),
                "filer_cik": holdings_subjects[(source, actor_id)].filer_cik
                if (source, actor_id) in holdings_subjects else None,
                "signal_basis": "disclosed_13f_holdings"
                if (source, actor_id) in holdings_subjects else
                "published_congress_filing" if source == "congress" else
                "public_opinion",
                "signal_count": len(signals),
                "directional_signal_count": len(holdings_directions[(source, actor_id)])
                if source in {"celebrity", "institution"} else len(signals),
                "attribution": holdings_subjects[(source, actor_id)].attribution
                if (source, actor_id) in holdings_subjects else None,
                "filing": holdings_metadata.get((source, actor_id)),
                "win_rate": directional_result.rate if directional_available else
                outcome.win_rate if cohort_ready else None,
                "win_rate_method": "latest_directional_price"
                if directional_available else "closed_trade_30d",
                "win_rate_basis": "13f_reported_share_change_proxy"
                if directional_available and source in {"celebrity", "institution"} else
                "disclosed_purchase_sale" if directional_available and source == "congress" else
                "public_opinion_follow_trade" if source not in {"celebrity", "institution"} else
                "disclosed_13f_follow_trade",
                "win_rate_as_of": directional_result.as_of if directional_available else None,
                "win_rate_wins": directional_result.wins if directional_available else
                sum(trade.net_return > 0 for trade in outcome.trades) if cohort_ready else None,
                "win_rate_losses": directional_result.losses if directional_available else
                sum(trade.net_return <= 0 for trade in outcome.trades) if cohort_ready else None,
                "win_rate_flat": directional_result.flat if directional_available else None,
                "win_rate_observations": directional_result.observations
                if directional_available else outcome.settled_decisions if cohort_ready else None,
                "win_rate_excluded": directional_result.excluded
                if directional_result else None,
                "closed_trade_win_rate": outcome.win_rate if cohort_ready else None,
                "follow_return": outcome.follow_return if cohort_ready else None,
                "directional_follow_return_proxy": directional_result.mean_directional_return
                if directional_available else None,
                "directional_follow_return_policy": "30d_open_or_asof_close"
                if directional_available else None,
                "follow_return_cost_sensitivity": sensitivity,
                "research_score": research_score_value(performance)
                if cohort_ready
                else None,
                "published_score": score.value,
                "status": "research_unverified" if cohort_ready else
                "directional_only" if directional_result and directional_result.rate is not None else
                "no_observable_trade" if not has_result else "insufficient_coverage",
                "audit_status": score.status,
                "settled_decisions": outcome.settled_decisions,
                "independent_decision_days": outcome.independent_decision_days,
                "executable_decisions": outcome.executable_decisions,
                "priced_decisions": outcome.priced_decisions,
                "price_coverage": coverage,
                "matched_benchmark_return": outcome.annualized_benchmark_return,
                "volatility": outcome.annualized_volatility,
                "max_drawdown": outcome.max_drawdown,
                "excluded": outcome.excluded,
            }
        )
    results.sort(
        key=lambda row: (
            row["research_score"] is None,
            -(row["research_score"] or 0.0),
            row["actor_id"],
        )
    )
    summary: dict[str, Any] = {
        "version": VERSION,
        "research_policy": "disclosure-current-direction-v3",
        "stage": "local_research_only",
        "window_start": start.isoformat(),
        "window_end": end.isoformat(),
        "observed_calendar_days": observed,
        "subject_count": len(results),
        "research_eligible_count": sum(
            row["research_score"] is not None for row in results
        ),
        "research_eligible_by_kind": dict(
            Counter(
                row["actor_kind"]
                for row in results
                if row["research_score"] is not None
            )
        ),
        "win_rate_available_by_kind": dict(Counter(
            row["actor_kind"] for row in results if row["win_rate"] is not None
        )),
        "subject_count_by_kind": dict(Counter(row["actor_kind"] for row in results)),
        "published_score_count": 0,
        "input_exclusions": dict(input_exclusions),
        "replay_exclusions": dict(replay_exclusions),
        "excluded_kinds": ["insider"],
        "caveats": [
            "Signals have not been individually verified against original posts.",
            "Daily prices and a fixed 25-bp round-trip estimate are not a verified execution audit.",
            "Only US stock/ETF long positions are replayed; unverified short/crypto routes are excluded.",
            "Read-only immutable SQLite may omit uncheckpointed WAL changes.",
            "Congress filings have dates but not verified public timestamps; next-day execution is only a conservative research approximation.",
            "Unreviewed congressional filing extraction and household ownership are not audited.",
            "13F positions are followed only after filing publication; they are not confirmed manager or celebrity trades.",
            "13F directional win rates use reported share-count changes, not confirmed buys or sells.",
            "Directional win rates compare next executable open with the latest daily close; flat moves remain in the denominator.",
            "Partial 13F reports cover only the disclosed slice, not the manager's full portfolio.",
            "Celebrity and institution identities sharing a filer CIK replay the same filing and are not independent evidence.",
            "Missing snapshots, prices or settled trades produce null metrics, not zero returns or fabricated scores.",
            "Results are hypothetical, not actual user returns or publishable Scores.",
        ],
    }
    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
    )
    (destination / "subjects.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n"
    )
    return summary
