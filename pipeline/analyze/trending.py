"""异动监测：对每个 ticker 用近 48h 小时级声量算 z-score，识别飙升 spike。"""
from __future__ import annotations

import datetime as dt
import statistics

from sqlalchemy import and_, delete, select

from ..common.db import session_scope, data_now
from ..common.models import ItemAnalysis, Mention, Post, TickerMeta, Trending


def run_trending(window_h: int = 24, recent_h: int = 6, market: str = "us") -> int:
    now = data_now(market)  # 按 market 各自锚定，避免另一市场更新时本市场落在窗口外
    cutoff = now - dt.timedelta(hours=48)

    with session_scope() as s:
        rows = s.execute(
            select(Mention.ticker, Mention.created_utc, ItemAnalysis.sentiment_score)
            .join(Post, Post.id == Mention.item_id)
            .outerjoin(ItemAnalysis, and_(ItemAnalysis.item_id == Mention.item_id,
                                          ItemAnalysis.item_type == "post"))
            .where(Mention.item_type == "post", Mention.created_utc >= cutoff,
                   Post.market == market, Post.source == "scan")
        ).all()

        # cn 看板只统计策划的中概/港股/A 股宇宙（ticker_meta.market='cn'）；
        # 剔除 cn 社区帖子里顺带提到的美股(NVDA/MSFT/GOOGL/TSLA...)。
        if market == "cn":
            allowed = {r[0] for r in s.execute(
                select(TickerMeta.ticker).where(TickerMeta.market == "cn")).all()}
            rows = [r for r in rows if r[0] in allowed]

        per: dict[str, dict] = {}
        for tk, created, sent in rows:
            ha = int((now - created).total_seconds() // 3600)
            ha = min(max(ha, 0), 47)
            d = per.setdefault(tk, dict(bins=[0] * 48, sent=[], win=0, prior=0))
            d["bins"][ha] += 1
            if ha < window_h and sent is not None:
                d["sent"].append(sent)
            if ha < window_h:
                d["win"] += 1
            elif ha < 48:
                d["prior"] += 1

        results = []
        for tk, d in per.items():
            bins = d["bins"]
            recent = sum(bins[:recent_h])
            baseline = bins[recent_h:48]
            mean = statistics.fmean(baseline) if baseline else 0.0
            std = statistics.pstdev(baseline) if len(baseline) > 1 else 0.0
            std_eff = max(std, 0.5)
            recent_rate = recent / recent_h
            z = round((recent_rate - mean) / std_eff, 2)
            sent_avg = round(statistics.fmean(d["sent"]), 3) if d["sent"] else 0.0
            is_spike = z >= 1.0 and recent >= 2
            results.append(dict(ticker=tk, win=d["win"], prior=d["prior"], mean=round(mean, 3),
                                std=round(std, 3), z=z, sent=sent_avg, spike=is_spike))

        results.sort(key=lambda r: (-r["z"], -r["win"]))

        s.execute(delete(Trending).where(Trending.window == "24h", Trending.market == market))
        for rank, r in enumerate(results, 1):
            s.add(Trending(
                ticker=r["ticker"], market=market, window="24h", as_of=now, mention_count=r["win"],
                baseline_mean=r["mean"], baseline_std=r["std"], zscore=r["z"],
                sentiment_avg=r["sent"], sentiment_delta=0.0, is_spike=r["spike"], rank=rank,
            ))
        nspike = sum(1 for r in results if r["spike"])
    print(f"[trending] ({market}) {len(results)} 个 ticker，spike {nspike} 个。")
    return len(results)


if __name__ == "__main__":
    run_trending()
