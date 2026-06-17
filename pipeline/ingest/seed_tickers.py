"""seed ticker 字典到 ticker_meta。

优先从 SEC 官方 company_tickers.json 拉全量（需合规 User-Agent）；
失败或 --fallback 时用随仓库的内置热门字典（pipeline/data/fallback_tickers.json）。
"""
from __future__ import annotations

import json

from ..common.config import PKG_DATA_DIR, settings
from ..common.db import session_scope
from ..common.models import TickerMeta

SEC_URL = "https://www.sec.gov/files/company_tickers.json"


def fetch_sec_tickers(user_agent: str) -> list[dict]:
    import requests

    resp = requests.get(SEC_URL, headers={"User-Agent": user_agent}, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    rows: list[dict] = []
    for v in data.values():
        tk = str(v.get("ticker", "")).upper().strip()
        if not tk:
            continue
        rows.append(
            {
                "ticker": tk,
                "name": str(v.get("title", "")).title(),
                "cik": str(v.get("cik_str", "")) or None,
                "sector": None,
            }
        )
    return rows


def load_fallback() -> list[dict]:
    path = PKG_DATA_DIR / "fallback_tickers.json"
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def seed_cn_hk() -> int:
    """把策划的中概/港股/A 股字典（cn_hk_tickers.json）merge 进 ticker_meta。

    含 market='cn'、exchange、丰富 aliases（英文/拼音/中文/数字码），供「中概·港股」看板抽取。
    不动 SEC 美股全量；与之并存（BABA 等 ADR 会被这里的中文名/别名覆盖增强）。
    """
    path = PKG_DATA_DIR / "cn_hk_tickers.json"
    with open(path, "r", encoding="utf-8") as f:
        rows = json.load(f)
    n = 0
    with session_scope() as s:
        for r in rows:
            s.merge(TickerMeta(
                ticker=r["ticker"].upper(),
                company_name=r.get("name", ""),
                cik=None,
                exchange=r.get("exchange"),
                sector=r.get("sector"),
                market=r.get("market", "cn"),
                is_active=True,
                aliases=r.get("aliases"),
            ))
            n += 1
    print(f"[seed-cn-hk] 写入/更新中概·港股 ticker_meta：{n} 行。")
    return n


def seed_tickers(use_fallback: bool = False) -> int:
    rows: list[dict] = []
    source = "fallback"
    if not use_fallback:
        ua = settings.reddit_user_agent or "reddit-kaito-pro (contact: admin@example.com)"
        try:
            rows = fetch_sec_tickers(ua)
            source = "SEC"
        except Exception as e:  # noqa: BLE001
            print(f"[seed] SEC 拉取失败（{e}），改用内置 fallback 字典。")
            rows = []
    if not rows:
        rows = load_fallback()
        source = "fallback"

    # 去重（同一 ticker 只保留首条）
    seen: set[str] = set()
    deduped: list[dict] = []
    for r in rows:
        tk = r["ticker"].upper()
        if tk in seen:
            continue
        seen.add(tk)
        deduped.append(r)
    rows = deduped

    n = 0
    with session_scope() as s:
        for r in rows:
            s.merge(
                TickerMeta(
                    ticker=r["ticker"].upper(),
                    company_name=r.get("name", ""),
                    cik=r.get("cik"),
                    exchange=r.get("exchange"),
                    sector=r.get("sector"),
                    is_active=True,
                    aliases=r.get("aliases"),
                )
            )
            n += 1
    print(f"[seed] 来源={source}，写入/更新 ticker_meta：{n} 行。")
    return n


if __name__ == "__main__":
    import sys

    seed_tickers(use_fallback="--fallback" in sys.argv)
