"""从云端 Supabase 拉真实 X/Twitter 推文 → 本地 dev.db 的 x_opinion + x_reply 表。
   ① x_opinion：tw_tweet ⋈ tw_tweet_ticker（标的关联），近 N 天、每标的按互动量取 top。逐项互动数全带（赞/转/评/引/看/藏）。
   ② x_reply：上面每条推文下「互动数多的评论」——tw_tweet 自关联 in_reply_to_tweet_id，按点赞取 top-K。
   供详情页第 1 块「个体观点·KOL」的 X 来源（真实推文 + 热门评论 + 互动数行）。
   头像：tw_tweet.raw_json 全空、tw_kol 无头像 → web 端用 unavatar.io/twitter/{handle} 兜底。
   用法：pipeline/.venv/bin/python -m pipeline.ingest.x_pull
   注：venv python（含 sqlalchemy+psycopg、.env→云端 postgres）。读云端、写本地 dev.db。
"""
from __future__ import annotations

import os
import sqlite3

from sqlalchemy import text

from ..common.db import session_scope

DB = os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db")
PER_TICKER = int(os.environ.get("X_PER_TICKER", "60"))
WINDOW_DAYS = int(os.environ.get("X_WINDOW_DAYS", "16"))
REPLIES_PER_TWEET = int(os.environ.get("X_REPLIES_PER_TWEET", "3"))


def main() -> None:
    db = os.path.abspath(DB)
    con = sqlite3.connect(db)
    # 全量重建（纯派生表）→ 保证 schema（含 bookmarks）随脚本演进，避免 ALTER 漂移。
    con.execute("DROP TABLE IF EXISTS x_opinion")
    con.execute(
        """CREATE TABLE x_opinion (
             tweet_id TEXT, ticker TEXT, handle TEXT, text TEXT, lang TEXT,
             likes INTEGER, retweets INTEGER, replies INTEGER, quotes INTEGER, views INTEGER, bookmarks INTEGER,
             created TEXT, url TEXT, PRIMARY KEY (ticker, tweet_id))"""
    )
    tickers = [r[0] for r in con.execute("SELECT ticker FROM gr_ticker").fetchall()]
    print(f"[x_pull] 标的数={len(tickers)} per_ticker={PER_TICKER} window={WINDOW_DAYS}d replies/tweet={REPLIES_PER_TWEET}")

    total = 0
    with session_scope() as s:
        for tk in tickers:
            rows = s.execute(
                text(
                    # 日期过滤放在 link 表（idx_tw_tt_ticker_created），先取 tweet_id 子集再 join → 快（~3s/标的）
                    """SELECT t.tweet_id, t.author_handle, t.text, t.lang,
                              COALESCE(t.like_count,0), COALESCE(t.retweet_count,0),
                              COALESCE(t.reply_count,0), COALESCE(t.quote_count,0),
                              COALESCE(t.view_count,0), COALESCE(t.bookmark_count,0),
                              t.created_at, t.url
                         FROM tw_tweet t
                         JOIN (SELECT tweet_id FROM tw_tweet_ticker
                                WHERE ticker = :tk AND created_at >= now() - make_interval(days => :w)) tt
                           ON tt.tweet_id = t.tweet_id
                        WHERE t.author_handle IS NOT NULL AND t.text IS NOT NULL
                        ORDER BY (COALESCE(t.like_count,0)+COALESCE(t.retweet_count,0)+COALESCE(t.reply_count,0)) DESC
                        LIMIT :lim"""
                ),
                {"tk": tk, "w": WINDOW_DAYS, "lim": PER_TICKER},
            ).fetchall()
            for r in rows:
                created = r[10].isoformat(sep=" ") if hasattr(r[10], "isoformat") else str(r[10] or "")
                con.execute(
                    "INSERT OR REPLACE INTO x_opinion VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (str(r[0]), tk, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], created[:19], r[11] or ""),
                )
            con.commit()
            total += len(rows)
            if rows:
                print(f"  [x] {tk}: {len(rows)}（top 互动 {rows[0][4] + rows[0][5]}）")

    n_authors = con.execute("SELECT count(DISTINCT handle) FROM x_opinion").fetchone()[0]
    print(f"[x_pull] 推文完成：{total} 条、{n_authors} 个作者 → x_opinion")

    # —— 热门评论：对已拉进 x_opinion 的每条推文，取其下点赞最高的前 K 条回复 ——
    con.execute("DROP TABLE IF EXISTS x_reply")
    con.execute(
        """CREATE TABLE x_reply (
             parent_tweet_id TEXT, reply_id TEXT, handle TEXT, text TEXT, lang TEXT,
             likes INTEGER, retweets INTEGER, replies INTEGER, created TEXT, url TEXT, rank INTEGER,
             PRIMARY KEY (parent_tweet_id, reply_id))"""
    )
    ids = [r[0] for r in con.execute("SELECT DISTINCT tweet_id FROM x_opinion").fetchall()]
    nrep = 0
    with session_scope() as s:
        for i in range(0, len(ids), 500):
            chunk = ids[i : i + 500]  # = ANY(:ids)：psycopg 把 list 适配成 PG 数组，免 IN-tuple 展开坑
            rows = s.execute(
                text(
                    """SELECT parent, tweet_id, author_handle, text, lang, lc, rc, rpc, created_at, url, rn FROM (
                          SELECT in_reply_to_tweet_id AS parent, tweet_id, author_handle, text, lang,
                                 COALESCE(like_count,0) lc, COALESCE(retweet_count,0) rc, COALESCE(reply_count,0) rpc,
                                 created_at, url,
                                 ROW_NUMBER() OVER (PARTITION BY in_reply_to_tweet_id
                                                    ORDER BY COALESCE(like_count,0) DESC, COALESCE(reply_count,0) DESC) rn
                            FROM tw_tweet
                           WHERE in_reply_to_tweet_id = ANY(:ids) AND text IS NOT NULL AND author_handle IS NOT NULL
                       ) z WHERE rn <= :top"""
                ),
                {"ids": chunk, "top": REPLIES_PER_TWEET},
            ).fetchall()
            for r in rows:
                created = r[8].isoformat(sep=" ") if hasattr(r[8], "isoformat") else str(r[8] or "")
                con.execute(
                    "INSERT OR REPLACE INTO x_reply VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (str(r[0]), str(r[1]), r[2], r[3], r[4], r[5], r[6], r[7], created[:19], r[9] or "", r[10]),
                )
            con.commit()
            nrep += len(rows)

    n_parents = con.execute("SELECT count(DISTINCT parent_tweet_id) FROM x_reply").fetchone()[0]
    print(f"[x_pull] 评论完成：{nrep} 条评论、覆盖 {n_parents} 条推文 → x_reply")
    con.close()


if __name__ == "__main__":
    main()
