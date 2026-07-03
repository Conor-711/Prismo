"""Discover finance/investing YouTube creators beyond the current ticker crawl.

The existing yt_video / yt_channel tables are ticker-centric snapshots. This
module builds a separate platform-level creator index by:
1. seeding from local yt_channel / yt_video,
2. searching YouTube with finance queries across languages,
3. hydrating channel statistics,
4. marking channels with > N subscribers and finance relevance.

Usage:
  pipeline/.venv/bin/python -m pipeline.ingest.youtube_platform_discovery --target 1000
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Iterable

import requests

from ..common.config import settings

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))
SEARCH = "https://www.googleapis.com/youtube/v3/search"
CHANNELS = "https://www.googleapis.com/youtube/v3/channels"


@dataclass(frozen=True)
class QuerySpec:
    q: str
    lang: str = ""
    region: str = ""
    kind: str = "channel"


FINANCE_TERMS = {
    "stocks": [
        "stock", "stocks", "stock market", "shares", "equity", "equities",
        "nasdaq", "nyse", "wall street", "earnings", "valuation", "dividend",
        "portfolio", "investing", "investment", "investor", "wealth",
        "finance", "financial", "market", "markets", "capital", "alpha",
    ],
    "trading": [
        "trading", "trader", "day trading", "swing trading", "technical analysis",
        "chart analysis", "price action", "forex", "futures",
    ],
    "options": ["options", "option trading", "covered call", "leaps", "put option", "call option"],
    "etf": ["etf", "etfs", "index fund", "s&p 500", "spy", "qqq", "vti", "voo"],
    "crypto": ["bitcoin", "crypto", "cryptocurrency", "ethereum", "btc", "mstr"],
    "zh": ["股票", "美股", "股市", "投资", "投資", "财经", "財經", "金融", "交易", "期权", "期權", "基金", "证券", "證券", "ETF"],
    "ko": ["주식", "미국주식", "해외주식", "투자", "증권", "경제", "금융", "시장", "옵션", "ETF"],
    "ja": ["株", "米国株", "株式投資", "投資", "金融", "市場", "証券", "ETF"],
    "de": ["aktie", "aktien", "börse", "boerse", "finanz", "investieren", "trading", "etf"],
    "es": ["bolsa", "acciones", "inversión", "inversion", "finanzas", "mercado", "trading", "etf"],
    "fr": ["bourse", "actions", "investissement", "finance", "marché", "trading", "etf"],
    "hi": ["शेयर", "स्टॉक", "निवेश", "बाजार", "ट्रेडिंग"],
}

NOISE_TERMS = [
    "gaming", "gameplay", "music", "official music", "lyrics", "movie", "anime",
    "sports highlights", "comedy", "asmr", "minecraft", "roblox", "fitness",
    "makeup", "recipe", "cooking", "vlog", "travel vlog",
]


BASE_QUERIES: list[QuerySpec] = [
    # English broad finance.
    QuerySpec("stock market investing", "en", "US"),
    QuerySpec("stocks investing", "en", "US"),
    QuerySpec("stock analysis", "en", "US"),
    QuerySpec("stock market analysis", "en", "US"),
    QuerySpec("US stocks investing", "en", "US"),
    QuerySpec("value investing stocks", "en", "US"),
    QuerySpec("growth stocks investing", "en", "US"),
    QuerySpec("dividend investing stocks", "en", "US"),
    QuerySpec("financial education investing", "en", "US"),
    QuerySpec("personal finance investing stocks", "en", "US"),
    QuerySpec("Wall Street market news", "en", "US"),
    QuerySpec("stock trading education", "en", "US"),
    QuerySpec("technical analysis stocks", "en", "US"),
    QuerySpec("day trading stocks", "en", "US"),
    QuerySpec("swing trading stocks", "en", "US"),
    QuerySpec("options trading stocks", "en", "US"),
    QuerySpec("stock options trading", "en", "US"),
    QuerySpec("ETF investing", "en", "US"),
    QuerySpec("index fund investing", "en", "US"),
    QuerySpec("SPY QQQ ETF investing", "en", "US"),
    QuerySpec("market macro investing", "en", "US"),
    QuerySpec("earnings stock analysis", "en", "US"),
    QuerySpec("portfolio management investing", "en", "US"),
    QuerySpec("retirement investing stocks", "en", "US"),
    QuerySpec("small cap stocks investing", "en", "US"),
    QuerySpec("AI stocks investing", "en", "US"),
    QuerySpec("semiconductor stocks investing", "en", "US"),
    QuerySpec("Tesla stock analysis", "en", "US"),
    QuerySpec("Nvidia stock analysis", "en", "US"),
    QuerySpec("Apple stock analysis", "en", "US"),
    QuerySpec("crypto stocks investing", "en", "US"),
    # Major English-language finance regions.
    QuerySpec("stock market investing", "en", "GB"),
    QuerySpec("stocks investing", "en", "CA"),
    QuerySpec("stock market investing", "en", "AU"),
    QuerySpec("stock market investing", "en", "IN"),
    QuerySpec("US stock market India", "en", "IN"),
    # Chinese.
    QuerySpec("美股 投资", "zh-Hans", "US"),
    QuerySpec("美股 分析", "zh-Hans", "US"),
    QuerySpec("股票 投资", "zh-Hans", "US"),
    QuerySpec("期权 交易", "zh-Hans", "US"),
    QuerySpec("ETF 投资", "zh-Hans", "US"),
    QuerySpec("財經 美股", "zh-Hant", "TW"),
    QuerySpec("股市 投資", "zh-Hant", "TW"),
    QuerySpec("港股 美股 投資", "zh-Hant", "HK"),
    # Korean.
    QuerySpec("미국주식 투자", "ko", "KR"),
    QuerySpec("주식 투자", "ko", "KR"),
    QuerySpec("해외주식 투자", "ko", "KR"),
    QuerySpec("주식 분석", "ko", "KR"),
    QuerySpec("ETF 투자", "ko", "KR"),
    QuerySpec("옵션 거래 주식", "ko", "KR"),
    # Japanese.
    QuerySpec("米国株 投資", "ja", "JP"),
    QuerySpec("株式投資", "ja", "JP"),
    QuerySpec("株 分析", "ja", "JP"),
    QuerySpec("ETF 投資", "ja", "JP"),
    # German / Spanish / French.
    QuerySpec("Aktien investieren", "de", "DE"),
    QuerySpec("Börse Aktien Analyse", "de", "DE"),
    QuerySpec("ETF investieren", "de", "DE"),
    QuerySpec("Bolsa acciones inversión", "es", "ES"),
    QuerySpec("acciones trading bolsa", "es", "ES"),
    QuerySpec("ETF inversión bolsa", "es", "ES"),
    QuerySpec("bourse actions investissement", "fr", "FR"),
    QuerySpec("actions trading finance", "fr", "FR"),
    # Other large finance YouTube markets.
    QuerySpec("stock market investing", "hi", "IN"),
    QuerySpec("share market investing", "hi", "IN"),
    QuerySpec("शेयर मार्केट निवेश", "hi", "IN"),
    QuerySpec("bolsa de valores investimentos", "pt", "BR"),
    QuerySpec("ações investimentos bolsa", "pt", "BR"),
]

VIDEO_EXPANSION_QUERIES: list[QuerySpec] = [
    QuerySpec("AAPL stock analysis", "en", "US", "video"),
    QuerySpec("MSFT stock analysis", "en", "US", "video"),
    QuerySpec("NVDA stock analysis", "en", "US", "video"),
    QuerySpec("TSLA stock analysis", "en", "US", "video"),
    QuerySpec("AMZN stock analysis", "en", "US", "video"),
    QuerySpec("GOOGL stock analysis", "en", "US", "video"),
    QuerySpec("META stock analysis", "en", "US", "video"),
    QuerySpec("NFLX stock analysis", "en", "US", "video"),
    QuerySpec("SPY ETF analysis", "en", "US", "video"),
    QuerySpec("QQQ ETF analysis", "en", "US", "video"),
    QuerySpec("options trading SPY", "en", "US", "video"),
    QuerySpec("美股 分析", "zh-Hans", "US", "video"),
    QuerySpec("米国株 投資", "ja", "JP", "video"),
    QuerySpec("미국주식 분석", "ko", "KR", "video"),
]


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _norm_text(*parts: object) -> str:
    return " ".join(str(p or "") for p in parts).lower()


def _finance_score(title: str, handle: str, desc: str, discovered_queries: str) -> tuple[int, list[str]]:
    text = _norm_text(title, handle, desc)
    queries = _norm_text(discovered_queries)
    tags: list[str] = []
    score = 0
    for tag, terms in FINANCE_TERMS.items():
        hits = [t for t in terms if t.lower() in text]
        if hits:
            tags.append(tag)
            score += min(4, len(hits)) * 2
    if not tags:
        for tag, terms in FINANCE_TERMS.items():
            if any(t.lower() in queries for t in terms):
                tags.append(f"query:{tag}")
                score += 1
                break
    noise = sum(1 for t in NOISE_TERMS if t in text)
    score -= noise * 2
    return max(score, 0), sorted(set(tags))


def _infer_language(default_language: str, country: str, title: str, desc: str, discovered_queries: str) -> str:
    if default_language:
        return default_language.split("-")[0].lower()
    text = _norm_text(title, desc, discovered_queries)
    if re.search(r"[\u4e00-\u9fff]", text):
        return "zh"
    if re.search(r"[\uac00-\ud7af]", text):
        return "ko"
    if re.search(r"[\u3040-\u30ff]", text):
        return "ja"
    if re.search(r"[\u0900-\u097f]", text):
        return "hi"
    if re.search(r"[\u0400-\u04ff]", text):
        return "ru"
    if any(t in text for t in ["aktien", "börse", "boerse", "investieren", "anleger"]):
        return "de"
    if any(t in text for t in ["bolsa", "acciones", "inversión", "inversion", "mercado"]):
        return "es"
    if any(t in text for t in ["bourse", "marché", "marche boursier"]):
        return "fr"
    if any(t in text for t in ["ações", "acoes", "investimentos", "bolsa de valores"]):
        return "pt"
    by_country = {
        "US": "en", "GB": "en", "CA": "en", "AU": "en", "IN": "en",
        "DE": "de", "AT": "de", "ES": "es", "MX": "es", "AR": "es",
        "FR": "fr", "BR": "pt", "PT": "pt", "KR": "ko", "JP": "ja",
        "TW": "zh", "HK": "zh", "CN": "zh",
    }
    if (country or "").upper() in by_country:
        return by_country[(country or "").upper()]
    english_terms = FINANCE_TERMS["stocks"] + FINANCE_TERMS["trading"] + FINANCE_TERMS["options"] + FINANCE_TERMS["etf"]
    if any(t in text for t in english_terms):
        return "en"
    letters = re.findall(r"[a-z]", text)
    non_ascii = re.findall(r"[^\x00-\x7f]", text)
    if len(letters) >= 12 and len(non_ascii) <= max(8, len(letters) // 8):
        return "en"
    return "unknown"


def ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_platform_channel (
             channel_id TEXT PRIMARY KEY,
             title TEXT,
             handle TEXT,
             description TEXT,
             country TEXT,
             default_language TEXT,
             inferred_language TEXT,
             published_at TEXT,
             subscriber_count INTEGER,
             video_count INTEGER,
             view_count INTEGER,
             hidden_subs INTEGER DEFAULT 0,
             thumbnail TEXT,
             topic_categories TEXT,
             finance_score INTEGER DEFAULT 0,
             finance_tags TEXT,
             qualifies INTEGER DEFAULT 0,
             discovered_queries TEXT,
             discovered_kinds TEXT,
             first_seen_at TEXT,
             last_seen_at TEXT,
             fetched_at TEXT
        )"""
    )
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_platform_discovery_query (
             query_key TEXT PRIMARY KEY,
             query TEXT,
             kind TEXT,
             relevance_language TEXT,
             region_code TEXT,
             searched_at TEXT,
             result_count INTEGER DEFAULT 0,
             channel_count INTEGER DEFAULT 0,
             status TEXT,
             error TEXT
        )"""
    )
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_platform_channel_query (
             channel_id TEXT,
             query_key TEXT,
             rank INTEGER,
             kind TEXT,
             found_at TEXT,
             PRIMARY KEY (channel_id, query_key)
        )"""
    )
    con.execute("CREATE INDEX IF NOT EXISTS ix_yt_platform_channel_qualifies ON yt_platform_channel(qualifies)")
    con.execute("CREATE INDEX IF NOT EXISTS ix_yt_platform_channel_subs ON yt_platform_channel(subscriber_count)")


def query_key(spec: QuerySpec) -> str:
    return f"{spec.kind}|{spec.lang}|{spec.region}|{spec.q}".lower()


def seed_from_local(con: sqlite3.Connection) -> int:
    now = _utc_now()
    rows = con.execute(
        """SELECT c.channel_id, c.title, c.handle, c.description, c.subscriber_count,
                  c.video_count, c.view_count, c.hidden_subs, v.queries
             FROM yt_channel c
             LEFT JOIN (
               SELECT channel_id, GROUP_CONCAT(DISTINCT ticker || ' stock') AS queries
                 FROM yt_video WHERE channel_id <> '' GROUP BY channel_id
             ) v ON v.channel_id = c.channel_id
            WHERE c.channel_id <> ''"""
    ).fetchall()
    n = 0
    for r in rows:
        channel_id, title, handle, desc, subs, vids, views, hidden, queries = r
        discovered = queries or "local yt_video seed"
        score, tags = _finance_score(title or "", handle or "", desc or "", discovered)
        lang = _infer_language("", "", title or "", desc or "", discovered)
        qualifies = 1 if (subs or 0) > 1000 and score >= 2 else 0
        con.execute(
            """INSERT INTO yt_platform_channel
               (channel_id,title,handle,description,subscriber_count,video_count,view_count,hidden_subs,
                inferred_language,finance_score,finance_tags,qualifies,discovered_queries,discovered_kinds,
                first_seen_at,last_seen_at,fetched_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(channel_id) DO UPDATE SET
                 title=COALESCE(excluded.title, yt_platform_channel.title),
                 handle=COALESCE(excluded.handle, yt_platform_channel.handle),
                 description=COALESCE(excluded.description, yt_platform_channel.description),
                 subscriber_count=excluded.subscriber_count,
                 video_count=excluded.video_count,
                 view_count=excluded.view_count,
                 hidden_subs=excluded.hidden_subs,
                 inferred_language=excluded.inferred_language,
                 finance_score=excluded.finance_score,
                 finance_tags=excluded.finance_tags,
                 qualifies=excluded.qualifies,
                 discovered_queries=COALESCE(yt_platform_channel.discovered_queries,'') || '; ' || excluded.discovered_queries,
                 discovered_kinds=COALESCE(yt_platform_channel.discovered_kinds,'') || '; local',
                 last_seen_at=excluded.last_seen_at,
                 fetched_at=excluded.fetched_at""",
            (
                channel_id, title or "", handle or "", desc or "", subs or 0, vids or 0, views or 0, hidden or 0,
                lang, score, json.dumps(tags, ensure_ascii=False), qualifies, discovered, "local",
                now, now, now,
            ),
        )
        n += 1
    con.commit()
    return n


def _search(sess: requests.Session, spec: QuerySpec, max_results: int = 50) -> tuple[list[tuple[str, int]], str | None]:
    params = {
        "part": "snippet",
        "q": spec.q,
        "type": spec.kind,
        "maxResults": max(1, min(50, max_results)),
        "key": settings.youtube_api_key,
    }
    if spec.lang:
        params["relevanceLanguage"] = spec.lang
    if spec.region:
        params["regionCode"] = spec.region
    if spec.kind == "video":
        params["order"] = "relevance"
        params["videoEmbeddable"] = "true"
    r = sess.get(SEARCH, params=params, timeout=30)
    if r.status_code != 200:
        return [], f"HTTP {r.status_code}: {r.text[:240]}"
    ids: list[tuple[str, int]] = []
    for idx, it in enumerate(r.json().get("items", []), 1):
        cid = ""
        if spec.kind == "channel":
            cid = ((it.get("id") or {}).get("channelId") or "").strip()
        elif spec.kind == "video":
            cid = ((it.get("snippet") or {}).get("channelId") or "").strip()
        if cid:
            ids.append((cid, idx))
    return ids, None


def _chunks(items: list[str], size: int) -> Iterable[list[str]]:
    for i in range(0, len(items), size):
        yield items[i:i + size]


def hydrate_channels(con: sqlite3.Connection, sess: requests.Session, ids: list[str], query_map: dict[str, set[str]]) -> int:
    if not ids:
        return 0
    now = _utc_now()
    got = 0
    for chunk in _chunks(sorted(set(ids)), 50):
        r = sess.get(
            CHANNELS,
            params={
                "part": "snippet,statistics,topicDetails",
                "id": ",".join(chunk),
                "key": settings.youtube_api_key,
                "maxResults": 50,
            },
            timeout=30,
        )
        if r.status_code != 200:
            print(f"  [yt-platform] channels.list HTTP {r.status_code}: {r.text[:160]}", flush=True)
            continue
        for it in r.json().get("items", []):
            cid = it.get("id") or ""
            sn = it.get("snippet") or {}
            st = it.get("statistics") or {}
            td = it.get("topicDetails") or {}
            title = sn.get("title") or ""
            handle = sn.get("customUrl") or ""
            desc = (sn.get("description") or "")[:1600]
            country = sn.get("country") or ""
            default_language = sn.get("defaultLanguage") or ""
            published_at = sn.get("publishedAt") or ""
            hidden = 1 if st.get("hiddenSubscriberCount") else 0
            subs = -1 if hidden else int(st.get("subscriberCount") or 0)
            video_count = int(st.get("videoCount") or 0)
            view_count = int(st.get("viewCount") or 0)
            thumbnail = (((sn.get("thumbnails") or {}).get("medium") or {}).get("url") or "")
            topics = td.get("topicCategories") or []
            discovered_queries = "; ".join(sorted(query_map.get(cid, set())))
            prev = con.execute(
                "SELECT discovered_queries, discovered_kinds FROM yt_platform_channel WHERE channel_id = ?",
                (cid,),
            ).fetchone()
            combined_queries = "; ".join(
                x for x in [prev[0] if prev else "", discovered_queries] if x
            )
            combined_kinds = "; ".join(sorted(set((prev[1] if prev and prev[1] else "").split("; ") + ["search"])))
            score, tags = _finance_score(title, handle, desc, combined_queries)
            inferred_language = _infer_language(default_language, country, title, desc, combined_queries)
            qualifies = 1 if subs > 1000 and score >= 2 else 0
            con.execute(
                """INSERT INTO yt_platform_channel
                   (channel_id,title,handle,description,country,default_language,inferred_language,published_at,
                    subscriber_count,video_count,view_count,hidden_subs,thumbnail,topic_categories,
                    finance_score,finance_tags,qualifies,discovered_queries,discovered_kinds,
                    first_seen_at,last_seen_at,fetched_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(channel_id) DO UPDATE SET
                    title=excluded.title,
                    handle=excluded.handle,
                    description=excluded.description,
                    country=excluded.country,
                    default_language=excluded.default_language,
                    inferred_language=excluded.inferred_language,
                    published_at=excluded.published_at,
                    subscriber_count=excluded.subscriber_count,
                    video_count=excluded.video_count,
                    view_count=excluded.view_count,
                    hidden_subs=excluded.hidden_subs,
                    thumbnail=excluded.thumbnail,
                    topic_categories=excluded.topic_categories,
                    finance_score=excluded.finance_score,
                    finance_tags=excluded.finance_tags,
                    qualifies=excluded.qualifies,
                    discovered_queries=excluded.discovered_queries,
                    discovered_kinds=excluded.discovered_kinds,
                    last_seen_at=excluded.last_seen_at,
                    fetched_at=excluded.fetched_at""",
                (
                    cid, title, handle, desc, country, default_language, inferred_language, published_at,
                    subs, video_count, view_count, hidden, thumbnail, json.dumps(topics, ensure_ascii=False),
                    score, json.dumps(tags, ensure_ascii=False), qualifies, combined_queries, combined_kinds,
                    now, now, now,
                ),
            )
            got += 1
        con.commit()
        time.sleep(0.1)
    return got


def qualified_count(con: sqlite3.Connection, min_subscribers: int) -> int:
    return int(con.execute(
        "SELECT COUNT(*) FROM yt_platform_channel WHERE qualifies = 1 AND subscriber_count > ?",
        (min_subscribers,),
    ).fetchone()[0])


def run(target: int, min_subscribers: int, max_searches: int, include_video_expansion: bool, force_queries: bool) -> None:
    if not settings.has_youtube:
        raise SystemExit("[yt-platform] Missing YOUTUBE_API_KEY")
    con = sqlite3.connect(os.path.abspath(DB))
    ensure(con)
    seeded = seed_from_local(con)
    print(f"[yt-platform] seeded local channels={seeded}; qualified={qualified_count(con, min_subscribers)}", flush=True)

    queries = BASE_QUERIES + (VIDEO_EXPANSION_QUERIES if include_video_expansion else [])
    sess = requests.Session()
    sess.headers["User-Agent"] = "prismo-yt-platform-discovery/0.1"

    used_searches = 0
    for spec in queries:
        if used_searches >= max_searches:
            break
        if qualified_count(con, min_subscribers) >= target:
            break
        key = query_key(spec)
        if not force_queries:
            done = con.execute(
                "SELECT status FROM yt_platform_discovery_query WHERE query_key = ? AND status = 'ok'",
                (key,),
            ).fetchone()
            if done:
                continue
        ids_with_rank, err = _search(sess, spec)
        used_searches += 1
        now = _utc_now()
        if err:
            con.execute(
                """INSERT OR REPLACE INTO yt_platform_discovery_query
                   (query_key,query,kind,relevance_language,region_code,searched_at,result_count,channel_count,status,error)
                   VALUES (?,?,?,?,?,?,?,?,?,?)""",
                (key, spec.q, spec.kind, spec.lang, spec.region, now, 0, 0, "error", err),
            )
            con.commit()
            print(f"  [yt-platform] {used_searches}/{max_searches} {spec.kind} '{spec.q}' -> {err}", flush=True)
            if "quota" in err.lower():
                break
            continue
        qmap: dict[str, set[str]] = defaultdict(set)
        for cid, rank in ids_with_rank:
            qmap[cid].add(spec.q)
            con.execute(
                """INSERT OR REPLACE INTO yt_platform_channel_query
                   (channel_id,query_key,rank,kind,found_at) VALUES (?,?,?,?,?)""",
                (cid, key, rank, spec.kind, now),
            )
        hydrated = hydrate_channels(con, sess, [cid for cid, _ in ids_with_rank], qmap)
        con.execute(
            """INSERT OR REPLACE INTO yt_platform_discovery_query
               (query_key,query,kind,relevance_language,region_code,searched_at,result_count,channel_count,status,error)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (key, spec.q, spec.kind, spec.lang, spec.region, now, len(ids_with_rank), hydrated, "ok", ""),
        )
        con.commit()
        print(
            f"  [yt-platform] {used_searches}/{max_searches} {spec.kind} '{spec.q}' "
            f"ids={len(ids_with_rank)} hydrated={hydrated} qualified={qualified_count(con, min_subscribers)}",
            flush=True,
        )
        time.sleep(0.2)

    print(
        f"[yt-platform] done searches={used_searches}; qualified={qualified_count(con, min_subscribers)}; "
        f"total_channels={con.execute('SELECT COUNT(*) FROM yt_platform_channel').fetchone()[0]}",
        flush=True,
    )
    con.close()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=int, default=1000)
    ap.add_argument("--min-subscribers", type=int, default=1000)
    ap.add_argument("--max-searches", type=int, default=90)
    ap.add_argument("--include-video-expansion", action="store_true")
    ap.add_argument("--force-queries", action="store_true")
    args = ap.parse_args()
    run(
        target=args.target,
        min_subscribers=args.min_subscribers,
        max_searches=args.max_searches,
        include_video_expansion=args.include_video_expansion,
        force_queries=args.force_queries,
    )


if __name__ == "__main__":
    main()
