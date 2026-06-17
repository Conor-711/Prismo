"""聚合：ticker 的 mindshare（加权声量份额）与小时级时间序列。

加权声量 = Σ  confidence · (1 + ln(1+post_score)) · subreddit_weight
mindshare% = ticker 加权 / 全体加权 · 100
"""
from __future__ import annotations

import datetime as dt
import math

import yaml
from sqlalchemy import and_, delete, select

from ..common.config import PKG_DATA_DIR, settings
from ..common.db import session_scope, data_now
from ..common.models import ItemAnalysis, Mention, Post, TickerMeta, TickerRollup


def _sub_weights() -> dict[str, float]:
    with open(PKG_DATA_DIR / "subreddits.yml", "r", encoding="utf-8") as f:
        return {e["name"].lower(): float(e.get("weight", 1.0)) for e in yaml.safe_load(f)["subreddits"]}


def _hour_floor(ts: dt.datetime) -> dt.datetime:
    return ts.replace(minute=0, second=0, microsecond=0)


def run_rollups(market: str = "us") -> int:
    weights = _sub_weights()
    now = data_now(market)
    window_h = settings.mindshare_window_hours
    max_h = max(window_h, 48)
    cutoff = now - dt.timedelta(hours=max_h)
    win_cutoff = now - dt.timedelta(hours=window_h)

    with session_scope() as s:
        rows = s.execute(
            select(
                Mention.ticker, Mention.confidence, Mention.item_id, Mention.author_id,
                Mention.created_utc, Mention.subreddit_id, Post.score,
                ItemAnalysis.sentiment_score, ItemAnalysis.stance,
            )
            .join(Post, Post.id == Mention.item_id)
            .outerjoin(ItemAnalysis, and_(ItemAnalysis.item_id == Mention.item_id,
                                          ItemAnalysis.item_type == "post"))
            .where(Mention.item_type == "post", Mention.created_utc >= cutoff,
                   Post.market == market, Post.source == "scan")
        ).all()

        # cn 看板只统计策划的中概/港股/A 股宇宙（ticker_meta.market='cn'）；
        # 否则 cn 社区帖子里顺带提到的美股(NVDA/MSFT/GOOGL/TSLA...)会混入中概·港股面板。
        if market == "cn":
            allowed = {r[0] for r in s.execute(
                select(TickerMeta.ticker).where(TickerMeta.market == "cn")).all()}
            rows = [r for r in rows if r[0] in allowed]

        # ---------- window 聚合 ----------
        win: dict[str, dict] = {}
        for tk, conf, item_id, author, created, sub_id, score, sent, stance in rows:
            if created < win_cutoff:
                continue
            w = weights.get(sub_id, 1.0)
            d = win.setdefault(tk, dict(mc=0, wm=0.0, eng=0, authors=set(), posts=set(),
                                        ssum=0.0, sn=0, bull=0, bear=0, neu=0))
            d["mc"] += 1
            d["wm"] += conf * (1.0 + math.log1p(max(0, score or 0))) * w
            d["eng"] += int(score or 0)
            if author:
                d["authors"].add(author)
            d["posts"].add(item_id)
            if sent is not None:
                d["ssum"] += sent
                d["sn"] += 1
            if stance == "bull":
                d["bull"] += 1
            elif stance == "bear":
                d["bear"] += 1
            else:
                d["neu"] += 1

        total_w = sum(d["wm"] for d in win.values()) or 1.0

        s.execute(delete(TickerRollup).where(TickerRollup.bucket == "window",
                                             TickerRollup.market == market))
        for tk, d in win.items():
            s.add(TickerRollup(
                ticker=tk, market=market, bucket="window", bucket_ts=now,
                mention_count=d["mc"], weighted_mentions=round(d["wm"], 3),
                engagement_sum=d["eng"], unique_authors=len(d["authors"]),
                post_count=len(d["posts"]), mindshare_pct=round(d["wm"] / total_w * 100, 2),
                sentiment_avg=round(d["ssum"] / d["sn"], 3) if d["sn"] else 0.0,
                bull_count=d["bull"], bear_count=d["bear"], neutral_count=d["neu"],
            ))

        # ---------- 小时级时间序列（近 48h，供 ticker 页 sparkline） ----------
        hourly: dict[tuple, dict] = {}
        for tk, conf, item_id, author, created, sub_id, score, sent, stance in rows:
            key = (tk, _hour_floor(created))
            w = weights.get(sub_id, 1.0)
            d = hourly.setdefault(key, dict(mc=0, wm=0.0, eng=0, ssum=0.0, sn=0, posts=set()))
            d["mc"] += 1
            d["wm"] += conf * (1.0 + math.log1p(max(0, score or 0))) * w
            d["eng"] += int(score or 0)
            d["posts"].add(item_id)
            if sent is not None:
                d["ssum"] += sent
                d["sn"] += 1

        s.execute(delete(TickerRollup).where(TickerRollup.bucket == "hour",
                                             TickerRollup.market == market))
        for (tk, hts), d in hourly.items():
            s.add(TickerRollup(
                ticker=tk, market=market, bucket="hour", bucket_ts=hts,
                mention_count=d["mc"], weighted_mentions=round(d["wm"], 3),
                engagement_sum=d["eng"], unique_authors=0, post_count=len(d["posts"]),
                mindshare_pct=0.0,
                sentiment_avg=round(d["ssum"] / d["sn"], 3) if d["sn"] else 0.0,
                bull_count=0, bear_count=0, neutral_count=0,
            ))

        nwin = len(win)
    print(f"[rollup] ({market}) window 内 {nwin} 个 ticker，mindshare 已归一化（合计≈100%）。")
    return nwin


if __name__ == "__main__":
    run_rollups()
