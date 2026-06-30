"""爬 YouTube 频道（作者）基础信息 → 本地 dev.db 的 yt_channel 表。
   供标的页「YouTube 正文」（OpinionExplorer 阅读面板）作者头像旁展示：粉丝数 / 视频数 / 个人简介。

   数据源：YouTube Data API v3 `channels.list?part=snippet,statistics`（需 `.env` 的 YOUTUBE_API_KEY；
   一次 50 个 channel_id、1 配额单位/次，~540 频道≈11 次）。读本地 yt_video 的 channel_id 全集，整表刷新
   （频道统计是动态的）。与 author_avatars.py 一样直接写本地快照；生产化应改写云端 + cloud-pull。

   用法：pipeline/.venv/bin/python -m pipeline.ingest.youtube_channels
   注：venv python（含 requests、.env→YOUTUBE_API_KEY）。
"""
from __future__ import annotations

import datetime as dt
import os
import sqlite3

import requests

from ..common.config import settings

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))
CHANNELS = "https://www.googleapis.com/youtube/v3/channels"


def ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_channel (
             channel_id TEXT PRIMARY KEY, title TEXT, handle TEXT,
             subscriber_count INTEGER, video_count INTEGER, view_count INTEGER,
             hidden_subs INTEGER DEFAULT 0, description TEXT, fetched_at TEXT)"""
    )


def main() -> None:
    if not settings.has_youtube:
        print("[yt-channels] ⚠ 缺 YOUTUBE_API_KEY（.env）→ 跳过")
        return
    db = os.path.abspath(DB)
    con = sqlite3.connect(db)
    ensure(con)
    now = dt.datetime.utcnow().isoformat()

    chans = [r[0] for r in con.execute(
        """SELECT channel_id FROM yt_video
            WHERE channel_id IS NOT NULL AND channel_id <> ''
            GROUP BY channel_id
            ORDER BY max(COALESCE(view_count,0)) DESC""").fetchall()]
    print(f"[yt-channels] 频道数={len(chans)}")

    sess = requests.Session()
    sess.headers["User-Agent"] = "redditalpha-yt/0.1"
    got = 0
    for i in range(0, len(chans), 50):
        chunk = chans[i:i + 50]
        try:
            r = sess.get(CHANNELS, params={"part": "snippet,statistics",
                                           "id": ",".join(chunk), "key": settings.youtube_api_key,
                                           "maxResults": 50}, timeout=30)
        except requests.RequestException as e:
            print(f"  [yt-channels] 批 {i//50} 请求失败：{e}")
            continue
        if r.status_code != 200:
            print(f"  [yt-channels] 批 {i//50} HTTP {r.status_code}：{r.text[:160]}")
            continue
        for it in r.json().get("items", []):
            sn, st = it.get("snippet", {}) or {}, it.get("statistics", {}) or {}
            hidden = 1 if st.get("hiddenSubscriberCount") else 0
            con.execute(
                "INSERT OR REPLACE INTO yt_channel "
                "(channel_id,title,handle,subscriber_count,video_count,view_count,hidden_subs,description,fetched_at) "
                "VALUES (?,?,?,?,?,?,?,?,?)",
                (it.get("id", ""), sn.get("title", ""), sn.get("customUrl", ""),
                 -1 if hidden else int(st.get("subscriberCount", 0) or 0),
                 int(st.get("videoCount", 0) or 0), int(st.get("viewCount", 0) or 0),
                 hidden, (sn.get("description", "") or "")[:600], now),
            )
            got += 1
        con.commit()
        print(f"  [yt-channels] {min(i+50, len(chans))}/{len(chans)}（累计 {got}）")

    with_subs = con.execute("SELECT count(*) FROM yt_channel WHERE subscriber_count > 0").fetchone()[0]
    print(f"[yt-channels] 完成：{got} 频道 → yt_channel（{with_subs} 有公开粉丝数）")
    con.close()


if __name__ == "__main__":
    main()
