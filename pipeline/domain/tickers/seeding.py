"""Ticker catalog seeding domain logic."""
from __future__ import annotations

import json

from ...common.config import PKG_DATA_DIR, settings
from ...common.db import session_scope
from ...common.models import TickerMeta

SEC_URL = "https://www.sec.gov/files/company_tickers.json"


def fetch_sec_tickers(user_agent: str) -> list[dict]:
    import requests

    response = requests.get(SEC_URL, headers={"User-Agent": user_agent}, timeout=30)
    response.raise_for_status()
    data = response.json()
    rows: list[dict] = []
    for value in data.values():
        ticker = str(value.get("ticker", "")).upper().strip()
        if not ticker:
            continue
        rows.append(
            {
                "ticker": ticker,
                "name": str(value.get("title", "")).title(),
                "cik": str(value.get("cik_str", "")) or None,
                "sector": None,
            }
        )
    return rows


def load_fallback() -> list[dict]:
    path = PKG_DATA_DIR / "fallback_tickers.json"
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def seed_cn_hk() -> int:
    """Merge curated China/Hong Kong ticker metadata into ticker_meta."""
    path = PKG_DATA_DIR / "cn_hk_tickers.json"
    with open(path, "r", encoding="utf-8") as handle:
        rows = json.load(handle)
    written = 0
    with session_scope() as session:
        for row in rows:
            session.merge(
                TickerMeta(
                    ticker=row["ticker"].upper(),
                    company_name=row.get("name", ""),
                    cik=None,
                    exchange=row.get("exchange"),
                    sector=row.get("sector"),
                    market=row.get("market", "cn"),
                    is_active=True,
                    aliases=row.get("aliases"),
                )
            )
            written += 1
    print(f"[seed-cn-hk] 写入/更新中概·港股 ticker_meta：{written} 行。")
    return written


def seed_tickers(use_fallback: bool = False) -> int:
    rows: list[dict] = []
    source = "fallback"
    if not use_fallback:
        user_agent = settings.reddit_user_agent or "reddit-kaito-pro (contact: admin@example.com)"
        try:
            rows = fetch_sec_tickers(user_agent)
            source = "SEC"
        except Exception as exc:  # noqa: BLE001
            print(f"[seed] SEC 拉取失败（{exc}），改用内置 fallback 字典。")
            rows = []
    if not rows:
        rows = load_fallback()
        source = "fallback"

    seen: set[str] = set()
    deduped: list[dict] = []
    for row in rows:
        ticker = row["ticker"].upper()
        if ticker in seen:
            continue
        seen.add(ticker)
        deduped.append(row)

    written = 0
    with session_scope() as session:
        for row in deduped:
            session.merge(
                TickerMeta(
                    ticker=row["ticker"].upper(),
                    company_name=row.get("name", ""),
                    cik=row.get("cik"),
                    exchange=row.get("exchange"),
                    sector=row.get("sector"),
                    is_active=True,
                    aliases=row.get("aliases"),
                )
            )
            written += 1
    print(f"[seed] 来源={source}，写入/更新 ticker_meta：{written} 行。")
    return written
