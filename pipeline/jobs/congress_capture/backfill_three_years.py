"""Resumable three-year congressional and 13F backfill for the subject feed."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import gzip
import json
import os
from pathlib import Path
import sqlite3
import tempfile

from dotenv import dotenv_values
import psycopg

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.jobs.congress_capture.cusip_tickers import tickers as cached_tickers
from pipeline.jobs.congress_capture.ios_feed import attach_prices, build_feed
from pipeline.jobs.congress_capture.refresh_cycle import (
    ROOT, congress_rows, download_congress_dataset, preserve_newer_prices,
    publish_if_changed, retain_unavailable_sources, three_year_start,
)
from pipeline.jobs.congress_capture.research_feed import build_research_feed, require_institutional_coverage
from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot
from pipeline.platforms.congress.disclosures import load_disclosures
from pipeline.platforms.institutional_holdings.sec_13f import SEC13FClient, FilingError, changes


DEFAULT_HISTORY = ROOT / "data/exports/institutional_holdings/history"
DEFAULT_REPORT = ROOT / "data/reports/subject-activity-three-year.json"
DEFAULT_CONGRESS_ARCHIVE = ROOT / "data/exports/congress/congress-trading-monitor-current.zip"


def quarter_before(day: date) -> date:
    month = ((day.month - 1) // 3) * 3 + 1
    return date(day.year, month, 1) - timedelta(days=1)


def checked_report(client: SEC13FClient, row: dict, cache_dir: Path) -> dict:
    path = cache_dir / str(row["cik"]) / (row["accession"] + ".json.gz")
    if path.is_file():
        with gzip.open(path, "rt", encoding="utf-8") as handle:
            report = json.load(handle)
        if all(report.get(key) == row[key] for key in ("cik", "accession", "periodOfReport", "filedAt")):
            return report
        raise FilingError("cached_report_identity_mismatch")
    report = client.report(row, allow_new_holdings=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.gz.tmp")
    try:
        with gzip.open(temporary, "wt", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, separators=(",", ":"))
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return report


def combine_quarter(reports: list[dict]) -> tuple[dict, list[dict]]:
    """Restatements replace the base; NEW HOLDINGS amendments supplement it."""
    ordered = sorted(reports, key=lambda item: (item["filedAt"], item["accession"]))
    bases = [item for item in ordered if item["form"] == "13F-HR"
             or item.get("amendmentType") == "RESTATEMENT"]
    if not bases or len({item["periodOfReport"] for item in ordered}) != 1:
        raise FilingError("incomplete_quarter_amendment_chain")
    base = bases[-1]
    supplements = [item for item in ordered if item.get("amendmentType") == "NEW HOLDINGS"
                   and (item["filedAt"], item["accession"]) > (base["filedAt"], base["accession"])]
    def identity(row: dict) -> tuple:
        return tuple(row.get(key) for key in ("cusip", "securityClass", "option", "shareType", "discretion"))
    combined_by_key = {identity(row): dict(row) for row in base["holdings"]}
    for item in supplements:
        for row in item["holdings"]:
            key = identity(row)
            previous = combined_by_key.get(key)
            if previous is None:
                combined_by_key[key] = dict(row)
            elif previous["issuer"].casefold() != row["issuer"].casefold():
                raise FilingError("supplemental_holding_identity_conflict")
            else:
                previous["reportedShares"] = str(Decimal(previous["reportedShares"])
                                                 + Decimal(row["reportedShares"]))
                previous["reportedValueUsd"] += row["reportedValueUsd"]
    return {**base, "holdings": list(combined_by_key.values())}, [base, *supplements]


def historical_filing(subject, report: dict, previous: dict | None) -> dict:
    current_period = date.fromisoformat(report["periodOfReport"])
    comparable = (previous is not None
                  and 75 <= (current_period - date.fromisoformat(previous["periodOfReport"])).days <= 105
                  and all(item["reportType"] == "13F HOLDINGS REPORT" for item in (report, previous)))
    return {
        "source": "SEC EDGAR Form 13F", "subjectId": subject.id, "title": subject.title,
        "kind": subject.kind, "attribution": subject.attribution,
        "periodOfReport": report["periodOfReport"], "filedAt": report["filedAt"],
        "filingUrl": report["filingUrl"], "accession": report["accession"],
        "disclosureStatus": "historical_quarterly_report",
        "holdings": report["holdings"],
        "changes": changes(report["holdings"], previous["holdings"]) if comparable else [],
    }


def backfill(*, database_url: str, contact: str, today: date, cache_dir: Path,
             dry_run: bool = True, price_db: Path | None = None,
             congress_archive: Path = DEFAULT_CONGRESS_ARCHIVE) -> dict:
    since = three_year_start(today)
    # One earlier quarter is used only as the baseline for share-change classification.
    baseline = quarter_before(since)
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        row = connection.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                                 "WHERE channel='production'").fetchone()
        if not row:
            raise RuntimeError("No production subject snapshot exists")
        live = row[0]

    with tempfile.TemporaryDirectory(prefix="bsmart-three-year-") as directory:
        archive = Path(directory) / "congress.zip"
        download_congress_dataset(archive)
        members, disclosures = load_disclosures(archive, start_date=since, end_date=today)
        years = Counter(item.transaction_date.year for item in disclosures)
        if len(disclosures) < 12_000 or len(members) < 120 or any(year not in years for year in range(since.year, today.year + 1)):
            raise ValueError("Three-year congressional source coverage is incomplete")
        congress_archive.parent.mkdir(parents=True, exist_ok=True)
        temporary_archive = congress_archive.with_suffix(".zip.tmp")
        try:
            temporary_archive.write_bytes(archive.read_bytes())
            temporary_archive.replace(congress_archive)
        finally:
            temporary_archive.unlink(missing_ok=True)

        client = SEC13FClient(contact, request_limit=6_000)
        by_cik: dict[int, list[tuple[dict, list[dict]]]] = {}
        errors: list[dict] = []
        for subject in SUBJECTS:
            if subject.filer_cik in by_cik:
                continue
            cik = subject.filer_cik
            try:
                rows = client.submissions(cik, earliest_period=baseline.isoformat())
                selected = [row for row in rows if row["periodOfReport"] >= baseline.isoformat()
                            and row["form"].startswith("13F-HR")]
                if not selected:
                    raise FilingError("no_three_year_holdings_reports")
            except FilingError as error:
                by_cik[cik] = []
                errors.append({"cik": cik, "period": None, "error": str(error)})
                continue
            by_period: dict[str, list[dict]] = {}
            for row in selected:
                by_period.setdefault(row["periodOfReport"], []).append(row)
            verified = []
            for period, period_rows in sorted(by_period.items()):
                try:
                    reports = [checked_report(client, row, cache_dir) for row in period_rows]
                    verified.append(combine_quarter(reports))
                except (FilingError, OSError, ValueError, KeyError, TypeError) as error:
                    errors.append({"cik": cik, "period": period, "error": str(error)})
            by_cik[cik] = verified

        filings = []
        coverage = {}
        for subject in SUBJECTS:
            history = by_cik[subject.filer_cik]
            coverage[subject.id] = sorted(report["periodOfReport"] for report, _ in history
                                          if report["periodOfReport"] >= since.isoformat())
            for index, (report, pieces) in enumerate(history):
                if report["periodOfReport"] < since.isoformat():
                    continue
                previous = history[index - 1][0] if index else None
                if report["managerName"].casefold() != subject.filer_name.casefold() and index == len(history) - 1:
                    errors.append({"cik": subject.filer_cik, "period": report["periodOfReport"],
                                   "error": "reporting_manager_mismatch"})
                    continue
                filings.append(historical_filing(subject, pieces[0], previous))
                for supplement in pieces[1:]:
                    filing = historical_filing(subject, supplement, None)
                    filing["changes"] = [{"cusip": row["cusip"], "securityClass": row["securityClass"],
                                          "option": row["option"], "shareType": row["shareType"],
                                          "reportedShareChange": row["reportedShares"],
                                          "classification": "new_reported_position"}
                                         for row in supplement["holdings"]]
                    filings.append(filing)
        institutional = build_feed({"source": "disclosed_capitol", "trades": []},
                                   institutional_snapshots=filings,
                                   cusip_tickers=cached_tickers())
        candidate, congress_report = build_research_feed(
            congress_rows(disclosures), members, institutional_feed=institutional,
            snapshot_at=datetime.now(timezone.utc).isoformat())
        candidate = retain_unavailable_sources(
            candidate, live, since=since, congress_ok=True,
            failed_institutional={f"{subject.kind}:{subject.id}" for subject in SUBJECTS
                                  if not coverage[subject.id]})
        require_institutional_coverage(candidate)
        if price_db and price_db.is_file():
            with sqlite3.connect(f"file:{price_db.resolve()}?mode=ro", uri=True) as connection:
                attach_prices(candidate, connection, as_of=today)
        candidate = preserve_newer_prices(candidate, live)
        validate_snapshot(candidate)
        if len(candidate["events"]) < len(live["events"]):
            raise ValueError("Three-year candidate lost existing events")
        report = {
            "since": since.isoformat(), "through": today.isoformat(),
            "congressSourceTrades": len(disclosures), "congressPublishedTrades": congress_report["published_trades"],
            "congressSourceByYear": dict(sorted(years.items())),
            "institutionalSubjects": len(coverage),
            "institutionalPeriods": sum(map(len, coverage.values())),
            "institutionalPeriodCoverage": coverage,
            "sourceErrors": errors, "secRequests": client.requests,
            "candidateSubjects": len(candidate["subjects"]), "candidateEvents": len(candidate["events"]),
            "candidateBytes": len(json.dumps(candidate, ensure_ascii=False, separators=(",", ":")).encode()),
        }
        # Never promote a partial backfill. A known non-restatement amendment remains quarantined.
        if errors:
            report["published"] = False
            report["blockedBySourceErrors"] = True
            return report
        report.update(publish_if_changed(candidate, database_url, dry_run=dry_run))
        return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Atomically publish only after every source passes")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--congress-archive", type=Path, default=DEFAULT_CONGRESS_ARCHIVE)
    parser.add_argument("--price-db", type=Path)
    args = parser.parse_args()
    env = dotenv_values(ROOT / ".env", interpolate=False)
    local = dotenv_values(ROOT / "services/client_api/.env.content.local", interpolate=False)
    database_url = os.environ.get("BSMART_CONTENT_DATABASE_URL") or local.get("BSMART_CONTENT_DATABASE_URL")
    contact = os.environ.get("BSMART_OFFICIAL_CONTACT") or env.get("BSMART_OFFICIAL_CONTACT")
    if not database_url or not contact:
        parser.error("BSMART_CONTENT_DATABASE_URL and BSMART_OFFICIAL_CONTACT are required")
    result = backfill(database_url=database_url, contact=contact,
                      today=datetime.now(timezone.utc).date(), cache_dir=args.cache_dir,
                      dry_run=not args.apply, price_db=args.price_db,
                      congress_archive=args.congress_archive)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.report.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(args.report)
    print(json.dumps({key: value for key, value in result.items() if key != "institutionalPeriodCoverage"}, ensure_ascii=False))
    if result["sourceErrors"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
