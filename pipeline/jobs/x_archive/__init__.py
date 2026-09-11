"""Local X archive import job."""
from __future__ import annotations

import json
from pathlib import Path

from ...common.db import engine
from ...platforms.x.archive import import_archives


def run(*, tweet_dirs: list[str], report: str, dry_run: bool = False) -> dict:
    result = import_archives(engine, [Path(path).expanduser() for path in tweet_dirs], dry_run=dry_run)
    destination = Path(report)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[x-archive] scanned={result['scanned']} inserted={result['inserted']} report={destination}", flush=True)
    return result
