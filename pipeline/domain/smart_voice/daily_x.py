"""Daily X scope and readiness checks around the unchanged Score engine."""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime

from . import v0_impl as score
from .client_read_model import build_smart_account_client_collections
from ..opinions.translation_completeness import validate_translation


def connect(database: str) -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{database}?mode=rw", uri=True, timeout=30)
    con.row_factory = sqlite3.Row
    # This workflow never migrates the source database.
    for table in ("x_opinion", "sv_call_candidate", "sv_call", "sv_call_settlement", "sv_investor_score", "price_daily", "kol_refined"):
        con.execute(f"SELECT 1 FROM {table} LIMIT 1")
    con.execute("SELECT trans_zh,trans_en FROM kol_refined LIMIT 0")
    return con


def candidates(con: sqlite3.Connection, post_ids: set[str]) -> list[dict]:
    result = []
    ids = sorted(post_ids)
    for offset in range(0, len(ids), 400):
        batch = ids[offset:offset + 400]
        result.extend(dict(row) for row in con.execute(
            f"SELECT c.*, s.candidate_id AS processed_id FROM sv_call_candidate c "
            f"LEFT JOIN sv_call s ON s.candidate_id=c.candidate_id "
            f"WHERE c.source='x' AND c.tweet_id IN ({','.join('?' for _ in batch)})", batch))
    return result


def extract(con: sqlite3.Connection, post_ids: set[str], workers: int, max_calls: int) -> dict:
    rows = candidates(con, post_ids)
    pending = [r for r in rows if not r["processed_id"]]
    if len(pending) > max_calls:
        raise RuntimeError(f"{len(pending)} pending Calls exceed the explicitly allowed {max_calls}")
    if pending:
        score.extract_calls(con, 0, workers, False, "rank", 0, 0, sources={"x"},
                            candidate_ids={r["candidate_id"] for r in pending}, initialize_schema=False,
                            complete_x_text=True)
    remaining = sum(not r["processed_id"] for r in candidates(con, post_ids))
    if remaining:
        raise RuntimeError(f"{remaining} Calls remain unprocessed; publication blocked")
    return {"candidates": len(rows), "processed": len(pending)}


def collections(con: sqlite3.Connection, as_of: datetime) -> dict:
    return {name: [item for item in items if item.get("platform") == "X"]
            for name, items in build_smart_account_client_collections(
                con, as_of=as_of, update_limit=0, update_days=30).items()}


def reading_rows(con: sqlite3.Connection, documents: dict) -> list[dict]:
    rows = {}
    for document in documents["smart-account-updates"]:
        key = (document["sourcePostId"], document["ticker"])
        rows[key] = {"source": "x", "item_id": key[0], "ticker": key[1],
                     "txt": document.get("originalText") or "", "created": document["publishedAt"]}
    return list(rows.values())


def validate_readings(con: sqlite3.Connection, rows: list[dict], *, require_translation: bool = True) -> dict:
    failures = []
    for row in rows:
        saved = con.execute("SELECT reason_zh,reason_en,trans_zh,trans_en FROM kol_refined "
                            "WHERE source='x' AND item_id=? AND ticker=?",
                            (row["item_id"], row["ticker"])).fetchone()
        summaries_ready = saved and saved["reason_zh"] and saved["reason_en"]
        translation_ready = not require_translation or (saved and validate_translation(
            row["txt"], {"zh": saved["trans_zh"] or "", "en": saved["trans_en"] or ""}))
        if not row["txt"].strip() or not summaries_ready or not translation_ready:
            failures.append(f"{row['item_id']}:{row['ticker']}")
    if failures:
        raise RuntimeError(f"Incomplete reading/translation for {len(failures)} published views: {failures[:5]}")
    return {"readyViews": len(rows), "translationMode": "required" if require_translation else "skipped"}


def price_scope(con: sqlite3.Connection) -> list[str]:
    tickers = {r[0] for r in con.execute("SELECT DISTINCT ticker FROM sv_call WHERE source='x' "
                "AND is_actionable_call=1 AND datetime(created_at)>=datetime('now','-370 days')")}
    # Reuse all existing benchmark series; never fabricate prices for missing symbols.
    tickers |= {"SPY", "QQQ", "XLK", "XLF", "XLE", "XLV", "XLY", "XLP", "XLI", "XLB", "XLU", "XLRE", "XLC", "SMH"}
    return sorted(tickers)
