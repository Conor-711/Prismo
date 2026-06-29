"""整体散户 每日讨论度 rollup（标的页『整体散户』视图的堆叠条状子面板）。

与 KOL 版（kol_volume.py）同范式、同输出形状（每 (ticker, day) 一行的纯计数），区别在**平台口径**：
散户=全量、纳入本土散户论坛、不含 YouTube。平台 = X / Reddit / 雪球 / Naver / Yahoo JP / PTT（+ 预留 Toss）。
当天**讨论该标的的帖子总量**（纯计数、非加权），按平台拆 n_<key>，n_total = 各平台之和 → web 堆叠条形图。

源（混合本地 + 云端，与 kol_volume 一致）：
  - **本地 dev.db**：Reddit(mentions⋈posts 去重帖)、四论坛(gr_post 按 source 计数)。
  - **云端 Supabase**：X = **直接数 `tw_tweet_ticker`**（稳定权威的标的↔推文链接表，含 created_at、全量全历史）。
    **不 join `tw_tweet`**——后者滚动窗口、tweet_id 漂移、join 会丢行（实测 0 命中）。

输出 → 本地 dev.db 的 `retail_volume_daily`（原生 DDL 自建、不入 models.py）。整表重算、幂等。
运行：**不要加 sqlite 覆盖**——本脚本自 hardcode 本地、从 .env 读云端拿 X。
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict

from sqlalchemy import create_engine, text

from ..common.config import ROOT, normalize_db_url, settings

LOCAL_URL = "sqlite:///./data/dev.db"

SRC_KEYS = ["reddit", "x", "xueqiu", "naver", "yahoojp", "ptt", "toss"]


def _cloud_url() -> str | None:
    """云端 Postgres 串：优先 settings（若没被 sqlite 覆盖），否则直接解析 .env 文件。"""
    u = settings.database_url or ""
    if u.startswith("postgres"):
        return normalize_db_url(u)
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("DATABASE_URL=") and "postgres" in line:
                v = line.split("=", 1)[1].strip().strip('"').strip("'")
                return normalize_db_url(v)
    return None


def rollup() -> int:
    local = create_engine(LOCAL_URL, connect_args={"check_same_thread": False})
    n_cols = ", ".join(f"n_{k} INTEGER DEFAULT 0" for k in SRC_KEYS)
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS retail_volume_daily ("
            "ticker TEXT NOT NULL, day TEXT NOT NULL, n_total INTEGER DEFAULT 0, "
            f"{n_cols}, updated_at TEXT, PRIMARY KEY (ticker, day))"))

    acc: dict[tuple[str, str], dict] = defaultdict(lambda: {k: 0 for k in SRC_KEYS})

    def add(ticker, day, n, src):
        if not ticker or not day or not n:
            return
        acc[(str(ticker).upper(), str(day)[:10])][src] += int(n)

    # 我们展示的标的全集（X 计数只取这些，避免 tw_tweet_ticker 数百标的的无关 bloat）
    with local.connect() as c:
        symbols = [str(r[0]).upper() for r in c.execute(text("SELECT ticker FROM gr_ticker")) if r[0]]

    # ---- 本地：Reddit（去重帖）+ 四论坛（按 source 计数）----
    with local.connect() as c:
        for tk, day, n in c.execute(text(
            "SELECT m.ticker, substr(p.created_utc,1,10), count(DISTINCT p.id) "
            "FROM mentions m JOIN posts p ON p.id=m.item_id AND m.item_type='post' "
            "WHERE COALESCE(p.source,'scan')='scan' GROUP BY 1,2")):
            add(tk, day, n, "reddit")
        print(f"[retail-volume] reddit ✓（累计 {len(acc)} 格）", flush=True)

        GR = {"xueqiu": "xueqiu", "naver": "naver", "yahoo_jp": "yahoojp", "ptt": "ptt", "toss": "toss"}
        for gsrc, key in GR.items():
            for tk, day, n in c.execute(text(
                "SELECT ticker, substr(created_utc,1,10), count(*) "
                "FROM gr_post WHERE source=:s GROUP BY 1,2"), {"s": gsrc}):
                add(tk, day, n, key)
            print(f"[retail-volume] {gsrc} ✓（累计 {len(acc)} 格）", flush=True)

    # ---- 云端 X（直接数 tw_tweet_ticker，不 join tw_tweet）----
    cu = _cloud_url()
    if cu:
        cloud = create_engine(cu, connect_args={"prepare_threshold": None}, pool_pre_ping=True)
        nx = 0
        with cloud.connect() as c:
            for tk, day, n in c.execute(text(
                "SELECT ticker, to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD'), count(*) "
                "FROM tw_tweet_ticker WHERE ticker = ANY(:syms) AND created_at IS NOT NULL GROUP BY 1,2"),
                {"syms": symbols}):
                add(tk, day, n, "x")
                nx += int(n or 0)
        print(f"[retail-volume] X ✓（{nx:,} 条推文计数；累计 {len(acc)} 格）", flush=True)
    else:
        print("[retail-volume] ⚠ 未找到云端 DATABASE_URL → 跳过 X（讨论度缺 X 贡献）", flush=True)

    # ---- 落库（整表重算）----
    now = dt.datetime.utcnow().isoformat()
    rows = []
    for (t, d), a in acc.items():
        total = sum(a[k] for k in SRC_KEYS)
        if total <= 0:
            continue
        row = {"ticker": t, "day": d, "n_total": total, "updated_at": now}
        for k in SRC_KEYS:
            row[f"n_{k}"] = a[k]
        rows.append(row)
    cols = "ticker,day,n_total," + ",".join(f"n_{k}" for k in SRC_KEYS) + ",updated_at"
    ph = ":ticker,:day,:n_total," + ",".join(f":n_{k}" for k in SRC_KEYS) + ",:updated_at"
    with local.begin() as c:
        c.execute(text("DELETE FROM retail_volume_daily"))
        ins = text(f"INSERT INTO retail_volume_daily ({cols}) VALUES ({ph})")
        for i in range(0, len(rows), 500):
            if rows[i:i + 500]:
                c.execute(ins, rows[i:i + 500])
    print(f"[retail-volume] 写入 {len(rows):,} (ticker,day) 行 → 本地 retail_volume_daily。", flush=True)
    return len(rows)


if __name__ == "__main__":
    rollup()
