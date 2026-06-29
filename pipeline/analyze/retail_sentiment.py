"""整体散户 每日净情绪 rollup（标的页『整体散户』视图的绿/红情绪面积子面板）。

与 KOL 版（kol_sentiment.py）同范式、同输出形状（每 (ticker, day) 一行的无界净值 net），
区别只在**人群/平台口径**：这里不区分 KOL，纳入**全量散户**，且把**本土散户论坛**算进来——
平台 = X / Reddit / 雪球 / Naver(韩) / Yahoo Finance JP / PTT(台)（+ 预留 Toss）。**不含 YouTube**
（YouTube 是创作者而非散户大众，留在 KOL 视图）。X/Reddit/雪球 与 KOL 视图共享同一批源数据（按用户
决策：散户靠『平台/地区构成』区别，不按作者过滤；共享平台上两视图数据相同是预期内的重叠）。

加权口径（与 KOL 略不同，更贴合『散户=人头』）：net += 情绪 × 相关性 × (1 + ln(1+互动))。
**(1+...) 的基座**让无互动数据的源（Yahoo JP 引擎不给赞/评 → 互动恒 0）仍按『一个帖子算一票』计入，
否则日本会整段从情绪曲线消失。相关性：reddit/x/xueqiu 复用 kol_relevance（缺省 0.7）；本土论坛
（naver/yahoo_jp/ptt）的帖子本就挂在该标的的股吧版块、天然切题 → 相关性取 1.0。

源（混合本地 + 云端，与 kol_sentiment 一致）：
  - **本地 dev.db**：Reddit(item_analysis)、雪球+Naver+YahooJP+PTT(gr_post.sentiment，按 source 拆)。
  - **云端 Supabase**：X = **`tw_tweet_ticker` ⋈ `tw_tweet_sentiment`**（稳定链接表，含 created_at；先跑 `tw-sentiment`）。
    不走 `tw_tweet`（滚动窗口、现已空 0 行 → join 必 0）；故 X 无逐帖互动数、权重退化为基座 1.0（每条算一票）。

输出 → 本地 dev.db 的 `retail_sentiment_daily`（原生 DDL 自建、不入 models.py；纯本地派生、随 `make site`
构建读）。整表重算、幂等。运行：**不要加 sqlite 覆盖**——本脚本自 hardcode 本地、从 .env 读云端拿 X。
"""
from __future__ import annotations

import datetime as dt
import math
from collections import defaultdict

from sqlalchemy import create_engine, text

from ..common.config import ROOT, normalize_db_url, settings

LOCAL_URL = "sqlite:///./data/dev.db"

# 散户视图的平台键（acc 内部 + 落库列 net_<key>）。gr_post.source 'yahoo_jp' → 键 'yahoojp'（列名无下划线歧义）。
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


def _w(engagement: float, relevance: float) -> float:
    # 散户口径：基座 1（每帖至少一票）+ 互动对数放大；再乘相关性。
    return max(0.0, relevance) * (1.0 + math.log1p(max(0.0, engagement)))


def rollup() -> int:
    local = create_engine(LOCAL_URL, connect_args={"check_same_thread": False})
    net_cols = ", ".join(f"net_{k} REAL DEFAULT 0" for k in SRC_KEYS)
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS retail_sentiment_daily ("
            "ticker TEXT NOT NULL, day TEXT NOT NULL, net REAL DEFAULT 0, "
            "n_posts INTEGER DEFAULT 0, n_bull INTEGER DEFAULT 0, n_bear INTEGER DEFAULT 0, "
            f"{net_cols}, updated_at TEXT, PRIMARY KEY (ticker, day))"))

    acc: dict[tuple[str, str], dict] = defaultdict(
        lambda: {"net": 0.0, "n": 0, "bull": 0, "bear": 0, **{k: 0.0 for k in SRC_KEYS}})

    def add(ticker, day, senti, w, src):
        if not ticker or not day:
            return
        senti = float(senti or 0.0)
        a = acc[(str(ticker).upper(), str(day)[:10])]
        v = senti * w
        a["net"] += v
        a[src] += v
        a["n"] += 1
        if senti > 0.15:
            a["bull"] += 1
        elif senti < -0.15:
            a["bear"] += 1

    # ---- 本地：Reddit ----
    with local.connect() as c:
        for tk, day, senti, eng, rel in c.execute(text(
            "SELECT m.ticker, substr(p.created_utc,1,10), a.sentiment_score, "
            "COALESCE(p.score,0)+COALESCE(p.num_comments,0), COALESCE(r.score,70)/100.0 "
            "FROM mentions m JOIN posts p ON p.id=m.item_id AND m.item_type='post' "
            "JOIN item_analysis a ON a.item_id=p.id AND a.item_type='post' "
            "LEFT JOIN kol_relevance r ON r.source='reddit' AND r.item_id=p.id AND r.ticker=m.ticker "
            "WHERE COALESCE(p.source,'scan')='scan'")):
            add(tk, day, senti, _w(eng or 0, rel or 0.7), "reddit")
        print(f"[retail-sentiment] reddit ✓（累计 {len(acc)} 格）", flush=True)

        # ---- 本地：四个散户论坛（gr_post，按 source 拆到不同平台键；本土版块天然切题→相关性 1.0）----
        GR = {"xueqiu": "xueqiu", "naver": "naver", "yahoo_jp": "yahoojp", "ptt": "ptt", "toss": "toss"}
        for gsrc, key in GR.items():
            n0 = len(acc)
            for tk, day, senti, eng in c.execute(text(
                "SELECT ticker, substr(created_utc,1,10), sentiment, "
                "COALESCE(likes,0)+COALESCE(comments,0) "
                "FROM gr_post WHERE source=:s AND sentiment IS NOT NULL"), {"s": gsrc}):
                add(tk, day, senti, _w(eng or 0, 1.0), key)
            print(f"[retail-sentiment] {gsrc} ✓（累计 {len(acc)} 格）", flush=True)

    # 展示标的全集（X 计数只取这些；tw_tweet_ticker 含外部工具的数百标的，避免无关 bloat）
    with local.connect() as c:
        symbols = [str(r[0]).upper() for r in c.execute(text("SELECT ticker FROM gr_ticker")) if r[0]]

    # ---- 云端 X（散户=全量推文，不过滤作者）----
    # ⚠ **用稳定的 `tw_tweet_ticker` ⋈ `tw_tweet_sentiment`**，绝不走 `tw_tweet_topic ⋈ tw_tweet`：
    # 外部工具的 `tw_tweet` 是滚动窗口、现已被清空(0 行) → 那条 join 必返 0（KOL 版 net_x 因此已是陈数据）。
    # `tw_tweet_ticker`（全量全历史、含 ticker + created_at）才是权威「这条推在讨论该标的」链接；情绪取 `tw_tweet_sentiment`。
    # 代价：`tw_tweet` 没了 → 拿不到逐帖互动数 → 权重退化为基座 1.0（每条已打分推文算一票，恰合『散户=人头』）。
    cu = _cloud_url()
    if cu:
        cloud = create_engine(cu, connect_args={"prepare_threshold": None}, pool_pre_ping=True)
        nx = 0
        with cloud.connect() as c:
            for tk, day, senti in c.execute(text(
                "SELECT tk.ticker, to_char(tk.created_at AT TIME ZONE 'UTC','YYYY-MM-DD'), s.sentiment "
                "FROM tw_tweet_ticker tk JOIN tw_tweet_sentiment s ON s.tweet_id=tk.tweet_id "
                "WHERE tk.ticker = ANY(:syms) AND tk.created_at IS NOT NULL"), {"syms": symbols}):
                add(tk, day, senti, _w(0.0, 1.0), "x")
                nx += 1
        print(f"[retail-sentiment] X ✓（{nx:,} 条已打分推文映射；累计 {len(acc)} 格）", flush=True)
    else:
        print("[retail-sentiment] ⚠ 未找到云端 DATABASE_URL → 跳过 X（净情绪缺 X 贡献）", flush=True)

    # ---- 落库（整表重算）----
    now = dt.datetime.utcnow().isoformat()
    rows = []
    for (t, d), a in acc.items():
        row = {"ticker": t, "day": d, "net": round(a["net"], 4), "n_posts": a["n"],
               "n_bull": a["bull"], "n_bear": a["bear"], "updated_at": now}
        for k in SRC_KEYS:
            row[f"net_{k}"] = round(a[k], 4)
        rows.append(row)
    cols = "ticker,day,net,n_posts,n_bull,n_bear," + ",".join(f"net_{k}" for k in SRC_KEYS) + ",updated_at"
    ph = ":ticker,:day,:net,:n_posts,:n_bull,:n_bear," + ",".join(f":net_{k}" for k in SRC_KEYS) + ",:updated_at"
    with local.begin() as c:
        c.execute(text("DELETE FROM retail_sentiment_daily"))
        ins = text(f"INSERT INTO retail_sentiment_daily ({cols}) VALUES ({ph})")
        for i in range(0, len(rows), 500):
            if rows[i:i + 500]:
                c.execute(ins, rows[i:i + 500])
    print(f"[retail-sentiment] 写入 {len(rows):,} (ticker,day) 行 → 本地 retail_sentiment_daily。", flush=True)
    return len(rows)


if __name__ == "__main__":
    rollup()
