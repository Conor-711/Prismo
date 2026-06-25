"""从云端 Supabase 拉真实 X/Twitter 推文 → 本地 dev.db 的 x_opinion 表。
   tw_tweet ⋈ tw_tweet_ticker（标的关联），近 N 天、每标的按互动量取 top。
   供详情页第 1 块「个体观点·KOL」的 X 来源（真实推文）。
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


def main() -> None:
    db = os.path.abspath(DB)
    con = sqlite3.connect(db)
    con.execute(
        """CREATE TABLE IF NOT EXISTS x_opinion (
             tweet_id TEXT, ticker TEXT, handle TEXT, text TEXT, lang TEXT,
             likes INTEGER, retweets INTEGER, replies INTEGER, quotes INTEGER, views INTEGER,
             created TEXT, url TEXT, PRIMARY KEY (ticker, tweet_id))"""
    )
    tickers = [r[0] for r in con.execute("SELECT ticker FROM gr_ticker").fetchall()]
    print(f"[x_pull] 标的数={len(tickers)} per_ticker={PER_TICKER} window={WINDOW_DAYS}d")

    total = 0
    with session_scope() as s:
        for tk in tickers:
            rows = s.execute(
                text(
                    # 日期过滤放在 link 表（idx_tw_tt_ticker_created），先取 tweet_id 子集再 join → 快（~3s/标的）
                    """SELECT t.tweet_id, t.author_handle, t.text, t.lang,
                              COALESCE(t.like_count,0), COALESCE(t.retweet_count,0),
                              COALESCE(t.reply_count,0), COALESCE(t.quote_count,0), COALESCE(t.view_count,0),
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
            con.execute("DELETE FROM x_opinion WHERE ticker = ?", (tk,))
            for r in rows:
                created = r[9].isoformat(sep=" ") if hasattr(r[9], "isoformat") else str(r[9] or "")
                con.execute(
                    "INSERT OR REPLACE INTO x_opinion VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (str(r[0]), tk, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], created[:19], r[10] or ""),
                )
            con.commit()
            total += len(rows)
            if rows:
                print(f"  [x] {tk}: {len(rows)}（top 互动 {rows[0][4] + rows[0][5]}）")

    n_authors = con.execute("SELECT count(DISTINCT handle) FROM x_opinion").fetchone()[0]
    print(f"[x_pull] 完成：{total} 条推文、{n_authors} 个作者 → x_opinion")
    con.close()


if __name__ == "__main__":
    main()
