"""真实数据爬虫：从 Arctic Shift（Reddit 数据镜像，含当天数据）拉取主流财经板块帖子。

沙箱出口 IP 被 Reddit 直连屏蔽，Arctic Shift 托管在别处可达，提供真实、当前的 Reddit 帖子。
生产环境推荐用官方 PRAW（reddit_ingest.py）；此爬虫便于无凭证快速取真实数据。
"""
from __future__ import annotations

import datetime as dt
import re
import time

import requests

from ..common.config import settings
from ..common.db import session_scope
from ..common.models import Comment
from .reddit_ingest import (
    load_subreddit_config, store_mentions, upsert_author, upsert_post, upsert_subreddit,
)
from .ticker_extract import load_ticker_dict

BASE = "https://arctic-shift.photon-reddit.com/api/posts/search"
COMMENTS_BASE = "https://arctic-shift.photon-reddit.com/api/comments/search"
UA = settings.reddit_user_agent or "Prismo/0.1 (research)"


def fetch_subreddit(name: str, days: int, max_count: int) -> list[dict]:
    """按时间倒序分页拉取近 `days` 天、至多 `max_count` 条提交。"""
    cutoff = dt.datetime.utcnow().timestamp() - days * 86400
    out: list[dict] = []
    before: int | None = None
    sess = requests.Session()
    sess.headers["User-Agent"] = UA

    while len(out) < max_count:
        params = {"subreddit": name, "limit": 100, "sort": "desc"}
        if before:
            params["before"] = int(before)
        try:
            r = sess.get(BASE, params=params, timeout=30)
        except requests.RequestException as e:
            print(f"  [scrape] r/{name} 网络错误：{e}")
            break
        if r.status_code != 200:
            print(f"  [scrape] r/{name} HTTP {r.status_code}，停止该板块。")
            break
        items = r.json().get("data", [])
        if not items:
            break
        stop = False
        for it in items:
            cu = it.get("created_utc")
            if cu is None:
                continue
            if cu < cutoff:
                stop = True
                break
            out.append(it)
        if stop or len(items) < 100:
            break
        before = items[-1]["created_utc"]
        time.sleep(0.6)
    return out[:max_count]


def scrape(days: int = 3, limit_per: int = 300, markets: set[str] | None = None) -> dict:
    """爬取 subreddits.yml 里的板块。markets=None 爬全部；否则只爬指定口径（如 {"cn"}）。"""
    subs = load_subreddit_config()
    if markets:
        subs = [e for e in subs if e.get("market", "us") in markets]
    stats = {"posts": 0, "mentions": 0, "subreddits": 0}

    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")

        for entry in subs:
            name = entry["name"]
            market = entry.get("market", "us")
            items = fetch_subreddit(name, days, limit_per)
            subscribers = int((items[0].get("subreddit_subscribers") if items else 0) or 0)
            sid = upsert_subreddit(s, name, display_name=name, subscribers=subscribers, market=market)
            stats["subreddits"] += 1

            for it in items:
                author = it.get("author")
                aid = upsert_author(s, author if author not in (None, "[deleted]") else None)
                created = dt.datetime.utcfromtimestamp(it["created_utc"])
                is_self = bool(it.get("is_self", True))
                title = it.get("title") or ""
                selftext = it.get("selftext") or ""
                if selftext in ("[removed]", "[deleted]"):
                    selftext = ""
                upsert_post(
                    s, id=it["id"], subreddit_id=sid, author_id=aid, market=market, title=title, selftext=selftext,
                    url=None if is_self else it.get("url"), permalink=it.get("permalink", ""),
                    flair=it.get("link_flair_text"), is_self=is_self, created_utc=created,
                    score=int(it.get("score", 0) or 0), upvote_ratio=float(it.get("upvote_ratio", 0) or 0),
                    num_comments=int(it.get("num_comments", 0) or 0),
                    total_awards=int(it.get("total_awards_received", 0) or 0),
                )
                stats["posts"] += 1
                stats["mentions"] += store_mentions(
                    s, tdict, item_id=it["id"], item_type="post",
                    text=f"{title}\n{selftext}", subreddit_id=sid, author_id=aid, created_utc=created,
                )
            print(f"  r/{name}: {len(items)} 帖")

    print(f"[scrape] 完成 {stats}")
    return stats


# ----------------------------- A 股 / 中国资产 关键词过滤扫描 -----------------------------
# 英文 Reddit 无活跃的沪深 A 股专版（r/AShares 等已停更），A 股讨论零散分布在综合中国社区。
# 故扫描这些综合版块，只保留「提及中概/港股/A 股标的 或 命中 A 股市场关键词」的帖（market=cn,
# tracked=False 不进侧栏）。这是把真实 A 股内容引入站点的主要途径（量天然较小，是 Reddit 的客观限制）。
CN_SOURCE_SUBS = ["Sino", "China", "shanghai", "EmergingMarkets", "ChinaStockMarket", "AShares"]

ASHARE_KEYWORDS = re.compile(
    r"\b(a[-\s]?shares?|shanghai composite|sse composite|sse index|csi\s?300|csi\s?500|"
    r"shenzhen (?:component|index)|star market|sci-?tech innovation board|chinext|"
    r"stock connect|northbound|southbound|mainland china stock|onshore china|"
    r"shanghai stock exchange|shenzhen stock exchange)\b"
    r"|沪深|A股|上证|深证|科创板|创业板|上交所|深交所|北向资金",
    re.I,
)


def scrape_china_filtered(days: int = 30, limit_per: int = 300, subs: list[str] | None = None) -> dict:
    """扫描综合中国社区，只保留与中国股市（含 A 股）相关的帖，写为 market=cn / tracked=False。"""
    from sqlalchemy import select
    from ..common.models import TickerMeta

    source_subs = subs or CN_SOURCE_SUBS
    stats = {"scanned": 0, "kept": 0, "ashare_kw": 0}

    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed` + `make seed-cn`。")
        from .ticker_extract import extract_mentions
        cn_tickers = {
            t for (t,) in s.execute(select(TickerMeta.ticker).where(TickerMeta.market == "cn")).all()
        }

        for name in source_subs:
            items = fetch_subreddit(name, days, limit_per)
            stats["scanned"] += len(items)
            sid = None
            kept = 0
            for it in items:
                title = it.get("title") or ""
                selftext = it.get("selftext") or ""
                if selftext in ("[removed]", "[deleted]"):
                    selftext = ""
                text = f"{title}\n{selftext}"
                ms = extract_mentions(text, tdict)
                has_cn = any(m["ticker"] in cn_tickers for m in ms)
                kw = bool(ASHARE_KEYWORDS.search(text))
                if not (has_cn or kw):
                    continue
                if kw:
                    stats["ashare_kw"] += 1
                if sid is None:  # 首次命中才登记该来源版块（tracked=False，不进侧栏）
                    subscribers = int((items[0].get("subreddit_subscribers") if items else 0) or 0)
                    sid = upsert_subreddit(s, name, display_name=name, subscribers=subscribers,
                                           market="cn", tracked=False)
                author = it.get("author")
                aid = upsert_author(s, author if author not in (None, "[deleted]") else None)
                created = dt.datetime.utcfromtimestamp(it["created_utc"])
                is_self = bool(it.get("is_self", True))
                upsert_post(
                    s, id=it["id"], subreddit_id=sid, author_id=aid, market="cn",
                    title=title, selftext=selftext,
                    url=None if is_self else it.get("url"), permalink=it.get("permalink", ""),
                    flair=it.get("link_flair_text"), is_self=is_self, created_utc=created,
                    score=int(it.get("score", 0) or 0), upvote_ratio=float(it.get("upvote_ratio", 0) or 0),
                    num_comments=int(it.get("num_comments", 0) or 0),
                    total_awards=int(it.get("total_awards_received", 0) or 0),
                )
                store_mentions(s, tdict, item_id=it["id"], item_type="post",
                               text=text, subreddit_id=sid, author_id=aid, created_utc=created)
                kept += 1
            stats["kept"] += kept
            print(f"  r/{name}: 命中 {kept}/{len(items)} 帖（与中国股市相关）")

    print(f"[scrape-china] 完成 {stats}")
    return stats


def fetch_comments(sess: requests.Session, post_id: str, limit: int = 100) -> list[dict]:
    try:
        r = sess.get(COMMENTS_BASE, params={"link_id": post_id, "limit": min(100, limit)}, timeout=30)
    except requests.RequestException:
        return []
    if r.status_code != 200:
        return []
    return r.json().get("data", []) or []


def scrape_comments(top_n: int = 700, per_post: int = 15, min_comments: int = 0, min_score: int = 0) -> dict:
    """为「展示优先级最高」的帖抓取高分评论，写入 comments 表（仅供站内展示，不参与 mention/分析）。"""
    from sqlalchemy import and_, desc, func, select

    from ..common.models import ItemAnalysis, Post

    stats = {"posts_scanned": 0, "comments": 0}
    sess = requests.Session()
    sess.headers["User-Agent"] = UA
    with session_scope() as s:
        # 按「展示优先级」(AI 质量分 → 赞数)选帖，而非靠 Arctic 存档时的 num_comments：
        # Arctic 在发帖瞬间存档，post.num_comments 多为 0，用它过滤会漏掉之后才积累评论的高质量帖
        # （如刚发布的高质量 DD / 今日Alpha）。质量分需 analyze 先跑（daily 已把本步移到 analyze 之后）。
        post_ids = [
            r[0]
            for r in s.execute(
                select(Post.id)
                .outerjoin(ItemAnalysis, and_(ItemAnalysis.item_id == Post.id,
                                              ItemAnalysis.item_type == "post"))
                .where(Post.num_comments >= min_comments)
                .order_by(desc(func.coalesce(ItemAnalysis.quality_score, 0.0)), desc(Post.score))
                .limit(top_n)
            ).all()
        ]
        for pid in post_ids:
            items = fetch_comments(sess, pid)
            stats["posts_scanned"] += 1
            clean = [
                it for it in items
                if (it.get("body") or "") not in ("", "[deleted]", "[removed]") and it.get("id")
            ]
            clean.sort(key=lambda x: int(x.get("score", 0) or 0), reverse=True)
            for it in clean[:per_post]:
                if min_score and int(it.get("score", 0) or 0) < min_score:
                    continue
                author = it.get("author")
                aid = upsert_author(s, author if author not in (None, "[deleted]") else None)
                cu = it.get("created_utc")
                created = dt.datetime.utcfromtimestamp(cu) if cu else dt.datetime.utcnow()
                s.merge(Comment(
                    id=it["id"], post_id=pid, author_id=aid, body=it.get("body") or "",
                    score=int(it.get("score", 0) or 0), created_utc=created, parent_id=it.get("parent_id"),
                ))
                stats["comments"] += 1
            time.sleep(0.4)
    print(f"[scrape-comments] 完成 {stats}")
    return stats


if __name__ == "__main__":
    scrape()
