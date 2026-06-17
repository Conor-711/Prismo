"""全球散户多区看板——中国大陆(雪球)维度的入库。

雪球(xueqiu.com)的散户讨论接口在阿里云 WAF 后面，requests 直连过不去；用 Claude-in-Chrome
真实浏览器（自然过 WAF）在页面内 XHR 拉 `/query/v1/symbol/search/status.json`，把精选标的近 14 天
的帖导出成 JSON。这里把那份 JSON 收进隔离表 gr_post（region='cn'），后续照常 gr-tag/gr-rollup。

导出 JSON 每条形如：
  {"sym","id","u"(作者),"ts"(ms),"like","reply","view","rt","src","t"(正文)}
默认读 data/exports/gr_cn_xueqiu.json。
"""
from __future__ import annotations

import datetime as dt
import json

from ..common.db import session_scope
from ..common.models import GrPost
from .global_retail_crawl import _ensure_tables, load_targets

DEFAULT_PATH = "data/exports/gr_cn_xueqiu.json"


def ingest(path: str = DEFAULT_PATH, since_days: int = 14) -> dict:
    _ensure_tables()
    universe = {t["ticker"] for t in load_targets()}
    with open(path, "r", encoding="utf-8") as f:
        rows = json.load(f)
    since = dt.datetime.utcnow() - dt.timedelta(days=since_days)
    n, skipped = 0, 0
    by: dict[str, int] = {}
    with session_scope() as s:
        for r in rows:
            sym = r.get("sym")
            if sym not in universe:
                skipped += 1
                continue
            ts = r.get("ts")
            created = dt.datetime.utcfromtimestamp(ts / 1000) if ts else dt.datetime.utcnow()
            if created < since:
                continue
            body = (r.get("t") or "").strip()
            if not body:
                continue
            pid = f"cn:xueqiu:{sym}:{r.get('id')}"
            s.merge(GrPost(
                id=pid, region="cn", source="xueqiu", ticker=sym, board_code=sym, lang="zh",
                author=(r.get("u") or "—")[:120], title="", body=body[:1500], label=None,
                url=f"https://xueqiu.com/{r.get('id')}" if r.get("id") else "",
                likes=int(r.get("like", 0) or 0), dislikes=0,
                views=int(r.get("view", 0) or 0), comments=int(r.get("reply", 0) or 0),
                images=0, verified=False,
                created_utc=created, fetched_at=dt.datetime.utcnow(),
            ))
            n += 1
            by[sym] = by.get(sym, 0) + 1
    print(f"[xueqiu] 入库 {n} 帖（跳过非宇宙 {skipped}）→ gr_post region=cn；命中 {len(by)} 标的")
    print(f"[xueqiu] Top: {sorted(by.items(), key=lambda x: -x[1])[:8]}")
    return {"ingested": n, "tickers": len(by)}


if __name__ == "__main__":
    import sys
    ingest(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH)
