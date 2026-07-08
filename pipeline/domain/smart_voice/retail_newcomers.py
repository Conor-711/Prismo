"""整体散户 每日『新增散户』rollup（标的页『整体数据』面板的第三块条状子面板）。

定义：在各平台中**每天新参与讨论**该标的的散户数 —— 某用户在该(平台,标的)上**首次出现**
(首次发帖 / 首条评论 / 讨论室首次发言)当天计 1。基于**已爬数据**为基线（"数据集内首次"）：
用户在我们数据里对该标的的最早一天 = 其"新增"日。多数平台(Reddit/雪球/Naver/YahooJP/PTT)有
2–4 周历史早于"近 2 周"展示窗、基线够用；Toss 历史短(仅 06-14 起)、早期会偏高(展示侧标注)。
**不含 X**（云端 tw_tweet_ticker 无作者列、无法定位"新增者"）、**不含 YouTube**（创作者非散户）。

与 retail_volume.py 同范式、同输出形状(每 (ticker,day) 一行纯计数)；区别：计的是**首次出现的去重作者数**
而非帖量。源（纯本地 dev.db）：
  - Reddit：发帖(posts⋈mentions 该标的) + 评论(comments⋈其父帖的 mentions) → 按 author_id 取该标的最早日。
  - 五论坛：gr_post 按 source(xueqiu/naver/yahoo_jp/ptt/toss) → 按 author 取该标的最早日。
输出 → 本地 dev.db 的 `retail_newcomers_daily`（原生 DDL 自建、不入 models.py）。整表重算、幂等。
运行：`make retail-newcomers`（纯本地，无需云端/凭证）。
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict

from sqlalchemy import create_engine, text

LOCAL_URL = "sqlite:///./data/dev.db"

# 平台键（不含 x / youtube）。顺序 = 落库列顺序。
NEW_KEYS = ["reddit", "xueqiu", "naver", "yahoojp", "ptt", "toss"]
# gr_post.source 值 → n_ 列键
GR = {"xueqiu": "xueqiu", "naver": "naver", "yahoo_jp": "yahoojp", "ptt": "ptt", "toss": "toss"}


def rollup() -> int:
    local = create_engine(LOCAL_URL, connect_args={"check_same_thread": False})
    n_cols = ", ".join(f"n_{k} INTEGER DEFAULT 0" for k in NEW_KEYS)
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS retail_newcomers_daily ("
            "ticker TEXT NOT NULL, day TEXT NOT NULL, n_total INTEGER DEFAULT 0, "
            f"{n_cols}, updated_at TEXT, PRIMARY KEY (ticker, day))"))

    # acc[(TICKER, first_day)][platform_key] = 当天该平台新增(首次出现)的去重作者数
    acc: dict[tuple[str, str], dict] = defaultdict(lambda: {k: 0 for k in NEW_KEYS})

    def first_days(rows) -> dict[tuple[str, str], str]:
        """rows = iterable of (ticker, author, day) → {(TICKER, author): 最早 day(YYYY-MM-DD)}。"""
        first: dict[tuple[str, str], str] = {}
        for tk, au, day in rows:
            if not tk or not au or not day:
                continue
            k = (str(tk).upper(), str(au))
            d = str(day)[:10]
            if k not in first or d < first[k]:
                first[k] = d
        return first

    def tally(first: dict[tuple[str, str], str], key: str) -> None:
        for (tk, _au), day in first.items():
            acc[(tk, day)][key] += 1

    with local.connect() as c:
        # ---- Reddit：发帖 + 评论(归到其父帖的标的)，按 author 取该标的最早一天 ----
        reddit_rows: list[tuple] = []
        for tk, au, day in c.execute(text(
            "SELECT m.ticker, p.author_id, substr(p.created_utc,1,10) "
            "FROM mentions m JOIN posts p ON p.id=m.item_id AND m.item_type='post' "
            "WHERE COALESCE(p.source,'scan')='scan' "
            "AND p.author_id IS NOT NULL AND p.author_id NOT IN ('[deleted]','')")):
            reddit_rows.append((tk, au, day))
        for tk, au, day in c.execute(text(
            "SELECT m.ticker, cm.author_id, substr(cm.created_utc,1,10) "
            "FROM comments cm JOIN posts p ON p.id=cm.post_id "
            "JOIN mentions m ON m.item_id=p.id AND m.item_type='post' "
            "WHERE COALESCE(p.source,'scan')='scan' "
            "AND cm.author_id IS NOT NULL AND cm.author_id NOT IN ('[deleted]','')")):
            reddit_rows.append((tk, au, day))
        tally(first_days(reddit_rows), "reddit")
        print(f"[retail-newcomers] reddit ✓（累计 {len(acc)} 格）", flush=True)

        # ---- 五论坛：gr_post 按 source，按 author 取该标的最早一天 ----
        for gsrc, key in GR.items():
            tally(first_days(c.execute(text(
                "SELECT ticker, author, substr(created_utc,1,10) "
                "FROM gr_post WHERE source=:s AND author<>''"), {"s": gsrc})), key)
            print(f"[retail-newcomers] {gsrc} ✓（累计 {len(acc)} 格）", flush=True)

    # ---- 落库（整表重算）----
    now = dt.datetime.utcnow().isoformat()
    out: list[dict] = []
    for (t, d), a in acc.items():
        total = sum(a[k] for k in NEW_KEYS)
        if total <= 0:
            continue
        row = {"ticker": t, "day": d, "n_total": total, "updated_at": now}
        for k in NEW_KEYS:
            row[f"n_{k}"] = a[k]
        out.append(row)
    cols = "ticker,day,n_total," + ",".join(f"n_{k}" for k in NEW_KEYS) + ",updated_at"
    ph = ":ticker,:day,:n_total," + ",".join(f":n_{k}" for k in NEW_KEYS) + ",:updated_at"
    with local.begin() as c:
        c.execute(text("DELETE FROM retail_newcomers_daily"))
        ins = text(f"INSERT INTO retail_newcomers_daily ({cols}) VALUES ({ph})")
        for i in range(0, len(out), 500):
            if out[i:i + 500]:
                c.execute(ins, out[i:i + 500])
    print(f"[retail-newcomers] 写入 {len(out):,} (ticker,day) 行 → 本地 retail_newcomers_daily。", flush=True)
    return len(out)


if __name__ == "__main__":
    rollup()
