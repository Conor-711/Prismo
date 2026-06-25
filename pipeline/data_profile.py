"""只读数据画像：行数 / 覆盖面 / 时间跨度 / 每日密度。

只读：仅 SELECT，绝不写库 / 不建表 / 不跑 DDL。
用法：DATABASE_URL=<Supabase URI> pipeline/.venv/bin/python -m pipeline.data_profile
"""
from __future__ import annotations

import os
import sys

from sqlalchemy import create_engine, text

from pipeline.common.config import normalize_db_url

URL = os.environ.get("DATABASE_URL")
if not URL:
    print("✗ 未设置 DATABASE_URL")
    sys.exit(1)

norm = normalize_db_url(URL)
connect_args = {"connect_timeout": 8} if norm.startswith("postgresql") else {}
eng = create_engine(norm, connect_args=connect_args)

ALL_TABLES = [
    "subreddits", "authors", "posts", "comments", "ticker_meta", "mentions",
    "item_analysis", "ticker_rollup", "market_mood", "trending", "narratives",
    "narrative_tickers", "narrative_posts", "daily_briefs",
    "asia_posts", "asia_analysis", "asia_ticker_summary", "asia_price",
    "gr_post", "gr_ticker_region", "gr_ticker", "gr_quote",
]


def q(conn, sql, **params):
    try:
        return conn.execute(text(sql), params).fetchall()
    except Exception as e:  # 表缺失 / 列差异 → 不崩，记一笔
        print(f"   (跳过：{str(e).splitlines()[0][:80]})")
        return None


def one(conn, sql, **params):
    rows = q(conn, sql, **params)
    return rows[0] if rows else None


def section(title):
    print(f"\n{'='*60}\n{title}\n{'='*60}")


with eng.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
    print(f"✓ 已连接：{eng.dialect.name}  ({norm.split('@')[-1][:50]})")

    section("① 各表行数")
    for t in ALL_TABLES:
        r = one(conn, f"SELECT COUNT(*) FROM {t}")
        if r is not None:
            print(f"  {t:22s} {r[0]:>8d}")

    section("② Reddit 主管线：覆盖面 & 时间跨度")
    r = q(conn, "SELECT market, COUNT(*) FROM posts GROUP BY market ORDER BY 2 DESC")
    if r:
        print("  帖子数 by market：", ", ".join(f"{m}={n}" for m, n in r))
    r = q(conn, "SELECT source, COUNT(*) FROM posts GROUP BY source ORDER BY 2 DESC")
    if r:
        print("  帖子数 by source：", ", ".join(f"{s}={n}" for s, n in r))
    r = one(conn, "SELECT MIN(created_utc), MAX(created_utc) FROM posts")
    if r:
        print(f"  发帖时间跨度：{r[0]}  →  {r[1]}")
    r = one(conn, "SELECT MIN(created_utc), MAX(created_utc) FROM comments")
    if r:
        print(f"  评论时间跨度：{r[0]}  →  {r[1]}")
    r = one(conn, "SELECT COUNT(DISTINCT author_id) FROM posts")
    if r:
        print(f"  涉及作者数：{r[0]}")
    r = one(conn, "SELECT COUNT(*) FROM authors WHERE crawled_at IS NOT NULL")
    if r:
        print(f"  作者库已爬作者数（crawled_at 非空）：{r[0]}")

    section("③ AI 打标覆盖率")
    p = one(conn, "SELECT COUNT(*) FROM posts WHERE source='scan'")
    ia = one(conn, "SELECT COUNT(*) FROM item_analysis")
    if p and ia:
        pct = (ia[0] / p[0] * 100) if p[0] else 0
        print(f"  scan 帖 {p[0]} / 已打标 item_analysis {ia[0]}  → 覆盖 {pct:.1f}%")
    r = q(conn, "SELECT stance, COUNT(*) FROM item_analysis GROUP BY stance ORDER BY 2 DESC")
    if r:
        print("  立场分布：", ", ".join(f"{s}={n}" for s, n in r))

    section("④ ticker 覆盖面")
    r = one(conn, "SELECT COUNT(*) FROM ticker_meta")
    if r:
        print(f"  字典内 ticker 总数：{r[0]}")
    r = q(conn, "SELECT market, COUNT(*) FROM ticker_meta GROUP BY market")
    if r:
        print("  字典 by market：", ", ".join(f"{m or 'us(空)'}={n}" for m, n in r))
    r = one(conn, "SELECT COUNT(DISTINCT ticker) FROM mentions")
    if r:
        print(f"  实际被提及的 ticker 数：{r[0]}")
    r = q(conn, """SELECT ticker, COUNT(*) c FROM mentions GROUP BY ticker
                   ORDER BY c DESC LIMIT 15""")
    if r:
        print("  Top15 提及：", ", ".join(f"{t}({c})" for t, c in r))

    section("⑤ 每日密度（近 21 天 scan 帖 / 天）")
    r = q(conn, """SELECT CAST(created_utc AS DATE) d, market, COUNT(*) c
                   FROM posts WHERE source='scan'
                     AND created_utc >= (CURRENT_DATE - INTERVAL '21 day')
                   GROUP BY 1,2 ORDER BY 1 DESC, 2""")
    if r:
        from collections import defaultdict
        by_day = defaultdict(dict)
        for d, m, c in r:
            by_day[str(d)][m] = c
        for d in sorted(by_day, reverse=True):
            row = by_day[d]
            print(f"  {d}  " + "  ".join(f"{m}={n}" for m, n in sorted(row.items())))

    section("⑥ 亚洲实验 asia_*（jp/kr）")
    r = q(conn, "SELECT market, COUNT(*) FROM asia_posts GROUP BY market")
    if r:
        print("  asia_posts by market：", ", ".join(f"{m}={n}" for m, n in r))
    r = q(conn, "SELECT ticker, COUNT(*) c FROM asia_posts GROUP BY ticker ORDER BY c DESC")
    if r:
        print("  by ticker：", ", ".join(f"{t}({c})" for t, c in r))
    r = one(conn, "SELECT MIN(created_utc), MAX(created_utc) FROM asia_posts")
    if r:
        print(f"  时间跨度：{r[0]}  →  {r[1]}")
    r = one(conn, "SELECT COUNT(*) FROM asia_posts WHERE sentiment IS NOT NULL")
    if r:
        print(f"  已打情绪分（sentiment 非空）：{r[0]}")

    section("⑦ 全球散户 gr_*（us/cn/jp/kr/tw，新首页数据）")
    r = q(conn, "SELECT region, COUNT(*) FROM gr_post GROUP BY region ORDER BY 2 DESC")
    if r:
        print("  gr_post by region：", ", ".join(f"{m}={n}" for m, n in r))
    r = one(conn, "SELECT MIN(created_utc), MAX(created_utc) FROM gr_post")
    if r:
        print(f"  gr_post 时间跨度：{r[0]}  →  {r[1]}")
    r = q(conn, "SELECT ticker, COUNT(*) c FROM gr_post GROUP BY ticker ORDER BY c DESC LIMIT 15")
    if r:
        print("  Top15 ticker：", ", ".join(f"{t}({c})" for t, c in r))
    r = q(conn, "SELECT region, COUNT(*) FROM gr_ticker_region GROUP BY region ORDER BY 2 DESC")
    if r:
        print("  gr_ticker_region by region：", ", ".join(f"{m}={n}" for m, n in r))
    r = q(conn, """SELECT regions_present, COUNT(*) FROM gr_ticker
                   GROUP BY regions_present ORDER BY 1 DESC""")
    if r:
        print("  gr_ticker 跨区覆盖（有几区数据→标的数）：",
              ", ".join(f"{k}区={n}" for k, n in r))
    r = one(conn, "SELECT COUNT(*) FROM gr_quote")
    if r:
        print(f"  gr_quote（最新价快照）：{r[0]} 支")

print("\n✓ 完成（只读，未写入任何数据）")
