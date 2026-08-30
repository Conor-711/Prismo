#!/usr/bin/env python3
"""Initialize X realtime PostgreSQL schemas and publish the formal X ranking."""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from pipeline.common.config import normalize_db_url
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from services.client_api.read_models import RealtimeReadModelPublisher
from services.client_api.state_store import ClientStateStore


RANKING_COLUMNS = (
    "investor_id",
    "source",
    "name",
    "handle",
    "language",
    "sv",
    "raw_z",
    "confidence",
    "n_eff",
    "settled_calls",
    "active_days",
    "covered_tickers",
    "top_tickers_json",
    "top_narratives_json",
    "platform_scores_json",
    "horizon_scores_json",
    "narrative_scores_json",
    "ticker_scores_json",
    "concentration_json",
    "rationale_zh",
    "rationale_en",
    "updated_at",
    "ability_scores_json",
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-db", default=str(ROOT / "data" / "dev.db"))
    parser.add_argument("--target-url", default="")
    parser.add_argument("--pool-limit", type=int, default=10)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def _target_url(explicit: str) -> str:
    load_dotenv(ROOT / ".env")
    value = (
        explicit
        or os.environ.get("BSMART_X_DATABASE_URL", "")
        or os.environ.get("DATABASE_URL", "")
    ).strip()
    if not value:
        raise RuntimeError("DATABASE_URL or BSMART_X_DATABASE_URL is required")
    if value.startswith("sqlite"):
        raise RuntimeError("The realtime production target must be PostgreSQL")
    return normalize_db_url(value)


def _ranking_rows(source_db: Path) -> list[dict[str, Any]]:
    if not source_db.is_file():
        raise FileNotFoundError(source_db)
    with sqlite3.connect(source_db) as connection:
        connection.row_factory = sqlite3.Row
        table_columns = {
            row[1] for row in connection.execute("pragma table_info(sv_investor_score)")
        }
        if not {"investor_id", "source", "handle", "sv", "n_eff", "settled_calls"}.issubset(
            table_columns
        ):
            raise RuntimeError("The source database has no compatible formal Score ranking")
        select_columns = [
            column if column in table_columns else f"null as {column}"
            for column in RANKING_COLUMNS
        ]
        rows = connection.execute(
            f"select {', '.join(select_columns)} from sv_investor_score where source='x'"
        ).fetchall()
    return [dict(row) for row in rows]


def _apply_migrations(database_url: str) -> None:
    engine = create_engine(database_url, pool_pre_ping=True, connect_args={"prepare_threshold": None})
    migration_names = (
        "20260806000001_x_smart_account_realtime.sql",
        "20260806000002_realtime_read_model_producers.sql",
        "20260806000003_x_formal_ranking.sql",
        "20260807000004_x_realtime_transport_state.sql",
    )
    try:
        with engine.begin() as connection:
            for name in migration_names:
                sql = (ROOT / "supabase" / "migrations" / name).read_text(encoding="utf-8")
                connection.exec_driver_sql(sql)
    finally:
        engine.dispose()


def _publish_ranking(database_url: str, rows: list[dict[str, Any]]) -> None:
    placeholders = ", ".join(f":{column}" for column in RANKING_COLUMNS)
    columns = ", ".join(RANKING_COLUMNS)
    engine = create_engine(database_url, pool_pre_ping=True, connect_args={"prepare_threshold": None})
    try:
        with engine.begin() as connection:
            connection.execute(text("delete from sv_investor_score where source='x'"))
            connection.execute(
                text(f"insert into sv_investor_score ({columns}) values ({placeholders})"),
                rows,
            )
    finally:
        engine.dispose()


def main() -> None:
    args = _arguments()
    rows = _ranking_rows(Path(args.source_db).resolve())
    formal = [
        row
        for row in rows
        if float(row.get("n_eff") or 0) >= 8 and int(row.get("settled_calls") or 0) >= 10
    ]
    if not formal:
        raise RuntimeError("No formal X authors satisfy n_eff>=8 and settled_calls>=10")
    print(
        f"source X authors={len(rows)} formal={len(formal)} "
        f"top_quartile={(len(formal) + 3) // 4}"
    )
    if args.dry_run:
        return

    database_url = _target_url(args.target_url)
    # A fresh local PostgreSQL database has no Client API base tables yet.
    # Create those ORM-owned tables before applying additive SQL migrations
    # that add producer metadata and indexes to them.
    read_models = RealtimeReadModelPublisher(database_url)
    state_store = ClientStateStore(database_url)
    repository: XRealtimeRepository | None = None
    try:
        _apply_migrations(database_url)
        _publish_ranking(database_url, rows)
        repository = XRealtimeRepository(database_url)
        repository.initialize()
        pool = repository.refresh_top_quartile(selection_limit=max(0, args.pool_limit))
        print(
            f"published X ranking={len(rows)} population={pool.population} "
            f"selected={pool.selected} pool={pool.pool_version}"
        )
    finally:
        state_store.dispose()
        read_models.dispose()
        if repository:
            repository.dispose()


if __name__ == "__main__":
    main()
