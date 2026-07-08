"""KOL 每日『新增 KOL』rollup（标的页『整体数据』面板 KOL 视图的第三块条状子面板）。

定义：在**有显著身份/粉丝数象征**的平台上，每天**首次参与讨论**该标的的 KOL 数 —— 某作者在该(平台,标的)上
**首次出现**当天计 1。平台 = **X（推特）/ YouTube / 雪球** 三家（有身份/粉丝象征；不含 Reddit 等匿名/无粉丝象征源）。
"新"= **数据集内首次**（用户在我们数据里对该标的的最早一天 = 其"新增"日）。

与 retail_newcomers.py 同范式、同输出形状（每 (ticker,day) 一行的首次出现去重作者计数）；区别在平台口径与 X 数据源：
**X 用本地 `x_opinion`（含 handle/作者）**，而非散户版的云端 `tw_tweet_ticker`（无作者列）。源（纯本地 dev.db）：
  - X：`x_opinion` 按 handle → 该标的最早一天。
  - YouTube：`yt_video` 按 channel_id（频道=作者）→ 该标的最早一天。
  - 雪球：`gr_post` source=xueqiu 按 author → 该标的最早一天。
输出 → 本地 dev.db 的 `kol_newcomers_daily`（原生 DDL 自建、不入 models.py）。整表重算、幂等。
运行：`make kol-newcomers`（纯本地，无需云端/凭证）。
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict

from sqlalchemy import create_engine, text

LOCAL_URL = "sqlite:///./data/dev.db"

# KOL 平台键（有身份/粉丝象征；不含 Reddit/本土论坛）。顺序 = 落库列顺序。
NEW_KEYS = ["x", "youtube", "xueqiu"]


def rollup() -> int:
    local = create_engine(LOCAL_URL, connect_args={"check_same_thread": False})
    n_cols = ", ".join(f"n_{k} INTEGER DEFAULT 0" for k in NEW_KEYS)
    with local.begin() as c:
        c.execute(text(
            "CREATE TABLE IF NOT EXISTS kol_newcomers_daily ("
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
        # X：x_opinion(本地、含作者 handle) 按 handle 取该标的最早一天
        tally(first_days(c.execute(text(
            "SELECT ticker, handle, substr(created,1,10) FROM x_opinion WHERE handle<>''"))), "x")
        print(f"[kol-newcomers] x ✓（累计 {len(acc)} 格）", flush=True)

        # YouTube：yt_video 按 channel_id(频道=作者) 取该标的最早一天
        tally(first_days(c.execute(text(
            "SELECT ticker, channel_id, substr(published_utc,1,10) FROM yt_video WHERE channel_id<>''"))), "youtube")
        print(f"[kol-newcomers] youtube ✓（累计 {len(acc)} 格）", flush=True)

        # 雪球：gr_post source=xueqiu 按 author 取该标的最早一天
        tally(first_days(c.execute(text(
            "SELECT ticker, author, substr(created_utc,1,10) FROM gr_post WHERE source='xueqiu' AND author<>''"))), "xueqiu")
        print(f"[kol-newcomers] xueqiu ✓（累计 {len(acc)} 格）", flush=True)

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
        c.execute(text("DELETE FROM kol_newcomers_daily"))
        ins = text(f"INSERT INTO kol_newcomers_daily ({cols}) VALUES ({ph})")
        for i in range(0, len(out), 500):
            if out[i:i + 500]:
                c.execute(ins, out[i:i + 500])
    print(f"[kol-newcomers] 写入 {len(out):,} (ticker,day) 行 → 本地 kol_newcomers_daily。", flush=True)
    return len(out)


if __name__ == "__main__":
    rollup()
