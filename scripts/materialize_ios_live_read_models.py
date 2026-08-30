#!/usr/bin/env python3
"""Materialize the local iOS read model from verified project data sources."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from pipeline.domain.smart_voice.hyperliquid import build_hyperliquid_client_collections
from pipeline.jobs.smart_voice.client_read_model import export_smart_account_client_read_model
from services.client_api.config import ClientAPISettings
from services.client_api.read_models import READ_MODEL_COLLECTIONS, ReadModelPublisher


def _load_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"Live source {path} must contain a JSON object.")
    return payload


def _load_array(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or any(not isinstance(item, dict) for item in payload):
        raise RuntimeError(f"Live collection {path} must contain an object array.")
    return payload


def materialize_live_read_models(
    *,
    source_database: Path,
    smart_money_payload: Path,
    staging_dir: Path,
    read_model_database_url: str,
    source_version: str | None = None,
    include_historical_updates: bool = True,
) -> dict[str, Any]:
    staging_dir.mkdir(parents=True, exist_ok=True)
    account_result = export_smart_account_client_read_model(
        db_path=str(source_database),
        output_dir=str(staging_dir),
        update_days=30,
        update_limit=500,
        profile_limit=0,
    )
    exported_account_updates = _load_array(staging_dir / "smart-account-updates.json")
    account_updates = exported_account_updates if include_historical_updates else []
    account_evidence = _load_array(staging_dir / "smart-account-evidence.json")
    smart_accounts = _load_array(staging_dir / "smart-accounts.json")
    payload = _load_object(smart_money_payload)
    source = payload.get("source") if isinstance(payload.get("source"), dict) else {}
    if source.get("provider") != "hyperdash":
        raise RuntimeError("The iOS live seed requires a verified Hyperdash payload.")
    if not payload.get("generatedAt") or not payload.get("leaderboard"):
        raise RuntimeError("The Hyperdash payload is missing its timestamp or account cohort.")

    projected = build_hyperliquid_client_collections(
        payload,
        smart_account_updates=account_updates,
    )
    collections: dict[str, list[dict[str, Any]]] = {
        name: [] for name in READ_MODEL_COLLECTIONS
    }
    collections.update(projected)
    collections["smart-account-updates"] = account_updates
    collections["smart-account-evidence"] = account_evidence
    collections["smart-accounts"] = smart_accounts

    resolved_version = source_version or (
        f"ios-live:{payload['generatedAt']}:{account_result['profiles']}"
    )
    publisher = ReadModelPublisher(read_model_database_url, channel="production")
    try:
        result = publisher.publish(collections, source_version=resolved_version)
    finally:
        publisher.dispose()
    return {
        "releaseId": result.release_id,
        "sourceVersion": resolved_version,
        "source": source.get("provider"),
        "sourceUpdatedAt": source.get("updatedAt") or payload.get("generatedAt"),
        "existing": result.existing,
        "counts": result.counts,
    }


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Seed the local iOS Client API with real Smart Account and Hyperdash data."
    )
    parser.add_argument("--source-database", type=Path, default=root / "data" / "dev.db")
    parser.add_argument(
        "--smart-money-payload",
        type=Path,
        default=root / "web" / "lib" / "data" / "hyperliquidSmartMoney.json",
    )
    parser.add_argument(
        "--staging-dir",
        type=Path,
        default=root / "data" / "runtime" / "ios-live-staging",
    )
    parser.add_argument("--source-version", default="")
    parser.add_argument(
        "--exclude-historical-updates",
        action="store_true",
        help="Keep author profiles but let realtime producers own all current updates and signals.",
    )
    arguments = parser.parse_args()
    if not arguments.source_database.is_file():
        parser.error(f"source database does not exist: {arguments.source_database}")
    if not arguments.smart_money_payload.is_file():
        parser.error(f"Smart Money payload does not exist: {arguments.smart_money_payload}")

    settings = ClientAPISettings.from_environment()
    database_url = os.environ.get(
        "BSMART_READ_MODEL_DATABASE_URL",
        settings.read_model_database_url or settings.database_url,
    )
    result = materialize_live_read_models(
        source_database=arguments.source_database.resolve(),
        smart_money_payload=arguments.smart_money_payload.resolve(),
        staging_dir=arguments.staging_dir.resolve(),
        read_model_database_url=database_url,
        source_version=arguments.source_version.strip() or None,
        include_historical_updates=not arguments.exclude_historical_updates,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
