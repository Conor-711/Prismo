"""Export the validated, home-window subject feed as the iOS offline fallback."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile

from dotenv import dotenv_values
import psycopg

from pipeline.jobs.congress_capture.refresh_cycle import ROOT
from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot

DEFAULT_OUTPUT = ROOT / "ios/BSmart/Resources/subject-activity.json"


def export_bundle(database_url: str, output: Path) -> dict:
    with psycopg.connect(database_url, connect_timeout=10) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT public.bsmart_subject_activity_read(NULL)")
            row = cursor.fetchone()
    if not row or not row[0]:
        raise RuntimeError("No production subject snapshot exists")
    snapshot = row[0]
    validate_snapshot(snapshot)
    research_count = sum(subject.get("research") is not None for subject in snapshot["subjects"])
    if research_count != len(snapshot["subjects"]):
        raise ValueError("Research is missing from the production subject roster")

    payload = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=f".{output.name}.",
                                         suffix=".tmp", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(payload)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, output)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    return {"subjects": len(snapshot["subjects"]), "events": len(snapshot["events"]),
            "researchSubjects": research_count, "bytes": len(payload)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    local = dotenv_values(ROOT / "services/client_api/.env.content.local", interpolate=False)
    url = os.environ.get("BSMART_CONTENT_DATABASE_URL") or local.get("BSMART_CONTENT_DATABASE_URL")
    if not url:
        parser.error("BSMART_CONTENT_DATABASE_URL is required")
    print(json.dumps(export_bundle(url, args.output)))


if __name__ == "__main__":
    main()
