"""数据库引擎与会话。DATABASE_URL 驱动：sqlite（开发）/ postgresql（生产）。"""
from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from .config import settings
from .models import Base

_DB_URL = settings.database_url


def _make_engine(url: str) -> Engine:
    from .config import normalize_db_url
    url = normalize_db_url(url)  # Supabase 的 postgres:// 串自动转 psycopg + 强制 SSL
    is_sqlite = url.startswith("sqlite")
    kwargs: dict = {"future": True, "pool_pre_ping": True}
    if is_sqlite:
        # 确保父目录存在（sqlite:///./data/dev.db）
        path = url.split("sqlite:///")[-1]
        if path and path not in (":memory:",):
            Path(path).resolve().parent.mkdir(parents=True, exist_ok=True)
        kwargs["connect_args"] = {"check_same_thread": False}
    else:
        # 兼容 Supabase 连接池（pgbouncer / transaction 模式）：关闭 psycopg 预编译语句缓存。
        kwargs["connect_args"] = {"prepare_threshold": None}
    return create_engine(url, **kwargs)


engine = _make_engine(_DB_URL)
# autoflush=True：保证同一会话内对相同主键的 merge 能正确 upsert（先 flush 再 SELECT）。
SessionLocal = sessionmaker(bind=engine, autoflush=True, expire_on_commit=False, future=True)


if engine.dialect.name == "sqlite":

    @event.listens_for(engine, "connect")
    def _sqlite_pragmas(dbapi_conn, _record):  # noqa: ANN001
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA foreign_keys=ON")
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA busy_timeout=8000")  # 并发写时等锁而非立即报 database is locked（多 AI session/管线并行）
        cur.close()


def init_db() -> None:
    """创建所有表（幂等）。"""
    Base.metadata.create_all(engine)


def drop_all() -> None:
    Base.metadata.drop_all(engine)


# 给「市场维度」做的幂等迁移：源表加 market 列（保留数据），派生/聚合表整表重建。
# 派生表（rollup/mood/trending/narratives）每次跑都全量重算，可安全 DROP；
# 它们的唯一约束从「不含 market」改成「含 market」，SQLite 无法 ALTER 约束，只能重建。
_ADD_COLUMNS = [
    ("subreddits", "market", "VARCHAR(8) DEFAULT 'us'"),
    ("subreddits", "tracked", "BOOLEAN DEFAULT 1"),
    ("posts", "market", "VARCHAR(8) DEFAULT 'us'"),
    ("posts", "source", "VARCHAR(8) DEFAULT 'scan'"),  # scan=板块扫描 / author=作者库历史爬取
    ("authors", "crawled_at", "DATETIME"),  # nullable：作者库上次爬取时间
    ("ticker_meta", "market", "VARCHAR(8)"),  # nullable：仅标记策划的中概/港股宇宙
]
# 这些派生表新增了 market 列：缺列即视为旧结构 → 整表重建。
_DERIVED_NEEDS_MARKET = ["ticker_rollup", "market_mood", "trending", "narratives"]
# narratives 重建后，这两张子表的 narrative_id 会变成孤儿 → 一并重建。
_DERIVED_CHILDREN = ["narrative_tickers", "narrative_posts"]


def _existing_columns(conn, table: str) -> set[str]:
    from sqlalchemy import text
    try:
        rows = conn.exec_driver_sql(f"PRAGMA table_info({table})").fetchall()
    except Exception:
        return set()
    return {r[1] for r in rows}


def migrate_market() -> None:
    """把已有库迁移到带 market 维度的新 schema（幂等，可重复跑）。"""
    if engine.dialect.name != "sqlite":
        print("[migrate] 非 sqlite，直接 create_all（生产请用正式迁移工具）。")
        init_db()
        return
    from sqlalchemy import inspect
    insp = inspect(engine)
    existing_tables = set(insp.get_table_names())
    with engine.begin() as conn:
        # 1) 源表加 market 列（保留数据）
        for table, col, decl in _ADD_COLUMNS:
            if table in existing_tables and col not in _existing_columns(conn, table):
                conn.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {col} {decl}")
                print(f"[migrate] {table} += {col}")
        # 2) 派生表：缺 market 列 → 整表重建（约束从「不含 market」改成「含 market」，SQLite 只能重建）
        rebuilt = False
        for table in _DERIVED_NEEDS_MARKET:
            if table in existing_tables and "market" not in _existing_columns(conn, table):
                conn.exec_driver_sql(f"DROP TABLE IF EXISTS {table}")
                print(f"[migrate] 重建派生表 {table}")
                rebuilt = True
        # narratives 被重建 → 其子表的 narrative_id 失效，一并重建
        if "narratives" not in existing_tables or "market" not in _existing_columns(conn, "narratives"):
            for table in _DERIVED_CHILDREN:
                conn.exec_driver_sql(f"DROP TABLE IF EXISTS {table}")
    # 3) 重新建表（含新列/新约束/加宽的 ticker 列）
    init_db()
    print("[migrate] 完成。")


@contextmanager
def session_scope() -> Session:
    """事务会话上下文：正常提交，异常回滚。"""
    s = SessionLocal()
    try:
        yield s
        s.commit()
    except Exception:
        s.rollback()
        raise
    finally:
        s.close()


def dialect() -> str:
    return engine.dialect.name


def data_now(market: str | None = None):
    """窗口锚点：取（该 market）库内最新帖的时间，让「过去 24h」窗口对齐数据本身，
    而非脚本运行时刻（静态数据集 / 离线分析也能正确出聚合）。无数据则退回 utcnow()。

    必须按 market 各自锚定：不同市场的数据新鲜度不同（如 cn 今天新爬、us 是几天前的存量），
    若用全局 max，旧市场会整体落在 24h 窗口之外导致聚合清空。
    """
    import datetime as _dt
    from sqlalchemy import select, func
    from .models import Post
    with session_scope() as s:
        stmt = select(func.max(Post.created_utc))
        if market is not None:
            stmt = stmt.where(Post.market == market)
        mx = s.execute(stmt).scalar()
    return mx or _dt.datetime.utcnow()
