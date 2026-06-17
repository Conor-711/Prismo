"""作者库：爬取「实力榜」Top 作者的 Reddit 历史帖，两级模型漏斗控成本。

流程（crawl_top_authors）：
  1. 选作者：用与 web/lib/queries.ts::getLeaderboard 相同的 alpha 公式算 Top N。
  2. 拉历史：Arctic Shift `posts/search?author=<name>`（去重已有帖）。
  3. 财经过滤：抽到 ≥1 ticker 或来自 tracked 板块，才进入下一步（不给非财经帖花钱）。
  4. 便宜粗筛：DeepSeek(LOW=deepseek-v4-flash) 批量给 0–1 质量分，只留 ≥ QUALITY_GATE。
  5. 入库：过线帖 upsert_post(source="author") + store_mentions；其余不入库 → 永不触达千问。
  6. 千问完整分析复用现有增量 run_analyze（item_analyze 只分析无 analysis 的新帖）。

缺 DeepSeek key 时整段跳过（粗筛闸不可用就不爬，避免把全部历史帖丢给贵的千问）。
"""
from __future__ import annotations

import datetime as dt
import math
import time

import requests
from sqlalchemy import text

from ..common.config import settings
from ..common.db import session_scope
from ..common.models import Author, Post, Subreddit
from .reddit_ingest import store_mentions, upsert_author, upsert_post
from .ticker_extract import extract_mentions, load_ticker_dict

BASE = "https://arctic-shift.photon-reddit.com/api/posts/search"
UA = settings.reddit_user_agent or "RedditAlpha/0.1 (research)"

QUALITY_GATE = 0.55       # 粗筛过线阈值（0–1）
MAX_FETCH_PER = 120       # 每位作者最多拉多少历史帖
PER_AUTHOR_CAP = 20       # 每位作者最多并入作者库多少篇（控千问成本）
PRESCREEN_BATCH = 10      # 每次 DeepSeek 粗筛多少篇


# ----------------------------- 选作者：复用 leaderboard 的 alpha 公式 -----------------------------
def top_authors(s, limit: int = 50) -> list[str]:
    """与 web 的 getLeaderboard 同公式：0.3*质量 + 0.3*影响 + 0.2*立场 + 0.2*产出。"""
    rows = s.execute(text(
        """SELECT p.author_id AS author, COUNT(*) AS posts,
                  COALESCE(SUM(p.score),0) AS upvotes,
                  COALESCE(SUM(p.num_comments),0) AS comments,
                  AVG(ia.quality_score) AS quality,
                  SUM(CASE WHEN ia.stance IN ('bull','bear') THEN 1 ELSE 0 END) AS conv_n
             FROM posts p JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
            WHERE p.author_id IS NOT NULL
            GROUP BY p.author_id"""
    )).all()
    if not rows:
        return []
    raw = []
    for author, posts, upvotes, comments, quality, conv_n in rows:
        q = max(0.0, min(1.0, float(quality or 0.0)))
        infl = math.log10(1 + (upvotes or 0) + 2 * (comments or 0))
        out = math.log10(1 + (posts or 0))
        conv = (conv_n or 0) / posts if posts else 0.0
        raw.append([author, q, infl, out, conv, upvotes or 0])
    infl_vals = [r[2] for r in raw]
    out_vals = [r[3] for r in raw]
    mn_i, mx_i = min(infl_vals), max(infl_vals)
    mn_o, mx_o = min(out_vals), max(out_vals)
    norm = lambda v, mn, mx: (v - mn) / (mx - mn) if mx > mn else 0.0
    scored = []
    for author, q, infl, out, conv, upvotes in raw:
        alpha = 0.3 * q + 0.3 * norm(infl, mn_i, mx_i) + 0.2 * conv + 0.2 * norm(out, mn_o, mx_o)
        scored.append((author, alpha, upvotes))
    scored.sort(key=lambda r: (-r[1], -r[2]))
    return [a for a, _, _ in scored[:limit]]


# ----------------------------- 拉历史帖（Arctic Shift 按作者） -----------------------------
def fetch_author(name: str, max_count: int = MAX_FETCH_PER) -> list[dict]:
    """按时间倒序分页拉取某作者至多 max_count 条提交。"""
    out: list[dict] = []
    before: int | None = None
    sess = requests.Session()
    sess.headers["User-Agent"] = UA
    while len(out) < max_count:
        params = {"author": name, "limit": 100, "sort": "desc"}
        if before:
            params["before"] = int(before)
        try:
            r = sess.get(BASE, params=params, timeout=30)
        except requests.RequestException as e:
            print(f"  [author-crawl] u/{name} 网络错误：{e}")
            break
        if r.status_code != 200:
            print(f"  [author-crawl] u/{name} HTTP {r.status_code}，停止。")
            break
        items = r.json().get("data", [])
        if not items:
            break
        out.extend(items)
        if len(items) < 100:
            break
        before = items[-1].get("created_utc")
        if not before:
            break
        time.sleep(0.6)
    return out[:max_count]


def _ensure_subreddit(s, name: str | None, market: str = "us") -> str | None:
    """确保 subreddit 行存在；新发现的版块设 tracked=False（不进侧栏、不改已有版块的 tracked）。"""
    if not name:
        return None
    sid = name.lower()
    if s.get(Subreddit, sid) is None:
        s.add(Subreddit(id=sid, display_name=name, subscribers=0, market=market, tracked=False))
    return sid


# ----------------------------- 便宜粗筛（DeepSeek LOW） -----------------------------
def prescreen_quality(candidates: list[dict]) -> dict[str, float]:
    """用 DeepSeek(LOW) 批量给每帖 0–1 的「投资干货质量分」。返回 {post_id: score}。"""
    from ..common.llm import LOW, messages_json

    scores: dict[str, float] = {}
    system = (
        "你是美股投资内容质检员。给每条 Reddit 帖子的「投资干货质量」打 0–1 分："
        "1=有深度的研究/DD（数据、估值、催化剂、风险），0=情绪宣泄/梗图/无实质内容。"
        '只输出 JSON：{"scores":[{"id":"<帖id>","q":0.0}]}，不要解释、不要代码块。'
    )
    for i in range(0, len(candidates), PRESCREEN_BATCH):
        batch = candidates[i : i + PRESCREEN_BATCH]
        lines = []
        for c in batch:
            body = (c.get("selftext") or "").replace("\n", " ").strip()[:600]
            lines.append(f"id={c['id']} | {(c.get('title') or '').strip()[:160]} | {body}")
        data = messages_json(LOW, system, "\n".join(lines), max_tokens=900)
        for row in (data or {}).get("scores", []):
            try:
                scores[str(row["id"])] = max(0.0, min(1.0, float(row.get("q", 0))))
            except (KeyError, TypeError, ValueError):
                continue
    return scores


# ----------------------------- 编排 -----------------------------
def crawl_top_authors(limit: int = 50, per_author_cap: int = PER_AUTHOR_CAP,
                      refresh_days: int = 7, max_fetch_per: int = MAX_FETCH_PER) -> dict:
    if not settings.has_deepseek:
        print("[author-crawl] 无 DeepSeek key，跳过（粗筛闸不可用，避免把全部历史帖送千问）。")
        return {"authors": 0, "added": 0, "skipped": "no_deepseek"}

    stats = {"authors": 0, "fetched": 0, "candidates": 0, "added": 0}
    now = dt.datetime.utcnow()
    fresh_cut = now - dt.timedelta(days=refresh_days)

    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")
        tracked = {r[0] for r in s.execute(
            text("SELECT id FROM subreddits WHERE tracked=1")).all()}

        authors = top_authors(s, limit)
        print(f"[author-crawl] 候选 Top {len(authors)} 作者，开始增量爬取（refresh>{refresh_days}d）…")

        for name in authors:
            a = s.get(Author, name)
            if a is not None and a.crawled_at is not None and a.crawled_at > fresh_cut:
                continue  # 近期已爬，跳过（每日增量控量）

            items = fetch_author(name, max_fetch_per)
            stats["fetched"] += len(items)

            # 新帖 + 财经相关 → 候选
            candidates: list[dict] = []
            for it in items:
                pid = it.get("id")
                if not pid or s.get(Post, pid) is not None:
                    continue  # 去重：已存在
                title = it.get("title") or ""
                selftext = it.get("selftext") or ""
                if selftext in ("[removed]", "[deleted]"):
                    selftext = ""
                sub = it.get("subreddit")
                finance = bool(extract_mentions(f"{title}\n{selftext}", tdict)) or (
                    sub and sub.lower() in tracked)
                if not finance:
                    continue
                candidates.append({"id": pid, "title": title, "selftext": selftext, "raw": it, "sub": sub})

            stats["candidates"] += len(candidates)

            # 便宜粗筛 → 过线 → 截断 per_author_cap
            if candidates:
                qmap = prescreen_quality(candidates)
                kept = [c for c in candidates if qmap.get(c["id"], 0.0) >= QUALITY_GATE]
                kept.sort(key=lambda c: -qmap.get(c["id"], 0.0))
                kept = kept[:per_author_cap]

                for c in kept:
                    it = c["raw"]
                    market = "us"
                    sid = _ensure_subreddit(s, c["sub"], market)
                    aid = upsert_author(s, name)
                    created = dt.datetime.utcfromtimestamp(it["created_utc"])
                    is_self = bool(it.get("is_self", True))
                    upsert_post(
                        s, id=c["id"], subreddit_id=sid, author_id=aid, market=market, source="author",
                        title=c["title"], selftext=c["selftext"],
                        url=None if is_self else it.get("url"), permalink=it.get("permalink", ""),
                        flair=it.get("link_flair_text"), is_self=is_self, created_utc=created,
                        score=int(it.get("score", 0) or 0), upvote_ratio=float(it.get("upvote_ratio", 0) or 0),
                        num_comments=int(it.get("num_comments", 0) or 0),
                        total_awards=int(it.get("total_awards_received", 0) or 0),
                    )
                    store_mentions(s, tdict, item_id=c["id"], item_type="post",
                                   text=f"{c['title']}\n{c['selftext']}", subreddit_id=sid,
                                   author_id=aid, created_utc=created)
                    stats["added"] += 1

            # 标记已爬（即使 0 篇过线，也避免明天重复爬同一人）
            a = s.get(Author, name)
            if a is not None:
                a.crawled_at = now
            stats["authors"] += 1

    print(f"[author-crawl] 完成 {stats}。过线帖将由 run_analyze(千问) 增量打标并入作者库。")
    return stats


if __name__ == "__main__":
    import sys
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    crawl_top_authors(limit=n)
