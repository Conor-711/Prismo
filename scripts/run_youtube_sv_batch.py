#!/usr/bin/env python3
"""Submit, resume, and collect transcript-backed YouTube SV Gemini batches."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(ROOT / "data" / "dev.db"))
    parser.add_argument("--name", default="", help="resume an existing Gemini batch resource")
    parser.add_argument("--limit", type=int, default=500)
    parser.add_argument("--model", default="gemini-3-flash-preview")
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--timeout-seconds", type=int, default=86_400)
    parser.add_argument("--submit-only", action="store_true")
    parser.add_argument("--extract-workers", type=int, default=8)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    db = Path(args.db).expanduser().resolve()
    os.environ["PRICE_DB"] = str(db)
    os.environ.setdefault("PYTHONPATH", str(ROOT))

    from pipeline.domain.opinions.youtube_batch import (
        submit_fulltext_batch,
        wait_and_collect_fulltext_batch,
    )
    from pipeline.domain.smart_voice.v0_impl import (
        YOUTUBE_TRANSCRIPT_CALL_VERSION,
        ensure_tables,
        extract_calls,
        materialize_youtube_transcript_videos,
        youtube_transcript_candidate_rows,
    )

    lock_path = Path(os.environ.get("YOUTUBE_SV_BATCH_LOCK", "/tmp/prismo-youtube-sv-batch.lock"))
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_file = lock_path.open("w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        raise SystemExit("another YouTube SV batch orchestrator is running") from exc
    lock_file.write(str(os.getpid()))
    lock_file.flush()

    name = args.name
    if not name:
        with sqlite3.connect(db) as con:
            con.row_factory = sqlite3.Row
            ensure_tables(con)
            active_video_ids: set[str] = set()
            if con.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='yt_fulltext_batch_job'"
            ).fetchone():
                for job in con.execute(
                    """SELECT video_ids_json FROM yt_fulltext_batch_job
                         WHERE collected_at IS NULL
                           AND state NOT IN (
                             'BATCH_STATE_FAILED','BATCH_STATE_CANCELLED','BATCH_STATE_EXPIRED'
                           )"""
                ):
                    try:
                        active_video_ids.update(str(value) for value in json.loads(job[0]))
                    except (TypeError, ValueError):
                        continue
            rows = youtube_transcript_candidate_rows(
                con,
                args.limit + len(active_video_ids),
                20,
                40,
                False,
            )
            rows = [row for row in rows if str(row["tweet_id"]) not in active_video_ids][: args.limit]
            video_ids = materialize_youtube_transcript_videos(con, rows)
        name = submit_fulltext_batch(db, video_ids, args.model)
        print(f"[yt-batch] resume with --name {name}", flush=True)
    if args.submit_only:
        return

    result = wait_and_collect_fulltext_batch(
        db,
        name,
        poll_seconds=args.poll_seconds,
        timeout_seconds=args.timeout_seconds,
    )
    if result["state"] != "BATCH_STATE_SUCCEEDED":
        raise SystemExit(f"batch did not succeed: {result}")

    with sqlite3.connect(db) as con:
        con.row_factory = sqlite3.Row
        ensure_tables(con)
        extract_calls(
            con,
            0,
            args.extract_workers,
            False,
            "author-balanced",
            20,
            40,
            {"youtube"},
        )
        ready = con.execute(
            """SELECT count(*) FROM (
                 SELECT investor_id FROM sv_call
                  WHERE source='youtube'
                    AND transcript_version=?
                    AND is_actionable_call=1
                  GROUP BY investor_id HAVING count(*)>=5
               )""",
            (YOUTUBE_TRANSCRIPT_CALL_VERSION,),
        ).fetchone()[0]
    print(f"[yt-batch] authors_with_5_transcript_calls={ready}/300", flush=True)


if __name__ == "__main__":
    main()
