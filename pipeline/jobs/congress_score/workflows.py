"""End-to-end one-year Congress Score workflow."""
from __future__ import annotations

import concurrent.futures
import datetime as dt
import json
import sqlite3
from pathlib import Path

from ...domain.congress_score.reporting import (
    write_evidence_csv,
    write_manifest,
    write_markdown_report,
    write_scores_csv,
)
from ...domain.congress_score.scoring import (
    build_member_scores,
    build_trade_events,
    settle_trade_events,
)
from ...platforms.congress import DEFAULT_DATASET_URL, download_dataset, load_disclosures
from ...platforms.congress.disclosures import dataset_sha256
from ...platforms.market_data.price_history import fetch_yahoo_history


def _load_db_prices(
    db_path: Path,
    tickers: set[str],
    *,
    start_date: dt.date,
    end_date: dt.date,
) -> dict[str, list[tuple[dt.date, float]]]:
    if not db_path.exists():
        return {}
    prices: dict[str, list[tuple[dt.date, float]]] = {}
    with sqlite3.connect(db_path) as connection:
        table = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='price_daily'"
        ).fetchone()
        if table is None:
            return {}
        ticker_list = sorted(tickers)
        for offset in range(0, len(ticker_list), 500):
            batch = ticker_list[offset : offset + 500]
            placeholders = ",".join("?" for _ in batch)
            sql = (
                "SELECT ticker, day, COALESCE(adj_close, close) FROM price_daily "
                f"WHERE ticker IN ({placeholders}) AND day >= ? AND day <= ? "
                "AND COALESCE(adj_close, close) IS NOT NULL ORDER BY ticker, day"
            )
            params = [*batch, start_date.isoformat(), end_date.isoformat()]
            for ticker, day, close in connection.execute(sql, params):
                prices.setdefault(str(ticker), []).append((dt.date.fromisoformat(day), float(close)))
    return prices


def _load_price_cache(path: Path) -> dict[str, list[tuple[dt.date, float]]]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    prices: dict[str, list[tuple[dt.date, float]]] = {}
    for ticker, rows in (payload.get("prices") or {}).items():
        parsed = []
        for row in rows:
            try:
                parsed.append((dt.date.fromisoformat(row[0]), float(row[1])))
            except (IndexError, TypeError, ValueError):
                continue
        if parsed:
            prices[ticker] = parsed
    return prices


def _write_price_cache(path: Path, prices: dict[str, list[tuple[dt.date, float]]]) -> None:
    payload = {
        "updated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "prices": {
            ticker: [[day.isoformat(), round(close, 6)] for day, close in rows]
            for ticker, rows in sorted(prices.items())
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def _merge_prices(
    target: dict[str, list[tuple[dt.date, float]]],
    additions: dict[str, list[tuple[dt.date, float]]],
) -> None:
    for ticker, rows in additions.items():
        by_day = {day: close for day, close in target.get(ticker, [])}
        by_day.update({day: close for day, close in rows})
        target[ticker] = sorted(by_day.items())


def _fetch_missing_prices(
    tickers: list[str],
    *,
    start_date: dt.date,
    end_date: dt.date,
    workers: int,
) -> tuple[dict[str, list[tuple[dt.date, float]]], dict[str, str]]:
    fetched: dict[str, list[tuple[dt.date, float]]] = {}
    failures: dict[str, str] = {}

    def fetch(ticker: str) -> tuple[str, list[tuple[dt.date, float]]]:
        raw = fetch_yahoo_history(ticker, start_date, end_date + dt.timedelta(days=1))
        return ticker, [(dt.date.fromisoformat(row[1]), float(row[7])) for row in raw]

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        future_by_ticker = {executor.submit(fetch, ticker): ticker for ticker in tickers}
        completed = 0
        for future in concurrent.futures.as_completed(future_by_ticker):
            ticker = future_by_ticker[future]
            completed += 1
            try:
                _, rows = future.result()
                if rows:
                    fetched[ticker] = rows
                else:
                    failures[ticker] = "no price rows"
            except Exception as exc:  # network errors are coverage gaps, not fabricated returns
                failures[ticker] = f"{type(exc).__name__}: {exc}"
            if completed % 100 == 0 or completed == len(tickers):
                print(f"price fetch {completed}/{len(tickers)}; resolved={len(fetched)} failed={len(failures)}")
    return fetched, failures


def run_congress_score(
    *,
    as_of: str | None,
    lookback_days: int,
    output_dir: str,
    db_path: str,
    source_zip: str | None,
    source_url: str,
    refresh_source: bool,
    min_purchase_days: int,
    workers: int,
    refresh_prices: bool,
) -> dict[str, object]:
    end_date = (
        dt.date.fromisoformat(as_of)
        if as_of
        else dt.datetime.now(dt.timezone.utc).date() - dt.timedelta(days=1)
    )
    start_date = end_date - dt.timedelta(days=lookback_days - 1)
    output = Path(output_dir).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    dataset_path = Path(source_zip).expanduser().resolve() if source_zip else output / "cache" / "congress-trading-monitor.zip"
    if source_zip is None:
        download_dataset(source_url, dataset_path, force=refresh_source)
    if not dataset_path.exists():
        raise FileNotFoundError(dataset_path)

    members, disclosures = load_disclosures(
        dataset_path,
        start_date=start_date,
        end_date=end_date,
    )
    events = build_trade_events(disclosures)
    tickers = {event.ticker for event in events} | {"SPY"}
    cache_path = output / "cache" / "yahoo_prices_1y.json"
    prices = _load_db_prices(
        Path(db_path).expanduser().resolve(),
        tickers,
        start_date=start_date,
        end_date=end_date,
    )
    cached_prices = {} if refresh_prices else _load_price_cache(cache_path)
    _merge_prices(prices, cached_prices)
    missing = sorted(
        tickers if refresh_prices else (ticker for ticker in tickers if len(prices.get(ticker, [])) < 2)
    )
    print(
        f"congress disclosures={len(disclosures)} members={len(members)} "
        f"events={len(events)} tickers={len(tickers)} missing_prices={len(missing)}"
    )
    failures: dict[str, str] = {}
    if missing:
        fetched, failures = _fetch_missing_prices(
            missing,
            start_date=start_date,
            end_date=end_date,
            workers=workers,
        )
        _merge_prices(prices, fetched)
        _write_price_cache(cache_path, {**cached_prices, **fetched})
    outcomes = settle_trade_events(events, prices)
    scores = build_member_scores(
        members=members,
        disclosures=disclosures,
        events=events,
        outcomes=outcomes,
        min_purchase_days=min_purchase_days,
    )
    ranked = [score for score in scores if score.status == "ranked"]
    price_resolved_ids = {outcome.event_id for outcome in outcomes}
    manifest: dict[str, object] = {
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "window_start": start_date.isoformat(),
        "window_end": end_date.isoformat(),
        "lookback_days": lookback_days,
        "dataset_url": source_url,
        "dataset_path": str(dataset_path),
        "dataset_sha256": dataset_sha256(dataset_path),
        "dataset_latest_transaction_date": max((row.transaction_date for row in disclosures), default=None).isoformat() if disclosures else None,
        "dataset_latest_filing_date": max((row.filing_date for row in disclosures if row.filing_date), default=None).isoformat() if disclosures else None,
        "member_count": len(members),
        "disclosure_count": len(disclosures),
        "eligible_event_count": len(events),
        "price_resolved_event_count": len(price_resolved_ids),
        "outcome_count": len(outcomes),
        "ranked_member_count": len(ranked),
        "observation_member_count": sum(score.status == "observation" for score in scores),
        "unscored_member_count": sum(score.status == "unscored" for score in scores),
        "minimum_purchase_decision_days": min_purchase_days,
        "benchmark": "SPY",
        "horizons_trading_days": [20, 60],
        "entry_policy": "next trading-session adjusted close after transaction date",
        "score_policy": "purchase-only 65% 20D + 35% 60D, equal decision-day weight, small-sample shrinkage, qualified-cohort percentile",
        "price_sources": ["local price_daily", "Yahoo chart fallback"],
        "failed_price_tickers": failures,
    }
    write_scores_csv(output / "congress_member_scores_1y.csv", scores)
    write_evidence_csv(output / "congress_trade_evidence_1y.csv", outcomes, scores)
    write_manifest(output / "source_manifest.json", manifest)
    write_markdown_report(
        output / "congress_score_report_1y.md",
        scores=scores,
        outcomes=outcomes,
        manifest=manifest,
    )
    print(
        f"ranked={len(ranked)} observation={manifest['observation_member_count']} "
        f"unscored={manifest['unscored_member_count']} outcomes={len(outcomes)} output={output}"
    )
    return manifest
