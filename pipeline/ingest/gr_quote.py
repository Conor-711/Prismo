"""抓各 gr 标的最新价，写 gr_quote，供标的页/总览展示「最新价 + 涨跌幅」。

数据源（按优先级，均无需 API key）：
  1) Nasdaq  api.nasdaq.com/api/quote/{T}/info?assetclass=stocks|etf  —— 主源，稳定、少封 IP。
  2) Yahoo   query1.finance.yahoo.com/v8/finance/chart/{T}            —— 兜底（部分机房 IP 会被 429）。
纯静态站没有逐笔实时——价格随本脚本/构建刷新（最新报价，约 15 分钟延迟）。
本地验证：DATABASE_URL='sqlite:///./data/dev.db' python -m pipeline.manage gr-quote
"""
from __future__ import annotations

import datetime as dt
import time

import requests

from ..common.db import engine, session_scope
from ..common.models import Base, GrQuote
from .global_retail_crawl import load_targets

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
NASDAQ = "https://api.nasdaq.com/api/quote/{sym}/info"
YQ = "https://query1.finance.yahoo.com/v8/finance/chart/{sym}"


def _ensure_tables() -> None:
    Base.metadata.create_all(engine, tables=[GrQuote.__table__])


def _num(s) -> float:
    """'$204.65' / '-1.33%' / '1,234.5' → float；失败返回 0。"""
    try:
        return float(str(s).replace("$", "").replace(",", "").replace("%", "").strip())
    except Exception:  # noqa: BLE001
        return 0.0


def _from_nasdaq(sess: requests.Session, ticker: str):
    """Nasdaq 报价 → (price, prev_close, change_pct, asof)；失败返回 None。"""
    for asset in ("stocks", "etf"):
        try:
            r = sess.get(NASDAQ.format(sym=ticker), params={"assetclass": asset}, timeout=20)
            r.raise_for_status()
            pd = ((r.json() or {}).get("data") or {}).get("primaryData") or {}
            price = _num(pd.get("lastSalePrice"))
            if not price:
                continue
            net = _num(pd.get("netChange"))
            pct = _num(pd.get("percentageChange"))
            # 涨跌幅按 deltaIndicator 定负号（netChange/percentageChange 偶尔不带符号）。
            if str(pd.get("deltaIndicator")) == "down":
                net, pct = -abs(net), -abs(pct)
            prev = round(price - net, 2) if net else (round(price / (1 + pct / 100), 2) if pct else price)
            return round(price, 2), prev, round(pct, 2), str(pd.get("lastTradeTimestamp") or "")
        except Exception:  # noqa: BLE001 — 换下一个 assetclass / 兜底源
            continue
    return None


def _from_yahoo(sess: requests.Session, ticker: str):
    """Yahoo 15m chart → (price, prev_close, change_pct, asof)；失败返回 None。"""
    try:
        r = sess.get(YQ.format(sym=ticker), params={"interval": "15m", "range": "1d"}, timeout=20)
        r.raise_for_status()
        meta = r.json()["chart"]["result"][0]["meta"]
        price = float(meta.get("regularMarketPrice") or 0)
        prev = float(meta.get("chartPreviousClose") or meta.get("previousClose") or 0)
        if not price or not prev:
            return None
        tsec = meta.get("regularMarketTime")
        asof = dt.datetime.utcfromtimestamp(int(tsec)).strftime("%Y-%m-%d %H:%M UTC") if tsec else ""
        return round(price, 2), round(prev, 2), round((price - prev) / prev * 100, 2), asof
    except Exception:  # noqa: BLE001
        return None


def fetch_quotes() -> dict:
    _ensure_tables()
    sess = requests.Session()
    sess.headers.update({"User-Agent": UA, "Accept": "application/json"})
    ok, fail = 0, 0
    with session_scope() as s:
        for tgt in load_targets():
            ticker = str(tgt["ticker"]).upper()
            q = _from_nasdaq(sess, ticker) or _from_yahoo(sess, ticker)
            if not q:
                print(f"  [quote] {ticker} 失败：无可用数据源")
                fail += 1
                continue
            price, prev, change_pct, asof = q
            s.merge(GrQuote(
                ticker=ticker,
                price=price,
                prev_close=prev,
                change_pct=change_pct,
                currency="USD",
                asof=asof,
                updated_at=dt.datetime.utcnow(),
            ))
            ok += 1
            print(f"  [quote] {ticker} {price:.2f} ({change_pct:+.2f}%)")
            time.sleep(0.25)
    print(f"✅ gr-quote: {ok} 成功 / {fail} 失败")
    return {"ok": ok, "fail": fail}
