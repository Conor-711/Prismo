"""Cross-community fixed narrative rotation.

Builds ``web/lib/data/narrativeRotation.json`` for the Prismo Narratives page.
This intentionally does not read or write the legacy ``narratives`` tables:
those are Reddit-only clustering artifacts. The new page is fixed-taxonomy,
cross-community, and static-build friendly.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import math
import re
import sqlite3
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..common.config import ROOT

DB = ROOT / "data" / "dev.db"
OUT = ROOT / "web" / "lib" / "data" / "narrativeRotation.json"


SOURCE_LABELS = {
    "reddit": {"zh": "Reddit", "en": "Reddit"},
    "x": {"zh": "X", "en": "X"},
    "youtube": {"zh": "YouTube", "en": "YouTube"},
    "xueqiu": {"zh": "雪球", "en": "Xueqiu"},
    "yahoo_jp": {"zh": "Yahoo 日本", "en": "Yahoo JP"},
    "naver": {"zh": "Naver", "en": "Naver"},
    "ptt": {"zh": "PTT", "en": "PTT"},
    "toss": {"zh": "Toss", "en": "Toss"},
}


CATEGORIES: list[dict[str, Any]] = [
    {
        "id": "ai_cloud",
        "slug": "ai-cloud",
        "title": {"zh": "AI、云与数据中心", "en": "AI, cloud & data centers"},
        "description": {
            "zh": "AI 应用、云平台、企业软件、数据中心服务器与算力基础设施板块。",
            "en": "AI apps, cloud platforms, enterprise software, data-center servers and compute infrastructure.",
        },
        "color": "#57D7BA",
        "tickers": ["PLTR", "ORCL", "MSFT", "DELL", "SMCI", "CRWV", "NBIS", "IBM", "SNOW", "CRM", "NOW", "ADBE"],
        "themes": ["AI", "AI 资本开支", "人工智能", "算力"],
        "keywords": [
            "ai", "artificial intelligence", "llm", "inference", "data center", "datacenter", "compute",
            "cloud", "saas", "enterprise software", "人工智能", "算力", "数据中心", "推理", "大模型",
            "云计算", "企业软件", "ai投資", "データセンター", "クラウド", "인공지능", "데이터센터", "클라우드",
        ],
    },
    {
        "id": "semiconductors",
        "slug": "semiconductors",
        "title": {"zh": "半导体与芯片链", "en": "Semiconductors & chips"},
        "description": {
            "zh": "GPU、存储、晶圆代工、EDA、设备、封装与先进制程板块。",
            "en": "GPUs, memory, foundries, EDA, equipment, packaging and advanced process nodes.",
        },
        "color": "#78A7FF",
        "tickers": ["NVDA", "AMD", "INTC", "TSM", "ASML", "AVGO", "QCOM", "MU", "ARM", "MRVL", "AMAT", "LRCX", "SMH", "SNDK"],
        "themes": ["半导体", "芯片"],
        "keywords": [
            "semiconductor", "chip", "chips", "gpu", "cuda", "foundry", "fab", "wafer", "memory", "hbm", "dram",
            "node", "lithography", "制程", "晶圆", "芯片", "半导体", "存储", "封装", "晶片", "半導体",
            "メモリ", "반도체", "칩", "메모리",
        ],
    },
    {
        "id": "mega_platforms",
        "slug": "mega-platforms",
        "title": {"zh": "大型平台与互联网", "en": "Mega platforms & internet"},
        "description": {
            "zh": "消费互联网、广告、电商、流媒体、应用生态与大型科技平台板块。",
            "en": "Consumer internet, ads, e-commerce, streaming, app ecosystems and mega-cap platforms.",
        },
        "color": "#4CC9F0",
        "tickers": ["AAPL", "GOOGL", "GOOG", "META", "AMZN", "NFLX", "DIS", "SHOP", "BABA", "PDD", "JD", "0700.HK", "RDDT", "UBER", "ABNB"],
        "themes": ["平台互联网", "电商"],
        "keywords": [
            "internet", "platform", "ecommerce", "e-commerce", "advertising", "streaming", "subscriber",
            "app store", "iphone", "android", "social media", "互联网", "平台", "电商", "广告", "流媒体",
            "应用生态", "订阅", "スマホ", "広告", "電子商取引", "플랫폼", "전자상거래", "광고",
        ],
    },
    {
        "id": "ev_autonomy",
        "slug": "ev-autonomy",
        "title": {"zh": "电动车与智能驾驶", "en": "EVs & autonomy"},
        "description": {
            "zh": "电动车整车、Robotaxi、电池、自动驾驶、补能网络与智能座舱板块。",
            "en": "EV makers, robotaxi, batteries, autonomy, charging networks and smart cockpits.",
        },
        "color": "#32C88F",
        "tickers": ["TSLA", "NIO", "RIVN", "LCID", "F", "GM", "XPEV", "LI", "1211.HK", "1810.HK", "300750.SZ", "UBER"],
        "themes": ["电动车", "自动驾驶"],
        "keywords": [
            "ev", "electric vehicle", "robotaxi", "fsd", "autonomous", "battery", "charging", "electric car",
            "电动车", "自动驾驶", "电池", "充电", "机器人出租车", "智能驾驶", "電気自動車", "自動運転",
            "バッテリー", "전기차", "배터리", "로보택시", "자율주행",
        ],
    },
    {
        "id": "energy_power",
        "slug": "energy-power",
        "title": {"zh": "能源、电力与核能", "en": "Energy, power & nuclear"},
        "description": {
            "zh": "油气、光伏、储能、电网、公用事业、核能与电力基础设施板块。",
            "en": "Oil & gas, solar, storage, grid, utilities, nuclear and power infrastructure.",
        },
        "color": "#F7C948",
        "tickers": ["XOM", "CVX", "USO", "ENPH", "FSLR", "OKLO", "CEG", "VST", "NEE", "SMR", "CCJ", "GEV"],
        "themes": ["能源", "核能"],
        "keywords": [
            "energy", "oil", "gas", "solar", "nuclear", "uranium", "power", "grid", "utility", "utilities",
            "storage", "能源", "原油", "天然气", "光伏", "核能", "铀", "电网", "电力", "储能",
            "エネルギー", "原油", "原子力", "電力", "에너지", "원전", "전력",
        ],
    },
    {
        "id": "crypto_fintech",
        "slug": "crypto-fintech",
        "title": {"zh": "加密资产与金融科技", "en": "Crypto assets & fintech"},
        "description": {
            "zh": "比特币、稳定币、交易所、矿企、支付、数字券商与零售交易板块。",
            "en": "Bitcoin, stablecoins, exchanges, miners, payments, brokers and retail trading rails.",
        },
        "color": "#E0A33E",
        "tickers": ["MSTR", "COIN", "SOFI", "HOOD", "PYPL", "SQ", "RIOT", "MARA", "IBIT", "BTC", "ETH"],
        "themes": ["加密", "金融科技"],
        "keywords": [
            "bitcoin", "btc", "crypto", "ethereum", "eth", "stablecoin", "coinbase", "fintech", "broker",
            "payment", "wallet", "比特币", "加密", "以太坊", "稳定币", "金融科技", "券商", "支付",
            "暗号資産", "仮想通貨", "비트코인", "가상자산", "핀테크",
        ],
    },
    {
        "id": "financials",
        "slug": "financials",
        "title": {"zh": "金融、银行与支付", "en": "Financials, banks & payments"},
        "description": {
            "zh": "大型银行、投行、保险、信用卡网络、资产管理与综合金融板块。",
            "en": "Large banks, investment banks, insurers, card networks, asset managers and diversified financials.",
        },
        "color": "#9E8CFF",
        "tickers": ["JPM", "BAC", "GS", "MS", "WFC", "C", "BRK.B", "V", "MA", "AXP", "BLK", "SCHW"],
        "themes": ["金融", "银行"],
        "keywords": [
            "bank", "banks", "financial", "credit card", "payments", "asset management", "insurance",
            "金融", "银行", "投行", "信用卡", "支付网络", "保险", "资产管理", "銀行", "金融株",
            "은행", "금융", "보험",
        ],
    },
    {
        "id": "healthcare_biotech",
        "slug": "healthcare-biotech",
        "title": {"zh": "医药、医疗与生物科技", "en": "Healthcare, pharma & biotech"},
        "description": {
            "zh": "制药、生物科技、医疗服务、器械、减重药与临床管线板块。",
            "en": "Pharma, biotech, healthcare services, devices, obesity drugs and clinical pipelines.",
        },
        "color": "#F26FD4",
        "tickers": ["PFE", "LLY", "MRNA", "NVO", "JNJ", "ABBV", "UNH", "ISRG", "VRTX", "REGN", "MRK", "TMO"],
        "themes": ["医药", "生物科技"],
        "keywords": [
            "pharma", "biotech", "healthcare", "drug", "vaccine", "obesity", "glp-1", "clinical trial",
            "fda", "医药", "医疗", "生物科技", "药物", "疫苗", "减重药", "临床", "バイオ", "医薬",
            "헬스케어", "바이오", "제약",
        ],
    },
    {
        "id": "space_defense",
        "slug": "space-defense",
        "title": {"zh": "航天、国防与工业", "en": "Space, defense & industrials"},
        "description": {
            "zh": "商业航天、卫星、航空、国防军工、工业自动化与先进制造板块。",
            "en": "Commercial space, satellites, aerospace, defense, industrial automation and advanced manufacturing.",
        },
        "color": "#FF5C6C",
        "tickers": ["BA", "RKLB", "ASTS", "SPCE", "ACHR", "RDW", "LMT", "NOC", "RTX", "GD", "GE", "KTOS"],
        "themes": ["航天", "国防"],
        "keywords": [
            "space", "satellite", "rocket", "aerospace", "defense", "drone", "industrial", "manufacturing",
            "航天", "卫星", "火箭", "航空", "国防", "军工", "工业", "制造", "宇宙", "防衛",
            "항공우주", "방산", "위성",
        ],
    },
    {
        "id": "retail_momentum",
        "slug": "retail-momentum",
        "title": {"zh": "散户高波动股", "en": "Retail momentum stocks"},
        "description": {
            "zh": "散户交易活跃、Meme 股、逼空候选与高波动小盘成长板块。",
            "en": "Retail-heavy, meme-stock, squeeze-candidate and high-volatility small-cap growth names.",
        },
        "color": "#B7C0C7",
        "tickers": ["GME", "AMC", "KOSS", "DJT", "BB", "SPCE", "SPCX", "LCID", "RDDT"],
        "themes": ["逼空 / Meme", "Meme"],
        "keywords": [
            "meme", "short squeeze", "squeeze", "gamma", "wsb", "wallstreetbets", "yolo", "hodl",
            "to the moon", "diamond hands", "short interest", "逼空", "空头挤压", "散户抱团", "妖股",
            "韭菜", "月球", "踏み上げ", "ショートスクイーズ", "숏스퀴즈", "개미",
        ],
    },
    {
        "id": "index_etf",
        "slug": "index-etf",
        "title": {"zh": "指数 ETF 与大盘风格", "en": "Index ETFs & market style"},
        "description": {
            "zh": "宽基指数、行业 ETF、杠杆 ETF、避险资产与市场风格轮动板块。",
            "en": "Broad indexes, sector ETFs, leveraged ETFs, hedges and market-style rotation.",
        },
        "color": "#8CCB5E",
        "tickers": ["SPY", "QQQ", "VOO", "VTI", "TQQQ", "TLT", "GLD", "DIA", "IWM", "SPX", "SMH", "USO"],
        "themes": ["ETF", "指数"],
        "keywords": [
            "index", "etf", "nasdaq", "s&p", "sp500", "market", "sector rotation", "指数", "宽基",
            "大盘", "行业轮动", "杠杆etf", "市場", "指数", "섹터", "지수", "etf",
        ],
    },
]


@dataclass
class Event:
    day: str
    source: str
    region: str
    tickers: list[str]
    text: str
    sentiment: float
    engagement: int


def _connect(path: str) -> sqlite3.Connection:
    p = path
    if not p.startswith("file:"):
        p = f"file:{p}?mode=ro"
    con = sqlite3.connect(p, uri=True)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    return con


def _clean_text(*parts: object) -> str:
    s = " ".join(str(p or "") for p in parts)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    return re.sub(r"\s+", " ", s).strip()


def _parse_json(value: object, fallback: Any) -> Any:
    if not isinstance(value, str) or not value:
        return fallback
    try:
        return json.loads(value)
    except Exception:
        return fallback


def _date(value: object) -> str:
    return str(value or "")[:10]


def _sentiment_from_stance(stance: object, fallback: float = 0.0) -> float:
    s = str(stance or "").lower()
    if s == "bull":
        return 0.55
    if s == "bear":
        return -0.55
    return fallback


def _stance(score: float) -> str:
    if score > 0.15:
        return "bull"
    if score < -0.15:
        return "bear"
    return "neutral"


def _days(start: str, end: str) -> list[str]:
    s = dt.date.fromisoformat(start)
    e = dt.date.fromisoformat(end)
    out: list[str] = []
    while s <= e:
        out.append(s.isoformat())
        s += dt.timedelta(days=1)
    return out


def _extract_tickers(items: object, fallback: str | None = None) -> list[str]:
    out: list[str] = []
    if isinstance(items, list):
        for it in items:
            if isinstance(it, dict) and it.get("ticker"):
                out.append(str(it["ticker"]).upper())
            elif isinstance(it, str):
                out.append(it.upper())
    if fallback:
        out.append(fallback.upper())
    seen: set[str] = set()
    return [t for t in out if t and not (t in seen or seen.add(t))]


def _category_for(text: str, tickers: list[str], themes: list[str] | None = None) -> str | None:
    hay = text.lower()
    theme_hay = " ".join(themes or []).lower()
    ticker_set = set(tickers)
    best_id = None
    best_score = 0
    for cat in CATEGORIES:
        score = 0
        for tk in cat["tickers"]:
            if tk in ticker_set:
                score += 3
        for th in cat["themes"]:
            if th.lower() in theme_hay:
                score += 6
        for kw in cat["keywords"]:
            k = kw.lower()
            if k and _keyword_hit(hay, k):
                score += 3 if len(k) < 5 else 4
        if score > best_score:
            best_score = score
            best_id = cat["id"]
    return best_id if best_score >= 3 else None


def _keyword_hit(hay: str, keyword: str) -> bool:
    # Short ASCII tokens like "ai" or "ev" must be standalone; substring matching
    # would misclassify words such as "again", "said", or "available".
    if re.fullmatch(r"[a-z0-9.+/-]+", keyword):
        return re.search(rf"(?<![a-z0-9]){re.escape(keyword)}(?![a-z0-9])", hay) is not None
    return keyword in hay


def _load_reddit(con: sqlite3.Connection) -> list[Event]:
    out: list[Event] = []
    sql = """
      SELECT p.id, p.title, p.selftext, p.score, p.num_comments, p.created_utc,
             ia.sentiment_score, ia.stance, ia.themes, ia.tickers
        FROM posts p
        JOIN item_analysis ia ON ia.item_id = p.id AND ia.item_type = 'post'
       WHERE p.market = 'us' AND p.source = 'scan'
    """
    for r in con.execute(sql):
        tickers = _extract_tickers(_parse_json(r["tickers"], []))
        out.append(Event(
            day=_date(r["created_utc"]),
            source="reddit",
            region="us",
            tickers=tickers,
            text=_clean_text(r["title"], r["selftext"], " ".join(_parse_json(r["themes"], []))),
            sentiment=float(r["sentiment_score"] or 0),
            engagement=int(r["score"] or 0) + int(r["num_comments"] or 0),
        ))
    return out


def _load_gr(con: sqlite3.Connection) -> list[Event]:
    out: list[Event] = []
    sql = """
      SELECT region, source, ticker, title, body, likes, comments, views, sentiment, stance, created_utc
        FROM gr_post
    """
    for r in con.execute(sql):
        source = str(r["source"] or "").strip() or str(r["region"] or "")
        sentiment = r["sentiment"]
        out.append(Event(
            day=_date(r["created_utc"]),
            source=source,
            region=str(r["region"] or ""),
            tickers=_extract_tickers([], str(r["ticker"] or "")),
            text=_clean_text(r["title"], r["body"], r["label"] if "label" in r.keys() else ""),
            sentiment=float(sentiment if sentiment is not None else _sentiment_from_stance(r["stance"])),
            engagement=int(r["likes"] or 0) + int(r["comments"] or 0) + int((r["views"] or 0) // 20),
        ))
    return out


def _load_x(con: sqlite3.Connection) -> list[Event]:
    out: list[Event] = []
    sql = """
      SELECT x.tweet_id, x.ticker, x.text, x.likes, x.retweets, x.replies, x.quotes,
             x.views, x.bookmarks, x.created, kr.stance
        FROM x_opinion x
        LEFT JOIN kol_refined kr
          ON kr.source = 'x' AND kr.item_id = x.tweet_id AND kr.ticker = x.ticker
       WHERE COALESCE(x.text, '') NOT LIKE 'RT @%'
    """
    for r in con.execute(sql):
        out.append(Event(
            day=_date(r["created"]),
            source="x",
            region="us",
            tickers=_extract_tickers([], str(r["ticker"] or "")),
            text=_clean_text(r["text"]),
            sentiment=_sentiment_from_stance(r["stance"]),
            engagement=(
                int(r["likes"] or 0) + int(r["retweets"] or 0) + int(r["replies"] or 0) +
                int(r["quotes"] or 0) + int(r["bookmarks"] or 0) + int((r["views"] or 0) // 100)
            ),
        ))
    return out


def _load_youtube(con: sqlite3.Connection) -> list[Event]:
    out: list[Event] = []
    sql = """
      SELECT v.ticker, v.title, v.description, v.view_count, v.like_count, v.comment_count,
             v.published_utc, a.stance, a.sentiment, a.summary_zh, a.summary_en,
             a.key_points_zh, a.key_points_en
        FROM yt_video v
        JOIN yt_analysis a ON a.video_id = v.id
    """
    for r in con.execute(sql):
        out.append(Event(
            day=_date(r["published_utc"]),
            source="youtube",
            region="global",
            tickers=_extract_tickers([], str(r["ticker"] or "")),
            text=_clean_text(r["title"], r["description"], r["summary_zh"], r["summary_en"], r["key_points_zh"], r["key_points_en"]),
            sentiment=float(r["sentiment"] if r["sentiment"] is not None else _sentiment_from_stance(r["stance"])),
            engagement=int(r["like_count"] or 0) + int(r["comment_count"] or 0) + int((r["view_count"] or 0) // 100),
        ))
    return out


def _safe_load(loader, con: sqlite3.Connection) -> list[Event]:
    try:
        return loader(con)
    except sqlite3.Error as e:
        print(f"[narrative-rotation] skip {loader.__name__}: {e}")
        return []


def _out_path(out_path: str) -> Path:
    p = Path(out_path)
    return p if p.is_absolute() else ROOT / p


def _empty_payload(window_days: int) -> dict[str, Any]:
    today = dt.date.today().isoformat()
    return {
        "version": 1,
        "updated_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "window": {"start": today, "end": today, "days": [today]},
        "sourceLabels": SOURCE_LABELS,
        "categories": CATEGORIES,
        "summary": {"active": 0, "totalVolume": 0, "topNarrative": None, "windowDays": window_days},
        "leaderboard": [],
        "series": {c["id"]: [{"day": today, "volume": 0, "share": 0, "sentiment": 0, "rank": None, "sources": {}}] for c in CATEGORIES},
        "details": {c["id"]: {"topTickers": [], "sources": [], "regions": []} for c in CATEGORIES},
    }


def build(db_path: str = str(DB), out_path: str = str(OUT), window_days: int = 21, recent_days: int = 3) -> dict[str, Any]:
    if not DB.exists() and db_path == str(DB):
        payload = _empty_payload(window_days)
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return payload

    con = _connect(db_path)
    raw_events: list[Event] = []
    for loader in (_load_gr, _load_reddit, _load_x, _load_youtube):
        raw_events.extend(_safe_load(loader, con))
    con.close()

    classified: list[tuple[Event, str]] = []
    for e in raw_events:
        if not e.day or len(e.day) != 10 or not e.text:
            continue
        cat = _category_for(e.text, e.tickers)
        if cat:
            classified.append((e, cat))

    if not classified:
        payload = _empty_payload(window_days)
        path = _out_path(out_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return payload

    max_day = max(e.day for e, _ in classified)
    end = dt.date.fromisoformat(max_day)
    start = end - dt.timedelta(days=max(1, window_days) - 1)
    days = _days(start.isoformat(), end.isoformat())
    day_set = set(days)
    events = [(e, c) for e, c in classified if e.day in day_set]

    cat_day: dict[tuple[str, str], dict[str, Any]] = defaultdict(lambda: {
        "volume": 0, "engagement": 0, "sent_sum": 0.0, "sent_w": 0.0,
        "bull": 0, "bear": 0, "neutral": 0, "sources": Counter(), "regions": Counter(), "tickers": Counter(),
    })
    total_by_day: Counter[str] = Counter()
    cat_total: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "volume": 0, "engagement": 0, "sent_sum": 0.0, "sent_w": 0.0,
        "sources": Counter(), "regions": Counter(), "tickers": Counter(),
    })

    for e, cat in events:
        key = (cat, e.day)
        weight = 1.0 + min(math.log1p(max(0, e.engagement)), 6.0)
        st = _stance(e.sentiment)
        d = cat_day[key]
        d["volume"] += 1
        d["engagement"] += max(0, e.engagement)
        d["sent_sum"] += e.sentiment * weight
        d["sent_w"] += weight
        d[st] += 1
        d["sources"][e.source] += 1
        d["regions"][e.region] += 1
        for t in e.tickers[:4]:
            d["tickers"][t] += 1

        t = cat_total[cat]
        t["volume"] += 1
        t["engagement"] += max(0, e.engagement)
        t["sent_sum"] += e.sentiment * weight
        t["sent_w"] += weight
        t["sources"][e.source] += 1
        t["regions"][e.region] += 1
        for tk in e.tickers[:4]:
            t["tickers"][tk] += 1
        total_by_day[e.day] += 1

    ranks_by_day: dict[str, dict[str, int]] = {}
    for day in days:
        rows = []
        for cat in [c["id"] for c in CATEGORIES]:
            d = cat_day[(cat, day)]
            if d["volume"] > 0:
                rows.append((cat, d["volume"], d["engagement"]))
        rows.sort(key=lambda x: (-x[1], -x[2], x[0]))
        ranks_by_day[day] = {cat: i + 1 for i, (cat, _v, _e) in enumerate(rows)}

    series: dict[str, list[dict[str, Any]]] = {}
    for cat in [c["id"] for c in CATEGORIES]:
        rows = []
        for day in days:
            d = cat_day[(cat, day)]
            sent = d["sent_sum"] / d["sent_w"] if d["sent_w"] else 0.0
            rows.append({
                "day": day,
                "volume": d["volume"],
                "share": round(d["volume"] / max(1, total_by_day[day]), 4),
                "sentiment": round(sent, 3),
                "rank": ranks_by_day[day].get(cat),
                "bull": d["bull"],
                "bear": d["bear"],
                "neutral": d["neutral"],
                "sources": dict(d["sources"]),
            })
        series[cat] = rows

    def period_summary(cat: str, ds: set[str]) -> dict[str, Any]:
        vol = eng = 0
        sent_sum = sent_w = 0.0
        total = sum(total_by_day[d] for d in ds)
        for dday in ds:
            d = cat_day[(cat, dday)]
            vol += d["volume"]
            eng += d["engagement"]
            sent_sum += d["sent_sum"]
            sent_w += d["sent_w"]
        return {
            "volume": vol,
            "engagement": eng,
            "share": vol / max(1, total),
            "sentiment": sent_sum / sent_w if sent_w else 0.0,
        }

    cur_days = set(days[-max(1, recent_days):])
    prev_days = set(days[-max(1, recent_days * 2):-max(1, recent_days)])

    current_rows = []
    previous_rows = []
    for cat in [c["id"] for c in CATEGORIES]:
        cur = period_summary(cat, cur_days)
        prv = period_summary(cat, prev_days)
        if cur["volume"] > 0:
            current_rows.append((cat, cur["volume"], cur["engagement"]))
        if prv["volume"] > 0:
            previous_rows.append((cat, prv["volume"], prv["engagement"]))
    current_rows.sort(key=lambda x: (-x[1], -x[2], x[0]))
    previous_rows.sort(key=lambda x: (-x[1], -x[2], x[0]))
    cur_rank = {cat: i + 1 for i, (cat, _v, _e) in enumerate(current_rows)}
    prev_rank = {cat: i + 1 for i, (cat, _v, _e) in enumerate(previous_rows)}

    cat_meta = {c["id"]: c for c in CATEGORIES}
    leaderboard: list[dict[str, Any]] = []
    details: dict[str, Any] = {}
    for cat in [c["id"] for c in CATEGORIES]:
        cur = period_summary(cat, cur_days)
        prv = period_summary(cat, prev_days)
        rank = cur_rank.get(cat)
        prior_rank = prev_rank.get(cat)
        rank_delta = (prior_rank - rank) if rank and prior_rank else None
        share_delta = cur["share"] - prv["share"]
        sentiment_delta = cur["sentiment"] - prv["sentiment"]
        if cur["volume"] <= 0:
            trend = "quiet"
        elif sentiment_delta <= -0.25:
            trend = "turning_bear"
        elif sentiment_delta >= 0.25:
            trend = "turning_bull"
        elif rank_delta is not None and rank_delta >= 2:
            trend = "rising"
        elif share_delta >= 0.025:
            trend = "gaining_share"
        elif share_delta <= -0.025:
            trend = "cooling"
        else:
            trend = "stable"

        total = cat_total[cat]
        top_tickers = [{"ticker": k, "count": v} for k, v in total["tickers"].most_common(10)]
        sources = [{"source": k, "count": v} for k, v in total["sources"].most_common()]
        regions = [{"region": k, "count": v} for k, v in total["regions"].most_common()]
        row = {
            "id": cat,
            "slug": cat_meta[cat]["slug"],
            "title": cat_meta[cat]["title"],
            "color": cat_meta[cat]["color"],
            "rank": rank,
            "previousRank": prior_rank,
            "rankDelta": rank_delta,
            "volume": cur["volume"],
            "share": round(cur["share"], 4),
            "shareDelta": round(share_delta, 4),
            "sentiment": round(cur["sentiment"], 3),
            "sentimentDelta": round(sentiment_delta, 3),
            "trend": trend,
            "topTickers": top_tickers[:6],
        }
        leaderboard.append(row)
        details[cat] = {
            "topTickers": top_tickers,
            "sources": sources,
            "regions": regions,
            "windowVolume": total["volume"],
            "windowSentiment": round(total["sent_sum"] / total["sent_w"], 3) if total["sent_w"] else 0.0,
        }

    leaderboard.sort(key=lambda r: (r["rank"] is None, r["rank"] or 999, -r["volume"], r["id"]))
    active = sum(1 for r in leaderboard if r["volume"] > 0)
    top = next((r["id"] for r in leaderboard if r["volume"] > 0), None)

    payload = {
        "version": 1,
        "updated_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "window": {"start": days[0], "end": days[-1], "days": days},
        "sourceLabels": SOURCE_LABELS,
        "categories": CATEGORIES,
        "summary": {
            "active": active,
            "totalVolume": sum(total_by_day.values()),
            "topNarrative": top,
            "windowDays": window_days,
            "recentDays": recent_days,
        },
        "leaderboard": leaderboard,
        "series": series,
        "details": details,
    }

    path = _out_path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[narrative-rotation] events={len(events)} categories={active} window={days[0]}..{days[-1]} -> {path}")
    return payload


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DB))
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--window-days", type=int, default=21)
    ap.add_argument("--recent-days", type=int, default=3)
    args = ap.parse_args()
    build(args.db, args.out, args.window_days, args.recent_days)


if __name__ == "__main__":
    main()
