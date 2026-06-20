"""只读快照导出：把云端核心表复制到本地 SQLite，供离线实验用。

只读源库（仅 SELECT + 反射）；只写本地目标 sqlite 文件。不动云端。
用法：
  DATABASE_URL=<cloud-uri> pipeline/.venv/bin/python -m pipeline.snapshot_pull data/prismo_snapshot.db
"""
from __future__ import annotations

import os
import sys

from sqlalchemy import MetaData, create_engine, insert, select

from pipeline.common.config import normalize_db_url

SRC_URL = os.environ.get("DATABASE_URL")
DST_PATH = sys.argv[1] if len(sys.argv) > 1 else "data/prismo_snapshot.db"
if not SRC_URL:
    print("✗ 未设置 DATABASE_URL（源云库）")
    sys.exit(1)

CORE_TABLES = [
    "subreddits", "authors", "posts", "comments", "ticker_meta", "mentions",
    "item_analysis", "ticker_rollup", "market_mood", "trending",
    "narratives", "narrative_tickers", "narrative_posts", "daily_briefs",
]

src = create_engine(normalize_db_url(SRC_URL), connect_args={"connect_timeout": 12})
dst = create_engine(f"sqlite:///{DST_PATH}")

md = MetaData()
md.reflect(bind=src, only=CORE_TABLES)
# 去掉 Postgres 专有 server-default（nextval(...)::regclass 等），否则 SQLite 建表失败
for tbl in md.tables.values():
    for col in tbl.columns:
        col.server_default = None
        col.autoincrement = False
md.create_all(dst)
print(f"反射到 {len(md.tables)} 张表 → 写入 {DST_PATH}")

with src.connect().execution_options(stream_results=True) as sconn, dst.begin() as dconn:
    for name in CORE_TABLES:
        if name not in md.tables:
            print(f"  跳过 {name}（源库无此表）")
            continue
        tbl = md.tables[name]
        rows = [dict(r._mapping) for r in sconn.execute(select(tbl))]
        if rows:
            dconn.execute(insert(tbl), rows)
        print(f"  {name:18s} {len(rows):>7d} 行")

print("✓ 快照完成（只读源、未写云端）")
