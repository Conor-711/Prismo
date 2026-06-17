"""抓标的日 K 收盘价（Naver 日K接口），写 asia_price，供「价格 vs 情绪/声量」叠加指数图。

Naver 日K：api.stock.naver.com/chart/foreign/item/{code}?periodType=dayCandle&count=N
→ {priceInfos:[{localDate:"YYYYMMDD", closePrice, openPrice, accumulatedTradingVolume}]}
四标的均走 foreignStock 代码（NVDA.O/MU.O/NOK/SPCX.O）；SpaceX 为 pre-IPO 追踪价、历史稀疏。
"""
from __future__ import annotations

import datetime as dt

import requests
from sqlalchemy import delete

from ..common.db import session_scope
from ..common.models import AsiaPrice

NAVER_CHART = "https://api.stock.naver.com/chart/foreign/item/{code}"
UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"


def fetch_prices(days: int = 14) -> dict:
    from .asia_crawl import load_targets, _ensure_tables
    _ensure_tables()
    sess = requests.Session()
    sess.headers.update({"User-Agent": UA, "Referer": "https://m.stock.naver.com/"})
    stats: dict[str, int] = {}

    with session_scope() as s:
        for tgt in load_targets():
            code = str(tgt.get("naver_code") or "")
            ticker = tgt["ticker"]
            if not code:
                continue
            try:
                r = sess.get(NAVER_CHART.format(code=code),
                             params={"periodType": "dayCandle", "count": days + 6}, timeout=20)
            except requests.RequestException as e:
                print(f"  [price] {ticker} 网络错误：{e}")
                continue
            if r.status_code != 200:
                print(f"  [price] {ticker} HTTP {r.status_code}")
                continue
            try:
                pis = (r.json() or {}).get("priceInfos") or []
            except ValueError:
                continue
            rows = []
            for p in pis[-days:]:
                ld = str(p.get("localDate") or "")
                if len(ld) != 8:
                    continue
                rows.append(AsiaPrice(
                    ticker=ticker, day=f"{ld[:4]}-{ld[4:6]}-{ld[6:8]}",
                    close=float(p.get("closePrice", 0) or 0), open=float(p.get("openPrice", 0) or 0),
                    volume=int(p.get("accumulatedTradingVolume", 0) or 0), currency="USD",
                    updated_at=dt.datetime.utcnow(),
                ))
            # 该标的全量重刷（先删后插，避免 (ticker,day) 唯一约束冲突）
            s.execute(delete(AsiaPrice).where(AsiaPrice.ticker == ticker))
            for row in rows:
                s.add(row)
            stats[ticker] = len(rows)
            print(f"  [price] {ticker}({code}): {len(rows)} 日K，最新 {rows[-1].day if rows else '-'} = {rows[-1].close if rows else '-'}")

    print(f"[asia-price] 完成 {stats}")
    return stats


if __name__ == "__main__":
    fetch_prices()
