"""抓各标的日 OHLC（Yahoo Finance chart API，免 key、plain ticker），写 price_daily 表。
供标的详情页「个体观点·KOL」第 1 块的价格折线（近 2 周）使用。

Yahoo: query1.finance.yahoo.com/v8/finance/chart/{TICKER}?interval=1d&range=1mo
→ {chart:{result:[{timestamp:[...], indicators:{quote:[{open,high,low,close,volume}]}}]}}

用法（本地）：python3 pipeline/ingest/price_daily.py          # 默认写 data/dev.db
            PRICE_DB=/abs/path.db python3 pipeline/ingest/price_daily.py
标的取自 dev.db 的 gr_ticker（+ ticker_meta 兜底）。每标的全量重刷（先删后插）。

注：这是把价格历史灌进本地快照 dev.db 的务实做法；要长期/生产化，应改为 session_scope
ingester 写云端 Supabase 再 cloud-pull（与 asia_price.py 同范式）。
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sqlite3
import time
import urllib.request

YAHOO = "https://query1.finance.yahoo.com/v8/finance/chart/{t}?interval=1d&range=1mo"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))


def fetch(ticker: str) -> list[tuple]:
    req = urllib.request.Request(YAHOO.format(t=ticker), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.load(r)
    res = ((d.get("chart") or {}).get("result")) or []
    if not res:
        return []
    res = res[0]
    ts = res.get("timestamp") or []
    q = ((res.get("indicators") or {}).get("quote") or [{}])[0]
    op, hi, lo, cl, vo = (q.get(k) or [] for k in ("open", "high", "low", "close", "volume"))
    rows: list[tuple] = []
    for i, t in enumerate(ts):
        c = cl[i] if i < len(cl) else None
        if c is None:
            continue  # 停牌/缺数据
        day = dt.datetime.utcfromtimestamp(t).strftime("%Y-%m-%d")
        o = op[i] if i < len(op) and op[i] is not None else c
        h = hi[i] if i < len(hi) and hi[i] is not None else max(o, c)
        l = lo[i] if i < len(lo) and lo[i] is not None else min(o, c)
        v = vo[i] if i < len(vo) and vo[i] is not None else 0
        rows.append((day, round(o, 2), round(h, 2), round(l, 2), round(c, 2), int(v)))
    return rows


def main() -> None:
    db = os.path.abspath(DB)
    con = sqlite3.connect(db)
    con.execute(
        """CREATE TABLE IF NOT EXISTS price_daily (
             ticker TEXT NOT NULL, day TEXT NOT NULL,
             open REAL, high REAL, low REAL, close REAL, volume INTEGER,
             PRIMARY KEY (ticker, day))"""
    )
    # 标的全集：gr_ticker（详情页折线）∪ yt_video（YouTube 作者页「含权标的表现」需覆盖其点过的票）
    # ∪ SPY（大盘基准，算超额收益/「跑赢大盘」）。ticker_meta 兜底（云端快照两表皆空时）。
    seen: dict[str, None] = {}

    def _add(rows: list) -> None:
        for r in rows:
            t = (r[0] or "").strip().upper()
            if t:
                seen.setdefault(t, None)

    _add(con.execute("SELECT ticker FROM gr_ticker").fetchall())
    try:
        _add(con.execute("SELECT DISTINCT ticker FROM yt_video WHERE ticker <> ''").fetchall())
    except sqlite3.OperationalError:
        pass  # 快照无 yt_video 表 → 跳过
    if not seen:
        _add(con.execute("SELECT symbol FROM ticker_meta").fetchall())
    seen.setdefault("SPY", None)  # 基准
    tickers = list(seen.keys())
    print(f"[price_daily] db={db} 标的数={len(tickers)}（含 SPY 基准 + YouTube 标的）")

    ok = 0
    for t in tickers:
        try:
            rows = fetch(t)
        except Exception as e:  # noqa: BLE001
            print(f"  [price] {t} 失败：{e}")
            continue
        if not rows:
            print(f"  [price] {t} 无数据")
            continue
        con.execute("DELETE FROM price_daily WHERE ticker = ?", (t,))
        con.executemany(
            "INSERT INTO price_daily (ticker, day, open, high, low, close, volume) VALUES (?,?,?,?,?,?,?)",
            [(t, *r) for r in rows],
        )
        con.commit()
        ok += 1
        print(f"  [price] {t}: {len(rows)} 日 K，最新 {rows[-1][0]} = {rows[-1][4]}")
        time.sleep(0.25)  # 礼貌限速

    total = con.execute("SELECT count(*) FROM price_daily").fetchone()[0]
    print(f"[price_daily] 完成：{ok}/{len(tickers)} 标的，共 {total} 行")
    con.close()


if __name__ == "__main__":
    main()
