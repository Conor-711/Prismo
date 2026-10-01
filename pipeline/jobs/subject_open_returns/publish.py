"""Attach reviewed three-year research estimates to the live subject feed."""

from __future__ import annotations

import argparse
import csv
from datetime import date
import json
import os
from pathlib import Path

from dotenv import dotenv_values
import psycopg

from pipeline.jobs.congress_capture.refresh_cycle import ADVISORY_LOCK, ROOT
from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot
from pipeline.domain.institutional_holdings.registry import SUBJECTS

DEFAULT_REPORT = ROOT / "data/reports/subject-open-returns-three-year"


def research_rows(report_dir: Path, *, subject_ids: set[str] | None = None) -> dict[str, dict]:
    manifest = json.loads((report_dir / "manifest.json").read_text())
    if manifest.get("published_score") is not None:
        raise ValueError("Research report unexpectedly contains a published Score")
    as_of = date.fromisoformat(manifest["as_of"])
    since = date.fromisoformat(manifest["source_since"])
    market = date.fromisoformat(manifest["latest_market_date"])
    if not since < market <= as_of or (as_of - market).days > 7:
        raise ValueError("Research market date is stale or invalid")
    output = {}
    with (report_dir / "subjects.csv").open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            subject_id = row["subject_id"]
            if subject_id in output or not subject_id.startswith(("politician:", "celebrity:", "institution:")):
                raise ValueError(f"Duplicate or invalid research identity: {subject_id}")
            def count(key: str) -> int:
                return int(row[key])

            def fraction(key: str) -> float | None:
                return float(row[key]) / 100 if row[key] else None
            wins = count("directional_wins")
            losses = count("directional_losses")
            output[subject_id] = {
                "method": "three_year_open_positions_v1",
                "asOf": as_of.isoformat(),
                "sourceSince": since.isoformat(),
                "latestMarketDate": market.isoformat(),
                "candidatePositions": count("candidate_positions"),
                "pricedPositions": count("priced_positions"),
                "directionalWins": wins,
                "directionalLosses": losses,
                "directionalObservations": count("directional_observations"),
                "directionalWinRate": wins / (wins + losses) if wins + losses else None,
                "openPositionPositiveRate": fraction("open_position_positive_rate_pct"),
                "meanOpenReturn": fraction("mean_open_return_pct"),
            }
    if subject_ids is not None:
        known = {f"{subject.kind}:{subject.id}" for subject in SUBJECTS}
        if not subject_ids or not subject_ids <= known or set(output) != subject_ids:
            raise ValueError("Scoped research must exactly match verified selected subjects")
    elif len(output) < 200:
        raise ValueError("Research roster is below the reviewed three-year baseline")
    return output


def merge_research(live: dict, rows: dict[str, dict]) -> tuple[dict, int]:
    live_ids = {subject["id"] for subject in live["subjects"]}
    missing = set(rows) - live_ids
    if missing:
        raise ValueError(f"Research has {len(missing)} subjects absent from production")
    subjects = []
    changed = 0
    for subject in live["subjects"]:
        research = rows.get(subject["id"])
        updated = {**subject, "research": research} if research else subject
        changed += updated != subject
        subjects.append(updated)
    merged = {**live, "subjects": subjects}
    validate_snapshot(merged)
    return merged, changed


def publish(report_dir: Path, database_url: str, *, dry_run: bool,
            subject_ids: set[str] | None = None) -> dict:
    rows = research_rows(report_dir, subject_ids=subject_ids)
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        with connection.transaction():
            with connection.cursor() as cursor:
                cursor.execute("SET LOCAL statement_timeout = '180s'")
                cursor.execute("SELECT pg_try_advisory_xact_lock(%s)", (ADVISORY_LOCK,))
                if not cursor.fetchone()[0]:
                    raise RuntimeError("Another subject publication is in progress")
                cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                               "WHERE channel='production' FOR UPDATE")
                row = cursor.fetchone()
                if not row:
                    raise RuntimeError("No production subject snapshot exists")
                merged, changed = merge_research(row[0], rows)
                if changed and not dry_run:
                    cursor.execute("UPDATE public.bsmart_subject_activity_snapshots "
                                   "SET payload=%s::jsonb, updated_at=now() WHERE channel='production'",
                                   (json.dumps(merged, ensure_ascii=False, allow_nan=False),))
                    cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                                   "WHERE channel='production'")
                    if cursor.fetchone()[0] != merged:
                        raise RuntimeError("Research publication failed readback verification")
                return {"published": bool(changed and not dry_run), "changedSubjects": changed,
                        "subjects": len(merged["subjects"]), "events": len(merged["events"]),
                        "asOf": next(iter(rows.values()))["asOf"]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--subject", action="append", choices=[subject.id for subject in SUBJECTS],
                        help="Require a report containing exactly these verified 13F identities")
    args = parser.parse_args()
    local = dotenv_values(ROOT / "services/client_api/.env.content.local", interpolate=False)
    url = os.environ.get("BSMART_CONTENT_DATABASE_URL") or local.get("BSMART_CONTENT_DATABASE_URL")
    if not url:
        parser.error("BSMART_CONTENT_DATABASE_URL is required")
    subject_ids = ({f"{subject.kind}:{subject.id}" for subject in SUBJECTS if subject.id in args.subject}
                   if args.subject else None)
    print(json.dumps(publish(args.report_dir, url, dry_run=not args.apply, subject_ids=subject_ids)))


if __name__ == "__main__":
    main()
