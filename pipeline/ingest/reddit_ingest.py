"""数据系统：用 PRAW 从 Reddit 财经板块拉取帖子/评论，并抽取 ticker 写入 DB。

需要 .env 的 Reddit 凭证；在你本机运行（沙箱出口 IP 被 Reddit 屏蔽）。
"""
from __future__ import annotations

import datetime as dt

import yaml
from sqlalchemy import select

from ..common.config import PKG_DATA_DIR, settings
from ..common.db import session_scope
from ..common.models import Author, Comment, Mention, Post, Subreddit
from .ticker_extract import TickerDict, extract_mentions, load_ticker_dict


# ----------------------------- upsert 助手（被 sample_loader 复用）-----------------------------
def upsert_subreddit(s, name: str, display_name: str = "", subscribers: int = 0,
                     market: str = "us", tracked: bool = True) -> str:
    sid = name.lower()
    s.merge(Subreddit(id=sid, display_name=display_name or name, subscribers=subscribers,
                      market=market, tracked=tracked))
    return sid


def upsert_author(s, username: str | None, created_utc: dt.datetime | None = None) -> str | None:
    if not username or username in ("[deleted]", "None"):
        return None
    a = s.get(Author, username)
    now = dt.datetime.utcnow()
    if a is None:
        s.add(Author(id=username, created_utc=created_utc, first_seen=now, last_seen=now))
    else:
        a.last_seen = now
    return username


def upsert_post(s, *, id, subreddit_id, author_id, title, selftext, url, permalink,
                flair, is_self, created_utc, score, upvote_ratio, num_comments, total_awards,
                market: str = "us", source: str = "scan"):
    s.merge(Post(
        id=id, subreddit_id=subreddit_id, author_id=author_id, market=market, source=source, title=title,
        selftext=selftext or "", url=url, permalink=permalink, flair=flair,
        is_self=is_self, created_utc=created_utc, score=score, upvote_ratio=upvote_ratio,
        num_comments=num_comments, total_awards=total_awards,
        fetched_at=dt.datetime.utcnow(), last_refreshed_at=dt.datetime.utcnow(),
    ))


def store_mentions(s, tdict: TickerDict, *, item_id, item_type, text, subreddit_id, author_id, created_utc) -> int:
    n = 0
    for mt in extract_mentions(text, tdict):
        s.merge(Mention(
            ticker=mt["ticker"], item_id=item_id, item_type=item_type,
            subreddit_id=subreddit_id, author_id=author_id,
            context_snippet=mt["context_snippet"], confidence=mt["confidence"],
            method=mt["method"], created_utc=created_utc,
        ))
        n += 1
    return n


def load_subreddit_config() -> list[dict]:
    with open(PKG_DATA_DIR / "subreddits.yml", "r", encoding="utf-8") as f:
        return yaml.safe_load(f).get("subreddits", [])


# ----------------------------- 主流程 -----------------------------
def ingest_once(limit: int | None = None, with_comments: bool = True) -> dict:
    """拉取一轮：每板块 new+hot+top(day)，可选顶层高分评论。返回统计。"""
    from ..common.reddit import get_reddit

    limit = limit or settings.ingest_post_limit
    reddit = get_reddit()
    subs = load_subreddit_config()
    stats = {"posts": 0, "comments": 0, "mentions": 0, "subreddits": 0}

    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")

        for entry in subs:
            name = entry["name"]
            market = entry.get("market", "us")
            sr = reddit.subreddit(name)
            sid = upsert_subreddit(s, name, display_name=str(getattr(sr, "title", name)),
                                   subscribers=int(getattr(sr, "subscribers", 0) or 0), market=market)
            stats["subreddits"] += 1

            seen: set[str] = set()
            listings = [sr.new(limit=limit), sr.hot(limit=limit), sr.top(time_filter="day", limit=limit)]
            for listing in listings:
                for sub in listing:
                    if sub.id in seen:
                        continue
                    seen.add(sub.id)
                    author_id = upsert_author(
                        s, str(sub.author) if sub.author else None,
                        dt.datetime.utcfromtimestamp(sub.author.created_utc) if getattr(sub.author, "created_utc", None) else None,
                    )
                    created = dt.datetime.utcfromtimestamp(sub.created_utc)
                    upsert_post(
                        s, id=sub.id, subreddit_id=sid, author_id=author_id, market=market,
                        title=sub.title or "", selftext=sub.selftext or "",
                        url=None if sub.is_self else sub.url, permalink=sub.permalink,
                        flair=sub.link_flair_text, is_self=bool(sub.is_self),
                        created_utc=created, score=int(sub.score or 0),
                        upvote_ratio=float(sub.upvote_ratio or 0), num_comments=int(sub.num_comments or 0),
                        total_awards=int(getattr(sub, "total_awards_received", 0) or 0),
                    )
                    stats["posts"] += 1
                    stats["mentions"] += store_mentions(
                        s, tdict, item_id=sub.id, item_type="post",
                        text=f"{sub.title}\n{sub.selftext or ''}", subreddit_id=sid,
                        author_id=author_id, created_utc=created,
                    )

                    if with_comments:
                        sub.comments.replace_more(limit=0)
                        for c in sub.comments[:30]:
                            if int(c.score or 0) < settings.ingest_comment_min_score:
                                continue
                            cauthor = upsert_author(s, str(c.author) if c.author else None)
                            ccreated = dt.datetime.utcfromtimestamp(c.created_utc)
                            s.merge(Comment(
                                id=c.id, post_id=sub.id, author_id=cauthor, body=c.body or "",
                                score=int(c.score or 0), created_utc=ccreated, parent_id=c.parent_id,
                            ))
                            stats["comments"] += 1
                            stats["mentions"] += store_mentions(
                                s, tdict, item_id=c.id, item_type="comment", text=c.body or "",
                                subreddit_id=sid, author_id=cauthor, created_utc=ccreated,
                            )

    print(f"[ingest] {stats}")
    return stats


if __name__ == "__main__":
    ingest_once()
