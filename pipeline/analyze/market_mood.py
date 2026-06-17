"""市场整体情绪（Reddit 版"贪婪/恐惧"），基于窗口内全部帖子的多空分布与情绪均值。"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import and_, delete, func, select

from ..common.config import settings
from ..common.db import session_scope, data_now
from ..common.models import ItemAnalysis, Mention, MarketMood, Post


def mood_label(m: float) -> str:
    if m <= -0.5:
        return "极度恐惧"
    if m <= -0.15:
        return "恐惧"
    if m < 0.15:
        return "中性"
    if m < 0.5:
        return "贪婪"
    return "极度贪婪"


def run_market_mood(market: str = "us") -> dict:
    now = data_now(market)  # 按 market 各自锚定最新帖，避免另一市场更新时把本市场挤出 24h 窗口
    cutoff = now - dt.timedelta(hours=settings.mindshare_window_hours)

    with session_scope() as s:
        rows = s.execute(
            select(ItemAnalysis.stance, ItemAnalysis.sentiment_score)
            .join(Post, Post.id == ItemAnalysis.item_id)
            .where(ItemAnalysis.item_type == "post", Post.created_utc >= cutoff,
                   Post.market == market, Post.source == "scan")
        ).all()
        total = len(rows)
        bull = sum(1 for st, _ in rows if st == "bull")
        bear = sum(1 for st, _ in rows if st == "bear")
        neu = total - bull - bear
        mood = round(sum(sc for _, sc in rows) / total, 3) if total else 0.0

        total_mentions = s.execute(
            select(func.count()).select_from(Mention)
            .join(Post, Post.id == Mention.item_id)
            .where(Mention.item_type == "post", Mention.created_utc >= cutoff,
                   Post.market == market, Post.source == "scan")
        ).scalar_one()

        pct = lambda x: round(x / total * 100, 1) if total else 0.0
        s.execute(delete(MarketMood).where(MarketMood.bucket == "window",
                                           MarketMood.market == market))
        s.add(MarketMood(
            market=market, bucket="window", bucket_ts=now, mood_score=mood,
            bull_pct=pct(bull), bear_pct=pct(bear), neutral_pct=pct(neu),
            total_mentions=int(total_mentions), total_posts=total, label=mood_label(mood),
        ))
    out = {"market": market, "mood": mood, "label": mood_label(mood), "bull": bull, "bear": bear, "neutral": neu, "posts": total}
    print(f"[mood] {out}")
    return out


if __name__ == "__main__":
    run_market_mood()
