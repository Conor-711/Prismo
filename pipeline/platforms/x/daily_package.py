"""Bounded, validated staging of user-supplied X JSONL packages."""
from __future__ import annotations

import hashlib
import json
import shutil
import stat
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath

MAX_BYTES = 2 * 1024**3
MAX_FILES = 5000


def stage_package(source: Path, destination: Path) -> dict:
    destination.mkdir(parents=True, exist_ok=True)
    files: list[tuple[str, Path]] = []
    if source.is_file() and source.suffix.lower() == ".zip":
        with zipfile.ZipFile(source) as archive:
            members = archive.infolist()
            if len(members) > MAX_FILES or sum(m.file_size for m in members) > MAX_BYTES:
                raise ValueError("Package exceeds the file/size limit")
            for member in members:
                path = PurePosixPath(member.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in member.filename or stat.S_ISLNK(member.external_attr >> 16):
                    raise ValueError("Unsafe archive path")
                if member.is_dir() or not path.name.startswith("tweets_") or path.suffix != ".jsonl":
                    continue
                target = destination / f"tweets_{len(files):05}.jsonl"
                with archive.open(member) as stream, target.open("wb") as output:
                    shutil.copyfileobj(stream, output)
                files.append((member.filename, target))
    else:
        paths = sorted(source.rglob("tweets_*.jsonl")) if source.is_dir() else [source]
        if len(paths) > MAX_FILES or sum(p.stat().st_size for p in paths) > MAX_BYTES:
            raise ValueError("Package exceeds the file/size limit")
        for path in paths:
            if path.is_symlink() or not path.is_file() or path.suffix != ".jsonl":
                raise ValueError("Expected JSONL files, a directory, or a ZIP package")
            target = destination / f"tweets_{len(files):05}.jsonl"
            shutil.copyfile(path, target)
            files.append((path.name, target))
    if not files:
        raise ValueError("No tweets_*.jsonl files found")

    hashes, post_ids, timestamps, authors = [], set(), [], set()
    rows = 0
    for _, path in files:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for number, raw in enumerate(stream, 1):
                digest.update(raw)
                if not raw.strip():
                    continue
                try:
                    post = json.loads(raw)
                    if not isinstance(post, dict):
                        raise ValueError("Expected object")
                    created = datetime.fromisoformat(str(post["created_at"]).replace("Z", "+00:00"))
                    if created.tzinfo is None or created > datetime.now(timezone.utc) + timedelta(minutes=5):
                        raise ValueError("Invalid source timestamp")
                    if not post.get("tweet_id") or not isinstance(post.get("text"), str) or not post.get("author_handle"):
                        raise ValueError("Missing post identity, author or original text")
                    if not isinstance(post.get("cashtags", []), list):
                        raise ValueError("cashtags must be an array")
                except (ValueError, KeyError, TypeError) as exc:
                    raise ValueError(f"Invalid package row {path.name}:{number}") from exc
                rows += 1
                post_ids.add(str(post["tweet_id"]))
                timestamps.append(created.astimezone(timezone.utc).isoformat())
                authors.add(str(post["author_handle"]).lower())
        hashes.append(digest.hexdigest())
    if not rows:
        raise ValueError("Empty package")
    return {
        "packageHash": hashlib.sha256("\n".join(sorted(hashes)).encode()).hexdigest(),
        "rows": rows, "uniquePosts": len(post_ids), "authors": len(authors),
        "sourceFrom": min(timestamps), "sourceThrough": max(timestamps),
        "postIds": sorted(post_ids), "fileHashes": sorted(hashes),
    }
