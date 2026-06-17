"""本地 SQLite ⇄ 云端 Postgres(Supabase) 数据同步。

架构：Supabase 是数据的「家」（唯一真源），本地 dev.db 只是构建时的临时快照。
  - cloud-push：把本地 dev.db 的「源数据」(帖子/评论/作者/AI 分析/提及/字典) 上传到云端。
      一次性迁移；增量、可重复跑（已存在的行会跳过）。派生表(榜单/情绪/异动/叙事/简报)
      是廉价的纯 SQL 重算，不迁移——迁移后在云端 `make rollup` 等重新生成即可。
  - cloud-pull：把云端最新数据整表拉回本地 dev.db 快照（全新覆盖），供 `make site` 构建读取。
      网站读取代码完全不用改，仍读本地 SQLite。

云端连接串放在 .env 的 DATABASE_URL（Supabase → Project Settings → Database → Connection string）。
"""
from __future__ import annotations

from pathlib import Path

from sqlalchemy import create_engine, insert, select

from .common.config import normalize_db_url, settings
from .common.models import (
    ALL_TABLES,
    Author,
    Comment,
    ItemAnalysis,
    Mention,
    Post,
    Subreddit,
    TickerMeta,
)
from .common.models import Base

# 源数据：耗时/花钱产生、必须长期保存（含 AI 分析）。迁移只搬这些；
# 派生表（rollup/mood/trending/narratives/briefs）迁移后在云端重算即可。
SOURCE_TABLES = [Subreddit, Author, Post, Comment, TickerMeta, Mention, ItemAnalysis]

LOCAL_URL = "sqlite:///./data/dev.db"


def _engine(url: str):
    is_sqlite = url.startswith("sqlite")
    kw: dict = {"future": True, "pool_pre_ping": True}
    if is_sqlite:
        p = url.split("sqlite:///")[-1]
        if p and p != ":memory:":
            Path(p).resolve().parent.mkdir(parents=True, exist_ok=True)
        kw["connect_args"] = {"check_same_thread": False}
    else:
        # 兼容 Supabase 连接池（pgbouncer / transaction 模式）：关闭 psycopg 预编译语句，
        # 否则连 6543 端口的连接池会报 "prepared statement already exists"。
        kw["connect_args"] = {"prepare_threshold": None}
    return create_engine(url, **kw)


def _wipe_sqlite(url: str) -> None:
    p = url.split("sqlite:///")[-1]
    for suf in ("", "-wal", "-shm"):
        try:
            Path(p + suf).unlink()
        except FileNotFoundError:
            pass


def _copy(src_url: str, dst_url: str, models, fresh: bool = False, batch: int = 1000) -> dict:
    """把 models 列出的表从 src 复制到 dst（按列表顺序＝父表先于子表，满足外键）。
    fresh=True 且 dst 为 sqlite：先删本地文件做「全新快照」；否则增量（跳过 dst 已存在的主键）。
    通过 SQLAlchemy 类型层读写，JSON/布尔/时间在 SQLite↔Postgres 间自动转换。"""
    src_url = normalize_db_url(src_url)
    dst_url = normalize_db_url(dst_url)
    if fresh and dst_url.startswith("sqlite"):
        _wipe_sqlite(dst_url)

    src = _engine(src_url)
    dst = _engine(dst_url)
    Base.metadata.create_all(dst)  # 确保目标端表结构存在（云端首次=建表）

    counts: dict[str, int] = {}
    with src.connect() as sconn, dst.begin() as dconn:
        for model in models:
            tbl = model.__table__
            pk = [c.name for c in tbl.primary_key.columns]
            rows = [dict(m._mapping) for m in sconn.execute(select(tbl))]
            if not rows:
                counts[tbl.name] = 0
                print(f"  {tbl.name:18s} 0", flush=True)
                continue
            existing: set = set()
            if not fresh:
                for m in dconn.execute(select(*[tbl.c[k] for k in pk])):
                    existing.add(tuple(m))
            to_ins = [r for r in rows if tuple(r[k] for k in pk) not in existing] if existing else rows
            for i in range(0, len(to_ins), batch):
                if to_ins[i : i + batch]:
                    dconn.execute(insert(tbl), to_ins[i : i + batch])
            counts[tbl.name] = len(to_ins)
            print(f"  {tbl.name:18s} {len(to_ins):>7d}/{len(rows)}", flush=True)
    return counts


def _cloud_url(explicit: str | None = None) -> str:
    url = normalize_db_url(explicit or settings.database_url or "")
    if not url.startswith("postgresql"):
        raise SystemExit(
            "云端未配置：请在 .env 把 DATABASE_URL 设为 Supabase 的 Postgres 连接串"
            "（Supabase → Project Settings → Database → Connection string）。详见 CLOUD_DB.md。"
        )
    return url


def push(local: str = LOCAL_URL, cloud: str | None = None) -> None:
    """本地 dev.db 的源数据 → 云端 Supabase（增量、可重复跑）。"""
    cloud = _cloud_url(cloud)
    print("[cloud-push] 上传源数据：本地 → 云端 Supabase …", flush=True)
    counts = _copy(local, cloud, SOURCE_TABLES, fresh=False)
    print(
        f"[cloud-push] 完成，新增 {sum(counts.values())} 行。"
        "派生表请在云端用 `make rollup`/narratives 等重新生成。"
    )


def pull(local: str = LOCAL_URL, cloud: str | None = None) -> None:
    """云端 Supabase → 本地 dev.db 全新快照（供 `make site` 构建读取）。"""
    cloud = _cloud_url(cloud)
    print("[cloud-pull] 拉取快照：云端 Supabase → 本地 data/dev.db（全新覆盖）…", flush=True)
    counts = _copy(cloud, local, ALL_TABLES, fresh=True)
    print(f"[cloud-pull] 完成，写入本地 {sum(counts.values())} 行。现在可 `make site` 构建。")
