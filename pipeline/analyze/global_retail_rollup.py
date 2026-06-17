"""全球散户多区看板——滚动聚合 + 跨区派生信号（共识 / 分歧）。

每 (region,ticker) → gr_ticker_region：
  - jp/kr/tw：从 gr_post（已 flash 打标）聚合 14 天窗口的 帖数/多空计数/平均情绪/互动。
  - us      ：**只读**现有 Reddit ticker_rollup（market='us'），不写主表、不污染。
每 ticker → gr_ticker：跨区平均、共识(all_bull/all_bear)、分歧(某区与其余相反)、情绪极差 spread。
全量重算（delete+insert，仿主管线 rollups），避免唯一约束冲突。
"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import delete, select, text

from ..common.db import session_scope
from ..common.models import GrPost, GrTicker, GrTickerRegion
from ..ingest.global_retail_crawl import _ensure_tables, load_targets

LEAN = 0.05  # |情绪均值|>LEAN 才算有方向（否则中性）
REGIONS = ["us", "jp", "kr", "tw", "cn"]  # cn=中国大陆(雪球)


def _mood(score: float) -> str:
    return "bull" if score > LEAN else "bear" if score < -LEAN else "neutral"


def _consensus(region_senti: dict[str, float]) -> tuple[str, float, str]:
    """present 区的情绪均值 → (consensus, spread, divergent_region)。"""
    pres = list(region_senti.items())
    if len(pres) < 2:
        return "sparse", 0.0, ""
    vals = [v for _, v in pres]
    spread = round(max(vals) - min(vals), 3)
    signs = {r: (1 if v > LEAN else -1 if v < -LEAN else 0) for r, v in pres}
    pos = [r for r, sg in signs.items() if sg > 0]
    neg = [r for r, sg in signs.items() if sg < 0]
    n = len(pres)
    if len(pos) == n:
        return "all_bull", spread, ""
    if len(neg) == n:
        return "all_bear", spread, ""
    if len(neg) == 1 and len(pos) == n - 1:  # 一个区看空，其余都看多
        return "divergent", spread, neg[0]
    if len(pos) == 1 and len(neg) == n - 1:  # 一个区看多，其余都看空
        return "divergent", spread, pos[0]
    return "mixed", spread, ""


def rollup(window_days: int = 14) -> dict:
    _ensure_tables()
    targets = load_targets()
    universe = {t["ticker"] for t in targets}
    name_en = {t["ticker"]: t.get("name_en", t["ticker"]) for t in targets}
    name_zh = {t["ticker"]: t.get("name_zh", t["ticker"]) for t in targets}
    since = dt.datetime.utcnow() - dt.timedelta(days=window_days)

    # region_rows[(region,ticker)] = dict(累加器)
    acc: dict[tuple, dict] = {}

    def slot(region: str, ticker: str) -> dict:
        return acc.setdefault((region, ticker), {"n": 0, "bull": 0, "bear": 0, "neu": 0, "ssum": 0.0, "sn": 0, "eng": 0})

    with session_scope() as s:
        # ---------- jp/kr/tw：从 gr_post 聚合 ----------
        rows = s.execute(
            select(GrPost.region, GrPost.ticker, GrPost.stance, GrPost.sentiment,
                   GrPost.likes, GrPost.comments, GrPost.views)
            .where(GrPost.created_utc >= since)
        ).all()
        for region, ticker, stance, senti, likes, comments, views in rows:
            if ticker not in universe:
                continue
            e = slot(region, ticker)
            e["n"] += 1
            if stance == "bull":
                e["bull"] += 1
            elif stance == "bear":
                e["bear"] += 1
            else:
                e["neu"] += 1
            if senti is not None:
                e["ssum"] += senti; e["sn"] += 1
            e["eng"] += int(likes or 0) + int(comments or 0) + int((views or 0) // 20)

        # ---------- us：只读现有 Reddit（mentions×item_analysis×posts），按 stance 计数，与日韩台一致 ----------
        conn = s.connection()
        urows = conn.execute(text(
            """SELECT m.ticker AS ticker,
                      SUM(CASE WHEN ia.stance='bull' THEN 1 ELSE 0 END) AS b,
                      SUM(CASE WHEN ia.stance='bear' THEN 1 ELSE 0 END) AS br,
                      SUM(CASE WHEN ia.stance NOT IN ('bull','bear') THEN 1 ELSE 0 END) AS ne,
                      COUNT(*) AS n, AVG(ia.sentiment_score) AS avg, SUM(COALESCE(p.score,0)) AS eng
                 FROM mentions m
                 JOIN posts p ON p.id = m.item_id AND m.item_type='post' AND p.market='us'
                 JOIN item_analysis ia ON ia.item_id = p.id AND ia.item_type='post'
                WHERE p.created_utc >= :since
                GROUP BY m.ticker"""
        ), {"since": since.strftime("%Y-%m-%d %H:%M:%S")}).all()
        for ticker, b, br, ne, n, avg, eng in urows:
            if ticker not in universe or not n:
                continue
            e = slot("us", ticker)
            e["n"] = int(n); e["bull"] = int(b or 0); e["bear"] = int(br or 0); e["neu"] = int(ne or 0)
            e["ssum"] = float(avg or 0); e["sn"] = 1; e["eng"] = int(eng or 0)

        # ---------- 写 gr_ticker_region（全量重算）----------
        s.execute(delete(GrTickerRegion))
        s.execute(delete(GrTicker))
        region_senti: dict[str, dict[str, float]] = {}  # ticker -> {region: senti_avg}
        for (region, ticker), e in acc.items():
            n = e["n"]
            if not n:
                continue
            senti = round(e["ssum"] / e["sn"], 3) if e["sn"] else 0.0
            bull, bear, neu = e["bull"], e["bear"], e["neu"]
            denom = max(1, bull + bear + neu)
            s.add(GrTickerRegion(
                region=region, ticker=ticker, post_count=n,
                bull_count=bull, bear_count=bear, neutral_count=neu,
                bull_pct=round(100 * bull / denom, 1), bear_pct=round(100 * bear / denom, 1),
                neutral_pct=round(100 * neu / denom, 1),
                sentiment_avg=senti, mood_label=_mood(senti), engagement=e["eng"],
                updated_at=dt.datetime.utcnow(),
            ))
            region_senti.setdefault(ticker, {})[region] = senti

        # ---------- 写 gr_ticker（跨区派生）----------
        nt = 0
        for ticker, rs in region_senti.items():
            consensus, spread, diverg = _consensus(rs)
            total_posts = sum(acc[(r, ticker)]["n"] for r in rs)
            avg = round(sum(rs.values()) / len(rs), 3)
            s.add(GrTicker(
                ticker=ticker, name_en=name_en.get(ticker, ticker), name_zh=name_zh.get(ticker, ticker),
                regions_present=len(rs), total_posts=total_posts, avg_sentiment=avg,
                consensus=consensus, spread=spread, divergent_region=diverg,
                updated_at=dt.datetime.utcnow(),
            ))
            nt += 1

    by_region = {r: sum(1 for (rg, _t) in acc if rg == r and acc[(rg, _t)]["n"]) for r in REGIONS}
    cons = {}
    for ticker, rs in region_senti.items():
        c = _consensus(rs)[0]
        cons[c] = cons.get(c, 0) + 1
    print(f"[gr-rollup] region×ticker 单元={sum(1 for v in acc.values() if v['n'])} | 各区有数标的={by_region}")
    print(f"[gr-rollup] ticker={nt} | 共识分布={cons}")
    return {"tickers": nt, "by_region": by_region, "consensus": cons}


if __name__ == "__main__":
    rollup()
