"""爬观点作者头像 → author_avatar 表（供详情页第 1 块「个体观点·KOL」的观点卡显示）。
  - Reddit：PRAW 只读客户端取 redditor.icon_img（真实头像，redditstatic CDN）。
  - YouTube：抓频道页 ytInitialData 里的 avatar 缩略图（yt3.googleusercontent CDN，重写为 s88 小图）。
  - 雪球（阿里云 WAF）/ X（当前仍 mock）暂不爬 → UI 用「来源色首字母」圆形兜底。
按互动量取 top（覆盖观点卡里实际会出现的高互动作者），幂等（已存且有 url 的跳过）。
用法：python3 -m pipeline.ingest.author_avatars      # 写 data/dev.db
注：与 price_daily.py 一样直接写本地快照；生产化应改写云端 + cloud-pull。
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
import re
import sqlite3
import time
import urllib.parse
import urllib.request

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
REDDIT_CAP = int(os.environ.get("AVATAR_REDDIT_CAP", "180"))
YT_CAP = int(os.environ.get("AVATAR_YT_CAP", "180"))


def ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS author_avatar (
             source TEXT NOT NULL, handle TEXT NOT NULL, url TEXT, fetched_at TEXT,
             PRIMARY KEY (source, handle))"""
    )


def have_urls(con: sqlite3.Connection, source: str) -> set[str]:
    return {r[0] for r in con.execute(
        "SELECT handle FROM author_avatar WHERE source=? AND url IS NOT NULL AND url<>''", (source,)
    ).fetchall()}


# Reddit app-only OAuth（不依赖 praw；凭证取自 .env via config.settings）
def reddit_token() -> tuple[str, str]:
    from ..common.config import settings

    cid, csec, ua = settings.reddit_client_id, settings.reddit_client_secret, settings.reddit_user_agent
    if not (cid and csec):
        raise RuntimeError("缺少 REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET")
    auth = base64.b64encode(f"{cid}:{csec}".encode()).decode()
    data = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(
        "https://www.reddit.com/api/v1/access_token",
        data=data,
        headers={"Authorization": "Basic " + auth, "User-Agent": ua},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)["access_token"], ua


def reddit_avatar(name: str, token: str, ua: str) -> str:
    req = urllib.request.Request(
        f"https://oauth.reddit.com/user/{name}/about",
        headers={"Authorization": "Bearer " + token, "User-Agent": ua},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        d = (json.load(r) or {}).get("data", {}) or {}
    url = d.get("snoovatar_img") or d.get("icon_img") or ""
    return url.split("?")[0] if url else ""  # 去 query → CDN 原图


def yt_avatar(channel_id: str) -> str | None:
    req = urllib.request.Request(
        f"https://www.youtube.com/channel/{channel_id}?hl=en", headers={"User-Agent": UA}
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        html = r.read().decode("utf-8", "ignore")
    m = re.search(r'"avatar":\{"thumbnails":\[\{"url":"([^"]+)"', html)
    if not m:
        return None
    url = m.group(1).replace("\\/", "/")
    return re.sub(r"=s\d+", "=s88", url)  # 缩到小图


def main() -> None:
    db = os.path.abspath(DB)
    con = sqlite3.connect(db)
    ensure(con)
    now = dt.datetime.utcnow().isoformat()

    # ---------- Reddit（PRAW）----------
    have = have_urls(con, "reddit")
    authors = [r[0] for r in con.execute(
        """SELECT p.author_id FROM posts p
             JOIN mentions m ON m.item_id = p.id AND m.item_type = 'post'
            WHERE p.author_id NOT IN ('[deleted]', '')
            GROUP BY p.author_id
            ORDER BY max(COALESCE(p.score,0) + COALESCE(p.num_comments,0)) DESC
            LIMIT ?""", (REDDIT_CAP,)).fetchall()]
    todo = [a for a in authors if a not in have]
    print(f"[avatars] reddit: 待爬 {len(todo)}（已存 {len(have)}）")
    try:
        token, rua = reddit_token()
        for i, a in enumerate(todo, 1):
            url = ""
            try:
                url = reddit_avatar(a, token, rua)
            except Exception:  # noqa: BLE001 — 用户封禁/删除/限流 → 留空兜底
                url = ""
            con.execute(
                "INSERT OR REPLACE INTO author_avatar (source,handle,url,fetched_at) VALUES ('reddit',?,?,?)",
                (a, url, now),
            )
            if i % 25 == 0:
                con.commit()
                print(f"  reddit {i}/{len(todo)}")
            time.sleep(1.0)  # app-only OAuth 限流 ~60/min
        con.commit()
    except Exception as e:  # noqa: BLE001 — 缺凭证/限流 → 整体跳过，UI 兜底
        print(f"[avatars] reddit 跳过：{e}")

    # ---------- YouTube（频道页）----------
    have = have_urls(con, "youtube")
    chans = [r[0] for r in con.execute(
        """SELECT channel_id FROM yt_video
            WHERE channel_id IS NOT NULL AND channel_id <> ''
            GROUP BY channel_id
            ORDER BY max(COALESCE(like_count,0) + COALESCE(comment_count,0)) DESC
            LIMIT ?""", (YT_CAP,)).fetchall()]
    todo = [c for c in chans if c not in have]
    print(f"[avatars] youtube: 待爬 {len(todo)}（已存 {len(have)}）")
    for i, cid in enumerate(todo, 1):
        url = ""
        try:
            url = yt_avatar(cid) or ""
        except Exception:  # noqa: BLE001
            url = ""
        con.execute(
            "INSERT OR REPLACE INTO author_avatar (source,handle,url,fetched_at) VALUES ('youtube',?,?,?)",
            (cid, url, now),
        )
        if i % 25 == 0:
            con.commit()
            print(f"  youtube {i}/{len(todo)}")
        time.sleep(0.3)
    con.commit()

    stats = con.execute(
        "SELECT source, count(*), sum(CASE WHEN url<>'' THEN 1 ELSE 0 END) FROM author_avatar GROUP BY source"
    ).fetchall()
    print(f"[avatars] 完成（source, 总数, 有头像）：{stats}")
    con.close()


if __name__ == "__main__":
    main()
