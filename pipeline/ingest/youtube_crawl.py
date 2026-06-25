"""YouTube 观点 · 视频发现：YouTube Data API v3 按标的搜「近 24h、浏览量 > 阈值」的视频 → yt_video。

- **全语种**（不设 relevanceLanguage）→ 把当地分析者（韩 슈퍼개미、日 testa、美 FinTube…）一并纳入。
- 浏览量门槛（默认 1000，`YT_MIN_VIEWS`）：低于此不入库、不分析。
- 缺 `YOUTUBE_API_KEY` 或 `--mock` → 生成多语种样本，便于无 key 验证 schema/看板。
配额：search.list=100 units/次、videos.list≈1 unit；免费 1万/天 → 每标的 1 次搜足够。
"""
from __future__ import annotations

import datetime as dt
import re
import time

import requests
import yaml

from ..common.config import PKG_DATA_DIR, settings
from ..common.db import session_scope
from ..common.models import Base, YtVideo

SEARCH = "https://www.googleapis.com/youtube/v3/search"
VIDEOS = "https://www.googleapis.com/youtube/v3/videos"


def load_universe(only: list[str] | None = None) -> list[dict]:
    with open(PKG_DATA_DIR / "global_targets.yml", encoding="utf-8") as f:
        ts = yaml.safe_load(f)["tickers"]
    if only:
        ts = [t for t in ts if t["ticker"] in set(only)]
    return ts


def _ensure_tables() -> None:
    from ..common.db import engine
    Base.metadata.create_all(engine, tables=[
        YtVideo.__table__,
        Base.metadata.tables["yt_analysis"],
        Base.metadata.tables["yt_ticker_summary"],
    ])


def _dur_seconds(iso: str) -> int:
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso or "")
    if not m:
        return 0
    h, mi, se = (int(x) if x else 0 for x in m.groups())
    return h * 3600 + mi * 60 + se


def _parse_dt(s: str) -> dt.datetime:
    try:
        return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, TypeError):
        return dt.datetime.utcnow()


def _search(sess, q: str, since: dt.datetime, max_results: int = 50, max_pages: int = 2) -> list[str]:
    """按时间分页搜（order=date 走完窗口），翻 max_pages 页拿全；每页≤50（=100 units/页）。"""
    ids: list[str] = []
    token: str | None = None
    for _ in range(max_pages):
        params = {"part": "snippet", "q": q, "type": "video", "order": "date",
                  "publishedAfter": since.strftime("%Y-%m-%dT%H:%M:%SZ"),
                  "maxResults": min(50, max_results), "key": settings.youtube_api_key}
        if token:
            params["pageToken"] = token
        try:
            r = sess.get(SEARCH, params=params, timeout=30)
        except requests.RequestException as e:
            print(f"  [yt] search '{q}' 网络错误：{e}")
            break
        if r.status_code != 200:
            print(f"  [yt] search '{q}' HTTP {r.status_code}: {r.text[:160]}")
            break
        j = r.json()
        ids += [it["id"]["videoId"] for it in j.get("items", []) if it.get("id", {}).get("videoId")]
        token = j.get("nextPageToken")
        if not token:
            break
        time.sleep(0.3)
    return ids


def _hydrate(sess, ids: list[str]) -> list[dict]:
    out: list[dict] = []
    for i in range(0, len(ids), 50):
        chunk = ids[i:i + 50]
        try:
            r = sess.get(VIDEOS, params={"part": "snippet,statistics,contentDetails",
                                         "id": ",".join(chunk), "key": settings.youtube_api_key}, timeout=30)
        except requests.RequestException:
            continue
        if r.status_code != 200:
            continue
        for it in r.json().get("items", []):
            sn, st, cd = it.get("snippet", {}), it.get("statistics", {}), it.get("contentDetails", {})
            out.append(dict(
                id=it["id"], channel=sn.get("channelTitle", ""), channel_id=sn.get("channelId", ""),
                title=sn.get("title", ""), description=(sn.get("description", "") or "")[:2000],
                lang=sn.get("defaultAudioLanguage") or sn.get("defaultLanguage") or "",
                duration_s=_dur_seconds(cd.get("duration", "")),
                view_count=int(st.get("viewCount", 0) or 0), like_count=int(st.get("likeCount", 0) or 0),
                comment_count=int(st.get("commentCount", 0) or 0),
                thumbnail=(sn.get("thumbnails", {}).get("medium", {}) or {}).get("url", ""),
                published=sn.get("publishedAt", ""),
            ))
    return out


def crawl(only: list[str] | None = None, since_hours: int = 24, min_views: int | None = None,
          per_ticker_results: int = 50, max_pages: int = 2, market: str = "us", mock: bool = False) -> dict:
    min_views = settings.yt_min_views if min_views is None else min_views
    _ensure_tables()
    targets = load_universe(only)
    since = dt.datetime.utcnow() - dt.timedelta(hours=since_hours)
    if mock or not settings.has_youtube:
        return _mock(targets, market, min_views)

    sess = requests.Session(); sess.headers["User-Agent"] = "redditalpha-yt/0.1"
    stats = {"videos": 0, "tickers": 0}
    print(f"[yt-crawl] {len(targets)} 标的 · 近 {since_hours}h · 浏览量>{min_views} · 全语种")
    with session_scope() as s:
        for t in targets:
            ids = _search(sess, f'{t["name_en"]} stock', since, max_results=per_ticker_results, max_pages=max_pages)
            vids = [v for v in _hydrate(sess, ids) if v["view_count"] >= min_views]
            kept = 0
            for v in vids:
                created = _parse_dt(v["published"])
                if created < since:
                    continue
                s.merge(YtVideo(
                    id=v["id"], ticker=t["ticker"], market=market, channel=v["channel"][:160],
                    channel_id=v["channel_id"], title=v["title"], description=v["description"],
                    lang=(v["lang"] or "")[:8], duration_s=v["duration_s"], view_count=v["view_count"],
                    like_count=v["like_count"], comment_count=v["comment_count"], thumbnail=v["thumbnail"],
                    url=f"https://www.youtube.com/watch?v={v['id']}", published_utc=created, analyzed=False))
                kept += 1
            if kept:
                stats["tickers"] += 1; stats["videos"] += kept
                print(f"  [yt] {t['ticker']}: {kept} 视频")
    print(f"[yt-crawl] 完成 {stats}")
    return stats


def _mock(targets: list[dict], market: str, min_views: int) -> dict:
    """无 key 时的多语种样本，供验证 schema + 看板渲染。"""
    import random
    _ensure_tables()
    chans = [("Bloomberg Markets", "en"), ("Meet Kevin", "en"), ("슈퍼개미 김정환", "ko"),
             ("염블리 염승환 주식", "ko"), ("テスタ 株チャンネル", "ja"), ("唐书房", "zh"), ("PTT 股海老手", "zh")]
    n = 0
    with session_scope() as s:
        for t in targets[:8]:
            for k in range(3):
                ch, lang = random.choice(chans)
                vid = f"mock_{t['ticker']}_{k}"[:20]
                s.merge(YtVideo(
                    id=vid, ticker=t["ticker"], market=market, channel=ch, channel_id="UCmock000",
                    title=f"{t['name_en']} 심층분석: 지금 매수 타이밍? (part {k + 1})",
                    description="mock video for schema/UI verification", lang=lang,
                    duration_s=random.choice([380, 540, 720, 1100]), view_count=random.randint(1500, 90000),
                    like_count=random.randint(50, 4000), comment_count=random.randint(10, 800),
                    thumbnail="", url=f"https://www.youtube.com/watch?v={vid}",
                    published_utc=dt.datetime.utcnow() - dt.timedelta(hours=random.randint(1, 23)),
                    analyzed=False))
                n += 1
    print(f"[yt-crawl] MOCK 写入 {n} 视频（{min(8, len(targets))} 标的，多语种）")
    return {"videos": n, "tickers": min(8, len(targets)), "mock": True}


if __name__ == "__main__":
    crawl(mock=True)
