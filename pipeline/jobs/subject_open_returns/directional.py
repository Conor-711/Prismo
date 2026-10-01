"""Existing post-disclosure directional win rate over the three-year source window."""

from __future__ import annotations

import sqlite3
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from itertools import pairwise
from pathlib import Path

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.domain.investor_ability.backtest import NEW_YORK, PublicSignal
from pipeline.domain.investor_ability.directional_win_rate import (
    latest_directional_win_rate,
)
from pipeline.domain.smart_voice.portfolio_backtest_engine import (
    PriceBar,
    PriceSeries,
    make_price_series,
)
from pipeline.jobs.congress_capture.cusip_tickers import tickers as mapped_tickers
from pipeline.jobs.subject_open_returns.identities import app_politician_ids
from pipeline.jobs.subject_open_returns.reports import reports_by_cik
from pipeline.platforms.congress.disclosures import load_disclosures
from pipeline.platforms.institutional_holdings.sec_13f import changes
from pipeline.platforms.market_data.price_history import fetch_yahoo_history


def _public_time(day: date) -> datetime:
    return datetime.combine(day, time(23, 59, 59), NEW_YORK)


def collect_signals(
    archive: Path, history: Path, since: date, as_of: date, *, subjects: tuple | None = None
) -> tuple[dict[str, list[PublicSignal]], dict[str, str], dict]:
    signals: dict[str, list[PublicSignal]] = defaultdict(list)
    names = {}
    excluded: Counter[str] = Counter()
    members, disclosures = (load_disclosures(archive, start_date=since, end_date=as_of)
                            if subjects is None else ([], []))
    identities = app_politician_ids(members, disclosures)
    for member in members:
        if subject_key := identities.get(member.member_id):
            names[f"politician:{subject_key}"] = member.name
    for item in disclosures:
        subject_key = identities.get(item.member.member_id)
        if not subject_key:
            excluded["congress_unpublished_identity"] += 1
            continue
        if item.asset_type not in {"ST", "Stock", "ETF"} or not item.ticker:
            excluded["congress_non_equity"] += 1
            continue
        if not item.filing_date or item.filing_date > as_of or not item.evidence_url:
            excluded["congress_no_public_filing"] += 1
            continue
        action = item.transaction_type
        if action == "Purchase":
            direction = "bull"
        elif action in {"Sale (Full)", "Sale (Partial)"}:
            direction = "bear"
        else:
            excluded["congress_non_directional"] += 1
            continue
        subject_id = f"politician:{subject_key}"
        signals[subject_id].append(
            PublicSignal(
                actor_id=subject_id,
                source="congress",
                event_id=item.trade_id,
                ticker=item.ticker,
                published_at=_public_time(item.filing_date),
                direction=direction,
                evidence_url=item.evidence_url,
            )
        )

    mapping = mapped_tickers()
    selected = SUBJECTS if subjects is None else subjects
    by_cik = {
        cik: reports_by_cik(history, cik, since, as_of)
        for cik in {subject.filer_cik for subject in selected}
    }
    for subject in selected:
        subject_id = f"{subject.kind}:{subject.id}"
        names[subject_id] = subject.title
        reports, errors = by_cik[subject.filer_cik]
        excluded["13f_report_errors"] += len(errors)
        for previous, current in pairwise(reports):
            period = date.fromisoformat(current["periodOfReport"])
            prior_period = date.fromisoformat(previous["periodOfReport"])
            if not 75 <= (period - prior_period).days <= 105 or any(
                report["reportType"] != "13F HOLDINGS REPORT"
                for report in (previous, current)
            ):
                excluded["13f_non_comparable_quarter"] += 1
                continue
            public = date.fromisoformat(current["publicAt"])
            if public > as_of:
                continue
            delta_by_cusip: dict[str, Decimal] = defaultdict(Decimal)
            for row in changes(current["holdings"], previous["holdings"]):
                if row.get("shareType") == "SH" and not row.get("option"):
                    delta_by_cusip[row["cusip"]] += Decimal(row["reportedShareChange"])
            for cusip, delta in delta_by_cusip.items():
                if not delta:
                    continue
                ticker = mapping.get(cusip)
                if not ticker:
                    excluded["13f_unmapped_change"] += 1
                    continue
                signals[subject_id].append(
                    PublicSignal(
                        actor_id=subject_id,
                        source=subject.kind,
                        event_id=f"{current['accession']}:{cusip}",
                        ticker=ticker,
                        published_at=_public_time(public),
                        direction="bull" if delta > 0 else "bear",
                        evidence_url=current["filingUrl"],
                    )
                )
    return signals, names, dict(excluded)


def _price_cache_schema(connection: sqlite3.Connection) -> None:
    connection.execute(
        "CREATE TABLE IF NOT EXISTS price_daily (ticker TEXT NOT NULL, day TEXT NOT NULL, "
        "open REAL NOT NULL, close REAL NOT NULL, PRIMARY KEY (ticker, day))"
    )
    connection.execute(
        "CREATE TABLE IF NOT EXISTS retrieved (ticker TEXT PRIMARY KEY, as_of TEXT NOT NULL)"
    )


def fill_price_cache(
    path: Path, tickers: set[str], start: date, as_of: date, workers: int
) -> dict[str, str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    failures = {}
    with sqlite3.connect(path) as connection:
        _price_cache_schema(connection)
        done = {
            ticker
            for ticker, day in connection.execute("SELECT ticker,as_of FROM retrieved")
            if day == as_of.isoformat()
        }
        needed = sorted((tickers | {"SPY"}) - done)

        def fetch(ticker: str) -> tuple[str, list[tuple]]:
            return ticker, fetch_yahoo_history(ticker, start, as_of + timedelta(days=1))

        with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
            futures = {executor.submit(fetch, ticker): ticker for ticker in needed}
            for index, future in enumerate(as_completed(futures), 1):
                ticker = futures[future]
                try:
                    _, raw = future.result()
                    if raw:
                        rows = [
                            (ticker, row[1], row[2] * row[7] / row[5], row[7])
                            for row in raw
                            if row[2] > 0 and row[5] > 0 and row[7] > 0
                        ]
                        connection.executemany(
                            "INSERT OR REPLACE INTO price_daily VALUES (?,?,?,?)", rows
                        )
                        connection.execute(
                            "INSERT OR REPLACE INTO retrieved VALUES (?,?)",
                            (ticker, as_of.isoformat()),
                        )
                    else:
                        failures[ticker] = "no_rows"
                except (OSError, ValueError, TypeError, IndexError) as error:
                    failures[ticker] = f"{type(error).__name__}: {error}"
                if index % 50 == 0 or index == len(needed):
                    connection.commit()
                    print(
                        f"Directional OHLC {index}/{len(needed)}; failed={len(failures)}",
                        flush=True,
                    )
    return failures


def _series(rows: list[tuple]) -> PriceSeries:
    return make_price_series(
        PriceBar(str(day), float(open_), float(close))
        for day, open_, close in rows
        if open_ > 0 and close > 0
    )


def read_prices(
    cache: Path, content_db: Path, tickers: set[str], start: date, as_of: date
) -> dict[str, PriceSeries]:
    output = {}
    with (
        sqlite3.connect(cache) as historical,
        sqlite3.connect(f"file:{content_db.resolve()}?mode=ro", uri=True) as current,
    ):
        for ticker in sorted(tickers | {"SPY"}):
            rows = {
                day: (day, open_, close)
                for day, open_, close in historical.execute(
                    "SELECT day,open,close FROM price_daily WHERE ticker=? AND day BETWEEN ? AND ?",
                    (ticker, start.isoformat(), as_of.isoformat()),
                )
            }
            for day, open_, close, adjusted in current.execute(
                "SELECT day,open,close,adj_close FROM price_daily WHERE ticker=? AND day BETWEEN ? AND ?",
                (ticker, start.isoformat(), as_of.isoformat()),
            ):
                if (
                    day not in rows
                    and open_
                    and close
                    and adjusted
                    and open_ > 0
                    and close > 0
                    and adjusted > 0
                ):
                    rows[day] = (day, open_ * adjusted / close, adjusted)
            if rows:
                output[ticker] = _series(list(rows.values()))
    return output


def calculate(
    signals: dict[str, list[PublicSignal]], prices: dict[str, PriceSeries], as_of: date
) -> dict[str, dict]:
    benchmark = prices.get("SPY")
    if benchmark is None:
        raise ValueError("SPY market calendar unavailable")
    results = {}
    for subject_id, rows in signals.items():
        metric = latest_directional_win_rate(rows, prices, benchmark, as_of=as_of)
        decided = metric.wins + metric.losses
        results[subject_id] = {
            "directional_win_rate_pct": metric.wins * 100 / decided if decided else None,
            "directional_wins": metric.wins,
            "directional_losses": metric.losses,
            "directional_flat": metric.flat,
            "directional_observations": metric.observations,
            "directional_excluded": metric.excluded,
        }
    return results
