"""刷新近 48 小时帖子的互动数据（score / num_comments / upvote_ratio）。

用 reddit.info() 批量按 fullname 拉取，省请求。需 Reddit 凭证。
"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import select

from ..common.db import session_scope
from ..common.models import Post


def _chunks(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def refresh_recent(hours: int = 48) -> int:
    from ..common.reddit import get_reddit

    reddit = get_reddit()
    updated = 0
    cutoff = dt.datetime.utcnow() - dt.timedelta(hours=hours)
    with session_scope() as s:
        ids = [pid for (pid,) in s.execute(select(Post.id).where(Post.created_utc >= cutoff)).all()]
        fullnames = [f"t3_{i}" for i in ids]
        for chunk in _chunks(fullnames, 100):
            for sub in reddit.info(fullnames=chunk):
                p = s.get(Post, sub.id)
                if not p:
                    continue
                p.score = int(sub.score or 0)
                p.num_comments = int(sub.num_comments or 0)
                p.upvote_ratio = float(sub.upvote_ratio or 0)
                p.last_refreshed_at = dt.datetime.utcnow()
                updated += 1
    print(f"[refresh] 更新 {updated} 帖。")
    return updated


if __name__ == "__main__":
    refresh_recent()
