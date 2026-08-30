from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any

from services.client_api.config import ClientAPISettings
from services.client_api.read_models import RealtimeReadModelPublisher


REQUIRED_COLLECTIONS = ("smart-money", "smart-money-movements", "smart-money-evidence")
DERIVED_COLLECTIONS = ("portfolio-signals", "ticker-intelligence")


def _load(input_dir: Path) -> tuple[dict[str, list[dict[str, Any]]], str]:
    manifest_path = input_dir / "smart-money-live-manifest.json"
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw)
    entries = manifest.get("collections") if isinstance(manifest, dict) else None
    if not isinstance(entries, dict):
        raise RuntimeError(f"Realtime manifest {manifest_path} has no collection map.")
    missing = set(REQUIRED_COLLECTIONS) - set(entries)
    if missing:
        raise RuntimeError(f"Realtime manifest is missing required collections: {sorted(missing)}")
    unsupported = set(entries) - set(REQUIRED_COLLECTIONS) - set(DERIVED_COLLECTIONS)
    if unsupported:
        raise RuntimeError(f"Realtime manifest contains unsupported collections: {sorted(unsupported)}")

    collections: dict[str, list[dict[str, Any]]] = {}
    for name in entries:
        path = input_dir / f"{name}.json"
        raw = path.read_bytes()
        expected_hash = str((entries.get(name) or {}).get("sha256") or "")
        actual_hash = hashlib.sha256(raw).hexdigest()
        if not expected_hash or actual_hash != expected_hash:
            raise RuntimeError(f"Realtime collection {path} does not match its committed manifest.")
        payload = json.loads(raw)
        if not isinstance(payload, list) or any(not isinstance(item, dict) for item in payload):
            raise RuntimeError(f"Realtime collection {path} must be an object array.")
        expected_count = (entries.get(name) or {}).get("count")
        if expected_count is not None and int(expected_count) != len(payload):
            raise RuntimeError(f"Realtime collection {path} count does not match its manifest.")
        collections[name] = payload
    if manifest_path.read_bytes() != manifest_raw:
        raise RuntimeError("Realtime manifest changed while collections were being read.")
    return collections, hashlib.sha256(manifest_raw).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Continuously publish live Smart Money collections into the Client API read model."
    )
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--once", action="store_true")
    arguments = parser.parse_args()
    input_dir = arguments.input_dir.resolve()
    settings = ClientAPISettings.from_environment()
    database_url = os.environ.get(
        "BSMART_READ_MODEL_DATABASE_URL",
        settings.read_model_database_url or settings.database_url,
    )
    publisher = RealtimeReadModelPublisher(database_url)
    last_hash = ""
    try:
        while True:
            try:
                collections, content_hash = _load(input_dir)
                if content_hash != last_hash:
                    result = publisher.publish_partitioned(
                        collections,
                        producer="hyperliquid-live",
                        source_version=f"hyperliquid-live:{content_hash}",
                    )
                    print(
                        "[smart-money-live-publish] "
                        + " ".join(f"{key}={value}" for key, value in result.counts.items()),
                        flush=True,
                    )
                    last_hash = content_hash
            except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
                if arguments.once:
                    raise
                print(f"[smart-money-live-publish] waiting error={exc}", flush=True)
            if arguments.once:
                break
            time.sleep(max(0.25, arguments.poll_seconds))
    finally:
        publisher.dispose()


if __name__ == "__main__":
    main()
