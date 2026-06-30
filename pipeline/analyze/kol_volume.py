"""KOL 每日讨论度 rollup（标的页折线K线图下方的「每日讨论度」条状子面板）。

每 (ticker, day) 一行：当天**讨论该标的的帖子 + YouTube 视频总量**（纯计数，非加权）。
按平台拆分 n_reddit / n_x / n_xueqiu / n_youtube，n_total = 四者之和 → web 端堆叠条形图。

源（混合本地 + 云端，与 kol_sentiment 同范式）：
  - **本地 dev.db**：Reddit(mentions⋈posts，去重帖)、雪球(gr_post source=xueqiu)、YouTube(yt_video)。
  - **云端 Supabase**：X = **直接数 `tw_tweet_ticker`**（外部工具灌入的标的↔推文链接表，含 created_at、
    全量全历史）。**不 join `tw_tweet`**——后者是滚动窗口、tweet_id 会漂移，join 会丢行（实测 0 命中）；
    tw_tweet_ticker 才是稳定权威的「这条推在讨论该标的」链接，计数即讨论量（含转/引/回，不区分类型）。

输出 → 本地 dev.db 的 `kol_volume_daily`（原生 DDL 自建、不入 models.py；纯本地派生、随构建读，
`make site` 直接用）。整表重算、幂等。运行：**不要加 sqlite 覆盖**——本脚本自己 hardcode 本地、并从 .env
读云端 URL，故 `make kol-volume` 同时拿到两边（与 kol-sentiment 一致）。
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict

from sqlalchemy import create_engine, text

from ..common.config import ROOT, normalize_db_url, settings

LOCAL_URL = "sqlite:///./data/dev.db"


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
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS kol_volume_daily ("
            "ticker TEXT NOT NULL, day TEXT NOT NULL, n_total INTEGER DEFAULT 0, "
            "n_reddit INTEGER DEFAULT 0, n_x INTEGER DEFAULT 0, n_xueqiu INTEGER DEFAULT 0, n_youtube INTEGER DEFAULT 0, "
            "updated_at TEXT, PRIMARY KEY (ticker, day))"))

    acc: dict[tuple[str, str], dict] = defaultdict(
        lambda: {"reddit": 0, "x": 0, "xueqiu": 0, "youtube": 0})

    def add(ticker, day, n, src):
        if not ticker or not day or not n:
            return
        acc[(str(ticker).upper(), str(day)[:10])][src] += int(n)

    # 我们展示的标的全集（tw_tweet_ticker 含外部工具的全部数百标的 → X 计数只取这些，避免无关 bloat）
    with local.connect() as c:
        symbols = [str(r[0]).upper() for r in c.execute(text("SELECT ticker FROM gr_ticker")) if r[0]]

    # ---- 本地三源（去重计数）----
    with local.connect() as c:
        for tk, day, n in c.execute(text(
            "SELECT m.ticker, substr(p.created_utc,1,10), count(DISTINCT p.id) "
            "FROM mentions m JOIN posts p ON p.id=m.item_id AND m.item_type='post' "
            "WHERE COALESCE(p.source,'scan')='scan' GROUP BY 1,2")):
            add(tk, day, n, "reddit")
        print(f"[kol-volume] reddit ✓（累计 {len(acc)} 格）", flush=True)

        for tk, day, n in c.execute(text(
            "SELECT ticker, substr(created_utc,1,10), count(*) "
            "FROM gr_post WHERE source='xueqiu' GROUP BY 1,2")):
            add(tk, day, n, "xueqiu")
        print(f"[kol-volume] xueqiu ✓（累计 {len(acc)} 格）", flush=True)

        for tk, day, n in c.execute(text(
            "SELECT ticker, substr(published_utc,1,10), count(*) "
            "FROM yt_video GROUP BY 1,2")):
            add(tk, day, n, "youtube")
        print(f"[kol-volume] youtube ✓（累计 {len(acc)} 格）", flush=True)

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
        print(f"[kol-volume] X ✓（{nx:,} 条推文计数；累计 {len(acc)} 格）", flush=True)
    else:
        print("[kol-volume] ⚠ 未找到云端 DATABASE_URL → 跳过 X（讨论度缺 X 贡献）", flush=True)

    # ---- 落库（整表重算）----
    now = dt.datetime.utcnow().isoformat()
    rows = []
    for (t, d), a in acc.items():
        total = a["reddit"] + a["x"] + a["xueqiu"] + a["youtube"]
        if total <= 0:
            continue
        rows.append({"ticker": t, "day": d, "n_total": total, "n_reddit": a["reddit"],
                     "n_x": a["x"], "n_xueqiu": a["xueqiu"], "n_youtube": a["youtube"], "updated_at": now})
    with local.begin() as c:
        c.execute(text("DELETE FROM kol_volume_daily"))
        ins = text("INSERT INTO kol_volume_daily VALUES "
                   "(:ticker,:day,:n_total,:n_reddit,:n_x,:n_xueqiu,:n_youtube,:updated_at)")
        for i in range(0, len(rows), 500):
            if rows[i:i + 500]:
                c.execute(ins, rows[i:i + 500])
    print(f"[kol-volume] 写入 {len(rows):,} (ticker,day) 行 → 本地 kol_volume_daily。", flush=True)
    return len(rows)


if __name__ == "__main__":
    rollup()
