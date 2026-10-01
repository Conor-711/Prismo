"""Backfill selected, verified 13F identities without replacing other live sources."""

from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import sqlite3

from dotenv import dotenv_values
import psycopg

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.jobs.congress_capture.backfill_three_years import (
    DEFAULT_HISTORY, checked_report, combine_quarter, historical_filing, quarter_before,
)
from pipeline.jobs.congress_capture.ios_feed import attach_prices, build_feed
from pipeline.jobs.congress_capture.refresh_cycle import (
    ADVISORY_LOCK, ROOT, content_changed, preserve_newer_prices, three_year_start,
)
from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot
from pipeline.platforms.institutional_holdings.sec_13f import SEC13FClient, FilingError


def collect(subjects: tuple, client: SEC13FClient, cache_dir: Path, today: date) -> tuple[dict, dict]:
    since = three_year_start(today)
    baseline = quarter_before(since).isoformat()
    filings, coverage = [], {}
    for subject in subjects:
        rows = client.submissions(subject.filer_cik, earliest_period=baseline)
        by_period: dict[str, list[dict]] = {}
        for row in rows:
            if baseline <= row["periodOfReport"] <= today.isoformat() and row["filedAt"] <= today.isoformat():
                if row["form"].startswith("13F-HR"):
                    by_period.setdefault(row["periodOfReport"], []).append(row)
        if not by_period:
            raise FilingError("no_three_year_holdings_reports")
        history = []
        for period_rows in (by_period[key] for key in sorted(by_period)):
            reports = [checked_report(client, row, cache_dir) for row in period_rows]
            if any(report["managerName"].casefold() != subject.filer_name.casefold() for report in reports):
                raise FilingError("reporting_manager_mismatch")
            history.append(combine_quarter(reports))
        coverage[subject.id] = [report["periodOfReport"] for report, _ in history
                                if report["periodOfReport"] >= since.isoformat()]
        for index, (report, pieces) in enumerate(history):
            if report["periodOfReport"] < since.isoformat():
                continue
            previous = history[index - 1][0] if index else None
            filings.append(historical_filing(subject, report, previous))
            for supplement in pieces[1:]:
                filing = historical_filing(subject, supplement, None)
                # A supplement reports additions, never a complete replacement portfolio.
                filing["changes"] = [{**row, "reportedShareChange": row["reportedShares"],
                                      "classification": "new_reported_position"}
                                     for row in supplement["holdings"]]
                filings.append(filing)
    feed = build_feed({"source": "disclosed_capitol", "trades": [],
                       "fetched_at": datetime.now(timezone.utc).isoformat()},
                      institutional_snapshots=filings)
    validate_snapshot(feed)
    return feed, coverage


def merge_selected(live: dict, incoming: dict) -> dict:
    validate_snapshot(incoming)
    known = {f"{subject.kind}:{subject.id}": subject for subject in SUBJECTS}
    subjects = {subject["id"]: subject for subject in live["subjects"]}
    for subject in incoming["subjects"]:
        identity = known.get(subject["id"])
        if identity is None or (subject["kind"], subject["name"]) != (identity.kind, identity.title):
            raise ValueError("Unverified selected subject identity")
        previous = subjects.get(subject["id"])
        if previous and (previous["kind"], previous["name"]) != (subject["kind"], subject["name"]):
            raise ValueError("Existing subject identity mismatch")
        subjects[subject["id"]] = {**(previous or {}), **subject,
                                   "metrics": previous.get("metrics") if previous else subject.get("metrics")}
    events = {event["id"]: event for event in live["events"]}
    for event in incoming["events"]:
        previous = events.get(event["id"])
        if previous and previous["subjectID"] != event["subjectID"]:
            raise ValueError("Existing event identity mismatch")
        events[event["id"]] = event
    merged = {**live, "snapshotAt": incoming["snapshotAt"],
              "subjects": sorted(subjects.values(), key=lambda row: row["id"]),
              "events": sorted(events.values(), key=lambda row: (row["displayDay"], row["id"]), reverse=True)}
    merged = preserve_newer_prices(merged, live)
    validate_snapshot(merged)
    return merged


def publish_selected(incoming: dict, database_url: str, *, dry_run: bool) -> dict:
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        with connection.transaction():
            connection.execute("SET LOCAL statement_timeout = '180s'")
            if not connection.execute("SELECT pg_try_advisory_xact_lock(%s)", (ADVISORY_LOCK,)).fetchone()[0]:
                raise RuntimeError("Another subject publication is in progress")
            row = connection.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                                     "WHERE channel='production' FOR UPDATE").fetchone()
            if not row:
                raise RuntimeError("No production subject snapshot exists")
            live = row[0]
            merged = merge_selected(live, incoming)
            # Fetching may overlap another refresh; never move the live timestamp backward.
            merged["snapshotAt"] = max(live["snapshotAt"], merged["snapshotAt"],
                                       key=lambda value: datetime.fromisoformat(value.replace("Z", "+00:00")))
            changed = content_changed(merged, live)
            if changed and not dry_run:
                connection.execute("UPDATE public.bsmart_subject_activity_snapshots "
                                   "SET payload=%s::jsonb, updated_at=now() WHERE channel='production'",
                                   (json.dumps(merged, ensure_ascii=False, allow_nan=False),))
                ids = [subject["id"] for subject in incoming["subjects"]]
                # Read back selected content and full counts without transferring the
                # multi-year snapshot a second time inside the locked transaction.
                actual = selected_readback(connection, ids)
                expected = selected_content(merged, ids)
                if actual != expected:
                    raise RuntimeError("Selected subject publication failed readback verification")
            return {"published": changed and not dry_run, "wouldPublish": changed and dry_run,
                    "subjects": len(merged["subjects"]), "events": len(merged["events"]),
                    "newEvents": len({event["id"] for event in merged["events"]}
                                     - {event["id"] for event in live["events"]}),
                    "selectedSubjects": [subject["id"] for subject in incoming["subjects"]]}


def selected_content(snapshot: dict, subject_ids: list[str]) -> dict:
    ids = set(subject_ids)
    return {"schemaVersion": snapshot["schemaVersion"], "snapshotAt": snapshot["snapshotAt"],
            "subjectCount": len(snapshot["subjects"]), "eventCount": len(snapshot["events"]),
            "subjects": sorted((s for s in snapshot["subjects"] if s["id"] in ids), key=lambda s: s["id"]),
            "events": sorted((e for e in snapshot["events"] if e["subjectID"] in ids), key=lambda e: e["id"])}


def selected_readback(connection, subject_ids: list[str]) -> dict:
    row = connection.execute("""SELECT jsonb_build_object(
        'schemaVersion', payload->'schemaVersion', 'snapshotAt', payload->'snapshotAt',
        'subjectCount', jsonb_array_length(payload->'subjects'),
        'eventCount', jsonb_array_length(payload->'events'),
        'subjects', (SELECT coalesce(jsonb_agg(s ORDER BY s->>'id'), '[]'::jsonb)
                     FROM jsonb_array_elements(payload->'subjects') s WHERE s->>'id'=ANY(%s::text[])),
        'events', (SELECT coalesce(jsonb_agg(e ORDER BY e->>'id'), '[]'::jsonb)
                   FROM jsonb_array_elements(payload->'events') e WHERE e->>'subjectID'=ANY(%s::text[])))
        FROM public.bsmart_subject_activity_snapshots WHERE channel='production'""",
        (subject_ids, subject_ids)).fetchone()
    if not row:
        raise RuntimeError("No production subject snapshot exists")
    return row[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", action="append", required=True, choices=[s.id for s in SUBJECTS])
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--output", type=Path, default=ROOT / "data/reports/selected-subject-backfill.json")
    parser.add_argument("--price-db", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    env = dotenv_values(ROOT / ".env", interpolate=False)
    local = dotenv_values(ROOT / "services/client_api/.env.content.local", interpolate=False)
    contact = os.environ.get("BSMART_OFFICIAL_CONTACT") or env.get("BSMART_OFFICIAL_CONTACT")
    url = os.environ.get("BSMART_CONTENT_DATABASE_URL") or local.get("BSMART_CONTENT_DATABASE_URL")
    if not contact or not url:
        parser.error("BSMART_OFFICIAL_CONTACT and BSMART_CONTENT_DATABASE_URL are required")
    today = datetime.now(timezone.utc).date()
    selected = tuple(subject for subject in SUBJECTS if subject.id in args.subject)
    feed, coverage = collect(selected, SEC13FClient(contact, request_limit=600), args.cache_dir, today)
    if args.price_db:
        with sqlite3.connect(f"file:{args.price_db.resolve()}?mode=ro", uri=True) as connection:
            attach_prices(feed, connection, as_of=today)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".tmp")
    temporary.write_text(json.dumps(feed, ensure_ascii=False, allow_nan=False) + "\n")
    temporary.replace(args.output)
    result = publish_selected(feed, url, dry_run=not args.apply)
    print(json.dumps({**result, "periodCoverage": coverage}))


if __name__ == "__main__":
    main()
