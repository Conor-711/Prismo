"""Prepare a media-only X release from a previously reviewed daily release."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from .opinion_media import attach_media_to_release, enrich_posts


def prepare(source: Path, destination: Path, database: Path, since: str) -> dict:
    if destination.exists():
        raise FileExistsError(destination)
    source_manifest = json.loads((source / "daily-x-manifest.json").read_text())
    updates = json.loads((source / "smart-account-updates.json").read_text())
    posts: dict[str, dict] = {}
    for row in updates:
        tweet_id = str(row.get("sourcePostId") or "")
        if row.get("platform") == "X" and row.get("publishedAt", "") >= since and tweet_id.isdigit():
            posts.setdefault(tweet_id, {"tweet_id": tweet_id, "text": row.get("originalText") or ""})
    destination.mkdir(parents=True)
    for name in ("smart-accounts", "smart-account-updates", "smart-account-evidence"):
        shutil.copy2(source / f"{name}.json", destination / f"{name}.json")
    manifest = dict(source_manifest)
    manifest["asOf"] = datetime.now(timezone.utc).isoformat()
    manifest["packageHash"] = hashlib.sha256(
        f"{source_manifest['packageHash']}:opinion-media:{since}:{manifest['asOf']}".encode()
    ).hexdigest()
    (destination / "daily-x-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    with sqlite3.connect(database) as connection:
        enriched = enrich_posts(connection, list(posts.values()))
        attached = attach_media_to_release(connection, destination)
    return {"sourcePosts": len(posts), **enriched, "attached": attached, "release": str(destination)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--since", default="2026-09-22")
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.output, args.database, args.since), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
