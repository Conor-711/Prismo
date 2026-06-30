"""KOL 每日净情绪 rollup（标的页折线K线图下方的绿/红情绪面积子面板）。

每 (ticker, day) 一行：跨平台把『提到该标的的帖子』按 **情绪 × ln(1+互动) × 相关性** 加权求和，
得到**无界净情绪值** net（>0 偏多=绿，<0 偏空=红）——量纲随声量×情绪强度放大（像 Kaito 那张图）。

源（混合本地 + 云端）：
  - **本地 dev.db**：Reddit(item_analysis.sentiment_score)、雪球(gr_post.sentiment)、YouTube(yt_analysis.sentiment)，
    互动取各自引擎量，相关性取 kol_relevance(0-100，缺省 0.7)。
  - **云端 Supabase**：X 推文 = tw_tweet_topic ⋈ tw_tweet ⋈ tw_tweet_sentiment（先跑 `tw-sentiment`），
    互动=赞+转+回+引，相关性用关键词命中强度 strong(1.0)/weak(0.6) 代理（X 全量无逐帖 relevance）。

输出 → 本地 dev.db 的 `kol_sentiment_daily`（原生 DDL 自建、不入 models.py；纯本地派生、随构建读，
`make site` 直接用）。整表重算、幂等。运行：**不要加 sqlite 覆盖**——本脚本自己 hardcode 本地、并从 .env
读云端 URL，故 `make kol-sentiment` 同时拿到两边。
"""
from __future__ import annotations

import datetime as dt
import math
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


def _w(engagement: float, relevance: float) -> float:
    return math.log1p(max(0.0, engagement)) * max(0.0, relevance)


def rollup() -> int:
    local = create_engine(LOCAL_URL, connect_args={"check_same_thread": False})
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS kol_sentiment_daily ("
            "ticker TEXT NOT NULL, day TEXT NOT NULL, net REAL DEFAULT 0, "
            "n_posts INTEGER DEFAULT 0, n_bull INTEGER DEFAULT 0, n_bear INTEGER DEFAULT 0, "
            "net_reddit REAL DEFAULT 0, net_x REAL DEFAULT 0, net_xueqiu REAL DEFAULT 0, net_youtube REAL DEFAULT 0, "
            "updated_at TEXT, PRIMARY KEY (ticker, day))"))

    acc: dict[tuple[str, str], dict] = defaultdict(
        lambda: {"net": 0.0, "n": 0, "bull": 0, "bear": 0, "reddit": 0.0, "x": 0.0, "xueqiu": 0.0, "youtube": 0.0})

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

    # ---- 本地三源 ----
    with local.connect() as c:
        n0 = len(acc)
        for tk, day, senti, eng, rel in c.execute(text(
            "SELECT m.ticker, substr(p.created_utc,1,10), a.sentiment_score, "
            "COALESCE(p.score,0)+COALESCE(p.num_comments,0), COALESCE(r.score,70)/100.0 "
            "FROM mentions m JOIN posts p ON p.id=m.item_id AND m.item_type='post' "
            "JOIN item_analysis a ON a.item_id=p.id AND a.item_type='post' "
            "LEFT JOIN kol_relevance r ON r.source='reddit' AND r.item_id=p.id AND r.ticker=m.ticker "
            "WHERE COALESCE(p.source,'scan')='scan'")):
            add(tk, day, senti, _w(eng or 0, rel or 0.7), "reddit")
        print(f"[kol-sentiment] reddit ✓（累计 {len(acc)} 格）", flush=True)

        for tk, day, senti, eng, rel in c.execute(text(
            "SELECT g.ticker, substr(g.created_utc,1,10), g.sentiment, "
            "COALESCE(g.likes,0)+COALESCE(g.comments,0), COALESCE(r.score,70)/100.0 "
            "FROM gr_post g LEFT JOIN kol_relevance r ON r.source='xueqiu' AND r.item_id=g.id AND r.ticker=g.ticker "
            "WHERE g.source='xueqiu' AND g.sentiment IS NOT NULL")):
            add(tk, day, senti, _w(eng or 0, rel or 0.7), "xueqiu")
        print(f"[kol-sentiment] xueqiu ✓（累计 {len(acc)} 格）", flush=True)

        for tk, day, senti, eng, rel in c.execute(text(
            "SELECT v.ticker, substr(v.published_utc,1,10), a.sentiment, "
            "COALESCE(v.like_count,0)+COALESCE(v.comment_count,0), COALESCE(r.score,70)/100.0 "
            "FROM yt_video v JOIN yt_analysis a ON a.video_id=v.id "
            "LEFT JOIN kol_relevance r ON r.source='youtube' AND r.item_id=v.id AND r.ticker=v.ticker")):
            add(tk, day, senti, _w(eng or 0, rel or 0.7), "youtube")
        print(f"[kol-sentiment] youtube ✓（累计 {len(acc)} 格）", flush=True)

    # ---- 云端 X ----
    cu = _cloud_url()
    if cu:
        cloud = create_engine(cu, connect_args={"prepare_threshold": None}, pool_pre_ping=True)
        nx = 0
        with cloud.connect() as c:
            # tw_tweet_topic 的标的列是 symbol（topic 的 symbol），不是 ticker
            for tk, day, senti, eng, strong in c.execute(text(
                "SELECT tt.symbol, to_char(tw.created_at,'YYYY-MM-DD'), s.sentiment, "
                "COALESCE(tw.like_count,0)+COALESCE(tw.retweet_count,0)+COALESCE(tw.reply_count,0)+COALESCE(tw.quote_count,0), tt.strong "
                "FROM tw_tweet_topic tt JOIN tw_tweet tw ON tw.tweet_id=tt.tweet_id "
                "JOIN tw_tweet_sentiment s ON s.tweet_id=tt.tweet_id")):
                add(tk, day, senti, _w(float(eng or 0), 1.0 if strong else 0.6), "x")
                nx += 1
            # 大票补 X：cashtag 在**本地临时匹配**归属（不写云端共享 tw_tweet_topic）。情绪分已由 tw-sentiment 打过。
            from .tweet_sentiment import MEGACAP, megacap_regex
            nm = 0
            for sym, tags in MEGACAP.items():
                for day, senti, eng in c.execute(text(
                    "SELECT to_char(tw.created_at,'YYYY-MM-DD'), s.sentiment, "
                    "COALESCE(tw.like_count,0)+COALESCE(tw.retweet_count,0)+COALESCE(tw.reply_count,0)+COALESCE(tw.quote_count,0) "
                    "FROM tw_tweet tw JOIN tw_tweet_sentiment s ON s.tweet_id=tw.tweet_id "
                    "WHERE tw.text ~* :pat"), {"pat": megacap_regex(tags)}):
                    add(sym, day, senti, _w(float(eng or 0), 1.0), "x")
                    nm += 1
            print(f"[kol-sentiment] X 大票补充 ✓（{nm:,} 条 cashtag 命中，本地归属）", flush=True)
        print(f"[kol-sentiment] X ✓（{nx:,} 条推文映射；累计 {len(acc)} 格）", flush=True)
    else:
        print("[kol-sentiment] ⚠ 未找到云端 DATABASE_URL → 跳过 X（净情绪缺 X 贡献）", flush=True)

    # ---- 落库（整表重算）----
    now = dt.datetime.utcnow().isoformat()
    rows = [{"ticker": t, "day": d, "net": round(a["net"], 4), "n_posts": a["n"],
             "n_bull": a["bull"], "n_bear": a["bear"],
             "net_reddit": round(a["reddit"], 4), "net_x": round(a["x"], 4),
             "net_xueqiu": round(a["xueqiu"], 4), "net_youtube": round(a["youtube"], 4),
             "updated_at": now} for (t, d), a in acc.items()]
    with local.begin() as c:
        c.execute(text("DELETE FROM kol_sentiment_daily"))
        ins = text("INSERT INTO kol_sentiment_daily VALUES "
                   "(:ticker,:day,:net,:n_posts,:n_bull,:n_bear,:net_reddit,:net_x,:net_xueqiu,:net_youtube,:updated_at)")
        for i in range(0, len(rows), 500):
            if rows[i:i + 500]:
                c.execute(ins, rows[i:i + 500])
    print(f"[kol-sentiment] 写入 {len(rows):,} (ticker,day) 行 → 本地 kol_sentiment_daily。", flush=True)
    return len(rows)


if __name__ == "__main__":
    rollup()
