"""Check congressional disclosures and SEC 13Fs, publishing only verified changes."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import zipfile

from dotenv import dotenv_values
import psycopg
import requests

from pipeline.jobs.congress_capture.ios_feed import build_feed
from pipeline.jobs.congress_capture.cusip_tickers import CUSIP, refresh_cache, resolved_tickers
from pipeline.jobs.congress_capture.research_feed import build_research_feed, require_institutional_coverage
from pipeline.jobs.congress_capture.subject_feed_publish import PRICE_FIELDS, validate_snapshot
from pipeline.jobs.institutional_holdings.__main__ import run as refresh_institutional
from pipeline.platforms.congress.disclosures import DEFAULT_DATASET_URL, load_disclosures


ROOT = Path(__file__).resolve().parents[3]
MAX_DATASET_BYTES = 50_000_000
ADVISORY_LOCK = 2_026_09_30_01
QUARANTINED_SEC_ERRORS = {"amendment_requires_review"}


def three_year_start(today: date) -> date:
    try:
        return today.replace(year=today.year - 3)
    except ValueError:
        return today.replace(year=today.year - 3, day=28)


def download_congress_dataset(destination: Path, session: requests.Session | None = None) -> None:
    client = session or requests.Session()
    with client.get(DEFAULT_DATASET_URL, stream=True, timeout=(15, 120),
                    headers={"User-Agent": "bSmart subject activity/1.0 (https://bsmart.today)"}) as response:
        response.raise_for_status()
        if int(response.headers.get("Content-Length") or 0) > MAX_DATASET_BYTES:
            raise ValueError("Congress dataset exceeds download limit")
        size = 0
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                size += len(chunk)
                if size > MAX_DATASET_BYTES:
                    raise ValueError("Congress dataset exceeds download limit")
                handle.write(chunk)
    if not zipfile.is_zipfile(destination):
        raise ValueError("Congress dataset is not a ZIP archive")


def congress_rows(disclosures: list) -> list[dict]:
    return [{
        "trade_id": trade.trade_id,
        "member_id": trade.member.member_id,
        "member_name": trade.member.name,
        "transaction_date": trade.transaction_date.isoformat(),
        "filing_date": trade.filing_date.isoformat() if trade.filing_date else None,
        "ticker": trade.ticker,
        "asset_name": trade.asset_name,
        "action": trade.transaction_type,
        "amount_low": trade.amount_low,
        "amount_high": trade.amount_high,
        "evidence_url": trade.evidence_url,
        "data_source": "kadoa_parsed_official_filing",
    } for trade in disclosures]


def failed_subject_ids(subjects: tuple, failed: set[str]) -> set[str]:
    return {f"{subject.kind}:{subject.id}" for subject in subjects if subject.id in failed}


def retain_unavailable_sources(candidate: dict, live: dict, *, since: date,
                               congress_ok: bool, failed_institutional: set[str]) -> dict:
    subjects = {subject["id"]: subject for subject in candidate["subjects"]}
    events = {event["id"]: event for event in candidate["events"]}
    live_subjects = {subject["id"]: subject for subject in live["subjects"]}
    def trade_identity(item: dict) -> tuple:
        return tuple(item.get(key) for key in ("subjectID", "ticker", "action", "occurredDay",
                                               "displayDay", "amountRange", "sourceURL"))
    trade_identities = {trade_identity(event) for event in events.values() if event["type"] == "trade"}
    refreshed_periods: dict[str, set[str]] = {}
    for event in events.values():
        if event["type"] == "holding":
            refreshed_periods.setdefault(event["subjectID"], set()).add(event["occurredDay"])
    for event in live["events"]:
        subject_id = event["subjectID"]
        is_congress = subject_id.startswith("politician:")
        is_house_gap = event.get("sourceNote", "").startswith("House Clerk filing; automatically extracted")
        is_older_holding = (event["type"] == "holding"
                            and event["occurredDay"] >= since.isoformat()
                            and subject_id in refreshed_periods
                            and event["occurredDay"] < min(refreshed_periods[subject_id]))
        retain = ((is_congress and (not congress_ok or is_house_gap))
                  or (subject_id in failed_institutional) or is_older_holding)
        if not retain or event["id"] in events:
            continue
        if date.fromisoformat(event["occurredDay"]) < since:
            continue
        if is_house_gap and trade_identity(event) in trade_identities:
            continue
        events[event["id"]] = event
        if event["type"] == "trade":
            trade_identities.add(trade_identity(event))
        if subject_id not in subjects:
            subjects[subject_id] = live_subjects[subject_id]
    return {**candidate, "subjects": sorted(subjects.values(), key=lambda item: item["id"]),
            "events": sorted(events.values(), key=lambda item: (item["displayDay"], item["id"]), reverse=True)}


def preserve_newer_prices(candidate: dict, live: dict) -> dict:
    live_events = {event["id"]: event for event in live["events"]}
    events = []
    for event in candidate["events"]:
        previous = live_events.get(event["id"])
        same_event = (previous is not None
                      and all(previous.get(key) == event.get(key) for key in
                              ("subjectID", "type", "occurredDay", "displayDay")))
        same_security = (same_event and (previous.get("ticker") == event.get("ticker")
                         or (event["type"] == "holding"
                             and previous.get("cusip") == event.get("cusip")
                             and previous.get("sourceURL") == event.get("sourceURL"))))
        if same_security:
            if (previous.get("latestPriceDay") or "") > (event.get("latestPriceDay") or ""):
                event = {**event, **{field: previous[field] for field in PRICE_FIELDS if field in previous}}
        if (previous and event["type"] == "holding"
                and all(previous.get(key) == event.get(key) for key in
                        ("subjectID", "cusip", "occurredDay", "displayDay", "sourceURL"))):
            if previous.get("ticker") and not event.get("ticker"):
                event = {**event, "ticker": previous["ticker"]}
            if previous.get("underlyingTicker") and not event.get("underlyingTicker"):
                event = {**event, "underlyingTicker": previous["underlyingTicker"]}
            old_note, new_note = previous.get("sourceNote") or "", event.get("sourceNote") or ""
            if old_note.startswith(new_note) and len(old_note) > len(new_note):
                event = {**event, "sourceNote": old_note}
        events.append(event)
    live_subjects = {subject["id"]: subject for subject in live["subjects"]}
    subjects = []
    for subject in candidate["subjects"]:
        previous = live_subjects.get(subject["id"])
        if (previous and previous["kind"] == subject["kind"]
                and previous["name"] == subject["name"]
                and previous.get("research") is not None
                and subject.get("research") is None):
            subject = {**subject, "research": previous["research"]}
        subjects.append(subject)
    return {**candidate, "subjects": subjects, "events": events}


def content_changed(candidate: dict, live: dict) -> bool:
    return candidate["subjects"] != live["subjects"] or candidate["events"] != live["events"]


def publish_if_changed(candidate: dict, database_url: str, *, dry_run: bool) -> dict:
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        with connection.transaction():
            with connection.cursor() as cursor:
                cursor.execute("SET LOCAL statement_timeout = '180s'")
                cursor.execute("SELECT pg_try_advisory_xact_lock(%s)", (ADVISORY_LOCK,))
                if not cursor.fetchone()[0]:
                    raise RuntimeError("Another subject refresh is publishing")
                cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                               "WHERE channel='production' FOR UPDATE")
                row = cursor.fetchone()
                if not row:
                    raise RuntimeError("No production subject snapshot exists")
                live = row[0]
                live_at = datetime.fromisoformat(live["snapshotAt"].replace("Z", "+00:00"))
                candidate_at = datetime.fromisoformat(candidate["snapshotAt"].replace("Z", "+00:00"))
                if live_at > candidate_at:
                    raise RuntimeError("Production snapshot became newer during refresh")
                candidate = preserve_newer_prices(candidate, live)
                validate_snapshot(candidate)
                if not content_changed(candidate, live):
                    return {"published": False, "subjects": len(live["subjects"]),
                            "events": len(live["events"]), "newEvents": 0}
                live_ids = {event["id"] for event in live["events"]}
                new_events = sum(event["id"] not in live_ids for event in candidate["events"])
                if not dry_run:
                    cursor.execute("UPDATE public.bsmart_subject_activity_snapshots "
                                   "SET payload=%s::jsonb, updated_at=now() WHERE channel='production'",
                                   (json.dumps(candidate, ensure_ascii=False, allow_nan=False),))
                    cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                                   "WHERE channel='production'")
                    if cursor.fetchone()[0] != candidate:
                        raise RuntimeError("Published subject snapshot failed readback verification")
                return {"published": not dry_run, "wouldPublish": dry_run,
                        "subjects": len(candidate["subjects"]), "events": len(candidate["events"]),
                        "newEvents": new_events}


def run_cycle(*, database_url: str, contact: str, dry_run: bool = False,
              today: date | None = None) -> dict:
    today = today or datetime.now(timezone.utc).date()
    since = three_year_start(today)
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        row = connection.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                                 "WHERE channel='production'").fetchone()
        if not row:
            raise RuntimeError("No production subject snapshot exists")
        live = row[0]

    warnings = []
    with tempfile.TemporaryDirectory(prefix="bsmart-subject-refresh-") as directory:
        temp = Path(directory)
        archive = temp / "congress.zip"
        try:
            download_congress_dataset(archive)
            members, disclosures = load_disclosures(archive, start_date=since, end_date=today)
            if len(disclosures) < 12_000 or len(members) < 120:
                raise ValueError("Congress source coverage fell below the verified baseline")
            congress_ok = True
        except (requests.RequestException, OSError, ValueError, zipfile.BadZipFile, KeyError) as exc:
            congress_ok = False
            members, disclosures = [], []
            warnings.append(f"congress: {type(exc).__name__}: {exc}")

        manifest = refresh_institutional(output_dir=temp / "institutional", contact=contact)
        failed_rows = [item for item in manifest["subjects"] if item["status"] == "error"]
        failed = {item["id"] for item in failed_rows}
        quarantined = [item["id"] for item in failed_rows
                       if item.get("error") in QUARANTINED_SEC_ERRORS]
        unexpected = [item for item in failed_rows if item["id"] not in quarantined]
        if unexpected:
            warnings.append(f"SEC 13F: {len(unexpected)} subject refreshes failed; retaining verified live records")
        from pipeline.domain.institutional_holdings.registry import SUBJECTS
        filings = [json.loads(path.read_text()) for subject in SUBJECTS
                   if (path := temp / "institutional" / f"{subject.id}.json").is_file()]
        draft = build_feed({"source": "disclosed_capitol", "trades": []},
                           institutional_snapshots=filings, cusip_tickers={})
        selected_cusips = {event["cusip"] for event in draft["events"]
                           if event["type"] == "holding"
                           and CUSIP.fullmatch(event["cusip"])}
        try:
            ticker_cache = refresh_cache(selected_cusips, persist=False)
            mapped_tickers = resolved_tickers(ticker_cache)
        except (requests.RequestException, ValueError) as exc:
            warnings.append(f"OpenFIGI: {type(exc).__name__}: {exc}; using cached mappings")
            mapped_tickers = None
        institutional = build_feed({"source": "disclosed_capitol", "trades": []},
                                   institutional_snapshots=filings, cusip_tickers=mapped_tickers)
        candidate, report = build_research_feed(congress_rows(disclosures), members,
                                                institutional_feed=institutional,
                                                snapshot_at=datetime.now(timezone.utc).isoformat())
        candidate = retain_unavailable_sources(candidate, live, since=since,
                                               congress_ok=congress_ok,
                                               failed_institutional=failed_subject_ids(SUBJECTS, failed))
        require_institutional_coverage(candidate)
        politician_count = Counter(subject["kind"] for subject in candidate["subjects"])["politician"]
        if politician_count < 80:
            raise ValueError("Congress subject coverage fell below the verified baseline")
        if len(candidate["events"]) < len(live["events"]) * 0.8:
            raise ValueError("Candidate snapshot lost more than 20% of existing events")
        result = publish_if_changed(candidate, database_url, dry_run=dry_run)
        return {"checkedAt": datetime.now(timezone.utc).isoformat(),
                "congressChecked": congress_ok, "institutionalChecked": len(SUBJECTS) - len(failed),
                "institutionalFailed": [item["id"] for item in unexpected],
                "institutionalQuarantined": quarantined, "warnings": warnings,
                "politicianEvents": report["published_trades"], **result}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    env = dotenv_values(ROOT / ".env", interpolate=False)
    local_content = dotenv_values(ROOT / "services/client_api/.env.content.local", interpolate=False)
    database_url = (os.environ.get("BSMART_CONTENT_DATABASE_URL")
                    or local_content.get("BSMART_CONTENT_DATABASE_URL"))
    contact = os.environ.get("BSMART_OFFICIAL_CONTACT") or env.get("BSMART_OFFICIAL_CONTACT")
    if not database_url or not contact:
        parser.error("BSMART_CONTENT_DATABASE_URL and BSMART_OFFICIAL_CONTACT are required")
    result = run_cycle(database_url=database_url, contact=contact, dry_run=args.dry_run)
    print(json.dumps(result, ensure_ascii=False))
    if result["warnings"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
