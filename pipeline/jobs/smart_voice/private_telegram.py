"""End-to-end orchestration for one public Telegram Private SV report."""
from __future__ import annotations

import datetime as dt
import os
import sqlite3
from pathlib import Path
from typing import Any

from ...domain.smart_voice.integral_scoring import (
    NARRATIVE_BENCHMARKS,
    SECTOR_BENCHMARKS,
)
from ...domain.smart_voice.private_report import build_private_report
from ...domain.smart_voice.private_audit import audit_private_telegram_calls
from ...domain.smart_voice.private_telegram import (
    build_telegram_candidates,
    candidate_tickers,
)
from ...domain.smart_voice.private_web_export import write_private_web_export
from ...domain.smart_voice.v0_impl import extract_calls, investor_key, settle_calls
from ...platforms.market_data import price_history
from ...platforms.telegram import crawl_public_channel


STAGES = ("crawl", "candidates", "prices", "extract", "audit", "settle", "report")


def _connection(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(path), timeout=120)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=120000")
    return con


def _price_window(con: sqlite3.Connection, handle: str) -> tuple[str, str]:
    row = con.execute(
        "SELECT MIN(published_at) AS first_at FROM telegram_public_message WHERE channel_handle=?",
        (handle,),
    ).fetchone()
    first_at = str(row["first_at"] or "") if row else ""
    first_day = (
        dt.date.fromisoformat(first_at[:10]) - dt.timedelta(days=35)
        if first_at
        else dt.date(2020, 1, 1)
    )
    return first_day.isoformat(), dt.datetime.now(dt.timezone.utc).date().isoformat()


def _copy_ticker_metadata(
    private: sqlite3.Connection,
    reference_db_path: Path,
    tickers: set[str],
) -> None:
    private.execute(
        """
        CREATE TABLE IF NOT EXISTS ticker_meta (
          ticker TEXT PRIMARY KEY,
          company_name TEXT DEFAULT '',
          sector TEXT DEFAULT '',
          aliases TEXT
        )
        """
    )
    if not tickers:
        return
    reference = sqlite3.connect(str(reference_db_path))
    reference.row_factory = sqlite3.Row
    slots = ",".join("?" for _ in tickers)
    rows = reference.execute(
        f"SELECT ticker,company_name,sector,aliases FROM ticker_meta WHERE ticker IN ({slots})",
        sorted(tickers),
    ).fetchall()
    reference.close()
    private.executemany(
        """
        INSERT INTO ticker_meta(ticker,company_name,sector,aliases)
        VALUES (?,?,?,?)
        ON CONFLICT(ticker) DO UPDATE SET
          company_name=excluded.company_name,
          sector=excluded.sector,
          aliases=excluded.aliases
        """,
        [
            (
                str(row["ticker"]),
                str(row["company_name"] or ""),
                str(row["sector"] or ""),
                str(row["aliases"] or "[]"),
            )
            for row in rows
        ],
    )
    private.commit()


def _prepare_price_history(
    con: sqlite3.Connection,
    *,
    private_db_path: Path,
    reference_db_path: Path,
    handle: str,
    start: str,
    end: str,
    workers: int,
) -> dict[str, Any]:
    calls = candidate_tickers(con, handle)
    benchmarks = {"SPY", *SECTOR_BENCHMARKS.values(), *NARRATIVE_BENCHMARKS.values()}
    tickers = calls | benchmarks
    _copy_ticker_metadata(con, reference_db_path, tickers)
    os.environ.setdefault("SV_PRICE_YAHOO_FALLBACK", "1")
    price_history.run(
        db=str(private_db_path),
        start=start,
        end=end,
        only=",".join(sorted(tickers)),
        workers=workers,
        sleep=0.05,
    )
    available = {
        str(row["ticker"]).upper()
        for row in con.execute(
            "SELECT ticker FROM price_daily GROUP BY ticker HAVING COUNT(*) >= 80"
        )
    }
    return {
        "requested_call_tickers": len(calls),
        "requested_benchmarks": len(benchmarks),
        "available_call_tickers": len(calls & available),
        "missing_call_tickers": sorted(calls - available),
        "available_benchmarks": sorted(benchmarks & available),
    }


def run_private_telegram_report(
    *,
    handle: str,
    private_db_path: str = "",
    reference_db_path: str = "",
    output_dir: str = "",
    web_output_path: str = "",
    stage: str = "all",
    max_pages: int = 0,
    crawl_sleep: float = 0.2,
    candidate_limit: int = 0,
    min_candidate_score: float = 0.0,
    extract_limit: int = 0,
    workers: int = 4,
    force_extract: bool = False,
    proxy: str = "",
) -> dict[str, Any]:
    """Run the isolated public-channel MVP without touching public SV exports."""
    selected = list(STAGES) if stage == "all" else [stage]
    if any(value not in STAGES for value in selected):
        raise ValueError(f"unsupported Private SV stage: {stage}")
    normalized_handle = handle.strip().lstrip("@").lower()
    root = Path(__file__).resolve().parents[3]
    private_path = (
        Path(private_db_path).expanduser().resolve()
        if private_db_path
        else root / "data" / "private_sv" / f"{normalized_handle}.db"
    )
    reference_path = (
        Path(reference_db_path).expanduser().resolve()
        if reference_db_path
        else root / "data" / "dev.db"
    )
    report_path = (
        Path(output_dir).expanduser().resolve()
        if output_dir
        else root / "data" / "reports" / "private_smart_voice" / normalized_handle
    )
    web_path = (
        Path(web_output_path).expanduser().resolve()
        if web_output_path
        else root / "web" / "lib" / "data" / "privateSmartVoiceMvp.json"
    )
    if not reference_path.exists():
        raise FileNotFoundError(f"reference database not found: {reference_path}")
    if proxy:
        os.environ["HTTP_PROXY"] = proxy
        os.environ["HTTPS_PROXY"] = proxy

    con = _connection(private_path)
    result: dict[str, Any] = {
        "handle": normalized_handle,
        "private_db": str(private_path),
        "output_dir": str(report_path),
    }
    try:
        if "crawl" in selected:
            result["crawl"] = crawl_public_channel(
                con,
                handle=normalized_handle,
                max_pages=max_pages,
                sleep_seconds=crawl_sleep,
            )
        if "candidates" in selected:
            result["candidates"] = build_telegram_candidates(
                con,
                reference_db_path=reference_path,
                handle=normalized_handle,
                limit=candidate_limit,
                min_score=min_candidate_score,
            )
        if "prices" in selected:
            start, end = _price_window(con, normalized_handle)
            result["prices"] = _prepare_price_history(
                con,
                private_db_path=private_path,
                reference_db_path=reference_path,
                handle=normalized_handle,
                start=start,
                end=end,
                workers=workers,
            )
        if "extract" in selected:
            result["extracted"] = extract_calls(
                con,
                limit=extract_limit,
                workers=workers,
                force=force_extract,
                extract_mode="rank",
                per_author_min=0,
                per_author_max=max(1, extract_limit or 100_000),
                sources={"telegram"},
                author_filter={investor_key("telegram", normalized_handle)},
            )
        if "audit" in selected:
            result["audit"] = audit_private_telegram_calls(
                con,
                investor_id=investor_key("telegram", normalized_handle),
                workers=workers,
                limit=extract_limit,
                force=force_extract,
            )
        if "settle" in selected:
            result["settlement_rows"] = settle_calls(con, sources={"telegram"})
        if "report" in selected:
            report = build_private_report(
                con,
                reference_db_path=reference_path,
                handle=normalized_handle,
                output_dir=report_path,
            )
            web_export = write_private_web_export(con, report, web_path)
            result["report"] = {
                "sv": report["score"]["sv"],
                "confidence": report["score"]["confidence"],
                "settled_calls": report["score"]["settled_calls"],
                "report_json": str(report_path / "report.json"),
                "report_markdown": str(report_path / "report.md"),
                "calls_csv": str(report_path / "calls.csv"),
                "web_export": web_export,
            }
    finally:
        con.close()
    return result
