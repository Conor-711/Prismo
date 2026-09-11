"""Publish a verified daily X partition; never migrate schemas or overwrite user data."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from .read_models import (RealtimeReadModelPublisher, RealtimeReadModelCollection,
                         ReadModelDocument, _base_collection, _decode_document)
from .daily_x_contract import Profile, View
from .smart_account_signals import build_portfolio_signals, SIGNAL_NAMESPACE

COLLECTIONS = ("smart-accounts", "smart-account-updates", "smart-account-evidence")


def is_x(collection: str, document: dict) -> bool:
    if collection == "portfolio-signals":
        return any(str(uuid.uuid5(SIGNAL_NAMESPACE, f"x:{item.get('referenceId')}:{document.get('ticker')}"))
                   == document.get("id") for item in document.get("evidence", []))
    return str(document.get("platform", "")).lower() in {"x", "twitter"} or str(
        document.get("id" if collection == "smart-accounts" else "authorId", "")
    ).startswith("x:")


def load_release(directory: Path) -> tuple[dict, dict, str]:
    path = directory / "daily-x-manifest.json"
    raw = path.read_bytes()
    manifest = json.loads(raw)
    names = set(manifest.get("collections", {}))
    if manifest.get("version") != 1 or manifest.get("status") != "ready" or not set(COLLECTIONS).issubset(names) or names - set(COLLECTIONS) - {"portfolio-signals"}:
        raise ValueError("Not a complete ready daily X release")
    collections = {}
    for name in sorted(names):
        content = (directory / f"{name}.json").read_bytes()
        entry = manifest["collections"][name]
        if hashlib.sha256(content).hexdigest() != entry["sha256"]:
            raise ValueError(f"Checksum mismatch: {name}")
        items = json.loads(content)
        if not isinstance(items, list) or len(items) != entry["count"]:
            raise ValueError(f"Count mismatch: {name}")
        if any(not isinstance(item, dict) or not item.get("id") or not is_x(name, item) for item in items):
            raise ValueError(f"Invalid/non-X document: {name}")
        if len({item["id"] for item in items}) != len(items):
            raise ValueError(f"Duplicate IDs: {name}")
        if name != "portfolio-signals":
            validator = Profile if name == "smart-accounts" else View
            for item in items:
                validator.model_validate_json(json.dumps(item), strict=True)
        collections[name] = items
    author_ids = {item["id"] for item in collections["smart-accounts"]}
    if not author_ids or any(item.get("authorId") not in author_ids for name in COLLECTIONS[1:] for item in collections[name]):
        raise ValueError("Missing author references")
    if path.read_bytes() != raw:
        raise ValueError("Manifest changed during validation")
    collections.setdefault("portfolio-signals", build_portfolio_signals(collections["smart-account-updates"]))
    digest = hashlib.sha256(raw + json.dumps(collections["portfolio-signals"], sort_keys=True).encode()).hexdigest()
    return collections, manifest, digest


def publish(directory: Path, database_url: str, *, apply: bool = False, allow_drop: bool = False,
            rollback: bool = False) -> dict:
    collections, manifest, digest = load_release(directory)
    as_of = datetime.fromisoformat(manifest["asOf"])
    now = datetime.now(timezone.utc)
    if as_of.tzinfo is None or as_of > now + timedelta(minutes=5):
        raise ValueError("Invalid release timestamp")
    if not rollback and as_of < now - timedelta(hours=36):
        raise ValueError("Release is older than 36 hours; use explicit --rollback only to restore a previous release")
    if not rollback:
        source_through = datetime.fromisoformat(manifest["sourceThrough"])
        if source_through.tzinfo is None or source_through > now + timedelta(minutes=5) or source_through < now - timedelta(hours=96):
            raise ValueError("Source package is not current; inspect its sourceThrough before daily publication")
    publisher = RealtimeReadModelPublisher(database_url, initialize_schema=False)
    try:
        expected, backup, versions = {}, {}, {}
        with Session(publisher.engine) as session:
            for name in collections:
                marker = session.get(RealtimeReadModelCollection, name)
                expected[name] = marker.content_hash if marker else None
                versions[name] = marker.source_version if marker else None
                items = ([_decode_document(row) for row in session.scalars(select(ReadModelDocument)
                         .where(ReadModelDocument.collection == name).order_by(ReadModelDocument.sort_order))]
                         if marker else _base_collection(session, name))
                backup[name] = [item for item in items if is_x(name, item)]
                if not allow_drop and len(backup[name]) >= 10 and len(collections[name]) < len(backup[name]) * 0.75:
                    raise ValueError(f"{name} would lose more than 25% of X rows; inspect and explicitly --allow-drop")
                prior = re.search(r"(?:^|:)x-daily:(\d{8}T\d{6}Z):", marker.source_version) if marker else None
                if prior and not rollback:
                    if prior.group(1) > as_of.strftime("%Y%m%dT%H%M%SZ"):
                        raise ValueError("A newer daily release is already online")
        result = {"status": "validated", "manifestHash": digest,
                  "counts": {k: len(v) for k, v in collections.items()}, "previousVersions": versions,
                  "target": {"driver": publisher.engine.url.get_backend_name(),
                             "host": publisher.engine.url.host, "port": publisher.engine.url.port,
                             "database": publisher.engine.url.database}, "publicAPIVerified": False}
        if not apply:
            return result
        if all(version and version.endswith(":" + digest) for version in versions.values()):
            result["status"] = "already-published"
            return result
        if os.environ.get("X_INGEST_ENABLED", "true").lower() not in {"0", "false", "no"}:
            raise ValueError("Daily publication requires X_INGEST_ENABLED=false and the realtime X writer stopped")
        # Keep an operator rollback package before the atomic replacement.
        backup_dir = directory / "backups" / now.strftime("%Y%m%dT%H%M%S%fZ")
        backup_dir.mkdir(parents=True)
        entries = {}
        for name, items in backup.items():
            raw = (json.dumps(items, ensure_ascii=False, indent=2) + "\n").encode()
            (backup_dir / f"{name}.json").write_bytes(raw)
            entries[name] = {"count": len(items), "sha256": hashlib.sha256(raw).hexdigest()}
        (backup_dir / "daily-x-manifest.json").write_text(json.dumps({
            "version": 1, "status": "ready", "asOf": now.isoformat(), "collections": entries,
            "rollbackOf": digest, "previousVersions": versions,
        }), encoding="utf-8")
        published = publisher.publish_partitioned(collections, producer="x-daily",
            source_version=f"x-daily:{as_of.strftime('%Y%m%dT%H%M%SZ')}:{digest}",
            owns_document=is_x, expected_hashes=expected)
        # Verify committed hashes, not just that the command returned successfully.
        with Session(publisher.engine) as session:
            for name, expected_hash in published.content_hashes.items():
                marker = session.get(RealtimeReadModelCollection, name)
                if marker is None or marker.content_hash != expected_hash:
                    raise RuntimeError("Post-publication verification failed")
        result.update(status="published", publishedAt=published.updated_at.isoformat(),
                      collectionHashes=published.content_hashes, rollbackDirectory=str(backup_dir))
        receipt = directory / "publication.json"
        temporary = receipt.with_suffix(".tmp")
        temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(receipt)
        return result
    finally:
        publisher.dispose()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-drop", action="store_true")
    parser.add_argument("--rollback", action="store_true")
    args = parser.parse_args()
    url = os.environ.get("BSMART_READ_MODEL_DATABASE_URL")
    if not url:
        parser.error("BSMART_READ_MODEL_DATABASE_URL is required (never pass credentials as CLI arguments)")
    print(json.dumps(publish(args.input_dir, url, apply=args.apply,
                             allow_drop=args.allow_drop, rollback=args.rollback), indent=2))


if __name__ == "__main__":
    main()
