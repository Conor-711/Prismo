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
from sqlalchemy import func, select, text

from ..common.config import settings
from ..common.db import session_scope
from ..common.models import Author, Post, Subreddit
from .reddit_ingest import store_mentions, upsert_author, upsert_post
from .ticker_extract import extract_mentions, load_ticker_dict

BASE = "https://arctic-shift.photon-reddit.com/api/posts/search"
UA = settings.reddit_user_agent or "Prismo/0.1 (research)"

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


def repeat_ticker_authors(s, limit: int = 500, min_ticker_posts: int = 3) -> list[str]:
    """选择重复发表 ticker 相关帖的 Reddit 作者，用于 SV 数据扩爬。

    这个池子不要求帖子都已完成 item_analysis，避免早期分析覆盖不足时漏掉
    有持续发帖记录的作者；排序仍用质量、互动、覆盖 ticker 数和方向性作为优先级。
    """
    rows = s.execute(
        text(
            """SELECT p.author_id AS author,
                      COUNT(DISTINCT p.id) AS posts,
                      COUNT(DISTINCT m.ticker) AS tickers,
                      COALESCE(SUM(CASE WHEN p.score > 0 THEN p.score ELSE 0 END),0) AS upvotes,
                      COALESCE(SUM(CASE WHEN p.num_comments > 0 THEN p.num_comments ELSE 0 END),0) AS comments,
                      AVG(COALESCE(ia.quality_score, 0.35)) AS quality,
                      SUM(CASE WHEN ia.stance IN ('bull','bear') THEN 1 ELSE 0 END) AS directional
                 FROM posts p
                 JOIN mentions m ON m.item_id=p.id AND m.item_type='post'
                 LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
                WHERE p.market='us'
                  AND p.author_id IS NOT NULL
                  AND p.author_id NOT IN ('[deleted]', 'None', 'AutoModerator')
                GROUP BY p.author_id
               HAVING posts >= :min_posts"""
        ),
        {"min_posts": max(1, min_ticker_posts)},
    ).all()
    scored = []
    for author, posts, tickers, upvotes, comments, quality, directional in rows:
        q = max(0.0, min(1.0, float(quality or 0.35)))
        engagement = float(upvotes or 0) + 2 * float(comments or 0)
        directional_share = float(directional or 0) / max(1.0, float(posts or 0))
        score = (
            q * 3.0
            + math.log1p(engagement) * 0.75
            + math.log1p(float(posts or 0)) * 0.9
            + math.log1p(float(tickers or 0)) * 0.8
            + directional_share * 1.2
        )
        scored.append((author, score, engagement, posts))
    scored.sort(key=lambda r: (-r[1], -r[2], -r[3], str(r[0]).lower()))
    return [a for a, _, _, _ in scored[:limit]]


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


def refresh_author_profiles(names: list[str], sleep: float = 0.15) -> dict:
    """补齐 Reddit 作者基础资料：创建时间、karma、已入库帖子数、影响力分。

    Reddit 没有稳定公开的「粉丝数」字段；第一版用可公开获取的账号年龄、
    link/comment karma、站内帖子表现作为作者画像存储。
    """
    stats = {"profiles": 0, "failed": 0, "skipped": 0}
    if not names:
        return stats
    if not settings.has_reddit:
        print("[author-profile] 无 Reddit 凭证，跳过作者资料刷新。")
        stats["skipped"] = len(names)
        return stats

    from ..common.reddit import get_reddit

    reddit = get_reddit()
    with session_scope() as s:
        for name in names:
            if not name or name in ("[deleted]", "None"):
                continue
            a = s.get(Author, name)
            if a is None:
                a = Author(id=name, first_seen=dt.datetime.utcnow(), last_seen=dt.datetime.utcnow())
                s.add(a)
                s.flush()

            post_stats = s.execute(
                select(
                    func.count(Post.id),
                    func.coalesce(func.sum(Post.score), 0),
                    func.coalesce(func.sum(Post.num_comments), 0),
                ).where(Post.author_id == name)
            ).one()
            post_count = int(post_stats[0] or 0)
            post_score = int(post_stats[1] or 0)
            post_comments = int(post_stats[2] or 0)

            try:
                r = reddit.redditor(name)
                created = getattr(r, "created_utc", None)
                if created:
                    a.created_utc = dt.datetime.utcfromtimestamp(float(created))
                a.comment_karma = int(getattr(r, "comment_karma", 0) or 0)
                a.link_karma = int(getattr(r, "link_karma", 0) or 0)
                stats["profiles"] += 1
            except Exception as exc:  # noqa: BLE001
                stats["failed"] += 1
                if stats["failed"] <= 8:
                    print(f"  [author-profile] u/{name} 刷新失败：{str(exc)[:120]}")

            a.post_count = post_count
            a.influence_score = (
                math.log10(1 + max(0, a.link_karma) + max(0, a.comment_karma))
                + math.log10(1 + max(0, post_score) + 2 * max(0, post_comments))
                + 0.2 * math.log10(1 + post_count)
            )
            a.last_seen = dt.datetime.utcnow()
            if stats["profiles"] % 25 == 0:
                s.flush()
            time.sleep(max(0.0, sleep))
    print(f"[author-profile] 完成 {stats}")
    return stats


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
def crawl_top_authors(
    limit: int = 50,
    per_author_cap: int = PER_AUTHOR_CAP,
    refresh_days: int = 7,
    max_fetch_per: int = MAX_FETCH_PER,
    since_days: int = 365,
    refresh_profiles: bool = True,
    pool: str = "leaderboard",
    min_ticker_posts: int = 3,
    quality_mode: str = "llm",
) -> dict:
    if quality_mode == "llm" and not settings.has_deepseek:
        print("[author-crawl] 无 DeepSeek key，跳过（粗筛闸不可用，避免把全部历史帖送千问）。")
        return {"authors": 0, "added": 0, "skipped": "no_deepseek"}

    stats = {"authors": 0, "fetched": 0, "candidates": 0, "added": 0, "profiles": 0}
    now = dt.datetime.utcnow()
    fresh_cut = now - dt.timedelta(days=refresh_days)
    history_cut = now - dt.timedelta(days=since_days) if since_days and since_days > 0 else None
    history_cut_ts = history_cut.timestamp() if history_cut else None
    selected_authors: list[str] = []

    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")
        tracked = {r[0] for r in s.execute(select(Subreddit.id).where(Subreddit.tracked.is_(True))).all()}

        if pool == "ticker-repeat":
            authors = repeat_ticker_authors(s, limit, min_ticker_posts)
        else:
            authors = top_authors(s, limit)
        selected_authors = list(authors)
        window = f"近 {since_days} 天" if since_days and since_days > 0 else "不限时间"
        print(
            f"[author-crawl] 候选 Top {len(authors)} 作者，pool={pool} "
            f"min_ticker_posts={min_ticker_posts}，开始增量爬取（{window}, refresh>{refresh_days}d）…",
            flush=True,
        )

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
                created_raw = it.get("created_utc")
                if history_cut_ts and created_raw and float(created_raw) < history_cut_ts:
                    continue
                title = it.get("title") or ""
                selftext = it.get("selftext") or ""
                if selftext in ("[removed]", "[deleted]"):
                    selftext = ""
                sub = it.get("subreddit")
                text = f"{title}\n{selftext}"
                mentions = extract_mentions(text, tdict)
                finance = bool(mentions) or (
                    sub and sub.lower() in tracked)
                if quality_mode == "heuristic" and not mentions:
                    finance = False
                if not finance:
                    continue
                candidates.append({
                    "id": pid,
                    "title": title,
                    "selftext": selftext,
                    "raw": it,
                    "sub": sub,
                    "mention_count": len(mentions),
                })

            stats["candidates"] += len(candidates)

            # 便宜粗筛 → 过线 → 截断 per_author_cap
            if candidates:
                if quality_mode == "heuristic":
                    def local_score(c: dict) -> float:
                        raw = c["raw"]
                        text_len = len((c.get("title") or "") + "\n" + (c.get("selftext") or ""))
                        sub = str(c.get("sub") or "").lower()
                        return (
                            min(3.0, math.log1p(max(0, text_len)) / 2.2)
                            + min(2.0, float(c.get("mention_count") or 0) * 0.45)
                            + min(2.0, math.log1p(max(0, int(raw.get("score", 0) or 0))) * 0.35)
                            + min(2.0, math.log1p(max(0, int(raw.get("num_comments", 0) or 0))) * 0.45)
                            + (0.7 if sub in tracked else 0.0)
                        )
                    kept = [c for c in candidates if local_score(c) >= 2.2]
                    kept.sort(key=local_score, reverse=True)
                else:
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
            s.commit()
            if stats["authors"] % 10 == 0:
                print(
                    f"  [author-crawl] progress authors={stats['authors']}/{len(authors)} "
                    f"fetched={stats['fetched']} candidates={stats['candidates']} added={stats['added']}",
                    flush=True,
                )

    if refresh_profiles:
        profile_stats = refresh_author_profiles(selected_authors)
        stats["profiles"] = profile_stats.get("profiles", 0)
    print(f"[author-crawl] 完成 {stats}。过线帖将由 run_analyze(千问) 增量打标并入作者库。", flush=True)
    return stats


if __name__ == "__main__":
    import sys
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    crawl_top_authors(limit=n)
