"""Export existing Smart Account rankings for Client API materialization."""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ...domain.smart_voice.client_read_model import build_smart_account_client_collections


def export_smart_account_client_read_model(
    *,
    db_path: str,
    output_dir: str,
    as_of: datetime | None = None,
    update_days: int = 30,
    update_limit: int = 500,
    profile_limit: int = 0,
    update_tickers: tuple[str, ...] = (),
) -> dict[str, Any]:
    database = Path(db_path).resolve()
    if not database.is_file():
        raise FileNotFoundError(f"Smart Account database not found: {database}")
    destination = Path(output_dir).resolve()
    destination.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        collections = build_smart_account_client_collections(
            connection,
            as_of=as_of or datetime.now(timezone.utc),
            update_days=update_days,
            update_limit=update_limit,
            profile_limit=profile_limit,
            update_tickers=update_tickers,
        )
    finally:
        connection.close()

    for collection, documents in collections.items():
        target = destination / f"{collection}.json"
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(documents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(target)

    return {
        "database": str(database),
        "output": str(destination),
        "profiles": len(collections["smart-accounts"]),
        "updates": len(collections["smart-account-updates"]),
        "evidence": len(collections["smart-account-evidence"]),
    }
