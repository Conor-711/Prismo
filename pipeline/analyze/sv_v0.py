"""Smart Voice hybrid pipeline.

The pipeline separates responsibilities:
  1. deterministic rules recall candidate X posts;
  2. LLM only structures whether a candidate is an actionable call;
  3. price settlement and investor scoring are deterministic.

The current scorer is SV v1-compatible: it treats a post as the evidence
budget, caps total weight for multi-ticker posts, prioritizes the author's
primary horizon, shrinks ticker base rates, and adds a bounded excess-return
component to directional accuracy. It also tracks call lifecycle: a later
opposite actionable call by the same investor on the same ticker closes the
older call early for horizons that have not yet naturally settled. Global SV
also applies a concentration gate so single-ticker specialists can rank highly
inside ticker segments without dominating the global leaderboard.

The pipeline writes local SQLite tables and exports ``web/lib/data/smartVoice.json``.
It is incremental: rerunning extraction skips candidates already present in
``sv_call`` unless ``--force`` is passed.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import datetime as dt
import heapq
import json
import math
import os
import re
import sqlite3
from pathlib import Path
from typing import Any

from ..common import llm


ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "data" / "dev.db"
EXPORT = ROOT / "web" / "lib" / "data" / "smartVoice.json"
TWEET_DIRS = [
    ROOT / "equity_trader_kol_tweets_2025h2",
    ROOT / "roster_tweets_6m_f5000",
]
HORIZONS = {"1D": 1, "5D": 5, "20D": 20, "60D": 60}
SV_SCORING_VERSION = "v1.3"
BASE_RATE_PRIOR = 20.0
BASE_RATE_MIN = 0.40
BASE_RATE_MAX = 0.65
RETURN_NORMALIZER = {"1D": 0.03, "5D": 0.08, "20D": 0.18, "60D": 0.35}
CALL_TYPES = {
    "single_ticker_call",
    "basket_call",
    "pair_trade",
    "sector_call",
    "portfolio_update",
    "retrospective",
    "context_mention",
}
TICKER_ROLES = {"primary", "basket_member", "context", "comparison", "excluded"}

NON_CALL_TAGS = {
    "SPY",  # benchmark; QQQ/IWM/SMH remain valid ETF calls
    "BTC", "ETH", "SOL", "DOGE", "XRP", "ADA", "BNB", "AVAX", "LINK", "MATIC",
    "PEPE", "SHIB", "USDT", "USDC", "USD", "EUR", "JPY", "GBP",
    "BTCUSD", "ETHUSD", "EURUSD", "USDJPY", "XAU", "XAUUSD", "XAGUSD",
    "SPX", "VIX", "DXY", "ES", "ES_F", "NQ", "NQ_F", "RTY", "YM",
    "CL", "CL_F", "GC", "GC_F", "SI", "SI_F", "HG", "ZB", "ZN",
    "BRENT", "NATGAS", "SOX", "DJI", "NDX", "TNX", "NASDAQ", "KOSPI",
}

BULL_RE = re.compile(
    r"\b(long|bullish|buy(?:ing|s|ed)?|bought|add(?:ing|ed)?|accumulat(?:e|ing)|calls?|"
    r"break(?:out)?|breaks? over|reclaim|support|bounce|rips?|squeeze|upside|target|pt|"
    r"going to|goes to|next stop|load(?:ing)?|starter|entry|dip buy|undervalued|cheap|"
    r"upgrade|outperform)\b|看多|做多|买入|加仓|建仓|目标|看到|上看|突破|支撑|反弹|低估",
    re.I,
)
BEAR_RE = re.compile(
    r"\b(short|bearish|puts?|sell(?:ing|s|ed)?|sold|trim(?:ming|med)?|avoid|fade|"
    r"downside|breakdown|breaks? below|reject(?:ed|ion)?|resistance|overvalued|expensive|"
    r"weak|dump|crash|downgrade|underperform)\b|看空|做空|卖出|减仓|止盈|下看|跌破|阻力|高估|回避",
    re.I,
)
TARGET_RE = re.compile(
    r"(?:target|pt|price target|to|towards?|看(?:到|至)|目标|上看|下看)\s*\$?\s*\d+(?:\.\d+)?"
    r"|\$\d+(?:\.\d+)?(?:\s*[-–]\s*\$?\d+(?:\.\d+)?)?",
    re.I,
)
HORIZON_RE = re.compile(
    r"\b(today|tomorrow|this week|next week|by (?:eow|eom|year end|year-end)|"
    r"\d+\s*(?:d|day|days|wk|week|weeks|mo|month|months))\b|今天|明天|本周|下周|月底|年底|"
    r"\d+\s*(?:天|日|周|个月|月)",
    re.I,
)
OPTION_RE = re.compile(r"\b\d+(?:\.\d+)?\s*[cp]\b|\b(?:calls?|puts?)\b", re.I)

SV_SYSTEM = (
    "You structure public equity-market posts into tradable calls for Smart Voice scoring. "
    "Judge only the specified ticker, but first understand whether the post is a single-ticker call, "
    "a basket/sector thesis, a pair trade, a portfolio update, a retrospective, or merely context. "
    "Do not decide whether the call was correct. "
    "If the post is news, a joke, a repost, a retrospective brag, a pure chart note without direction, "
    "or only mentions the ticker in a watchlist with no directional implication, mark it non-actionable. "
    "If the specified ticker is only a comparison, ecosystem reference, or context mention, mark it non-actionable "
    "or set ticker_role to context/comparison/excluded. "
    "If it contains a conditional trade plan, it can be actionable if direction is clear. "
    "Return strict JSON only with these fields: "
    "{\"is_actionable_call\":boolean,\"direction\":\"bull|bear|neutral\","
    "\"horizon_bucket\":\"1D|5D|20D|60D|unknown\",\"horizon_explicit\":boolean,"
    "\"target_price\":number|null,\"conviction_score\":number,"
    "\"evidence_score\":number,\"specificity_score\":number,"
    "\"call_type\":\"single_ticker_call|basket_call|pair_trade|sector_call|portfolio_update|retrospective|context_mention\","
    "\"ticker_role\":\"primary|basket_member|context|comparison|excluded\","
    "\"ticker_relevance\":number,"
    "\"target_price_owner\":\"ticker symbol if a target price belongs to a specific ticker else empty\","
    "\"evidence_span\":\"short original quote supporting this ticker call\","
    "\"summary_zh\":\"short Chinese summary\",\"summary_en\":\"short English summary\","
    "\"exclusion_reason\":\"short reason if non-actionable else empty\"}. "
    "Scoring fields are 0..1. evidence_score measures reasoning/data quality, not correctness. "
    "specificity_score measures explicit ticker/target/entry/condition/horizon detail. "
    "ticker_relevance is 0..1 and should be low if the ticker is one of many basket members. "
    "Simple but clear calls are valid. Detailed wrongness is not judged here."
)

TICKER_NARRATIVE: dict[str, str] = {
    "NVDA": "semis", "MU": "semis", "AMD": "semis", "INTC": "semis", "AVGO": "semis",
    "AMAT": "semis", "LRCX": "semis", "TSM": "semis", "ASML": "semis", "SMH": "semis",
    "MRVL": "semis", "QCOM": "semis", "ARM": "semis", "SNDK": "semis",
    "PLTR": "ai_infra", "SMCI": "ai_infra", "DELL": "ai_infra", "CRWV": "ai_infra",
    "NBIS": "ai_infra", "ORCL": "ai_infra", "IBM": "ai_infra",
    "MSFT": "software", "CRM": "software", "NOW": "software", "ADBE": "software",
    "SNOW": "software", "DDOG": "software", "NET": "software", "MDB": "software",
    "NFLX": "media", "DIS": "media", "ROKU": "media", "SPOT": "media",
    "TSLA": "ev", "RIVN": "ev", "LCID": "ev", "NIO": "ev", "XPEV": "ev",
    "COIN": "crypto", "MSTR": "crypto", "MARA": "crypto", "RIOT": "crypto",
    "IREN": "crypto", "CLSK": "crypto", "HUT": "crypto", "BITF": "crypto",
    "HOOD": "fintech", "PYPL": "fintech", "SQ": "fintech", "AFRM": "fintech",
    "AMZN": "consumer", "BABA": "consumer", "PDD": "consumer", "COST": "consumer",
    "WMT": "consumer", "SBUX": "consumer", "NKE": "consumer",
}
NARRATIVE_LABELS = {
    "semis": {"zh": "半导体", "en": "Semiconductors"},
    "ai_infra": {"zh": "AI 基础设施", "en": "AI infrastructure"},
    "software": {"zh": "软件与云", "en": "Software & cloud"},
    "media": {"zh": "媒体娱乐", "en": "Media & entertainment"},
    "ev": {"zh": "电动车", "en": "EV"},
    "crypto": {"zh": "加密相关", "en": "Crypto-linked"},
    "consumer": {"zh": "消费与零售", "en": "Consumer"},
    "fintech": {"zh": "金融科技", "en": "Fintech"},
    "other": {"zh": "其他", "en": "Other"},
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def jdump(v: Any) -> str:
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def clamp(n: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, n))


def connect() -> sqlite3.Connection:
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=8000")
    return con


def ensure_tables(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS sv_call_candidate (
          candidate_id TEXT PRIMARY KEY,
          tweet_id TEXT NOT NULL,
          ticker TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'x',
          author_id TEXT,
          author_handle TEXT,
          created_at TEXT,
          created_day TEXT,
          tweet_type TEXT,
          lang TEXT,
          text TEXT,
          url TEXT,
          like_count INTEGER DEFAULT 0,
          retweet_count INTEGER DEFAULT 0,
          reply_count INTEGER DEFAULT 0,
          quote_count INTEGER DEFAULT 0,
          view_count INTEGER DEFAULT 0,
          bookmark_count INTEGER DEFAULT 0,
          interactions REAL DEFAULT 0,
          heuristic_score REAL DEFAULT 0,
          reason TEXT,
          candidate_rank INTEGER,
          source_file TEXT,
          inserted_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_ticker ON sv_call_candidate(ticker);
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_author ON sv_call_candidate(author_id);
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_created ON sv_call_candidate(created_at);

        CREATE TABLE IF NOT EXISTS sv_call (
          candidate_id TEXT PRIMARY KEY,
          tweet_id TEXT NOT NULL,
          ticker TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'x',
          investor_id TEXT,
          author_handle TEXT,
          created_at TEXT,
          language TEXT,
          is_actionable_call INTEGER NOT NULL DEFAULT 0,
          direction TEXT NOT NULL DEFAULT 'neutral',
          horizon_bucket TEXT NOT NULL DEFAULT 'unknown',
          horizon_explicit INTEGER NOT NULL DEFAULT 0,
          target_price REAL,
          conviction_score REAL DEFAULT 0,
          evidence_score REAL DEFAULT 0,
          specificity_score REAL DEFAULT 0,
          call_weight REAL DEFAULT 0,
          call_type TEXT DEFAULT '',
          ticker_role TEXT DEFAULT '',
          ticker_relevance REAL DEFAULT 0,
          target_price_owner TEXT DEFAULT '',
          evidence_span TEXT DEFAULT '',
          scoring_version TEXT DEFAULT 'v0',
          summary_zh TEXT DEFAULT '',
          summary_en TEXT DEFAULT '',
          exclusion_reason TEXT DEFAULT '',
          model TEXT,
          tagged_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_sv_call_action ON sv_call(is_actionable_call, direction);
        CREATE INDEX IF NOT EXISTS idx_sv_call_investor ON sv_call(investor_id);
        CREATE INDEX IF NOT EXISTS idx_sv_call_ticker ON sv_call(ticker);

        CREATE TABLE IF NOT EXISTS sv_call_settlement (
          candidate_id TEXT NOT NULL,
          horizon TEXT NOT NULL,
          ticker TEXT NOT NULL,
          investor_id TEXT,
          created_at TEXT,
          entry_day TEXT,
          exit_day TEXT,
          entry_price REAL,
          exit_price REAL,
          benchmark_entry_price REAL,
          benchmark_exit_price REAL,
          return_pct REAL,
          benchmark_return_pct REAL,
          excess_return_pct REAL,
          expected_hit REAL,
          actual_hit INTEGER,
          score_weight REAL,
          contribution REAL,
          exit_reason TEXT DEFAULT 'horizon',
          superseded_by_candidate_id TEXT,
          status TEXT NOT NULL,
          PRIMARY KEY(candidate_id, horizon)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_settle_investor ON sv_call_settlement(investor_id);
        CREATE INDEX IF NOT EXISTS idx_sv_settle_ticker ON sv_call_settlement(ticker);

        CREATE TABLE IF NOT EXISTS sv_investor_score (
          investor_id TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          name TEXT,
          handle TEXT,
          language TEXT,
          sv REAL,
          raw_z REAL,
          confidence TEXT,
          n_eff REAL,
          settled_calls INTEGER,
          active_days INTEGER,
          covered_tickers INTEGER,
          top_tickers_json TEXT,
          top_narratives_json TEXT,
          platform_scores_json TEXT,
          horizon_scores_json TEXT,
          narrative_scores_json TEXT,
          ticker_scores_json TEXT,
          concentration_json TEXT,
          rationale_zh TEXT,
          rationale_en TEXT,
          updated_at TEXT
        );

        CREATE TABLE IF NOT EXISTS sv_segment_score (
          segment_type TEXT NOT NULL,
          segment_key TEXT NOT NULL,
          investor_id TEXT NOT NULL,
          score REAL,
          raw_z REAL,
          n_eff REAL,
          settled_calls INTEGER,
          PRIMARY KEY(segment_type, segment_key, investor_id)
        );
        """
    )
    existing_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_call)").fetchall()}
    extra_cols = {
        "call_type": "TEXT DEFAULT ''",
        "ticker_role": "TEXT DEFAULT ''",
        "ticker_relevance": "REAL DEFAULT 0",
        "target_price_owner": "TEXT DEFAULT ''",
        "evidence_span": "TEXT DEFAULT ''",
        "scoring_version": "TEXT DEFAULT 'v0'",
    }
    for name, ddl in extra_cols.items():
        if name not in existing_cols:
            con.execute(f"ALTER TABLE sv_call ADD COLUMN {name} {ddl}")
    existing_settle_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_call_settlement)").fetchall()}
    extra_settle_cols = {
        "exit_reason": "TEXT DEFAULT 'horizon'",
        "superseded_by_candidate_id": "TEXT",
    }
    for name, ddl in extra_settle_cols.items():
        if name not in existing_settle_cols:
            con.execute(f"ALTER TABLE sv_call_settlement ADD COLUMN {name} {ddl}")
    existing_score_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_investor_score)").fetchall()}
    extra_score_cols = {
        "concentration_json": "TEXT",
    }
    for name, ddl in extra_score_cols.items():
        if name not in existing_score_cols:
            con.execute(f"ALTER TABLE sv_investor_score ADD COLUMN {name} {ddl}")
    con.commit()


def price_tickers(con: sqlite3.Connection, min_rows: int = 80) -> set[str]:
    rows = con.execute(
        "SELECT ticker, count(*) AS n FROM price_daily WHERE close IS NOT NULL GROUP BY ticker HAVING n >= ?",
        (min_rows,),
    ).fetchall()
    return {str(r["ticker"]).upper() for r in rows}


def tweet_files(tweet_dirs: list[Path]) -> list[Path]:
    out: list[Path] = []
    for folder in tweet_dirs:
        if folder.exists():
            out += sorted(folder.glob("tweets_*.jsonl"))
    return out


def parse_tags(obj: dict[str, Any]) -> list[str]:
    tags = []
    for raw in obj.get("cashtags") or []:
        t = str(raw or "").strip().upper().lstrip("$").replace("-", ".")
        if t:
            tags.append(t)
    return sorted(set(tags))


def interactions(obj: dict[str, Any]) -> float:
    return (
        float(obj.get("like_count") or 0)
        + float(obj.get("retweet_count") or 0) * 2
        + float(obj.get("reply_count") or 0)
        + float(obj.get("quote_count") or 0) * 2
        + math.log1p(float(obj.get("view_count") or 0)) * 0.25
        + float(obj.get("bookmark_count") or 0) * 2
    )


def heuristic(text: str) -> tuple[float, str]:
    reasons: list[str] = []
    score = 0.0
    if BULL_RE.search(text):
        score += 16
        reasons.append("bullish_terms")
    if BEAR_RE.search(text):
        score += 16
        reasons.append("bearish_terms")
    if TARGET_RE.search(text):
        score += 12
        reasons.append("target_or_price")
    if HORIZON_RE.search(text):
        score += 5
        reasons.append("horizon")
    if OPTION_RE.search(text):
        score += 5
        reasons.append("option_terms")
    if len(text) >= 120:
        score += 4
        reasons.append("substantive_length")
    if len(text) < 12:
        score -= 8
    return score, ",".join(reasons)


def candidate_tuple(obj: dict[str, Any], ticker: str, score: float, reason: str, source_file: str, rank: int) -> tuple:
    tweet_id = str(obj.get("tweet_id") or "")
    created = str(obj.get("created_at") or "")
    text = str(obj.get("text") or "")
    return (
        f"{tweet_id}:{ticker}",
        tweet_id,
        ticker,
        "x",
        str(obj.get("author_id") or ""),
        str(obj.get("author_handle") or ""),
        created,
        created[:10],
        str(obj.get("tweet_type") or ""),
        str(obj.get("lang") or ""),
        text,
        str(obj.get("url") or ""),
        int(obj.get("like_count") or 0),
        int(obj.get("retweet_count") or 0),
        int(obj.get("reply_count") or 0),
        int(obj.get("quote_count") or 0),
        int(obj.get("view_count") or 0),
        int(obj.get("bookmark_count") or 0),
        interactions(obj),
        score,
        reason,
        rank,
        source_file,
        utc_now(),
    )


def insert_candidates(con: sqlite3.Connection, rows: list[tuple]) -> int:
    if not rows:
        return 0
    con.executemany(
        """INSERT OR IGNORE INTO sv_call_candidate
           (candidate_id,tweet_id,ticker,source,author_id,author_handle,created_at,created_day,
            tweet_type,lang,text,url,like_count,retweet_count,reply_count,quote_count,view_count,
            bookmark_count,interactions,heuristic_score,reason,candidate_rank,source_file,inserted_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        rows,
    )
    return con.total_changes


def build_candidates(con: sqlite3.Connection, tweet_dirs: list[Path], limit: int, min_score: float, only: set[str] | None) -> int:
    ensure_tables(con)
    valid = price_tickers(con) - NON_CALL_TAGS
    if only:
        valid &= only
    files = tweet_files(tweet_dirs)
    heap: list[tuple[float, int, tuple]] = []
    seq = 0
    inserted = 0
    batch: list[tuple] = []
    scanned = matched = 0

    for path in files:
        with path.open(encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                scanned += 1
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if str(obj.get("tweet_type") or "").lower() == "retweet":
                    continue
                text = str(obj.get("text") or "")
                score, reason = heuristic(text)
                if score < min_score:
                    continue
                tags = [t for t in parse_tags(obj) if t in valid]
                if not tags:
                    continue
                matched += len(tags)
                priority = score * 10 + math.log1p(interactions(obj)) * 2
                for ticker in tags:
                    seq += 1
                    row = candidate_tuple(obj, ticker, score, reason, path.name, 0)
                    if limit > 0:
                        item = (priority, seq, row)
                        if len(heap) < limit:
                            heapq.heappush(heap, item)
                        elif item > heap[0]:
                            heapq.heapreplace(heap, item)
                    else:
                        batch.append(row)
                        if len(batch) >= 1000:
                            before = con.total_changes
                            insert_candidates(con, batch)
                            con.commit()
                            inserted += con.total_changes - before
                            batch.clear()

    if limit > 0:
        ordered = [x[2] for x in sorted(heap, key=lambda x: (-x[0], x[1]))]
        ranked = []
        for i, row in enumerate(ordered, 1):
            lst = list(row)
            lst[21] = i
            ranked.append(tuple(lst))
        before = con.total_changes
        insert_candidates(con, ranked)
        con.commit()
        inserted += con.total_changes - before
    elif batch:
        before = con.total_changes
        insert_candidates(con, batch)
        con.commit()
        inserted += con.total_changes - before
    print(f"[sv-v0] candidates scanned={scanned} matched_pairs={matched} inserted={inserted} limit={limit}", flush=True)
    return inserted


def norm_num(v: Any, default: float = 0.0) -> float:
    try:
        if v is None or isinstance(v, bool):
            return default
        n = float(v)
        if math.isnan(n) or math.isinf(n):
            return default
        return n
    except (TypeError, ValueError):
        return default


def normalize_call(data: Any) -> dict[str, Any]:
    d = data if isinstance(data, dict) else {}
    direction = str(d.get("direction") or "neutral").strip().lower()
    if direction not in {"bull", "bear", "neutral"}:
        direction = "neutral"
    horizon = str(d.get("horizon_bucket") or "unknown").strip().upper()
    if horizon not in HORIZONS:
        horizon = "unknown"
    target = d.get("target_price")
    target_price = norm_num(target, 0.0) if target not in (None, "", "null") else None
    if target_price is not None and not (0 < target_price < 1_000_000):
        target_price = None
    actionable = bool(d.get("is_actionable_call")) and direction in {"bull", "bear"}
    conviction = clamp(norm_num(d.get("conviction_score"), 0.5), 0, 1)
    evidence = clamp(norm_num(d.get("evidence_score"), 0.25), 0, 1)
    specificity = clamp(norm_num(d.get("specificity_score"), 0.35), 0, 1)
    call_type = str(d.get("call_type") or "").strip().lower()
    if call_type not in CALL_TYPES:
        call_type = ""
    ticker_role = str(d.get("ticker_role") or "").strip().lower()
    if ticker_role not in TICKER_ROLES:
        ticker_role = ""
    ticker_relevance = clamp(norm_num(d.get("ticker_relevance"), 0.0), 0, 1)
    target_price_owner = str(d.get("target_price_owner") or "").strip().upper().lstrip("$")[:16]
    evidence_span = str(d.get("evidence_span") or "")[:360]
    explicit = bool(d.get("horizon_explicit")) and horizon != "unknown"
    horizon_mult = 1.0 if explicit else (0.75 if horizon != "unknown" else 0.55)
    weight = 0.0
    if actionable:
        weight = (
            1.0
            * (0.75 + 0.50 * conviction)
            * (0.85 + 0.35 * evidence)
            * (0.90 + 0.30 * specificity + (0.10 if target_price else 0.0))
            * horizon_mult
        )
        weight = clamp(weight, 0.4, 1.8)
    return {
        "is_actionable_call": 1 if actionable else 0,
        "direction": direction if actionable else "neutral",
        "horizon_bucket": horizon,
        "horizon_explicit": 1 if explicit else 0,
        "target_price": target_price,
        "conviction_score": conviction,
        "evidence_score": evidence,
        "specificity_score": specificity,
        "call_weight": weight,
        "call_type": call_type,
        "ticker_role": ticker_role,
        "ticker_relevance": ticker_relevance,
        "target_price_owner": target_price_owner,
        "evidence_span": evidence_span,
        "scoring_version": SV_SCORING_VERSION,
        "summary_zh": str(d.get("summary_zh") or "")[:240],
        "summary_en": str(d.get("summary_en") or "")[:240],
        "exclusion_reason": str(d.get("exclusion_reason") or "")[:180],
    }


def user_prompt(row: sqlite3.Row) -> str:
    return (
        f"Ticker to judge: {row['ticker']}\n"
        f"Created at: {row['created_at']}\n"
        f"Tweet type: {row['tweet_type']}\n"
        f"Language: {row['lang']}\n"
        f"Heuristic reason: {row['reason']}\n"
        "Post text:\n"
        f"{str(row['text'])[:2200]}"
    )


def write_call(con: sqlite3.Connection, candidate: sqlite3.Row, norm: dict[str, Any], model: str) -> None:
    con.execute(
        """INSERT INTO sv_call
           (candidate_id,tweet_id,ticker,source,investor_id,author_handle,created_at,language,
            is_actionable_call,direction,horizon_bucket,horizon_explicit,target_price,
            conviction_score,evidence_score,specificity_score,call_weight,call_type,ticker_role,
            ticker_relevance,target_price_owner,evidence_span,scoring_version,summary_zh,summary_en,
            exclusion_reason,model,tagged_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(candidate_id) DO UPDATE SET
             is_actionable_call=excluded.is_actionable_call,
             direction=excluded.direction,
             horizon_bucket=excluded.horizon_bucket,
             horizon_explicit=excluded.horizon_explicit,
             target_price=excluded.target_price,
             conviction_score=excluded.conviction_score,
             evidence_score=excluded.evidence_score,
             specificity_score=excluded.specificity_score,
             call_weight=excluded.call_weight,
             call_type=excluded.call_type,
             ticker_role=excluded.ticker_role,
             ticker_relevance=excluded.ticker_relevance,
             target_price_owner=excluded.target_price_owner,
             evidence_span=excluded.evidence_span,
             scoring_version=excluded.scoring_version,
             summary_zh=excluded.summary_zh,
             summary_en=excluded.summary_en,
             exclusion_reason=excluded.exclusion_reason,
             model=excluded.model,
             tagged_at=excluded.tagged_at""",
        (
            candidate["candidate_id"],
            candidate["tweet_id"],
            candidate["ticker"],
            "x",
            candidate["author_id"],
            candidate["author_handle"],
            candidate["created_at"],
            candidate["lang"],
            norm["is_actionable_call"],
            norm["direction"],
            norm["horizon_bucket"],
            norm["horizon_explicit"],
            norm["target_price"],
            norm["conviction_score"],
            norm["evidence_score"],
            norm["specificity_score"],
            norm["call_weight"],
            norm["call_type"],
            norm["ticker_role"],
            norm["ticker_relevance"],
            norm["target_price_owner"],
            norm["evidence_span"],
            norm["scoring_version"],
            norm["summary_zh"],
            norm["summary_en"],
            norm["exclusion_reason"],
            model,
            utc_now(),
        ),
    )


def ranked_candidate_rows(con: sqlite3.Connection, limit: int, force: bool) -> list[sqlite3.Row]:
    where = "" if force else "WHERE c.candidate_id IS NULL"
    sql = f"""
        SELECT cc.*
          FROM sv_call_candidate cc
          LEFT JOIN sv_call c ON c.candidate_id = cc.candidate_id
          {where}
         ORDER BY COALESCE(cc.candidate_rank, 999999999), cc.heuristic_score DESC, cc.interactions DESC
         LIMIT ?
    """
    return con.execute(sql, (limit if limit > 0 else 1_000_000_000,)).fetchall()


def author_balanced_candidate_rows(
    con: sqlite3.Connection,
    limit: int,
    force: bool,
    per_author_min: int,
    per_author_max: int,
) -> list[sqlite3.Row]:
    rows = ranked_candidate_rows(con, 0, force)
    if not rows:
        return []
    if limit <= 0:
        limit = len(rows)
    per_author_min = max(1, per_author_min)
    per_author_max = max(per_author_min, per_author_max)

    existing = collections.Counter()
    if not force:
        for r in con.execute("SELECT investor_id, count(*) AS n FROM sv_call GROUP BY investor_id"):
            if r["investor_id"]:
                existing[str(r["investor_id"])] = int(r["n"] or 0)

    by_author: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    for row in rows:
        author = str(row["author_id"] or row["author_handle"] or "unknown")
        by_author[author].append(row)

    selected: list[sqlite3.Row] = []
    selected_ids: set[str] = set()
    selected_counts = collections.Counter()

    def take(author: str, n: int) -> None:
        if n <= 0 or len(selected) >= limit:
            return
        pool = by_author[author]
        taken = 0
        while pool and taken < n and len(selected) < limit:
            row = pool.pop(0)
            cid = str(row["candidate_id"])
            if cid in selected_ids:
                continue
            selected.append(row)
            selected_ids.add(cid)
            selected_counts[author] += 1
            taken += 1

    authors = sorted(
        by_author,
        key=lambda a: (
            min(existing[a], per_author_min),
            -(len(by_author[a])),
            by_author[a][0]["candidate_rank"] or 999999999,
        ),
    )

    # Phase 1: give every available author enough LLM slots to reach the
    # production minimum before allocating extra depth to already-rich authors.
    for author in authors:
        current = existing[author]
        if current >= per_author_min:
            continue
        take(author, min(per_author_min - current, per_author_max - current))
        if len(selected) >= limit:
            break

    # Phase 2: round-robin extra slots, capped per author, still preserving each
    # author's internal rank order.
    while len(selected) < limit:
        moved = False
        for author in authors:
            current = existing[author] + selected_counts[author]
            if current >= per_author_max:
                continue
            before = len(selected)
            take(author, 1)
            moved = moved or len(selected) > before
            if len(selected) >= limit:
                break
        if not moved:
            break

    selected_authors = len({str(r["author_id"] or r["author_handle"] or "unknown") for r in selected})
    print(
        f"[sv-v0] author-balanced selected={len(selected)} authors={selected_authors} "
        f"pending_rows={len(rows)} per_author_min={per_author_min} per_author_max={per_author_max}",
        flush=True,
    )
    return selected


def extract_calls(
    con: sqlite3.Connection,
    limit: int,
    workers: int,
    force: bool,
    extract_mode: str,
    per_author_min: int,
    per_author_max: int,
) -> int:
    ensure_tables(con)
    if not llm.available(llm.LOW):
        print("[sv-v0] LOW model key unavailable; extraction skipped.", flush=True)
        return 0
    if extract_mode == "author-balanced":
        rows = author_balanced_candidate_rows(con, limit, force, per_author_min, per_author_max)
    else:
        rows = ranked_candidate_rows(con, limit, force)
    if not rows:
        print("[sv-v0] no candidates need extraction.", flush=True)
        return 0
    model = llm.model_label(llm.LOW)
    print(f"[sv-v0] extracting {len(rows)} candidates with {model} workers={workers}", flush=True)
    done = actionable = fail = 0
    buffer: list[tuple[sqlite3.Row, dict[str, Any]]] = []

    def work(row: sqlite3.Row) -> tuple[sqlite3.Row, dict[str, Any]]:
        data = None
        for _ in range(2):
            data = llm.messages_json(llm.LOW, SV_SYSTEM, user_prompt(row), max_tokens=520)
            if isinstance(data, dict):
                break
        return row, normalize_call(data)

    def flush() -> None:
        nonlocal done, actionable
        if not buffer:
            return
        for cand, norm in buffer:
            write_call(con, cand, norm, model)
            actionable += int(norm["is_actionable_call"])
        con.commit()
        done += len(buffer)
        buffer.clear()

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futures = [pool.submit(work, r) for r in rows]
        for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                buffer.append(fut.result())
            except Exception as exc:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [sv-v0] extract failed: {str(exc)[:120]}", flush=True)
            if len(buffer) >= 30:
                flush()
            if i % 100 == 0:
                print(f"  [sv-v0] extracted {i}/{len(rows)} done={done}+buf{len(buffer)} actionable={actionable} fail={fail}", flush=True)
    flush()
    print(f"[sv-v0] extraction done={done} actionable={actionable} fail={fail}", flush=True)
    return done


def load_prices(con: sqlite3.Connection) -> dict[str, list[tuple[str, float]]]:
    out: dict[str, list[tuple[str, float]]] = collections.defaultdict(list)
    for r in con.execute(
        "SELECT ticker, day, COALESCE(adj_close, close) AS px FROM price_daily WHERE close IS NOT NULL ORDER BY ticker, day"
    ):
        out[str(r["ticker"]).upper()].append((str(r["day"]), float(r["px"])))
    return dict(out)


def first_idx_on_or_after(days: list[tuple[str, float]], day: str) -> int | None:
    lo, hi = 0, len(days)
    while lo < hi:
        mid = (lo + hi) // 2
        if days[mid][0] < day:
            lo = mid + 1
        else:
            hi = mid
    return lo if lo < len(days) else None


def base_rates(prices: dict[str, list[tuple[str, float]]]) -> dict[tuple[str, str], float]:
    spy = prices.get("SPY") or []
    spy_by_day = {d: p for d, p in spy}
    rates: dict[tuple[str, str], float] = {}
    for ticker, rows in prices.items():
        if ticker == "SPY":
            continue
        for h, n in HORIZONS.items():
            wins = total = 0
            for i in range(0, max(0, len(rows) - n)):
                d0, p0 = rows[i]
                d1, p1 = rows[i + n]
                sp0 = spy_by_day.get(d0)
                sp1 = spy_by_day.get(d1)
                if not sp0 or not sp1 or p0 <= 0 or sp0 <= 0:
                    continue
                excess = (p1 / p0 - 1) - (sp1 / sp0 - 1)
                wins += 1 if excess > 0 else 0
                total += 1
            raw = wins / total if total else 0.5
            shrunk = (wins + 0.5 * BASE_RATE_PRIOR) / (total + BASE_RATE_PRIOR) if total else raw
            rates[(ticker, h)] = clamp(shrunk, BASE_RATE_MIN, BASE_RATE_MAX)
    return rates


def horizon_factor(call_bucket: str, explicit: int, horizon: str) -> float:
    if call_bucket in HORIZONS:
        if call_bucket == horizon:
            return 1.0
        order = list(HORIZONS)
        dist = abs(order.index(call_bucket) - order.index(horizon))
        if explicit:
            return 0.15 if dist == 1 else 0.0
        return 0.25 if dist == 1 else 0.0
    return {"1D": 0.0, "5D": 0.25, "20D": 0.50, "60D": 0.25}[horizon]


def text_tickers(text: str) -> list[str]:
    tags = re.findall(r"\$([A-Za-z][A-Za-z0-9.]{0,9})", text or "")
    return [t.upper().replace("-", ".") for t in tags if t.upper() not in NON_CALL_TAGS]


def ticker_mentions(text: str, ticker: str) -> int:
    t = re.escape(ticker.upper())
    return len(re.findall(rf"(?<![A-Z0-9])\$?{t}(?![A-Z0-9])", text or "", re.I))


def infer_call_meta(call: sqlite3.Row) -> dict[str, Any]:
    ticker = str(call["ticker"]).upper()
    text = str(call["text"] or "")
    summary = f"{call['summary_zh'] or ''} {call['summary_en'] or ''}"
    tags = text_tickers(text)
    unique_tags = sorted(set(tags))
    tag_count = len(unique_tags)
    current_mentions = ticker_mentions(text, ticker)
    summary_mentions = ticker_mentions(summary, ticker)

    call_type = str(call["call_type"] or "").lower()
    if call_type not in CALL_TYPES:
        lower = text.lower()
        if re.search(r"\b(look back|called it|told you|since i said|ever since|was right|laughed at)\b", lower):
            call_type = "retrospective"
        elif re.search(r"\b(portfolio|holdings?|watchlist|strong buys?|strong sells?|trim list|buy list|sell list)\b", lower) or tag_count >= 8:
            call_type = "basket_call"
        elif tag_count >= 3:
            call_type = "basket_call"
        else:
            call_type = "single_ticker_call"

    target_owner = str(call["target_price_owner"] or "").upper().lstrip("$")
    if not target_owner and call["target_price"] is not None:
        summary_tags = [t for t in text_tickers(summary) if t not in NON_CALL_TAGS]
        if summary_tags:
            target_owner = summary_tags[0]

    role = str(call["ticker_role"] or "").lower()
    if role not in TICKER_ROLES:
        if target_owner and target_owner != ticker:
            role = "context"
        elif call_type == "single_ticker_call":
            role = "primary"
        elif summary_mentions or current_mentions >= 2:
            role = "primary" if tag_count <= 3 else "basket_member"
        elif tag_count >= 3 and current_mentions >= 1:
            role = "basket_member"
        else:
            role = "context"

    relevance = float(call["ticker_relevance"] or 0)
    if relevance <= 0:
        relevance = 0.35
        if current_mentions:
            relevance += 0.20
        if re.search(rf"\${re.escape(ticker)}\b", text[:600], re.I):
            relevance += 0.20
        if summary_mentions:
            relevance += 0.20
        if call["target_price"] is not None and (summary_mentions or tag_count <= 2):
            relevance += 0.10
        if tag_count > 3:
            relevance -= min(0.35, (tag_count - 3) * 0.025)
        if target_owner and target_owner != ticker:
            relevance *= 0.30
        if call_type == "portfolio_update":
            relevance *= 0.70
        elif call_type == "retrospective":
            relevance *= 0.45
        relevance = clamp(relevance, 0.05, 1.0)

    type_mult = {
        "single_ticker_call": 1.00,
        "pair_trade": 0.90,
        "basket_call": 0.75,
        "sector_call": 0.65,
        "portfolio_update": 0.45,
        "retrospective": 0.25,
        "context_mention": 0.0,
    }.get(call_type, 0.75)
    role_mult = {
        "primary": 1.00,
        "basket_member": 0.75,
        "comparison": 0.25,
        "context": 0.0,
        "excluded": 0.0,
    }.get(role, 0.0)
    if relevance < 0.20:
        role_mult = 0.0
    return {
        "call_type": call_type,
        "ticker_role": role,
        "ticker_relevance": relevance,
        "target_price_owner": target_owner,
        "weight_multiplier": type_mult * role_mult * relevance,
        "tag_count": tag_count,
    }


def post_weight_cap(n_calls: int) -> float:
    if n_calls <= 1:
        return 1.8
    return min(2.8, 1.15 + 0.35 * math.sqrt(n_calls))


def annotate_supersessions(enriched: list[dict[str, Any]]) -> int:
    """Mark calls closed by a later opposite same-investor same-ticker call."""
    by_key: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for item in enriched:
        call = item["call"]
        investor = str(call["investor_id"] or "")
        ticker = str(call["ticker"] or "").upper()
        if investor and ticker:
            by_key[(investor, ticker)].append(item)

    closed = 0
    for items in by_key.values():
        items.sort(key=lambda x: (str(x["call"]["created_at"] or ""), str(x["call"]["candidate_id"] or "")))
        for i, item in enumerate(items):
            call = item["call"]
            direction = str(call["direction"])
            created = str(call["created_at"] or "")
            for later in items[i + 1:]:
                later_call = later["call"]
                later_created = str(later_call["created_at"] or "")
                if later_created <= created:
                    continue
                if str(later_call["direction"]) == direction:
                    continue
                item["superseded_at"] = later_created
                item["superseded_by_candidate_id"] = str(later_call["candidate_id"])
                closed += 1
                break
    return closed


def settle_calls(con: sqlite3.Connection) -> int:
    ensure_tables(con)
    prices = load_prices(con)
    rates = base_rates(prices)
    spy = prices.get("SPY") or []
    if not spy:
        raise SystemExit("[sv-v0] missing SPY prices; run make sv-price-history first.")
    con.execute("DELETE FROM sv_call_settlement")
    rows = con.execute(
        """SELECT c.*, cc.text AS text, cc.tweet_id AS source_tweet_id
             FROM sv_call c JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
            WHERE c.is_actionable_call=1 AND c.direction IN ('bull','bear') AND c.call_weight > 0"""
    ).fetchall()
    enriched: list[dict[str, Any]] = []
    by_tweet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for call in rows:
        meta = infer_call_meta(call)
        raw_weight = float(call["call_weight"]) * float(meta["weight_multiplier"])
        if raw_weight <= 0:
            continue
        item = {"call": call, "meta": meta, "raw_weight": raw_weight, "effective_weight": raw_weight}
        enriched.append(item)
        by_tweet[str(call["tweet_id"])].append(item)

    for items in by_tweet.values():
        if not items:
            continue
        cap = post_weight_cap(len(items))
        total = sum(float(x["raw_weight"]) for x in items)
        scale = min(1.0, cap / total) if total > 0 else 0.0
        for item in items:
            item["effective_weight"] = float(item["raw_weight"]) * scale

    superseded = annotate_supersessions(enriched)
    out: list[tuple] = []
    for item in enriched:
        call = item["call"]
        ticker = str(call["ticker"]).upper()
        series = prices.get(ticker)
        if not series:
            continue
        created_day = str(call["created_at"] or "")[:10]
        idx = first_idx_on_or_after(series, created_day)
        spy_idx = first_idx_on_or_after(spy, created_day)
        if idx is None or spy_idx is None:
            continue
        entry_day, entry_px = series[idx]
        spy_entry_day, spy_entry = spy[spy_idx]
        supersede_idx = None
        supersede_spy_idx = None
        superseded_at = item.get("superseded_at")
        if superseded_at:
            supersede_day = str(superseded_at)[:10]
            supersede_idx = first_idx_on_or_after(series, supersede_day)
            if supersede_idx is not None and supersede_idx <= idx:
                supersede_idx = None
            if supersede_idx is not None:
                supersede_exit_day = series[supersede_idx][0]
                supersede_spy_idx = first_idx_on_or_after(spy, supersede_exit_day)
        for h, n in HORIZONS.items():
            weight = float(item["effective_weight"]) * horizon_factor(str(call["horizon_bucket"]), int(call["horizon_explicit"] or 0), h)
            if weight <= 0:
                continue
            status = "pending"
            values = [None] * 10
            contribution = None
            actual_hit = None
            expected = rates.get((ticker, h), 0.5)
            exit_reason = "horizon"
            superseded_by = None
            natural_idx = idx + n
            natural_spy_idx = spy_idx + n
            exit_idx = natural_idx if natural_idx < len(series) and natural_spy_idx < len(spy) else None
            exit_spy_idx = natural_spy_idx if exit_idx is not None else None
            if supersede_idx is not None and supersede_spy_idx is not None and (exit_idx is None or supersede_idx < exit_idx):
                exit_idx = supersede_idx
                exit_spy_idx = supersede_spy_idx
                exit_reason = "superseded"
                superseded_by = str(item.get("superseded_by_candidate_id") or "")
            if exit_idx is not None and exit_spy_idx is not None:
                exit_day, exit_px = series[exit_idx]
                spy_exit_day, spy_exit = spy[exit_spy_idx]
                ret = exit_px / entry_px - 1
                bret = spy_exit / spy_entry - 1
                excess = ret - bret
                directional_excess = excess if call["direction"] == "bull" else -excess
                if call["direction"] == "bull":
                    actual_hit = 1 if excess > 0 else 0
                    expected_hit = expected
                else:
                    actual_hit = 1 if excess < 0 else 0
                    expected_hit = 1 - expected
                ret_component = clamp(directional_excess / RETURN_NORMALIZER[h], -1.0, 1.0)
                contribution = weight * (0.75 * (actual_hit - expected_hit) + 0.25 * ret_component)
                status = "settled"
                values = [exit_day, exit_px, spy_entry, spy_exit, ret, bret, excess, expected_hit, actual_hit, contribution]
            else:
                expected_hit = expected if call["direction"] == "bull" else 1 - expected
                values = [None, None, spy_entry, None, None, None, None, expected_hit, None, None]
            out.append(
                (
                    call["candidate_id"], h, ticker, call["investor_id"], call["created_at"],
                    entry_day, values[0], entry_px, values[1], values[2], values[3],
                    values[4], values[5], values[6], values[7], values[8], weight, values[9],
                    exit_reason, superseded_by, status,
                )
            )
    con.executemany(
        """INSERT OR REPLACE INTO sv_call_settlement
           (candidate_id,horizon,ticker,investor_id,created_at,entry_day,exit_day,entry_price,exit_price,
            benchmark_entry_price,benchmark_exit_price,return_pct,benchmark_return_pct,excess_return_pct,
            expected_hit,actual_hit,score_weight,contribution,exit_reason,superseded_by_candidate_id,status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        out,
    )
    con.commit()
    print(f"[sv-v0] settled rows={len(out)} raw_calls={len(rows)} effective_calls={len(enriched)} superseded_calls={superseded}", flush=True)
    return len(out)


def aggregate_stats(rows: list[sqlite3.Row], k: float = 30.0) -> dict[str, Any] | None:
    vals = [r for r in rows if r["status"] == "settled" and r["actual_hit"] is not None]
    if not vals:
        return None
    sum_contrib = sum(float(r["contribution"] or 0) for r in vals)
    variance = sum((float(r["score_weight"] or 0) ** 2) * float(r["expected_hit"] or 0.5) * (1 - float(r["expected_hit"] or 0.5)) for r in vals)
    z = sum_contrib / math.sqrt(variance) if variance > 1e-9 else 0.0
    weights = [float(r["score_weight"] or 0) for r in vals if float(r["score_weight"] or 0) > 0]
    n_eff = (sum(weights) ** 2 / sum(w * w for w in weights)) if weights else 0.0
    ticker_weights: collections.Counter[str] = collections.Counter()
    ticker_positive_contrib: collections.Counter[str] = collections.Counter()
    for r in vals:
        ticker = str(r["ticker"])
        ticker_weights[ticker] += float(r["score_weight"] or 0)
        ticker_positive_contrib[ticker] += max(0.0, float(r["contribution"] or 0))
    total_ticker_weight = sum(ticker_weights.values())
    top_ticker, top_ticker_weight = ticker_weights.most_common(1)[0] if ticker_weights else ("", 0.0)
    top_weight_share = top_ticker_weight / total_ticker_weight if total_ticker_weight > 0 else 0.0
    total_positive_contrib = sum(ticker_positive_contrib.values())
    top_positive_ticker, top_positive_contribution = (
        ticker_positive_contrib.most_common(1)[0] if ticker_positive_contrib else ("", 0.0)
    )
    top_positive_share = top_positive_contribution / total_positive_contrib if total_positive_contrib > 0 else 0.0
    weight_eff_tickers = (
        total_ticker_weight * total_ticker_weight / sum(w * w for w in ticker_weights.values())
        if total_ticker_weight > 0
        else 0.0
    )
    positive_eff_tickers = (
        total_positive_contrib * total_positive_contrib / sum(v * v for v in ticker_positive_contrib.values() if v > 0)
        if total_positive_contrib > 0
        else 0.0
    )
    z_shrunk = z * n_eff / (n_eff + k)
    return {
        "raw_z": z_shrunk,
        "n_eff": n_eff,
        "settled_calls": len({r["candidate_id"] for r in vals}),
        "active_days": len({str(r["created_at"])[:10] for r in vals}),
        "covered_tickers": len({r["ticker"] for r in vals}),
        "concentration": {
            "topTicker": top_ticker,
            "topTickerWeightShare": round(top_weight_share, 4),
            "topPositiveTicker": top_positive_ticker,
            "topPositiveContributionShare": round(top_positive_share, 4),
            "effectiveTickersByWeight": round(weight_eff_tickers, 3),
            "effectiveTickersByPositiveContribution": round(positive_eff_tickers, 3),
        },
    }


def robust_scores(raw_by_id: dict[str, float]) -> dict[str, int]:
    if not raw_by_id:
        return {}
    vals = sorted(raw_by_id.values())
    med = vals[len(vals) // 2]
    deviations = sorted(abs(v - med) for v in vals)
    mad = deviations[len(deviations) // 2]
    scale = mad * 1.4826
    if scale < 0.25:
        mean = sum(vals) / len(vals)
        var = sum((v - mean) ** 2 for v in vals) / max(1, len(vals) - 1)
        scale = max(math.sqrt(var), 0.5)
    return {k: int(round(clamp(100 + 10 * ((v - med) / scale), 40, 180))) for k, v in raw_by_id.items()}


def confidence(n_eff: float, calls: int) -> str:
    if n_eff >= 60 and calls >= 80:
        return "high"
    if n_eff >= 25 and calls >= 35:
        return "medium"
    if n_eff >= 10 and calls >= 15:
        return "low"
    return "observing"


def reliability_cap(level: str) -> int:
    # Low-sample accounts can be promising, but they should not dominate the
    # production leaderboard until the evidence base thickens.
    return {"observing": 109, "low": 123, "medium": 145, "high": 180}.get(level, 109)


def concentration_cap(st: dict[str, Any]) -> int:
    c = st.get("concentration") or {}
    top_share = max(
        float(c.get("topTickerWeightShare") or 0),
        float(c.get("topPositiveContributionShare") or 0),
    )
    effective_tickers = min(
        float(c.get("effectiveTickersByWeight") or 0),
        float(c.get("effectiveTickersByPositiveContribution") or 0),
    )
    if top_share >= 0.75 or effective_tickers < 2.0:
        return 118
    if top_share >= 0.60 or effective_tickers < 3.0:
        return 126
    if top_share >= 0.50 or effective_tickers < 4.0:
        return 135
    return 180


def score_investors(con: sqlite3.Connection) -> int:
    ensure_tables(con)
    joined = con.execute(
        """SELECT s.*, c.author_handle, c.language, c.direction
             FROM sv_call_settlement s JOIN sv_call c ON c.candidate_id=s.candidate_id
            WHERE s.status='settled'"""
    ).fetchall()
    by_inv: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    for r in joined:
        if r["investor_id"]:
            by_inv[str(r["investor_id"])].append(r)

    global_stats = {inv: aggregate_stats(rows, 30.0) for inv, rows in by_inv.items()}
    global_stats = {k: v for k, v in global_stats.items() if v}
    qualified = {k: v["raw_z"] for k, v in global_stats.items() if v["n_eff"] >= 8 and v["settled_calls"] >= 10}
    if len(qualified) < 8:
        qualified = {k: v["raw_z"] for k, v in global_stats.items()}
    sv_scores = robust_scores(qualified)
    fallback_scores = robust_scores({k: v["raw_z"] for k, v in global_stats.items()})

    con.execute("DELETE FROM sv_investor_score")
    con.execute("DELETE FROM sv_segment_score")

    rows_to_write = []
    segment_rows = []
    for inv, rows in by_inv.items():
        st = global_stats.get(inv)
        if not st:
            continue
        handle = next((r["author_handle"] for r in rows if r["author_handle"]), inv)
        lang_counts = collections.Counter(str(r["language"] or "en") for r in rows)
        top_lang = lang_counts.most_common(1)[0][0] if lang_counts else "en"
        ticker_counts = collections.Counter(str(r["ticker"]) for r in rows)
        top_tickers = [t for t, _ in ticker_counts.most_common(8)]
        narrative_counts = collections.Counter(TICKER_NARRATIVE.get(t, "other") for t in ticker_counts)
        top_narratives = [n for n, _ in narrative_counts.most_common(4)]

        segment_scores: dict[tuple[str, str], int] = {}
        for h in HORIZONS:
            sub = [r for r in rows if r["horizon"] == h]
            ag = aggregate_stats(sub, 25.0)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("horizon", h)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("horizon", h, inv, segment_scores[("horizon", h)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for t, _ in ticker_counts.most_common(12):
            sub = [r for r in rows if r["ticker"] == t]
            ag = aggregate_stats(sub, 10.0)
            if ag and ag["n_eff"] >= 1.5:
                segment_scores[("ticker", t)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("ticker", t, inv, segment_scores[("ticker", t)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for n in set(TICKER_NARRATIVE.get(str(r["ticker"]), "other") for r in rows):
            sub = [r for r in rows if TICKER_NARRATIVE.get(str(r["ticker"]), "other") == n]
            ag = aggregate_stats(sub, 20.0)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("narrative", n)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("narrative", n, inv, segment_scores[("narrative", n)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))

        horizon_json = {h: segment_scores.get(("horizon", h)) for h in HORIZONS}
        ticker_json = {t: segment_scores[("ticker", t)] for t in ticker_counts if ("ticker", t) in segment_scores}
        narrative_json = {n: segment_scores[("narrative", n)] for n in set(top_narratives) if ("narrative", n) in segment_scores}
        level = confidence(st["n_eff"], st["settled_calls"])
        raw_sv = sv_scores.get(inv, fallback_scores.get(inv, 100))
        rel_cap = reliability_cap(level)
        conc_cap = concentration_cap(st)
        sv = min(raw_sv, rel_cap, conc_cap)
        concentration = dict(st.get("concentration") or {})
        concentration.update(
            {
                "cap": conc_cap,
                "capApplied": conc_cap < raw_sv,
                "rawSvBeforeConcentrationCap": raw_sv,
            }
        )
        rows_to_write.append(
            (
                inv, "x", f"@{handle}", handle, top_lang if top_lang in {"zh", "en", "ko", "ja"} else "en",
                sv, st["raw_z"], level, st["n_eff"], st["settled_calls"],
                st["active_days"], st["covered_tickers"], jdump(top_tickers), jdump(top_narratives),
                jdump({"x": sv}), jdump(horizon_json), jdump(narrative_json), jdump(ticker_json),
                jdump(concentration),
                f"基于 {st['settled_calls']} 个已结算 X call；SV {SV_SCORING_VERSION} 按单帖权重封顶、相对 SPY 的方向准确度、收益幅度、后续反向观点提前结算、集中度门槛与样本置信度归一。",
                f"Based on {st['settled_calls']} settled X calls; SV {SV_SCORING_VERSION} caps post-level weight and normalizes directional accuracy, bounded excess return, call lifecycle early closes, concentration gates, and evidence size versus SPY.",
                utc_now(),
            )
        )

    con.executemany(
        """INSERT INTO sv_investor_score
           (investor_id,source,name,handle,language,sv,raw_z,confidence,n_eff,settled_calls,active_days,
            covered_tickers,top_tickers_json,top_narratives_json,platform_scores_json,horizon_scores_json,
            narrative_scores_json,ticker_scores_json,concentration_json,rationale_zh,rationale_en,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        rows_to_write,
    )
    con.executemany(
        """INSERT INTO sv_segment_score
           (segment_type,segment_key,investor_id,score,raw_z,n_eff,settled_calls)
           VALUES (?,?,?,?,?,?,?)""",
        segment_rows,
    )
    con.commit()
    print(f"[sv-v0] scored investors={len(rows_to_write)} segment_rows={len(segment_rows)}", flush=True)
    return len(rows_to_write)


def export_json(con: sqlite3.Connection) -> None:
    rows = con.execute(
        """SELECT * FROM sv_investor_score
            ORDER BY sv DESC,
                     CASE confidence
                       WHEN 'high' THEN 4
                       WHEN 'medium' THEN 3
                       WHEN 'low' THEN 2
                       ELSE 1
                     END DESC,
                     n_eff DESC,
                     settled_calls DESC
            LIMIT 200"""
    ).fetchall()
    investors = []
    for r in rows:
        handle = str(r["handle"] or "")
        investors.append(
            {
                "id": f"x:{r['investor_id']}",
                "source": "x",
                "name": r["name"] or f"@{handle}",
                "handle": handle,
                "avatar": f"https://unavatar.io/twitter/{handle}" if handle else None,
                "url": f"https://x.com/{handle}" if handle else None,
                "language": r["language"] or "en",
                "sv": int(round(float(r["sv"] or 100))),
                "confidence": r["confidence"] or "observing",
                "nEff": round(float(r["n_eff"] or 0), 1),
                "settledCalls": int(r["settled_calls"] or 0),
                "activeDays": int(r["active_days"] or 0),
                "coveredTickers": int(r["covered_tickers"] or 0),
                "topTickers": json.loads(r["top_tickers_json"] or "[]"),
                "topNarratives": json.loads(r["top_narratives_json"] or "[]"),
                "platformScores": json.loads(r["platform_scores_json"] or "{}"),
                "horizonScores": json.loads(r["horizon_scores_json"] or "{}"),
                "narrativeScores": json.loads(r["narrative_scores_json"] or "{}"),
                "tickerScores": json.loads(r["ticker_scores_json"] or "{}"),
                "concentration": json.loads(r["concentration_json"] or "{}"),
                "rationaleZh": r["rationale_zh"] or "",
                "rationaleEn": r["rationale_en"] or "",
            }
        )
    current = [
        {"key": "semis", **NARRATIVE_LABELS["semis"], "weight": 34},
        {"key": "ai_infra", **NARRATIVE_LABELS["ai_infra"], "weight": 24},
        {"key": "software", **NARRATIVE_LABELS["software"], "weight": 16},
        {"key": "crypto", **NARRATIVE_LABELS["crypto"], "weight": 10},
    ]
    payload = {
        "version": 4,
        "scoringVersion": SV_SCORING_VERSION,
        "updatedAt": utc_now()[:10],
        "investors": investors,
        "x": investors,
        "youtube": [],
        "currentNarratives": current,
    }
    EXPORT.parent.mkdir(parents=True, exist_ok=True)
    EXPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[sv-v0] exported {len(investors)} investors -> {EXPORT}", flush=True)


def run(args: argparse.Namespace) -> None:
    con = connect()
    ensure_tables(con)
    only = {x.strip().upper() for x in args.only.split(",") if x.strip()} if args.only else None
    tweet_dirs = [Path(p).expanduser() for p in args.tweet_dir] if args.tweet_dir else TWEET_DIRS
    stages = ["candidates", "extract", "settle", "score", "export"] if args.stage == "all" else [args.stage]
    if "candidates" in stages:
        build_candidates(con, tweet_dirs, args.candidate_limit, args.min_score, only)
    if "extract" in stages:
        extract_calls(
            con,
            args.extract_limit,
            args.workers,
            args.force,
            args.extract_mode,
            args.per_author_min,
            args.per_author_max,
        )
    if "settle" in stages:
        settle_calls(con)
    if "score" in stages:
        score_investors(con)
    if "export" in stages:
        export_json(con)
    con.close()


def main() -> None:
    ap = argparse.ArgumentParser(description="Smart Voice v0 hybrid scorer")
    ap.add_argument("--stage", choices=["candidates", "extract", "settle", "score", "export", "all"], default="all")
    ap.add_argument("--candidate-limit", type=int, default=50_000, help="0 means insert all recalled candidates.")
    ap.add_argument("--extract-limit", type=int, default=1_000, help="0 means all pending candidates.")
    ap.add_argument("--extract-mode", choices=["rank", "author-balanced"], default="rank")
    ap.add_argument("--per-author-min", type=int, default=20)
    ap.add_argument("--per-author-max", type=int, default=80)
    ap.add_argument("--min-score", type=float, default=12.0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--only", default="", help="Comma-separated ticker subset.")
    ap.add_argument("--tweet-dir", action="append", default=[], help="Override/add tweet JSONL directories.")
    ap.add_argument("--force", action="store_true", help="Re-extract candidates already in sv_call.")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
