"""抓各 gr 标的最新价（Yahoo 15m chart），写 gr_quote，供标的页展示「最新价 + 涨跌幅」。

Yahoo: query1.finance.yahoo.com/v8/finance/chart/{TICKER}?interval=15m&range=1d
→ meta.regularMarketPrice（最新价）, meta.chartPreviousClose（前收）, meta.regularMarketTime。
纯静态站没有逐笔实时——价格随本脚本/构建刷新（约 15 分钟延迟的最新报价）。
本地验证：DATABASE_URL='sqlite:///./data/dev.db' python -m pipeline.manage gr-quote
"""
from __future__ import annotations

import datetime as dt

import requests

from ..common.db import engine, session_scope
from ..common.models import Base, GrQuote
from .global_retail_crawl import load_targets

YQ = "https://query1.finance.yahoo.com/v8/finance/chart/{sym}"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"


def _ensure_tables() -> None:
    Base.metadata.create_all(engine, tables=[GrQuote.__table__])


def fetch_quotes() -> dict:
    _ensure_tables()
    sess = requests.Session()
    sess.headers.update({"User-Agent": UA})
    ok, fail = 0, 0
    with session_scope() as s:
        for tgt in load_targets():
            ticker = str(tgt["ticker"]).upper()
            try:
                r = sess.get(YQ.format(sym=ticker), params={"interval": "15m", "range": "1d"}, timeout=20)
                r.raise_for_status()
                meta = r.json()["chart"]["result"][0]["meta"]
                price = float(meta.get("regularMarketPrice") or 0)
                prev = float(meta.get("chartPreviousClose") or meta.get("previousClose") or 0)
            except Exception as e:  # noqa: BLE001 — 单个标的失败不影响其余
                print(f"  [quote] {ticker} 失败：{e}")
                fail += 1
                continue
            if not price or not prev:
                print(f"  [quote] {ticker} 无价格，跳过")
                fail += 1
                continue
            change_pct = round((price - prev) / prev * 100, 2) if prev else 0.0
            tsec = meta.get("regularMarketTime")
            try:
                asof = dt.datetime.utcfromtimestamp(int(tsec)).strftime("%Y-%m-%d %H:%M UTC") if tsec else ""
            except Exception:  # noqa: BLE001
                asof = ""
            s.merge(GrQuote(
                ticker=ticker,
                price=round(price, 2),
                prev_close=round(prev, 2),
                change_pct=change_pct,
                currency=str(meta.get("currency") or "USD"),
                asof=asof,
                updated_at=dt.datetime.utcnow(),
            ))
            ok += 1
            print(f"  [quote] {ticker} {price:.2f} ({change_pct:+.2f}%)")
    print(f"✅ gr-quote: {ok} 成功 / {fail} 失败")
    return {"ok": ok, "fail": fail}
