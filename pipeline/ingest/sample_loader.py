"""把内置样本帖（pipeline/data/sample_posts.json）载入 DB，供离线开发/验证。

用 hours_ago 相对时间 → created_utc = now - hours_ago，让 demo 永远"新鲜"。
"""
from __future__ import annotations

import datetime as dt
import json

from ..common.config import PKG_DATA_DIR
from ..common.db import session_scope
from .reddit_ingest import store_mentions, upsert_author, upsert_post, upsert_subreddit
from .ticker_extract import load_ticker_dict

# 板块订阅数（近似，仅为 UI 展示真实感）
SUBSCRIBERS = {
    "wallstreetbets": 15800000, "stocks": 7400000, "investing": 2900000,
    "StockMarket": 4100000, "options": 1600000, "ValueInvesting": 2200000,
    "SecurityAnalysis": 210000, "thetagang": 220000,
}


def load_sample() -> dict:
    with open(PKG_DATA_DIR / "sample_posts.json", "r", encoding="utf-8") as f:
        rows = json.load(f)

    now = dt.datetime.utcnow()
    stats = {"posts": 0, "mentions": 0}
    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`（demo 用 `seed-tickers --fallback`）。")

        for r in rows:
            sub = r["subreddit"]
            sid = upsert_subreddit(s, sub, display_name=sub, subscribers=SUBSCRIBERS.get(sub, 0))
            author_id = upsert_author(s, r.get("author"))
            created = now - dt.timedelta(hours=float(r.get("hours_ago", 1)))
            upsert_post(
                s, id=r["id"], subreddit_id=sid, author_id=author_id,
                title=r.get("title", ""), selftext=r.get("selftext", ""),
                url=None, permalink=f"/r/{sub}/comments/{r['id']}/",
                flair=r.get("flair"), is_self=True, created_utc=created,
                score=int(r.get("score", 0)), upvote_ratio=float(r.get("upvote_ratio", 0)),
                num_comments=int(r.get("num_comments", 0)), total_awards=0,
            )
            stats["posts"] += 1
            stats["mentions"] += store_mentions(
                s, tdict, item_id=r["id"], item_type="post",
                text=f"{r.get('title','')}\n{r.get('selftext','')}",
                subreddit_id=sid, author_id=author_id, created_utc=created,
            )

    print(f"[sample] 载入样本 {stats}")
    return stats


if __name__ == "__main__":
    load_sample()
