"""Smart Account hybrid pipeline.

The pipeline separates responsibilities:
  1. deterministic rules recall candidate X posts;
  2. LLM only structures whether a candidate is an actionable call;
  3. price settlement and investor scoring are deterministic.

The current scorer uses one evidence-bearing horizon per call and integrates
the cumulative directional excess-return path against both SPY and an
auditable industry ETF. It also tracks call lifecycle: a later opposite
actionable call by the same investor on the same ticker closes the older call
early. Global Score applies time decay, sample shrinkage, and a concentration gate
before platform-relative scores are exposed.

The pipeline writes local SQLite tables and exports ``web/lib/data/smartVoice.json``.
It is incremental: rerunning extraction skips candidates already present in
``sv_call`` unless ``--force`` is passed.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import datetime as dt
import html
import heapq
import json
import math
import os
import re
import sqlite3
from pathlib import Path
from typing import Any

from ...common import deepseek, gemini, llm
from ...common.config import ROOT as PROJECT_ROOT, RUNTIME_DATA_DIR, settings
from ...common.ticker_extraction import ALIASES
from ...common.youtube_filters import (
    YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
    YOUTUBE_MIN_DISPLAY_SUBSCRIBERS,
)
from .time_decay import (
    DEFAULT_TIME_DECAY_CONFIG,
    TIME_DECAY_VERSION,
    SVTimeDecayConfig,
    evidence_age_days,
    evidence_decay_weight,
    evidence_is_available,
    parse_day,
)
from .integral_scoring import (
    INTEGRAL_SCORING_VERSION,
    industry_benchmark,
    integrate_directional_path,
    primary_horizon,
)
from .youtube_transcript_calls import (
    TranscriptDocument,
    YOUTUBE_TRANSCRIPT_CALL_VERSION,
    extract_from_transcript,
    transcript_document,
)
from .x_call_policy import X_CALL_POLICY_VERSION, enforce_x_policy


ROOT = PROJECT_ROOT
DB = Path(os.environ.get("PRICE_DB", str(RUNTIME_DATA_DIR / "dev.db"))).resolve()
EXPORT = ROOT / "web" / "lib" / "data" / "smartVoice.json"
TWEET_DIRS = [
    ROOT / "equity_trader_kol_tweets_2025h2",
    ROOT / "roster_tweets_6m_f5000",
]
SV_PLATFORMS = {"x", "youtube", "reddit", "xueqiu", "toss"}
SUPPORTED_SOURCES = {"x", "youtube", "reddit", "xueqiu"}
SOURCE_LABELS = {
    "x": {"zh": "X", "en": "X"},
    "youtube": {"zh": "YouTube", "en": "YouTube"},
    "reddit": {"zh": "Reddit", "en": "Reddit"},
    "xueqiu": {"zh": "雪球", "en": "Xueqiu"},
    "toss": {"zh": "Toss", "en": "Toss"},
}
HORIZONS = {"1D": 1, "5D": 5, "20D": 20, "60D": 60, "90D": 90, "180D": 180}
# Call extraction and investor aggregation are versioned independently. Existing
# transcript-backed calls remain valid when the ranking formula changes.
SV_SCORING_VERSION = "v1.8-transcript-lifecycle"
SV_RANKING_VERSION = "v2.1-dual-benchmark-moderate-decay"
YOUTUBE_UPLOAD_MAPPING_VERSION = "youtube-title-v3"
YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE = 0.90
PLATFORM_QUALIFICATION = {
    "x": {"n_eff": 8.0, "settled_calls": 10},
    "youtube": {"n_eff": 4.0, "settled_calls": 5},
    "reddit": {"n_eff": 3.0, "settled_calls": 4},
    "xueqiu": {"n_eff": 5.0, "settled_calls": 8},
    "toss": {"n_eff": 5.0, "settled_calls": 8},
}
BASE_RATE_PRIOR = 20.0
BASE_RATE_MIN = 0.40
BASE_RATE_MAX = 0.65
RETURN_NORMALIZER = {"1D": 0.03, "5D": 0.08, "20D": 0.18, "60D": 0.35, "90D": 0.45, "180D": 0.70}
PATH_SCORE_WEIGHTS = {
    "endpoint": 0.40,
    "opportunity": 0.30,
    "persistence": 0.20,
    "retracement": 0.10,
}
DAILY_CALL_EVIDENCE_CAP = 1.8
SAME_DAY_DIRECTION_THRESHOLD = 0.25
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
INVESTOR_STYLES = {"fundamental", "technical", "event_driven", "macro", "flow_momentum", "mixed", "unknown"}
CALL_STRUCTURES = {
    "conviction_call",
    "conditional_setup",
    "invalidation_call",
    "watchlist",
    "risk_update",
    "reversal_call",
    "retrospective",
}
LIFECYCLE_ACTIONS = {
    "open_call",
    "reinforce_call",
    "invalidate_prior_call",
    "close_prior_call",
    "reverse_call",
    "no_trade_setup",
    "retrospective",
    "none",
}
ENTRY_STATUSES = {"active_entry", "conditional_setup", "watchlist_only", "not_applicable"}
HORIZON_TYPE_WEIGHTS = {
    "technical": {"1D": 0.10, "5D": 0.30, "20D": 0.28, "60D": 0.18, "90D": 0.09, "180D": 0.05},
    "fundamental": {"1D": 0.03, "5D": 0.07, "20D": 0.20, "60D": 0.27, "90D": 0.28, "180D": 0.15},
    "event_driven": {"1D": 0.08, "5D": 0.20, "20D": 0.28, "60D": 0.24, "90D": 0.14, "180D": 0.06},
    "macro": {"1D": 0.04, "5D": 0.10, "20D": 0.22, "60D": 0.28, "90D": 0.24, "180D": 0.12},
    "flow_momentum": {"1D": 0.12, "5D": 0.32, "20D": 0.28, "60D": 0.16, "90D": 0.08, "180D": 0.04},
    "mixed": {"1D": 0.06, "5D": 0.15, "20D": 0.23, "60D": 0.25, "90D": 0.21, "180D": 0.10},
    "unknown": {"1D": 0.05, "5D": 0.15, "20D": 0.25, "60D": 0.25, "90D": 0.20, "180D": 0.10},
}

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
TECHNICAL_RE = re.compile(
    r"\b(break(?:out|down)?|support|resistance|ema|sma|rsi|macd|pivot|trend(?:line)?|"
    r"triangle|wedge|flag|channel|candles?|engulfing|lower highs?|lower lows?|higher lows?|"
    r"gap(?:ping)?|reclaim|lost|hold(?:ing)? above|below|volume confirmation|setup|price action)\b|"
    r"突破|跌破|支撑|阻力|均线|趋势线|形态|技术|量能|确认",
    re.I,
)
FUNDAMENTAL_RE = re.compile(
    r"\b(revenue|earnings|eps|margin|guidance|valuation|multiple|cash flow|fcf|tam|"
    r"backlog|capex|demand|supply|profit|balance sheet|fundamental|estimate|consensus)\b|"
    r"营收|利润|利润率|估值|现金流|指引|订单|需求|供给|基本面",
    re.I,
)
FLOW_RE = re.compile(r"\b(options? flow|gamma|short interest|squeeze|oi|unusual flow|0dte|calls?|puts?)\b", re.I)
CONDITIONAL_SETUP_RE = re.compile(
    r"\b(if|when|once|unless|needs? to|must|waiting for|wait for|requires?|"
    r"confirmation|confirmed breakout|breakout above|break above|hold above|holds? support|"
    r"pivot off|setup|no trade until|watch(?:ing)? for)\b|如果|若|一旦|需要|等待|确认|站稳|守住",
    re.I,
)
WATCHLIST_RE = re.compile(r"\b(watchlist|watching|on watch|keep an eye|monitor|观察|关注|候选)\b", re.I)
INVALIDATE_BULL_RE = re.compile(
    r"\b(broke below|breaks? below|lost (?:its )?(?:the )?(?:50 )?(?:ema|sma|support)|"
    r"lost support|failed breakout|breakout failed|invalidated|no attractive long setup|"
    r"no long setup|no technical reason to .*go long|neither occurred|sellers? (?:have )?taken control|"
    r"bearish follow-through|weakness .*confirm|prior support .*resistance|momentum .*downside|"
    r"until .*stabilization|demand returning)\b|跌破|失守|多头.*失效|没有.*看多|无.*做多|支撑.*转为阻力",
    re.I,
)
INVALIDATE_BEAR_RE = re.compile(
    r"\b(broke above|breaks? above|reclaimed|reclaims|invalidated .*short|no attractive short setup|"
    r"no short setup|no technical reason to .*short|buyers? (?:have )?taken control|"
    r"bullish follow-through|prior resistance .*support)\b|突破|收复|空头.*失效|没有.*看空|无.*做空",
    re.I,
)

SV_SYSTEM = (
    "You structure public equity-market posts or videos into tradable calls for Smart Account scoring. "
    "Judge only the specified ticker, but first understand whether the post is a single-ticker call, "
    "a basket/sector thesis, a pair trade, a portfolio update, a retrospective, or merely context. "
    "Do not decide whether the call was correct. "
    "An actionable call must be the CONTENT AUTHOR'S OWN forward-looking directional forecast, explicit "
    "position action, or directional risk-management action for the specified ticker. "
    "News reporting, market briefs, past price-move recaps, corporate announcements, earnings-result recaps, "
    "gainer/loser lists, analyst targets, quoted third-party views, jokes, reposts, retrospective brags, "
    "pure chart observations without direction, and watchlist mentions are non-actionable. "
    "Never turn a historical move such as 'AMD surged on a partnership' into a bullish forecast. "
    "Never treat a current price, reported analyst target, or price printed in market data as the author's target. "
    "If the specified ticker is only a comparison, ecosystem reference, or context mention, mark it non-actionable "
    "or set ticker_role to context/comparison/excluded. "
    "If it contains a conditional trade plan, it can be actionable if direction is clear. "
    "For every actionable call, evidence_span must be a short VERBATIM quote from the content that itself expresses "
    "the author's forecast or position action. If no such exact quote exists, mark it non-actionable. "
    "Return strict JSON only with these fields: "
    "{\"is_actionable_call\":boolean,\"direction\":\"bull|bear|neutral\","
    "\"horizon_bucket\":\"1D|5D|20D|60D|90D|180D|unknown\",\"horizon_explicit\":boolean,"
    "\"target_price\":number|null,\"conviction_score\":number,"
    "\"evidence_score\":number,\"specificity_score\":number,"
    "\"call_type\":\"single_ticker_call|basket_call|pair_trade|sector_call|portfolio_update|retrospective|context_mention\","
    "\"ticker_role\":\"primary|basket_member|context|comparison|excluded\","
    "\"ticker_relevance\":number,"
    "\"target_price_owner\":\"ticker symbol if a target price belongs to a specific ticker else empty\","
    "\"investor_style\":\"fundamental|technical|event_driven|macro|flow_momentum|mixed|unknown\","
    "\"call_structure\":\"conviction_call|conditional_setup|invalidation_call|watchlist|risk_update|reversal_call|retrospective\","
    "\"lifecycle_action\":\"open_call|reinforce_call|invalidate_prior_call|close_prior_call|reverse_call|no_trade_setup|retrospective|none\","
    "\"affected_direction\":\"bull|bear|unknown\","
    "\"entry_status\":\"active_entry|conditional_setup|watchlist_only|not_applicable\","
    "\"trigger_condition\":\"short trigger condition if any else empty\","
    "\"invalidation_condition\":\"short invalidation condition if any else empty\","
    "\"evidence_span\":\"short original quote supporting this ticker call\","
    "\"statement_mode\":\"prediction|position_action|risk_management|education|news|retrospective|other\","
    "\"instrument_scope\":\"stock|options|portfolio|other\","
    "\"option_strategy\":\"none|covered_call|protective_put|cash_secured_put|speculative_call|speculative_put|spread|other\","
    "\"underlying_direction\":\"bull|bear|neutral|unknown\","
    "\"call_owner\":\"post_author|named_guest|quoted_third_party|unknown\","
    "\"host_endorsement\":\"explicit|implicit|none|opposes\","
    "\"summary_zh\":\"short Chinese summary\",\"summary_en\":\"short English summary\","
    "\"exclusion_reason\":\"short reason if non-actionable else empty\"}. "
    "Scoring fields are 0..1. evidence_score measures reasoning/data quality, not correctness. "
    "specificity_score measures explicit ticker/target/entry/condition/horizon detail. "
    "ticker_relevance is 0..1 and should be low if the ticker is one of many basket members. "
    "Simple but clear calls are valid. Detailed wrongness is not judged here."
)

SV_X_AUDIT_SYSTEM = (
    "You audit existing X/Twitter Smart Account calls for attribution errors. "
    "The previous extraction is untrusted. A call survives only when the POST AUTHOR personally makes a "
    "forward-looking bull/bear forecast, states an actual position action, or gives directional risk management "
    "for the specified ticker. News reporting, market briefs, historical price recaps, company announcements, "
    "earnings recaps, analyst targets, quoted views, and lists of movers are not the author's call. "
    "For example, 'AMD surged on an OpenAI partnership' is past news and must be rejected. "
    "Do not infer a forecast from positive or negative facts. The evidence_span must be a short exact verbatim "
    "substring of the supplied post that itself proves the author-owned direction. "
    "Return strict JSON only: {\"items\":[{"
    "\"candidate_id\":\"exact supplied id\","
    "\"is_author_owned_call\":boolean,"
    "\"direction\":\"bull|bear|neutral\","
    "\"statement_mode\":\"prediction|position_action|risk_management|education|news|retrospective|other\","
    "\"call_owner\":\"post_author|quoted_third_party|unknown\","
    "\"call_type\":\"single_ticker_call|basket_call|pair_trade|sector_call|portfolio_update|retrospective|context_mention\","
    "\"ticker_role\":\"primary|basket_member|context|comparison|excluded\","
    "\"evidence_span\":\"exact quote or empty\","
    "\"target_price_is_authored\":boolean,"
    "\"exclusion_reason\":\"short reason when rejected\"}]}. "
    "Return one item for every supplied candidate_id and preserve each id exactly."
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
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_ticker_created
          ON sv_call_candidate(ticker, created_at);
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_author ON sv_call_candidate(author_id);
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_created ON sv_call_candidate(created_at);
        CREATE INDEX IF NOT EXISTS idx_sv_candidate_source_rank
          ON sv_call_candidate(source, candidate_rank, heuristic_score, interactions);

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
          investor_style TEXT DEFAULT 'unknown',
          call_structure TEXT DEFAULT '',
          lifecycle_action TEXT DEFAULT '',
          affected_direction TEXT DEFAULT 'unknown',
          entry_status TEXT DEFAULT '',
          trigger_condition TEXT DEFAULT '',
          invalidation_condition TEXT DEFAULT '',
          evidence_span TEXT DEFAULT '',
          evidence_segment_start INTEGER,
          evidence_segment_end INTEGER,
          statement_mode TEXT DEFAULT '',
          instrument_scope TEXT DEFAULT '',
          option_strategy TEXT DEFAULT '',
          underlying_direction TEXT DEFAULT 'unknown',
          call_owner TEXT DEFAULT 'unknown',
          host_endorsement TEXT DEFAULT 'none',
          transcript_model TEXT DEFAULT '',
          transcript_created_at TEXT DEFAULT '',
          transcript_version TEXT DEFAULT '',
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
        CREATE INDEX IF NOT EXISTS idx_sv_call_source ON sv_call(source);
        CREATE INDEX IF NOT EXISTS idx_sv_call_ticker_action_created
          ON sv_call(ticker, is_actionable_call, direction, created_at);

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
          max_favorable_excess REAL,
          peak_day TEXT,
          time_to_peak_days INTEGER,
          positive_day_share REAL,
          avg_directional_excess REAL,
          retracement REAL,
          endpoint_component REAL,
          opportunity_component REAL,
          persistence_component REAL,
          retracement_penalty REAL,
          exit_reason TEXT DEFAULT 'horizon',
          superseded_by_candidate_id TEXT,
          status TEXT NOT NULL,
          PRIMARY KEY(candidate_id, horizon)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_settle_investor ON sv_call_settlement(investor_id);
        CREATE INDEX IF NOT EXISTS idx_sv_settle_ticker ON sv_call_settlement(ticker);
        CREATE INDEX IF NOT EXISTS idx_sv_settle_ticker_status_investor
          ON sv_call_settlement(ticker, status, investor_id, candidate_id);

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

        CREATE TABLE IF NOT EXISTS sv_investor_score_snapshot (
          run_id TEXT NOT NULL,
          scoring_version TEXT NOT NULL,
          created_at TEXT NOT NULL,
          investor_id TEXT NOT NULL,
          source TEXT NOT NULL,
          name TEXT,
          handle TEXT,
          language TEXT,
          sv REAL,
          raw_z REAL,
          rank_no INTEGER,
          confidence TEXT,
          n_eff REAL,
          settled_calls INTEGER,
          active_days INTEGER,
          covered_tickers INTEGER,
          horizon_scores_json TEXT,
          ticker_scores_json TEXT,
          concentration_json TEXT,
          PRIMARY KEY(run_id, investor_id)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_snapshot_created ON sv_investor_score_snapshot(created_at);
        CREATE INDEX IF NOT EXISTS idx_sv_snapshot_investor ON sv_investor_score_snapshot(investor_id);
        """
    )
    existing_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_call)").fetchall()}
    extra_cols = {
        "call_type": "TEXT DEFAULT ''",
        "ticker_role": "TEXT DEFAULT ''",
        "ticker_relevance": "REAL DEFAULT 0",
        "target_price_owner": "TEXT DEFAULT ''",
        "investor_style": "TEXT DEFAULT 'unknown'",
        "call_structure": "TEXT DEFAULT ''",
        "lifecycle_action": "TEXT DEFAULT ''",
        "affected_direction": "TEXT DEFAULT 'unknown'",
        "entry_status": "TEXT DEFAULT ''",
        "trigger_condition": "TEXT DEFAULT ''",
        "invalidation_condition": "TEXT DEFAULT ''",
        "evidence_span": "TEXT DEFAULT ''",
        "evidence_segment_start": "INTEGER",
        "evidence_segment_end": "INTEGER",
        "statement_mode": "TEXT DEFAULT ''",
        "instrument_scope": "TEXT DEFAULT ''",
        "option_strategy": "TEXT DEFAULT ''",
        "underlying_direction": "TEXT DEFAULT 'unknown'",
        "call_owner": "TEXT DEFAULT 'unknown'",
        "host_endorsement": "TEXT DEFAULT 'none'",
        "transcript_model": "TEXT DEFAULT ''",
        "transcript_created_at": "TEXT DEFAULT ''",
        "transcript_version": "TEXT DEFAULT ''",
        "scoring_version": "TEXT DEFAULT 'v0'",
    }
    for name, ddl in extra_cols.items():
        if name not in existing_cols:
            con.execute(f"ALTER TABLE sv_call ADD COLUMN {name} {ddl}")
    existing_settle_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_call_settlement)").fetchall()}
    extra_settle_cols = {
        "is_primary_horizon": "INTEGER NOT NULL DEFAULT 0",
        "settlement_version": "TEXT DEFAULT ''",
        "market_auc": "REAL",
        "market_mean_auc": "REAL",
        "market_integral_component": "REAL",
        "market_terminal_component": "REAL",
        "market_positive_area": "REAL",
        "market_negative_area": "REAL",
        "market_adverse_area_share": "REAL",
        "industry_benchmark_ticker": "TEXT",
        "industry_benchmark_method": "TEXT",
        "industry_benchmark_entry_price": "REAL",
        "industry_benchmark_exit_price": "REAL",
        "industry_benchmark_return_pct": "REAL",
        "industry_excess_return_pct": "REAL",
        "industry_expected_hit": "REAL",
        "industry_actual_hit": "INTEGER",
        "industry_score_weight": "REAL",
        "industry_contribution": "REAL",
        "industry_auc": "REAL",
        "industry_mean_auc": "REAL",
        "industry_integral_component": "REAL",
        "industry_terminal_component": "REAL",
        "industry_positive_area": "REAL",
        "industry_negative_area": "REAL",
        "industry_adverse_area_share": "REAL",
        "industry_status": "TEXT DEFAULT 'unavailable'",
        "max_favorable_excess": "REAL",
        "peak_day": "TEXT",
        "time_to_peak_days": "INTEGER",
        "positive_day_share": "REAL",
        "avg_directional_excess": "REAL",
        "retracement": "REAL",
        "endpoint_component": "REAL",
        "opportunity_component": "REAL",
        "persistence_component": "REAL",
        "retracement_penalty": "REAL",
        "exit_reason": "TEXT DEFAULT 'horizon'",
        "superseded_by_candidate_id": "TEXT",
    }
    for name, ddl in extra_settle_cols.items():
        if name not in existing_settle_cols:
            con.execute(f"ALTER TABLE sv_call_settlement ADD COLUMN {name} {ddl}")
    existing_score_cols = {r["name"] for r in con.execute("PRAGMA table_info(sv_investor_score)").fetchall()}
    extra_score_cols = {
        "ability_scores_json": "TEXT",
        "concentration_json": "TEXT",
    }
    for name, ddl in extra_score_cols.items():
        if name not in existing_score_cols:
            con.execute(f"ALTER TABLE sv_investor_score ADD COLUMN {name} {ddl}")
    existing_snapshot_cols = {
        r["name"]
        for r in con.execute("PRAGMA table_info(sv_investor_score_snapshot)").fetchall()
    }
    if "ability_scores_json" not in existing_snapshot_cols:
        con.execute(
            "ALTER TABLE sv_investor_score_snapshot ADD COLUMN ability_scores_json TEXT"
        )
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


def source_set(raw: str | None) -> set[str]:
    values = {x.strip().lower() for x in (raw or "").split(",") if x.strip()}
    if not values or "all" in values:
        return set(SV_PLATFORMS)
    unknown = values - SV_PLATFORMS
    if unknown:
        raise SystemExit(f"[sv-v0] unsupported source(s): {', '.join(sorted(unknown))}")
    return values


def investor_key(source: str, raw_id: str) -> str:
    raw = str(raw_id or "").strip()
    if not raw:
        return ""
    if source != "x":
        return f"{source}:{raw.lower()}"
    return raw


def table_columns(con: sqlite3.Connection, name: str) -> set[str]:
    try:
        return {str(r["name"]) for r in con.execute(f"PRAGMA table_info({name})").fetchall()}
    except sqlite3.DatabaseError:
        return set()


def table_exists(con: sqlite3.Connection, name: str) -> bool:
    return bool(table_columns(con, name))


def youtube_candidate_eligibility_predicate(
    con: sqlite3.Connection,
    candidate_alias: str = "cc",
) -> str:
    """Return the shared YouTube subscriber/duration eligibility predicate."""
    checks: list[str] = []
    if table_exists(con, "yt_video") and table_exists(con, "yt_channel"):
        checks.append(
            f"EXISTS (SELECT 1 FROM yt_video yv JOIN yt_channel yc ON yc.channel_id=yv.channel_id "
            f"WHERE yv.id={candidate_alias}.tweet_id "
            f"AND COALESCE(yv.duration_s,0)>{YOUTUBE_MIN_DISPLAY_DURATION_SECONDS} "
            f"AND COALESCE(yc.subscriber_count,0)>={YOUTUBE_MIN_DISPLAY_SUBSCRIBERS})"
        )
    if all(
        table_exists(con, name)
        for name in ("yt_channel_upload", "yt_author_pool", "yt_author_pool_run")
    ):
        checks.append(
            f"EXISTS (SELECT 1 FROM yt_channel_upload yu JOIN yt_author_pool yp "
            f"ON yp.channel_id=yu.channel_id AND yp.pool_version=(SELECT pool_version "
            f"FROM yt_author_pool_run ORDER BY created_at DESC LIMIT 1) AND yp.selected=1 "
            f"WHERE yu.video_id={candidate_alias}.tweet_id "
            f"AND COALESCE(yu.duration_s,0)>{YOUTUBE_MIN_DISPLAY_DURATION_SECONDS} "
            f"AND COALESCE(yp.subscriber_count,0)>={YOUTUBE_MIN_DISPLAY_SUBSCRIBERS})"
        )
    return f"({' OR '.join(checks)})" if checks else "0"


def sv_extract_provider_order() -> list[str]:
    raw = os.environ.get("SV_EXTRACT_PROVIDERS", "qwen,deepseek,gemini")
    providers: list[str] = []
    for item in raw.split(","):
        provider = item.strip().lower()
        if provider in {"qwen", "deepseek", "gemini"} and provider not in providers:
            providers.append(provider)
    return providers or ["qwen", "deepseek", "gemini"]


def sv_audit_provider_order() -> list[str]:
    raw = os.environ.get(
        "SV_AUDIT_PROVIDERS",
        os.environ.get("SV_EXTRACT_PROVIDERS", "qwen,deepseek,gemini"),
    )
    providers: list[str] = []
    for item in raw.split(","):
        provider = item.strip().lower()
        if provider in {"qwen", "deepseek", "gemini"} and provider not in providers:
            providers.append(provider)
    return providers or ["qwen", "deepseek", "gemini"]


def sv_extract_provider_available(provider: str) -> bool:
    if provider == "qwen":
        return llm.available(llm.LOW)
    if provider == "deepseek":
        return settings.has_deepseek
    if provider == "gemini":
        return settings.has_gemini
    return False


def sv_extract_model_label(provider: str) -> str:
    if provider == "qwen":
        return llm.model_label(llm.LOW)
    if provider == "deepseek":
        return f"deepseek:{settings.deepseek_model_low}"
    return f"gemini:{settings.gemini_model}"


def sv_extract_messages_json(
    provider: str,
    system: str,
    prompt: str,
    max_tokens: int,
) -> dict[str, Any] | None:
    try:
        if provider == "qwen":
            return llm.messages_json(llm.LOW, system, prompt, max_tokens=max_tokens)
        if provider == "deepseek":
            return deepseek.messages_json(
                system,
                prompt,
                model=settings.deepseek_model_low,
                max_tokens=max_tokens,
            )
        if provider == "gemini":
            return gemini.messages_json(
                system,
                prompt,
                model=settings.gemini_model,
                max_tokens=max_tokens,
            )
    except Exception:
        return None
    return None


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


def reddit_interactions(row: sqlite3.Row) -> float:
    return (
        max(0.0, float(row["score"] or 0))
        + max(0.0, float(row["num_comments"] or 0)) * 2
        + max(0.0, float(row["total_awards"] or 0)) * 3
    )


def reddit_url(row: sqlite3.Row) -> str:
    permalink = str(row["permalink"] or "")
    if permalink.startswith("http"):
        return permalink
    if permalink:
        return "https://www.reddit.com" + permalink
    return str(row["url"] or "")


def reddit_candidate_tuple(row: sqlite3.Row, ticker: str, score: float, reason: str, rank: int) -> tuple:
    post_id = str(row["id"] or "")
    created = str(row["created_utc"] or "")
    title = str(row["title"] or "").strip()
    body = str(row["selftext"] or "").strip()
    text = f"{title}\n\n{body}".strip()
    author = str(row["author_id"] or "")
    return (
        f"reddit:{post_id}:{ticker}",
        post_id,
        ticker,
        "reddit",
        investor_key("reddit", author),
        author,
        created,
        created[:10],
        "reddit_post",
        "en",
        text,
        reddit_url(row),
        int(row["score"] or 0),
        0,
        int(row["num_comments"] or 0),
        0,
        0,
        int(row["total_awards"] or 0),
        reddit_interactions(row),
        score,
        reason,
        rank,
        f"reddit:{row['source'] or 'scan'}:{row['subreddit_id'] or ''}",
        utc_now(),
    )


def latest_xueqiu_pool_version(con: sqlite3.Connection) -> str:
    if not table_exists(con, "xueqiu_author_pool"):
        return ""
    row = con.execute(
        """SELECT pool_version
             FROM xueqiu_author_pool
            WHERE selected=1
            GROUP BY pool_version
            ORDER BY MAX(updated_at) DESC, pool_version DESC
            LIMIT 1"""
    ).fetchone()
    return str(row["pool_version"] or "") if row else ""


def xueqiu_pool_completion(con: sqlite3.Connection, pool_version: str) -> tuple[int, int]:
    row = con.execute(
        """SELECT COUNT(*) AS total,
                  SUM(CASE WHEN EXISTS (
                        SELECT 1 FROM xueqiu_author_crawl_job j
                         WHERE j.pool_version=p.pool_version
                           AND j.user_id=p.user_id
                           AND j.status='done'
                  ) THEN 1 ELSE 0 END) AS done
             FROM xueqiu_author_pool p
            WHERE p.pool_version=?
              AND p.selected=1
              AND p.author_type='creator'""",
        (pool_version,),
    ).fetchone()
    return int(row["total"] or 0), int(row["done"] or 0)


def xueqiu_payload(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    try:
        value = json.loads(raw or "{}")
    except (TypeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def xueqiu_clean_text(row: sqlite3.Row) -> str:
    payload = xueqiu_payload(row["raw"])
    title = str(payload.get("title") or "").strip()
    body = html.unescape(re.sub(r"<[^>]+>", " ", str(row["text"] or "")))
    body = re.sub(r"\s+", " ", body).strip()
    if title and title not in body:
        return f"{title}\n\n{body}".strip()
    return body


def xueqiu_interactions(row: sqlite3.Row) -> float:
    return (
        max(0.0, float(row["like_count"] or 0))
        + max(0.0, float(row["reply_count"] or 0)) * 2.0
        + max(0.0, float(row["retweet_count"] or 0)) * 2.0
        + math.log1p(max(0.0, float(row["view_count"] or 0))) * 0.25
    )


def xueqiu_candidate_tuple(
    row: sqlite3.Row,
    pool_version: str,
    score: float,
    reason: str,
    rank: int,
) -> tuple:
    post_id = str(row["native_id"] or "")
    ticker = str(row["ticker"] or "").upper()
    author_id = str(row["author_id"] or "")
    created = str(row["created_utc"] or "")
    return (
        f"xueqiu:{post_id}:{ticker}",
        post_id,
        ticker,
        "xueqiu",
        investor_key("xueqiu", author_id),
        str(row["author"] or author_id),
        created,
        created[:10],
        "xueqiu_post",
        str(row["lang"] or "zh"),
        xueqiu_clean_text(row),
        str(row["url"] or ""),
        int(row["like_count"] or 0),
        int(row["retweet_count"] or 0),
        int(row["reply_count"] or 0),
        0,
        int(row["view_count"] or 0),
        0,
        xueqiu_interactions(row),
        score,
        reason,
        rank,
        f"xueqiu:pool={pool_version}:mapping={row['role']}:{float(row['confidence'] or 0):.2f}",
        utc_now(),
    )


def build_xueqiu_candidates(
    con: sqlite3.Connection,
    limit: int,
    min_score: float,
    only: set[str] | None,
    pool_version: str,
    since_days: int,
    require_complete_pool: bool = True,
) -> int:
    ensure_tables(con)
    required = {
        "xueqiu_raw_post",
        "xueqiu_post_ticker",
        "xueqiu_author_pool",
        "xueqiu_author_crawl_job",
    }
    if not all(table_exists(con, name) for name in required):
        print("[sv-v0] xueqiu author-pool tables missing; skip xueqiu candidates.", flush=True)
        return 0
    pool_version = pool_version or latest_xueqiu_pool_version(con)
    if not pool_version:
        print("[sv-v0] xueqiu selected pool missing; skip xueqiu candidates.", flush=True)
        return 0
    total_authors, done_authors = xueqiu_pool_completion(con, pool_version)
    if total_authors == 0:
        print(f"[sv-v0] xueqiu pool {pool_version} has no selected creators.", flush=True)
        return 0
    if require_complete_pool and done_authors < total_authors:
        print(
            f"[sv-v0] xueqiu pool incomplete: {done_authors}/{total_authors} done; "
            "candidate recall is gated until the one-year pool is complete.",
            flush=True,
        )
        return 0

    valid = price_tickers(con) - NON_CALL_TAGS
    if only:
        valid &= only
    max_created = con.execute(
        """SELECT MAX(r.created_utc) AS mx
             FROM xueqiu_raw_post r
             JOIN xueqiu_author_pool p ON p.user_id=r.author_id
            WHERE p.pool_version=? AND p.selected=1 AND p.author_type='creator'""",
        (pool_version,),
    ).fetchone()
    max_day = str(max_created["mx"] or utc_now())[:10]
    cutoff = (
        dt.datetime.fromisoformat(max_day) - dt.timedelta(days=max(1, since_days))
    ).strftime("%Y-%m-%d")
    rows = con.execute(
        """SELECT r.*, m.ticker, m.role, m.confidence
             FROM xueqiu_raw_post r
             JOIN xueqiu_post_ticker m ON m.native_id=r.native_id
             JOIN xueqiu_author_pool p
               ON p.user_id=r.author_id AND p.pool_version=?
             JOIN xueqiu_author_crawl_job j
               ON j.user_id=r.author_id AND j.pool_version=p.pool_version
            WHERE p.selected=1
              AND p.author_type='creator'
              AND j.status='done'
              AND r.created_utc>=?
              AND r.created_utc>=j.since_utc
              AND (j.until_utc IS NULL OR r.created_utc<=j.until_utc)
              AND m.confidence>=0.65""",
        (pool_version, cutoff),
    ).fetchall()

    heap: list[tuple[float, int, tuple]] = []
    batch: list[tuple] = []
    scanned = matched = inserted = 0
    seq = 0
    for row in rows:
        scanned += 1
        ticker = str(row["ticker"] or "").upper()
        if ticker not in valid:
            continue
        payload = xueqiu_payload(row["raw"])
        if payload.get("retweeted_status") or payload.get("retweeted_status_id"):
            continue
        text = xueqiu_clean_text(row)
        if len(text) < 40:
            continue
        h_score, h_reason = heuristic(text)
        mapping_confidence = clamp(norm_num(row["confidence"], 0.0), 0.0, 1.0)
        score = (
            h_score
            + mapping_confidence * 8.0
            + min(14.0, math.log1p(xueqiu_interactions(row)) * 2.0)
            + (4.0 if len(text) >= 240 else 0.0)
        )
        if score < min_score:
            continue
        reasons = [x for x in h_reason.split(",") if x]
        reasons += [f"mapping={row['role']}:{mapping_confidence:.2f}", "selected_pool"]
        matched += 1
        priority = score * 10 + math.log1p(xueqiu_interactions(row)) * 2
        seq += 1
        item = xueqiu_candidate_tuple(row, pool_version, score, ",".join(reasons), 0)
        if limit > 0:
            wrapped = (priority, seq, item)
            if len(heap) < limit:
                heapq.heappush(heap, wrapped)
            elif wrapped > heap[0]:
                heapq.heapreplace(heap, wrapped)
        else:
            batch.append(item)
            if len(batch) >= 1000:
                before = con.total_changes
                insert_candidates(con, batch)
                con.commit()
                inserted += con.total_changes - before
                batch.clear()

    if limit > 0:
        ordered = [x[2] for x in sorted(heap, key=lambda x: (-x[0], x[1]))]
        ranked = []
        for index, row in enumerate(ordered, 1):
            values = list(row)
            values[21] = index
            ranked.append(tuple(values))
        before = con.total_changes
        insert_candidates(con, ranked)
        con.commit()
        inserted += con.total_changes - before
    elif batch:
        before = con.total_changes
        insert_candidates(con, batch)
        con.commit()
        inserted += con.total_changes - before
    print(
        f"[sv-v0] xueqiu candidates scanned={scanned} matched={matched} "
        f"authors={done_authors}/{total_authors} inserted={inserted} "
        f"since_days={since_days} limit={limit}",
        flush=True,
    )
    return inserted


def json_text_list(raw: Any, limit: int = 6) -> list[str]:
    try:
        value = json.loads(raw or "[]")
    except (TypeError, json.JSONDecodeError):
        value = raw
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()][:limit]
    if isinstance(value, str) and value.strip():
        return [value.strip()[:400]]
    return []


def youtube_interactions(row: sqlite3.Row) -> float:
    return (
        max(0.0, float(row["view_count"] or 0)) * 0.01
        + max(0.0, float(row["like_count"] or 0)) * 2.0
        + max(0.0, float(row["comment_count"] or 0)) * 3.0
    )


def youtube_candidate_text(row: sqlite3.Row) -> str:
    parts = [
        f"Video title: {row['title'] or ''}",
        f"Channel: {row['channel'] or row['channel_title'] or ''}",
        f"Description: {str(row['description'] or '')[:900]}",
    ]
    if row["stance"] or row["summary_zh"] or row["summary_en"]:
        parts.append(
            "Prior video analysis: "
            f"stance={row['stance'] or 'unknown'}, conviction={row['conviction'] or ''}, "
            f"summary_zh={row['summary_zh'] or ''}, summary_en={row['summary_en'] or ''}"
        )
    points = json_text_list(row["key_points_zh"]) or json_text_list(row["key_points_en"])
    if points:
        parts.append("Analysis points:\n" + "\n".join(f"- {p[:220]}" for p in points[:6]))
    digest = json_text_list(row["digest_summary_zh"]) or json_text_list(row["digest_summary_en"])
    if digest:
        parts.append("Investor digest:\n" + "\n".join(f"- {p[:220]}" for p in digest[:7]))
    chapters = []
    try:
        chapters_raw = json.loads(row["chapters"] or "[]")
        if isinstance(chapters_raw, list):
            for ch in chapters_raw[:8]:
                if isinstance(ch, dict):
                    label = ch.get("t_en") or ch.get("t_zh") or ""
                    if label:
                        chapters.append(str(label).strip())
    except json.JSONDecodeError:
        chapters = []
    if chapters:
        parts.append("Chapters: " + " | ".join(chapters))
    judgment = []
    for label, key in [
        ("horizon", "horizon_en"),
        ("target", "target"),
        ("key levels", "key_levels_en"),
    ]:
        value = str(row[key] or "").strip()
        if value:
            judgment.append(f"{label}: {value}")
    if not judgment:
        for label, key in [("horizon", "horizon_zh"), ("key levels", "key_levels_zh")]:
            value = str(row[key] or "").strip()
            if value:
                judgment.append(f"{label}: {value}")
    if row["price_target"]:
        judgment.append(f"raw price target: {row['price_target']}")
    if judgment:
        parts.append("Structured judgment: " + "; ".join(judgment))
    fulltext = str(row["content_en"] or row["content_zh"] or "").strip()
    if fulltext:
        parts.append("Transcript excerpt:\n" + fulltext[:1800])
    return "\n\n".join(p for p in parts if p.strip())


def youtube_candidate_tuple(row: sqlite3.Row, score: float, reason: str, rank: int) -> tuple:
    video_id = str(row["id"] or "")
    ticker = str(row["ticker"] or "").upper()
    created = str(row["published_utc"] or "")
    channel_id = str(row["channel_id"] or "")
    handle = str(row["handle"] or row["channel"] or row["channel_title"] or channel_id)
    text = youtube_candidate_text(row)
    mapping_method = str(row["mapping_method"] or "legacy")
    mapping_confidence = clamp(norm_num(row["mapping_confidence"], 1.0), 0.0, 1.0)
    return (
        f"youtube:{video_id}:{ticker}",
        video_id,
        ticker,
        "youtube",
        investor_key("youtube", channel_id),
        handle,
        created,
        created[:10],
        "youtube_video",
        str(row["lang"] or row["default_language"] or row["inferred_language"] or ""),
        text,
        str(row["url"] or ""),
        int(row["like_count"] or 0),
        0,
        int(row["comment_count"] or 0),
        0,
        int(row["view_count"] or 0),
        0,
        youtube_interactions(row),
        score,
        reason,
        rank,
        f"youtube:subs>={row['subscriber_count'] or 0}:mapping={mapping_method}:{mapping_confidence:.2f}:"
        f"transcript={'yes' if row['content_en'] or row['content_zh'] else 'no'}",
        utc_now(),
    )


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


def reddit_author_pool(
    con: sqlite3.Connection,
    limit: int,
    since_days: int,
    min_posts: int,
) -> set[str]:
    if limit <= 0:
        return set()
    max_created = con.execute("SELECT MAX(created_utc) AS mx FROM posts WHERE market='us'").fetchone()
    max_day = str(max_created["mx"] or utc_now())[:10]
    cutoff = (
        dt.datetime.fromisoformat(max_day)
        - dt.timedelta(days=max(1, since_days))
    ).strftime("%Y-%m-%d")
    rows = con.execute(
        """
        SELECT p.author_id,
               COUNT(DISTINCT p.id) AS posts,
               COUNT(DISTINCT m.ticker) AS tickers,
               COALESCE(SUM(MAX(p.score, 0) + 2 * MAX(p.num_comments, 0)), 0) AS engagement,
               AVG(COALESCE(ia.quality_score, 0.35)) AS quality,
               SUM(CASE WHEN ia.stance IN ('bull','bear') THEN 1 ELSE 0 END) AS directional
          FROM posts p
          JOIN mentions m ON m.item_id=p.id AND m.item_type='post'
          LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
         WHERE p.market='us'
           AND p.author_id IS NOT NULL
           AND p.author_id NOT IN ('[deleted]', 'None')
           AND p.created_utc >= ?
         GROUP BY p.author_id
        HAVING posts >= ?
        """,
        (cutoff, max(1, min_posts)),
    ).fetchall()
    scored = []
    for r in rows:
        posts = int(r["posts"] or 0)
        tickers = int(r["tickers"] or 0)
        engagement = float(r["engagement"] or 0)
        quality = clamp(float(r["quality"] or 0.35), 0.0, 1.0)
        directional = int(r["directional"] or 0)
        score = (
            quality * 3.0
            + math.log1p(engagement) * 0.75
            + math.log1p(posts) * 0.9
            + math.log1p(tickers) * 0.8
            + (directional / max(1, posts)) * 1.2
        )
        scored.append((score, engagement, posts, str(r["author_id"])))
    scored.sort(key=lambda x: (-x[0], -x[1], -x[2], x[3].lower()))
    return {author for _, _, _, author in scored[:limit]}


def build_reddit_candidates(
    con: sqlite3.Connection,
    limit: int,
    min_score: float,
    only: set[str] | None,
    author_limit: int,
    since_days: int,
    min_author_posts: int,
) -> int:
    ensure_tables(con)
    valid = price_tickers(con) - NON_CALL_TAGS
    if only:
        valid &= only
    author_pool = reddit_author_pool(con, author_limit, since_days, min_author_posts)
    if author_limit > 0 and not author_pool:
        print("[sv-v0] reddit author pool empty; skip reddit candidates.", flush=True)
        return 0
    max_created = con.execute("SELECT MAX(created_utc) AS mx FROM posts WHERE market='us'").fetchone()
    max_day = str(max_created["mx"] or utc_now())[:10]
    cutoff = (
        dt.datetime.fromisoformat(max_day)
        - dt.timedelta(days=max(1, since_days))
    ).strftime("%Y-%m-%d")
    rows = con.execute(
        """
        SELECT p.id, p.subreddit_id, p.author_id, p.title, p.selftext, p.url, p.permalink,
               p.source, p.created_utc, p.score, p.num_comments, p.total_awards,
               m.ticker, m.confidence AS mention_confidence,
               ia.quality_score, ia.stance, ia.sentiment_score
          FROM posts p
          JOIN mentions m ON m.item_id=p.id AND m.item_type='post'
          LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
         WHERE p.market='us'
           AND p.author_id IS NOT NULL
           AND p.author_id NOT IN ('[deleted]', 'None')
           AND p.created_utc >= ?
        """,
        (cutoff,),
    ).fetchall()
    heap: list[tuple[float, int, tuple]] = []
    batch: list[tuple] = []
    scanned = matched = inserted = 0
    seq = 0
    for row in rows:
        scanned += 1
        author = str(row["author_id"] or "")
        if author_pool and author not in author_pool:
            continue
        ticker = str(row["ticker"] or "").upper()
        if ticker not in valid:
            continue
        title = str(row["title"] or "")
        body = str(row["selftext"] or "")
        if body in {"[removed]", "[deleted]"}:
            body = ""
        text = f"{title}\n{body}".strip()
        if len(text) < 40:
            continue
        h_score, h_reason = heuristic(text)
        quality = clamp(norm_num(row["quality_score"], 0.35), 0.0, 1.0)
        mention_conf = clamp(norm_num(row["mention_confidence"], 0.0), 0.0, 1.0)
        stance = str(row["stance"] or "")
        score = (
            h_score
            + quality * 14
            + mention_conf * 8
            + min(14.0, math.log1p(reddit_interactions(row)) * 2.25)
            + (6.0 if stance in {"bull", "bear"} else 0.0)
            + (4.0 if len(text) >= 240 else 0.0)
        )
        if score < min_score:
            continue
        reasons = [x for x in h_reason.split(",") if x]
        reasons += [f"quality={quality:.2f}", f"mention={mention_conf:.2f}"]
        if stance in {"bull", "bear"}:
            reasons.append(f"stance={stance}")
        matched += 1
        priority = score * 10 + math.log1p(reddit_interactions(row)) * 2
        seq += 1
        item = reddit_candidate_tuple(row, ticker, score, ",".join(reasons), 0)
        if limit > 0:
            wrapped = (priority, seq, item)
            if len(heap) < limit:
                heapq.heappush(heap, wrapped)
            elif wrapped > heap[0]:
                heapq.heapreplace(heap, wrapped)
        else:
            batch.append(item)
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
    print(
        f"[sv-v0] reddit candidates scanned={scanned} matched={matched} "
        f"authors={len(author_pool) if author_pool else 'all'} inserted={inserted} "
        f"since_days={since_days} limit={limit}",
        flush=True,
    )
    return inserted


def build_youtube_candidates(
    con: sqlite3.Connection,
    limit: int,
    min_score: float,
    only: set[str] | None,
    min_subscribers: int,
    since_days: int,
) -> int:
    ensure_tables(con)
    min_subscribers = max(min_subscribers, YOUTUBE_MIN_DISPLAY_SUBSCRIBERS)
    legacy_available = table_exists(con, "yt_video") and table_exists(con, "yt_channel")
    upload_tables = {
        "yt_channel_upload",
        "yt_channel_upload_ticker",
        "yt_author_pool",
        "yt_author_pool_run",
    }
    upload_available = all(table_exists(con, name) for name in upload_tables)
    if not legacy_available and not upload_available:
        print(
            "[sv-v0] youtube candidate sources missing: expected yt_video+yt_channel "
            "or the versioned author-upload tables; skip youtube candidates.",
            flush=True,
        )
        return 0
    valid = price_tickers(con) - NON_CALL_TAGS
    if only:
        valid &= only
    max_dates: list[str] = []
    if legacy_available:
        row = con.execute(
            "SELECT MAX(published_utc) AS mx FROM yt_video WHERE market='us'"
        ).fetchone()
        if row and row["mx"]:
            max_dates.append(str(row["mx"])[:10])
    if upload_available:
        row = con.execute("SELECT MAX(published_utc) AS mx FROM yt_channel_upload").fetchone()
        if row and row["mx"]:
            max_dates.append(str(row["mx"])[:10])
    max_day = max(max_dates) if max_dates else utc_now()[:10]
    cutoff = (
        dt.datetime.fromisoformat(max_day)
        - dt.timedelta(days=max(1, since_days))
    ).strftime("%Y-%m-%d")
    optional_tables = {
        name: table_columns(con, name)
        for name in ("yt_analysis", "yt_digest", "yt_fulltext", "yt_judgment")
    }
    def can_join(table: str) -> bool:
        return "video_id" in optional_tables.get(table, set())

    def optional_joins(video_id_expression: str) -> str:
        joins: list[str] = []
        if can_join("yt_analysis"):
            joins.append(f"LEFT JOIN yt_analysis a ON a.video_id = {video_id_expression}")
        if can_join("yt_digest"):
            joins.append(f"LEFT JOIN yt_digest d ON d.video_id = {video_id_expression}")
        if can_join("yt_fulltext"):
            joins.append(f"LEFT JOIN yt_fulltext f ON f.video_id = {video_id_expression}")
        if can_join("yt_judgment"):
            joins.append(f"LEFT JOIN yt_judgment j ON j.video_id = {video_id_expression}")
        return " ".join(joins)

    def opt_col(table: str, alias: str, column: str, out: str | None = None, default: str = "''") -> str:
        output = out or column
        if can_join(table) and column in optional_tables.get(table, set()):
            return f"{alias}.{column} AS {output}"
        return f"{default} AS {output}"

    optional_projection = ",\n               ".join(
        [
            opt_col("yt_analysis", "a", "stance"),
            opt_col("yt_analysis", "a", "sentiment", default="0"),
            opt_col("yt_analysis", "a", "conviction", default="0"),
            opt_col("yt_analysis", "a", "summary_zh"),
            opt_col("yt_analysis", "a", "summary_en"),
            opt_col("yt_analysis", "a", "key_points_zh"),
            opt_col("yt_analysis", "a", "key_points_en"),
            opt_col("yt_analysis", "a", "price_target"),
            opt_col("yt_digest", "d", "summary_zh", "digest_summary_zh"),
            opt_col("yt_digest", "d", "summary_en", "digest_summary_en"),
            opt_col("yt_digest", "d", "chapters"),
            opt_col("yt_fulltext", "f", "content_zh"),
            opt_col("yt_fulltext", "f", "content_en"),
            opt_col("yt_judgment", "j", "horizon_zh"),
            opt_col("yt_judgment", "j", "horizon_en"),
            opt_col("yt_judgment", "j", "target"),
            opt_col("yt_judgment", "j", "key_levels_zh"),
            opt_col("yt_judgment", "j", "key_levels_en"),
        ]
    )
    pool_version = ""
    if upload_available:
        latest_pool = con.execute(
            "SELECT pool_version FROM yt_author_pool_run ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
        pool_version = str(latest_pool["pool_version"] or "") if latest_pool else ""
    rows: list[sqlite3.Row] = []
    if legacy_available:
        legacy_pool_join = (
            "JOIN yt_author_pool lp ON lp.channel_id=v.channel_id "
            "AND lp.pool_version=? AND lp.selected=1"
            if pool_version
            else ""
        )
        legacy_params: list[Any] = []
        if pool_version:
            legacy_params.append(pool_version)
        legacy_params.extend(
            [cutoff, max(0, min_subscribers), YOUTUBE_MIN_DISPLAY_DURATION_SECONDS]
        )
        rows.extend(
            con.execute(
                f"""
                SELECT v.id, v.ticker, v.market, v.channel, v.channel_id, v.title, v.description,
                       v.lang, '' AS default_language, '' AS inferred_language,
                       v.duration_s, v.view_count, v.like_count, v.comment_count, v.url, v.published_utc,
                       c.title AS channel_title, c.handle, c.subscriber_count,
                       c.video_count AS channel_video_count, c.view_count AS channel_view_count,
                       {optional_projection},
                       1.0 AS mapping_confidence, 'legacy' AS mapping_method
                  FROM yt_video v
                  JOIN yt_channel c ON c.channel_id = v.channel_id
                  {legacy_pool_join}
                  {optional_joins("v.id")}
                 WHERE v.market = 'us'
                   AND v.published_utc >= ?
                   AND COALESCE(c.subscriber_count, 0) >= ?
                   AND COALESCE(v.duration_s, 0) > ?
                """,
                legacy_params,
            ).fetchall()
        )
    if upload_available:
        legacy_exclusion = (
            "AND NOT EXISTS (SELECT 1 FROM yt_video lv "
            "WHERE lv.id=u.video_id AND lv.ticker=m.ticker)"
            if legacy_available
            else ""
        )
        rows.extend(
            con.execute(
                f"""
                SELECT u.video_id AS id, m.ticker, 'us' AS market,
                       COALESCE(NULLIF(p.handle, ''), NULLIF(u.channel_title, ''), p.title) AS channel,
                       u.channel_id, u.title, u.description,
                       u.default_language AS lang, u.default_language, '' AS inferred_language,
                       u.duration_s, u.view_count, u.like_count, u.comment_count,
                       u.url, u.published_utc,
                       COALESCE(NULLIF(p.title, ''), u.channel_title) AS channel_title,
                       p.handle, p.subscriber_count,
                       p.platform_video_count AS channel_video_count, 0 AS channel_view_count,
                       {optional_projection},
                       m.confidence AS mapping_confidence, m.method AS mapping_method
                  FROM yt_channel_upload u
                  JOIN yt_channel_upload_ticker m ON m.video_id=u.video_id
                  JOIN yt_author_pool p
                    ON p.channel_id=u.channel_id AND p.pool_version=? AND p.selected=1
                  {optional_joins("u.video_id")}
                 WHERE u.published_utc >= ?
                   AND m.mapping_version=?
                   AND m.confidence>=?
                   AND COALESCE(p.subscriber_count, 0) >= ?
                   AND COALESCE(u.duration_s, 0) > ?
                   {legacy_exclusion}
                """,
                (
                    pool_version,
                    cutoff,
                    YOUTUBE_UPLOAD_MAPPING_VERSION,
                    YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE,
                    max(0, min_subscribers),
                    YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
                ),
            ).fetchall()
        )
    heap: list[tuple[float, int, tuple]] = []
    batch: list[tuple] = []
    scanned = matched = inserted = 0
    seq = 0
    for row in rows:
        scanned += 1
        ticker = str(row["ticker"] or "").upper()
        if ticker not in valid:
            continue
        text = youtube_candidate_text(row)
        if len(text) < 60:
            continue
        h_score, h_reason = heuristic(text)
        stance = str(row["stance"] or "").lower()
        conviction = clamp(norm_num(row["conviction"], 0.0), 0.0, 1.0)
        has_target = bool(str(row["target"] or row["price_target"] or "").strip())
        has_horizon = bool(str(row["horizon_en"] or row["horizon_zh"] or "").strip())
        has_fulltext = bool(str(row["content_en"] or row["content_zh"] or "").strip())
        mapping_method = str(row["mapping_method"] or "legacy")
        mapping_confidence = clamp(norm_num(row["mapping_confidence"], 1.0), 0.0, 1.0)
        mapping_bonus = mapping_confidence * 8.0 if mapping_method != "legacy" else 0.0
        score = (
            h_score
            + (8.0 if stance in {"bull", "bear"} else 0.0)
            + conviction * 10.0
            + (8.0 if has_target else 0.0)
            + (5.0 if has_horizon else 0.0)
            + (5.0 if row["digest_summary_zh"] or row["digest_summary_en"] else 0.0)
            + (3.0 if has_fulltext else 0.0)
            + min(14.0, math.log1p(youtube_interactions(row)) * 1.6)
            + mapping_bonus
        )
        if score < min_score:
            continue
        reasons = [x for x in h_reason.split(",") if x]
        if stance in {"bull", "bear", "neutral"}:
            reasons.append(f"stance={stance}")
        if has_target:
            reasons.append("target")
        if has_horizon:
            reasons.append("horizon")
        if has_fulltext:
            reasons.append("transcript")
        if mapping_method != "legacy":
            reasons.append(f"mapping={mapping_method}:{mapping_confidence:.2f}")
        matched += 1
        priority = score * 10 + math.log1p(youtube_interactions(row)) * 2
        seq += 1
        item = youtube_candidate_tuple(row, score, ",".join(reasons), 0)
        if limit > 0:
            wrapped = (priority, seq, item)
            if len(heap) < limit:
                heapq.heappush(heap, wrapped)
            elif wrapped > heap[0]:
                heapq.heapreplace(heap, wrapped)
        else:
            batch.append(item)
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
    print(
        f"[sv-v0] youtube candidates scanned={scanned} matched={matched} "
        f"min_subscribers={min_subscribers} inserted={inserted} since_days={since_days} limit={limit}",
        flush=True,
    )
    return inserted


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
    investor_style = str(d.get("investor_style") or "unknown").strip().lower()
    if investor_style not in INVESTOR_STYLES:
        investor_style = "unknown"
    call_structure = str(d.get("call_structure") or "").strip().lower()
    if call_structure not in CALL_STRUCTURES:
        call_structure = "conviction_call" if actionable else ""
    lifecycle_action = str(d.get("lifecycle_action") or "").strip().lower()
    if lifecycle_action not in LIFECYCLE_ACTIONS:
        lifecycle_action = "open_call" if actionable else "none"
    affected_direction = str(d.get("affected_direction") or "unknown").strip().lower()
    if affected_direction not in {"bull", "bear", "unknown"}:
        affected_direction = "unknown"
    entry_status = str(d.get("entry_status") or "").strip().lower()
    if entry_status not in ENTRY_STATUSES:
        entry_status = "active_entry" if actionable else "not_applicable"
    evidence_span = str(d.get("evidence_span") or "")[:360]
    statement_mode = str(d.get("statement_mode") or "other").strip().lower()
    if statement_mode not in {
        "prediction", "position_action", "risk_management", "education",
        "news", "retrospective", "other",
    }:
        statement_mode = "other"
    instrument_scope = str(d.get("instrument_scope") or "other").strip().lower()
    if instrument_scope not in {"stock", "options", "portfolio", "other"}:
        instrument_scope = "other"
    option_strategy = str(d.get("option_strategy") or "none").strip().lower()
    if option_strategy not in {
        "none", "covered_call", "protective_put", "cash_secured_put",
        "speculative_call", "speculative_put", "spread", "other",
    }:
        option_strategy = "other"
    underlying_direction = str(d.get("underlying_direction") or "unknown").strip().lower()
    if underlying_direction not in {"bull", "bear", "neutral", "unknown"}:
        underlying_direction = "unknown"
    call_owner = str(d.get("call_owner") or "unknown").strip().lower()
    if call_owner not in {
        "post_author", "channel_host", "named_guest", "quoted_third_party", "unknown",
    }:
        call_owner = "unknown"
    host_endorsement = str(d.get("host_endorsement") or "none").strip().lower()
    if host_endorsement not in {"explicit", "implicit", "none", "opposes"}:
        host_endorsement = "none"
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
        "investor_style": investor_style,
        "call_structure": call_structure,
        "lifecycle_action": lifecycle_action,
        "affected_direction": affected_direction,
        "entry_status": entry_status,
        "trigger_condition": str(d.get("trigger_condition") or "")[:240],
        "invalidation_condition": str(d.get("invalidation_condition") or "")[:240],
        "evidence_span": evidence_span,
        "evidence_segment_start": d.get("evidence_segment_start"),
        "evidence_segment_end": d.get("evidence_segment_end"),
        "statement_mode": statement_mode,
        "instrument_scope": instrument_scope,
        "option_strategy": option_strategy,
        "underlying_direction": underlying_direction,
        "call_owner": call_owner,
        "host_endorsement": host_endorsement,
        "transcript_model": str(d.get("transcript_model") or "")[:120],
        "transcript_created_at": str(d.get("transcript_created_at") or "")[:64],
        "transcript_version": str(d.get("transcript_version") or "")[:80],
        "scoring_version": SV_SCORING_VERSION,
        "summary_zh": str(d.get("summary_zh") or "")[:240],
        "summary_en": str(d.get("summary_en") or "")[:240],
        "exclusion_reason": str(d.get("exclusion_reason") or "")[:180],
    }


def user_prompt(row: sqlite3.Row) -> str:
    source = str(row["source"] or "x")
    item_label = {
        "reddit": "Reddit post",
        "youtube": "YouTube video",
    }.get(source, "Tweet")
    text_cap = 5200 if source == "youtube" else 2200
    return (
        f"Ticker to judge: {row['ticker']}\n"
        f"Source: {source}\n"
        f"Created at: {row['created_at']}\n"
        f"{item_label} type: {row['tweet_type']}\n"
        f"Language: {row['lang']}\n"
        f"Heuristic reason: {row['reason']}\n"
        f"{item_label} text:\n"
        f"{str(row['text'])[:text_cap]}"
    )


def write_call(con: sqlite3.Connection, candidate: sqlite3.Row, norm: dict[str, Any], model: str) -> None:
    con.execute(
        """INSERT INTO sv_call
           (candidate_id,tweet_id,ticker,source,investor_id,author_handle,created_at,language,
            is_actionable_call,direction,horizon_bucket,horizon_explicit,target_price,
            conviction_score,evidence_score,specificity_score,call_weight,call_type,ticker_role,
            ticker_relevance,target_price_owner,investor_style,call_structure,lifecycle_action,
            affected_direction,entry_status,trigger_condition,invalidation_condition,
            evidence_span,evidence_segment_start,evidence_segment_end,statement_mode,
            instrument_scope,option_strategy,underlying_direction,call_owner,host_endorsement,transcript_model,
            transcript_created_at,transcript_version,scoring_version,summary_zh,summary_en,
            exclusion_reason,model,tagged_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
             investor_style=excluded.investor_style,
             call_structure=excluded.call_structure,
             lifecycle_action=excluded.lifecycle_action,
             affected_direction=excluded.affected_direction,
             entry_status=excluded.entry_status,
             trigger_condition=excluded.trigger_condition,
             invalidation_condition=excluded.invalidation_condition,
             evidence_span=excluded.evidence_span,
             evidence_segment_start=excluded.evidence_segment_start,
             evidence_segment_end=excluded.evidence_segment_end,
             statement_mode=excluded.statement_mode,
             instrument_scope=excluded.instrument_scope,
             option_strategy=excluded.option_strategy,
             underlying_direction=excluded.underlying_direction,
             call_owner=excluded.call_owner,
             host_endorsement=excluded.host_endorsement,
             transcript_model=excluded.transcript_model,
             transcript_created_at=excluded.transcript_created_at,
             transcript_version=excluded.transcript_version,
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
            candidate["source"] or "x",
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
            norm["investor_style"],
            norm["call_structure"],
            norm["lifecycle_action"],
            norm["affected_direction"],
            norm["entry_status"],
            norm["trigger_condition"],
            norm["invalidation_condition"],
            norm["evidence_span"],
            norm["evidence_segment_start"],
            norm["evidence_segment_end"],
            norm["statement_mode"],
            norm["instrument_scope"],
            norm["option_strategy"],
            norm["underlying_direction"],
            norm["call_owner"],
            norm["host_endorsement"],
            norm["transcript_model"],
            norm["transcript_created_at"],
            norm["transcript_version"],
            norm["scoring_version"],
            norm["summary_zh"],
            norm["summary_en"],
            norm["exclusion_reason"],
            model,
            utc_now(),
        ),
    )


def ranked_candidate_rows(
    con: sqlite3.Connection,
    limit: int,
    force: bool,
    sources: set[str] | None = None,
    transcript_backed: bool = False,
    tickers: set[str] | None = None,
    youtube_created_since: str | None = None,
    reddit_created_since: str | None = None,
) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[Any] = []
    if not force:
        clauses.append(
            "(c.candidate_id IS NULL OR (cc.source='youtube' "
            "AND (COALESCE(c.scoring_version,'')<>? "
            "OR COALESCE(c.transcript_version,'')<>?)))"
        )
        params.extend([SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION])
    if sources:
        placeholders = ",".join("?" for _ in sources)
        clauses.append(f"cc.source IN ({placeholders})")
        params.extend(sorted(sources))
        if "youtube" in sources:
            clauses.append(
                f"(cc.source<>'youtube' OR {youtube_candidate_eligibility_predicate(con, 'cc')})"
            )
        if (
            "youtube" in sources
            and table_exists(con, "yt_author_pool")
            and table_exists(con, "yt_author_pool_run")
        ):
            clauses.append(
                "(cc.source <> 'youtube' OR cc.author_id IN ("
                "SELECT 'youtube:' || lower(p.channel_id) FROM yt_author_pool p "
                "WHERE p.pool_version=(SELECT pool_version FROM yt_author_pool_run "
                "ORDER BY created_at DESC LIMIT 1) AND p.selected=1))"
            )
        if "youtube" in sources and table_exists(con, "yt_channel_upload_ticker"):
            clauses.append(
                "(cc.source <> 'youtube' OR COALESCE(cc.source_file, '') NOT LIKE '%mapping=%' "
                "OR cc.source_file LIKE '%mapping=legacy:%' OR EXISTS ("
                "SELECT 1 FROM yt_channel_upload_ticker ym "
                "WHERE ym.video_id=cc.tweet_id AND ym.ticker=cc.ticker "
                "AND ym.mapping_version=? AND ym.confidence>=?))"
            )
            params.extend(
                [YOUTUBE_UPLOAD_MAPPING_VERSION, YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE]
            )
        if "youtube" in sources and transcript_backed:
            if table_exists(con, "yt_fulltext"):
                clauses.append(
                    "(cc.source<>'youtube' OR EXISTS (SELECT 1 FROM yt_fulltext yf "
                    "WHERE yf.video_id=cc.tweet_id AND "
                    "length(COALESCE(yf.content_en,'') || COALESCE(yf.content_zh,''))>=80))"
                )
            else:
                clauses.append("cc.source<>'youtube'")
    if tickers:
        placeholders = ",".join("?" for _ in tickers)
        clauses.append(f"cc.ticker IN ({placeholders})")
        params.extend(sorted(tickers))
    if youtube_created_since:
        clauses.append("(cc.source<>'youtube' OR cc.created_at>=?)")
        params.append(youtube_created_since)
    if reddit_created_since:
        clauses.append("(cc.source<>'reddit' OR cc.created_at>=?)")
        params.append(reddit_created_since)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    sql = f"""
        SELECT cc.*
          FROM sv_call_candidate cc
          LEFT JOIN sv_call c ON c.candidate_id = cc.candidate_id
          {where}
         ORDER BY COALESCE(cc.candidate_rank, 999999999), cc.heuristic_score DESC, cc.interactions DESC
         LIMIT ?
    """
    params.append(limit if limit > 0 else 1_000_000_000)
    return con.execute(sql, params).fetchall()


def author_balanced_candidate_rows(
    con: sqlite3.Connection,
    limit: int,
    force: bool,
    per_author_min: int,
    per_author_max: int,
    sources: set[str] | None = None,
    transcript_backed: bool = False,
    author_filter: set[str] | None = None,
    tickers: set[str] | None = None,
    youtube_created_since: str | None = None,
    reddit_created_since: str | None = None,
) -> list[sqlite3.Row]:
    rows = ranked_candidate_rows(
        con,
        0,
        force,
        sources,
        transcript_backed=transcript_backed,
        tickers=tickers,
        youtube_created_since=youtube_created_since,
        reddit_created_since=reddit_created_since,
    )
    if not rows:
        return []
    if limit <= 0:
        limit = len(rows)
    per_author_min = max(1, per_author_min)
    per_author_max = max(per_author_min, per_author_max)

    existing = collections.Counter()
    actionable = collections.Counter()
    if not force:
        sql = (
            "SELECT investor_id, count(*) AS n FROM sv_call "
            "WHERE (source<>'youtube' OR (scoring_version=? AND transcript_version=?))"
        )
        params: list[Any] = [SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION]
        if sources:
            placeholders = ",".join("?" for _ in sources)
            sql += f" AND source IN ({placeholders})"
            params.extend(sorted(sources))
        sql += " GROUP BY investor_id"
        for r in con.execute(sql, params):
            if r["investor_id"]:
                existing[str(r["investor_id"])] = int(r["n"] or 0)

        action_sql = (
            "SELECT investor_id, count(*) AS n FROM sv_call "
            "WHERE is_actionable_call=1 "
            "AND (source<>'youtube' OR (scoring_version=? AND transcript_version=?))"
        )
        action_params: list[Any] = [SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION]
        if sources:
            placeholders = ",".join("?" for _ in sources)
            action_sql += f" AND source IN ({placeholders})"
            action_params.extend(sorted(sources))
        action_sql += " GROUP BY investor_id"
        for r in con.execute(action_sql, action_params):
            if r["investor_id"]:
                actionable[str(r["investor_id"])] = int(r["n"] or 0)

    by_author: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    for row in rows:
        author = str(row["author_id"] or row["author_handle"] or "unknown")
        if author_filter is not None and author not in author_filter:
            continue
        by_author[author].append(row)
    if not by_author:
        return []

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
            actionable[a] >= int(PLATFORM_QUALIFICATION.get("youtube", {}).get("settled_calls", 5))
            if sources == {"youtube"} else False,
            -actionable[a] if sources == {"youtube"} else 0,
            min(existing[a], per_author_min),
            -(len(by_author[a])),
            by_author[a][0]["candidate_rank"] or 999999999,
        ),
    )

    # Phase 1: round-robin authors toward the production minimum. Filling one
    # author completely before moving on wastes small paid batches on a narrow
    # creator set and delays confidence-pool coverage.
    while len(selected) < limit:
        moved = False
        for author in authors:
            current = existing[author] + selected_counts[author]
            if current >= per_author_min:
                continue
            before = len(selected)
            take(author, 1)
            moved = moved or len(selected) > before
            if len(selected) >= limit:
                break
        if not moved:
            break

    # Phase 2: round-robin extra slots, capped per author, still preserving each
    # author's internal rank order.
    allocation_authors = authors
    if sources == {"youtube"} and author_filter is None:
        qualification_calls = int(PLATFORM_QUALIFICATION["youtube"]["settled_calls"])
        allocation_authors = [author for author in authors if actionable[author] < qualification_calls]
    while len(selected) < limit:
        moved = False
        for author in allocation_authors:
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


def load_youtube_transcript_documents(
    con: sqlite3.Connection,
    rows: list[sqlite3.Row],
) -> dict[str, TranscriptDocument]:
    if not table_exists(con, "yt_fulltext"):
        return {}
    video_ids = sorted(
        {
            str(row["tweet_id"])
            for row in rows
            if str(row["source"] or "x") == "youtube" and row["tweet_id"]
        }
    )
    documents: dict[str, TranscriptDocument] = {}
    for offset in range(0, len(video_ids), 500):
        batch = video_ids[offset : offset + 500]
        placeholders = ",".join("?" for _ in batch)
        for row in con.execute(
            f"""SELECT video_id,content_zh,content_en,segments,model,created_at
                  FROM yt_fulltext WHERE video_id IN ({placeholders})""",
            batch,
        ):
            document = transcript_document(row)
            if document is not None:
                documents[document.video_id] = document
    return documents


def youtube_transcript_candidate_rows(
    con: sqlite3.Connection,
    limit: int,
    per_author_min: int,
    per_author_max: int,
    force: bool,
    tickers: set[str] | None = None,
    created_since: str | None = None,
) -> list[sqlite3.Row]:
    """Select unique author-balanced videos that still need full transcripts."""
    rows = ranked_candidate_rows(
        con,
        0,
        True,
        {"youtube"},
        tickers=tickers,
        youtube_created_since=created_since,
    )
    if not rows:
        return []
    documents = load_youtube_transcript_documents(con, rows) if not force else {}
    existing_video_ids = set(documents)
    existing_by_author: collections.Counter[str] = collections.Counter()
    actionable_by_author: collections.Counter[str] = collections.Counter()
    if not force:
        for call_row in con.execute(
            """SELECT investor_id, count(*) AS n
                 FROM sv_call
                WHERE source='youtube'
                  AND scoring_version=?
                  AND transcript_version=?
                  AND is_actionable_call=1
                GROUP BY investor_id""",
            (SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION),
        ):
            if call_row["investor_id"]:
                actionable_by_author[str(call_row["investor_id"])] = int(call_row["n"] or 0)
    by_author: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    seen_by_author: dict[str, set[str]] = collections.defaultdict(set)
    for row in rows:
        author = str(row["author_id"] or row["author_handle"] or "unknown")
        video_id = str(row["tweet_id"] or "")
        if not video_id or video_id in seen_by_author[author]:
            continue
        seen_by_author[author].add(video_id)
        if video_id in existing_video_ids:
            existing_by_author[author] += 1
        else:
            by_author[author].append(row)
    if limit <= 0:
        limit = sum(len(items) for items in by_author.values())
    per_author_min = max(1, per_author_min)
    per_author_max = max(per_author_min, per_author_max)
    authors = sorted(
        by_author,
        key=lambda author: (
            actionable_by_author[author] >= int(PLATFORM_QUALIFICATION["youtube"]["settled_calls"]),
            -min(
                actionable_by_author[author],
                int(PLATFORM_QUALIFICATION["youtube"]["settled_calls"]),
            ),
            min(existing_by_author[author], per_author_min),
            -len(by_author[author]),
            by_author[author][0]["candidate_rank"] or 999999999,
        ),
    )
    selected: list[sqlite3.Row] = []
    selected_by_author: collections.Counter[str] = collections.Counter()

    def take(author: str, count: int) -> None:
        while by_author[author] and count > 0 and len(selected) < limit:
            selected.append(by_author[author].pop(0))
            selected_by_author[author] += 1
            count -= 1

    qualification_calls = int(PLATFORM_QUALIFICATION["youtube"]["settled_calls"])

    # Authors one or two calls below readiness need more than one candidate to
    # have a reasonable chance of crossing the threshold in this batch. This
    # only allocates transcript work; it does not alter settlement or scoring.
    for author in authors:
        deficit = qualification_calls - actionable_by_author[author]
        burst = 3 if deficit == 1 else 2 if deficit == 2 else 0
        if burst <= 0:
            continue
        capacity = max(
            0,
            per_author_max - existing_by_author[author] - selected_by_author[author],
        )
        take(author, min(burst, capacity))
        if len(selected) >= limit:
            break

    # Spread each batch across not-yet-ready authors before deepening any one
    # channel. Ready authors do not consume migration capacity while the
    # confidence pool is still below its launch target.
    unready_authors = [
        author for author in authors
        if actionable_by_author[author] < qualification_calls
    ]
    while len(selected) < limit:
        moved = False
        for author in unready_authors:
            current = existing_by_author[author] + selected_by_author[author]
            if current >= per_author_max or not by_author[author]:
                continue
            before = len(selected)
            take(author, 1)
            moved = moved or len(selected) > before
            if len(selected) >= limit:
                break
        if not moved:
            break
    while len(selected) < limit:
        moved = False
        for author in authors:
            current = existing_by_author[author] + selected_by_author[author]
            if current >= per_author_max or not by_author[author]:
                continue
            before = len(selected)
            take(author, 1)
            moved = moved or len(selected) > before
            if len(selected) >= limit:
                break
        if not moved:
            break
    return selected


def materialize_youtube_transcript_videos(
    con: sqlite3.Connection,
    rows: list[sqlite3.Row],
) -> set[str]:
    """Expose author-pool uploads to the existing fulltext generator."""
    if not rows or not table_exists(con, "yt_video"):
        return set()
    best_by_video: dict[str, sqlite3.Row] = {}
    for row in rows:
        best_by_video.setdefault(str(row["tweet_id"]), row)
    video_ids = sorted(best_by_video)
    materialized: set[str] = set()
    for offset in range(0, len(video_ids), 500):
        batch = video_ids[offset : offset + 500]
        placeholders = ",".join("?" for _ in batch)
        materialized.update(
            str(row["id"])
            for row in con.execute(
                f"SELECT id FROM yt_video WHERE id IN ({placeholders})",
                batch,
            )
        )
        uploads = con.execute(
            f"""SELECT * FROM yt_channel_upload
                  WHERE video_id IN ({placeholders})""",
            batch,
        ).fetchall()
        for upload in uploads:
            video_id = str(upload["video_id"])
            candidate = best_by_video[video_id]
            con.execute(
                """INSERT INTO yt_video
                   (id,ticker,market,channel,channel_id,title,description,lang,duration_s,
                    view_count,like_count,comment_count,thumbnail,url,published_utc,analyzed,fetched_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     ticker=excluded.ticker,market=excluded.market,channel=excluded.channel,
                     channel_id=excluded.channel_id,title=excluded.title,description=excluded.description,
                     lang=excluded.lang,duration_s=excluded.duration_s,view_count=excluded.view_count,
                     like_count=excluded.like_count,comment_count=excluded.comment_count,
                     thumbnail=excluded.thumbnail,url=excluded.url,published_utc=excluded.published_utc,
                     fetched_at=excluded.fetched_at""",
                (
                    video_id,
                    str(candidate["ticker"] or "").upper(),
                    "us",
                    str(upload["channel_title"] or candidate["author_handle"] or ""),
                    str(upload["channel_id"] or ""),
                    str(upload["title"] or ""),
                    str(upload["description"] or ""),
                    str(upload["default_language"] or candidate["lang"] or ""),
                    int(upload["duration_s"] or 0),
                    int(upload["view_count"] or 0),
                    int(upload["like_count"] or 0),
                    int(upload["comment_count"] or 0),
                    str(upload["thumbnail"] or ""),
                    str(upload["url"] or ""),
                    str(upload["published_utc"] or ""),
                    0,
                    utc_now(),
                ),
            )
            materialized.add(video_id)
    con.commit()
    return materialized


def generate_youtube_candidate_transcripts(
    con: sqlite3.Connection,
    limit: int,
    workers: int,
    per_author_min: int,
    per_author_max: int,
    force: bool,
    tickers: set[str] | None = None,
    created_since: str | None = None,
) -> int:
    rows = youtube_transcript_candidate_rows(
        con,
        limit,
        per_author_min,
        per_author_max,
        force,
        tickers,
        created_since,
    )
    video_ids = materialize_youtube_transcript_videos(con, rows)
    print(
        f"[sv-v0] youtube transcript queue selected={len(rows)} "
        f"materialized={len(video_ids)}",
        flush=True,
    )
    if not video_ids:
        return 0
    from ..opinions.youtube import generate_fulltext

    return generate_fulltext(
        only=None,
        per_ticker=0,
        workers=workers,
        force=force,
        low_res=True,
        frames=False,
        limit=limit if limit > 0 else None,
        # Gemini rejects inputs at the documented 10,800-second boundary;
        # keep a strict margin instead of retrying a deterministic 400.
        max_native_min=179,
        fail_after=3,
        max_rate_waits=12,
        video_ids=video_ids,
        db_path=DB,
        max_total_minutes=settings.yt_daily_video_minutes,
        prefer_transcript=True,
    )


def extract_calls(
    con: sqlite3.Connection,
    limit: int,
    workers: int,
    force: bool,
    extract_mode: str,
    per_author_min: int,
    per_author_max: int,
    sources: set[str] | None = None,
    author_filter: set[str] | None = None,
    tickers: set[str] | None = None,
    youtube_created_since: str | None = None,
    reddit_created_since: str | None = None,
) -> int:
    ensure_tables(con)
    providers = [
        provider
        for provider in sv_extract_provider_order()
        if sv_extract_provider_available(provider)
    ]
    if not providers:
        print("[sv-v0] no extraction provider key available; extraction skipped.", flush=True)
        return 0
    if extract_mode == "author-balanced":
        rows = author_balanced_candidate_rows(
            con,
            limit,
            force,
            per_author_min,
            per_author_max,
            sources,
            transcript_backed=True,
            author_filter=author_filter,
            tickers=tickers,
            youtube_created_since=youtube_created_since,
            reddit_created_since=reddit_created_since,
        )
    else:
        rows = ranked_candidate_rows(
            con,
            limit,
            force,
            sources,
            transcript_backed=True,
            tickers=tickers,
            youtube_created_since=youtube_created_since,
            reddit_created_since=reddit_created_since,
        )
    if not rows:
        print("[sv-v0] no candidates need extraction.", flush=True)
        return 0
    youtube_documents = load_youtube_transcript_documents(con, rows)
    transcript_missing = sum(
        1
        for row in rows
        if str(row["source"] or "x") == "youtube"
        and str(row["tweet_id"] or "") not in youtube_documents
    )
    if transcript_missing:
        print(
            f"[sv-v0] youtube transcript gate skipped={transcript_missing}; "
            "run the YouTube Score transcript stage first.",
            flush=True,
        )
    rows = [
        row
        for row in rows
        if str(row["source"] or "x") != "youtube"
        or str(row["tweet_id"] or "") in youtube_documents
    ]
    if not rows:
        print("[sv-v0] no transcript-backed candidates need extraction.", flush=True)
        return 0
    provider_labels = [sv_extract_model_label(provider) for provider in providers]
    print(
        f"[sv-v0] extracting {len(rows)} candidates with "
        f"{' -> '.join(provider_labels)} workers={workers}",
        flush=True,
    )
    done = actionable = fail = 0
    buffer: list[tuple[sqlite3.Row, dict[str, Any], str]] = []

    def request_with_fallback(
        system: str,
        prompt: str,
        max_tokens: int,
    ) -> tuple[dict[str, Any] | None, str]:
        for provider in providers:
            for _ in range(2):
                data = sv_extract_messages_json(provider, system, prompt, max_tokens)
                if isinstance(data, dict):
                    return data, sv_extract_model_label(provider)
        raise RuntimeError(
            "all Smart Account extraction providers failed to return valid JSON"
        )

    def work(row: sqlite3.Row) -> tuple[sqlite3.Row, dict[str, Any], str]:
        if str(row["source"] or "x") == "youtube":
            document = youtube_documents[str(row["tweet_id"])]
            used_models: list[str] = []

            def request_json(system: str, prompt: str) -> Any:
                data, model_label = request_with_fallback(system, prompt, 760)
                if isinstance(data, dict):
                    used_models.append(model_label)
                return data

            norm = extract_from_transcript(
                row, document, request_json=request_json, normalize=normalize_call
            )
            model = "+".join(dict.fromkeys(used_models)) or provider_labels[-1]
            return row, norm, model
        data, model = request_with_fallback(SV_SYSTEM, user_prompt(row), 1_200)
        norm = normalize_call(data)
        norm["ticker"] = str(row["ticker"] or "").upper()
        if str(row["source"] or "x") == "x":
            norm = enforce_x_policy(norm, str(row["text"] or ""))
        norm.pop("ticker", None)
        return row, norm, model

    def flush() -> None:
        nonlocal done, actionable
        if not buffer:
            return
        for cand, norm, model in buffer:
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


def _x_audit_prompt(rows: list[sqlite3.Row]) -> str:
    items = []
    for row in rows:
        items.append(
            {
                "candidate_id": str(row["candidate_id"]),
                "ticker": str(row["ticker"]),
                "created_at": str(row["created_at"] or ""),
                "previous_direction": str(row["direction"] or ""),
                "previous_target_price": row["target_price"],
                "previous_summary": str(row["summary_en"] or row["summary_zh"] or ""),
                "post_text": str(row["source_text"] or "")[:2400],
            }
        )
    return (
        "Audit every item independently. Previous labels are hints only and may be false positives.\n"
        + json.dumps(items, ensure_ascii=False, separators=(",", ":"))
    )


def _x_audit_items(data: Any, rows: list[sqlite3.Row]) -> dict[str, dict[str, Any]] | None:
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        return None
    expected = {str(row["candidate_id"]) for row in rows}
    parsed: dict[str, dict[str, Any]] = {}
    for item in data["items"]:
        if not isinstance(item, dict):
            continue
        candidate_id = str(item.get("candidate_id") or "")
        if candidate_id in expected:
            parsed[candidate_id] = item
    return parsed if set(parsed) == expected else None


def audit_x_calls(
    con: sqlite3.Connection,
    limit: int,
    workers: int,
    force: bool,
    tickers: set[str] | None = None,
    batch_size: int = 10,
) -> int:
    """Batch-audit every active X call for author ownership and verbatim evidence."""
    batch_size = max(
        1,
        int(os.environ.get("SV_AUDIT_BATCH_SIZE", str(batch_size)) or batch_size),
    )
    providers = [
        provider
        for provider in sv_audit_provider_order()
        if sv_extract_provider_available(provider)
    ]
    if not providers:
        print("[sv-v0] no configured provider for X call audit.", flush=True)
        return 0

    clauses = ["s.source='x'", "s.is_actionable_call=1"]
    params: list[Any] = []
    if not force:
        clauses.append("COALESCE(s.model,'') NOT LIKE ?")
        params.append(f"audit:{X_CALL_POLICY_VERSION}:%")
    if tickers:
        placeholders = ",".join("?" for _ in tickers)
        clauses.append(f"s.ticker IN ({placeholders})")
        params.extend(sorted(tickers))
    sql = (
        "SELECT s.*, c.text AS source_text "
        "FROM sv_call s JOIN sv_call_candidate c ON c.candidate_id=s.candidate_id "
        f"WHERE {' AND '.join(clauses)} "
        "ORDER BY s.created_at, s.candidate_id"
    )
    if limit > 0:
        sql += " LIMIT ?"
        params.append(limit)
    rows = list(con.execute(sql, params))
    if not rows:
        print("[sv-v0] no X calls need ownership audit.", flush=True)
        return 0

    batches = [rows[i : i + max(1, batch_size)] for i in range(0, len(rows), max(1, batch_size))]
    labels = [sv_extract_model_label(provider) for provider in providers]
    print(
        f"[sv-v0] auditing {len(rows)} active X calls in {len(batches)} batches "
        f"with {' -> '.join(labels)} workers={workers}",
        flush=True,
    )

    def request_batch(batch: list[sqlite3.Row]) -> tuple[list[sqlite3.Row], dict[str, dict[str, Any]], str]:
        prompt = _x_audit_prompt(batch)
        for provider in providers:
            for _ in range(2):
                data = sv_extract_messages_json(
                    provider,
                    SV_X_AUDIT_SYSTEM,
                    prompt,
                    max(4_000, batch_size * 220),
                )
                parsed = _x_audit_items(data, batch)
                if parsed is not None:
                    return batch, parsed, sv_extract_model_label(provider)
        raise RuntimeError("all Smart Account audit providers failed to return a complete batch")

    audited = kept = rejected = fail = 0
    pending_updates: list[tuple[sqlite3.Row, dict[str, Any], str]] = []

    def flush() -> None:
        nonlocal audited, kept, rejected
        if not pending_updates:
            return
        for row, audit, model_label in pending_updates:
            base = dict(row)
            base.update(
                {
                    "is_actionable_call": bool(audit.get("is_author_owned_call")),
                    "direction": str(audit.get("direction") or "neutral"),
                    "statement_mode": str(audit.get("statement_mode") or "other"),
                    "call_owner": str(audit.get("call_owner") or "unknown"),
                    "call_type": str(audit.get("call_type") or row["call_type"] or ""),
                    "ticker_role": str(audit.get("ticker_role") or row["ticker_role"] or ""),
                    "evidence_span": str(audit.get("evidence_span") or ""),
                    "exclusion_reason": str(audit.get("exclusion_reason") or ""),
                    "target_price": (
                        row["target_price"]
                        if bool(audit.get("target_price_is_authored"))
                        else None
                    ),
                    "target_price_owner": (
                        str(row["ticker"]) if bool(audit.get("target_price_is_authored")) else ""
                    ),
                }
            )
            norm = normalize_call(base)
            norm["ticker"] = str(row["ticker"] or "").upper()
            norm = enforce_x_policy(norm, str(row["source_text"] or ""))
            norm.pop("ticker", None)
            is_kept = int(norm["is_actionable_call"])
            old_model = str(row["model"] or "")
            audit_model = f"audit:{X_CALL_POLICY_VERSION}:{model_label}|base:{old_model}"[:240]
            con.execute(
                """UPDATE sv_call
                      SET is_actionable_call=?, direction=?, horizon_bucket=?, horizon_explicit=?,
                          target_price=?, conviction_score=?, evidence_score=?, specificity_score=?,
                          call_weight=?, call_type=?, ticker_role=?, ticker_relevance=?,
                          target_price_owner=?, investor_style=?, call_structure=?, lifecycle_action=?,
                          affected_direction=?, entry_status=?, trigger_condition=?,
                          invalidation_condition=?, evidence_span=?, statement_mode=?, instrument_scope=?,
                          option_strategy=?, underlying_direction=?, call_owner=?, host_endorsement=?,
                          scoring_version=?, exclusion_reason=?, model=?, tagged_at=?
                    WHERE candidate_id=?""",
                (
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
                    norm["investor_style"],
                    norm["call_structure"],
                    norm["lifecycle_action"],
                    norm["affected_direction"],
                    norm["entry_status"],
                    norm["trigger_condition"],
                    norm["invalidation_condition"],
                    norm["evidence_span"],
                    norm["statement_mode"],
                    norm["instrument_scope"],
                    norm["option_strategy"],
                    norm["underlying_direction"],
                    norm["call_owner"],
                    norm["host_endorsement"],
                    norm["scoring_version"],
                    norm["exclusion_reason"],
                    audit_model,
                    utc_now(),
                    row["candidate_id"],
                ),
            )
            kept += is_kept
            rejected += 1 - is_kept
            audited += 1
        con.commit()
        pending_updates.clear()

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futures = [pool.submit(request_batch, batch) for batch in batches]
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                batch, parsed, model_label = future.result()
                for row in batch:
                    pending_updates.append((row, parsed[str(row["candidate_id"])], model_label))
            except Exception as exc:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [sv-v0] audit failed: {str(exc)[:120]}", flush=True)
            if len(pending_updates) >= 80:
                flush()
            if i % 50 == 0:
                print(
                    f"  [sv-v0] audited batches {i}/{len(batches)} "
                    f"rows={audited}+buf{len(pending_updates)} kept={kept} "
                    f"rejected={rejected} failed_batches={fail}",
                    flush=True,
                )
    flush()
    print(
        f"[sv-v0] X audit done={audited} kept={kept} rejected={rejected} "
        f"failed_batches={fail}",
        flush=True,
    )
    return audited


def load_prices(con: sqlite3.Connection) -> dict[str, list[tuple[str, float]]]:
    out: dict[str, list[tuple[str, float]]] = collections.defaultdict(list)
    for r in con.execute(
        "SELECT ticker, day, COALESCE(adj_close, close) AS px FROM price_daily WHERE close IS NOT NULL ORDER BY ticker, day"
    ):
        out[str(r["ticker"]).upper()].append((str(r["day"]), float(r["px"])))
    return dict(out)


def load_price_bars(con: sqlite3.Connection) -> dict[str, list[dict[str, Any]]]:
    """Load adjusted opens and closes for tradable, point-in-time paths."""
    output: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for row in con.execute(
        """SELECT ticker,day,open,close,adj_close
             FROM price_daily
            WHERE close IS NOT NULL
            ORDER BY ticker,day"""
    ):
        close = float(row["close"] or 0.0)
        adjusted_close = float(row["adj_close"] or close)
        raw_open = float(row["open"] or close)
        if close <= 0 or adjusted_close <= 0 or raw_open <= 0:
            continue
        adjustment = adjusted_close / close
        output[str(row["ticker"]).upper()].append(
            {
                "day": str(row["day"]),
                "open": raw_open * adjustment,
                "close": adjusted_close,
            }
        )
    return dict(output)


def first_bar_after(bars: list[dict[str, Any]], day: str) -> int | None:
    lo, hi = 0, len(bars)
    while lo < hi:
        mid = (lo + hi) // 2
        if str(bars[mid]["day"]) <= day:
            lo = mid + 1
        else:
            hi = mid
    return lo if lo < len(bars) else None


def integral_path_for_benchmark(
    stock_bars: list[dict[str, Any]],
    benchmark_bars: list[dict[str, Any]],
    entry_index: int,
    horizon_steps: int,
    direction: str,
    normalizer: float,
    forced_exit_day: str | None = None,
) -> dict[str, Any] | None:
    """Build one prefix-integral snapshot against a specified benchmark."""
    if entry_index >= len(stock_bars) or horizon_steps <= 0:
        return None
    benchmark_by_day = {str(bar["day"]): bar for bar in benchmark_bars}
    entry_bar = stock_bars[entry_index]
    benchmark_entry = benchmark_by_day.get(str(entry_bar["day"]))
    if not benchmark_entry:
        return None
    stock_entry = float(entry_bar["open"])
    benchmark_entry_price = float(benchmark_entry["open"])
    if stock_entry <= 0 or benchmark_entry_price <= 0:
        return None

    direction_sign = 1.0 if direction == "bull" else -1.0
    path: list[float] = []
    path_days: list[str] = []
    exit_day = ""
    stock_exit = benchmark_exit = 0.0
    exit_reason = "horizon"
    for bar in stock_bars[entry_index:]:
        day = str(bar["day"])
        benchmark_bar = benchmark_by_day.get(day)
        if not benchmark_bar:
            continue
        use_open = bool(forced_exit_day and day >= forced_exit_day)
        stock_point = float(bar["open"] if use_open else bar["close"])
        benchmark_point = float(
            benchmark_bar["open"] if use_open else benchmark_bar["close"]
        )
        stock_return = stock_point / stock_entry - 1.0
        benchmark_return = benchmark_point / benchmark_entry_price - 1.0
        path.append(direction_sign * (stock_return - benchmark_return))
        path_days.append(day)
        exit_day = day
        stock_exit = stock_point
        benchmark_exit = benchmark_point
        if use_open:
            exit_reason = "superseded"
            break
        if len(path) >= horizon_steps:
            break
    if not path:
        return None
    result = integrate_directional_path(path, normalizer)
    if result is None:
        return None
    raw_return = stock_exit / stock_entry - 1.0
    benchmark_return = benchmark_exit / benchmark_entry_price - 1.0
    excess_return = raw_return - benchmark_return
    return {
        "entry_day": str(entry_bar["day"]),
        "exit_day": exit_day,
        "entry_price": stock_entry,
        "exit_price": stock_exit,
        "benchmark_entry_price": benchmark_entry_price,
        "benchmark_exit_price": benchmark_exit,
        "return_pct": raw_return,
        "benchmark_return_pct": benchmark_return,
        "excess_return_pct": excess_return,
        "directional_excess": result.terminal_excess,
        "path_days": path_days,
        "result": result,
        "exit_reason": exit_reason,
        "complete": exit_reason == "superseded" or len(path) >= horizon_steps,
    }


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


def infer_analysis_type(text: str, stored: str = "unknown") -> str:
    stored = (stored or "unknown").lower()
    if stored in INVESTOR_STYLES and stored != "unknown":
        return stored
    technical = len(TECHNICAL_RE.findall(text or ""))
    fundamental = len(FUNDAMENTAL_RE.findall(text or ""))
    flow = len(FLOW_RE.findall(text or ""))
    if flow and flow >= max(technical, fundamental):
        return "flow_momentum"
    if technical >= 2 and technical >= fundamental * 1.5:
        return "technical"
    if fundamental >= 2 and fundamental >= technical:
        return "fundamental"
    if technical and fundamental:
        return "mixed"
    if technical:
        return "technical"
    if fundamental:
        return "fundamental"
    return "unknown"


def infer_structure(text: str, stored: str = "", actionable: bool = True) -> tuple[str, str, str, str]:
    stored = (stored or "").lower()
    if stored in CALL_STRUCTURES:
        structure = stored
    elif INVALIDATE_BULL_RE.search(text or "") or INVALIDATE_BEAR_RE.search(text or ""):
        structure = "invalidation_call"
    elif WATCHLIST_RE.search(text or "") and not actionable:
        structure = "watchlist"
    elif CONDITIONAL_SETUP_RE.search(text or ""):
        structure = "conditional_setup"
    else:
        structure = "conviction_call" if actionable else "watchlist"

    action = "open_call" if actionable else "none"
    affected = "unknown"
    entry_status = "active_entry" if actionable else "not_applicable"
    if structure == "conditional_setup":
        entry_status = "conditional_setup"
    elif structure == "watchlist":
        action = "no_trade_setup"
        entry_status = "watchlist_only"
    elif structure == "invalidation_call":
        action = "invalidate_prior_call"
        entry_status = "not_applicable"
        if INVALIDATE_BULL_RE.search(text or ""):
            affected = "bull"
        elif INVALIDATE_BEAR_RE.search(text or ""):
            affected = "bear"
    elif structure == "reversal_call":
        action = "reverse_call"
    elif structure == "risk_update":
        action = "close_prior_call"
        entry_status = "not_applicable"
    elif structure == "retrospective":
        action = "retrospective"
        entry_status = "not_applicable"
    return structure, action, affected, entry_status


def horizon_factor(call_bucket: str, explicit: int, horizon: str, analysis_type: str = "unknown") -> float:
    base = HORIZON_TYPE_WEIGHTS.get(analysis_type, HORIZON_TYPE_WEIGHTS["unknown"])
    if call_bucket in HORIZONS:
        if call_bucket == horizon:
            primary = 0.65 if explicit else 0.45
            return primary + (1.0 - primary) * base[horizon]
        spillover = 0.35 if explicit else 0.55
        return spillover * base[horizon]
    return base[horizon]


def text_tickers(text: str) -> list[str]:
    tags = re.findall(r"\$([A-Za-z][A-Za-z0-9.]{0,9})", text or "")
    return [t.upper().replace("-", ".") for t in tags if t.upper() not in NON_CALL_TAGS]


def ticker_mentions(text: str, ticker: str) -> int:
    t = re.escape(ticker.upper())
    return len(re.findall(rf"(?<![A-Z0-9])\$?{t}(?![A-Z0-9])", text or "", re.I))


def is_comparison_reference(text: str, ticker: str) -> bool:
    """Detect titles where the ticker is a benchmark, not the recommended asset."""
    match = re.search(r"^Video title:\s*(.+)$", text or "", re.I | re.M)
    lines = str(text or "").splitlines()
    title = match.group(1).strip() if match else (lines[0] if lines else "")
    terms = {ticker.lower()}
    terms.update(
        alias.lower()
        for alias, symbol in ALIASES.items()
        if symbol.upper() == ticker.upper() and len(alias) >= 4
    )
    if not terms:
        return False
    term_pattern = "(?:" + "|".join(
        re.escape(term) for term in sorted(terms, key=len, reverse=True)
    ) + ")"
    patterns = (
        rf"\b(?:the\s+)?(?:next|new|another)\s+{term_pattern}\b",
        rf"\bmiss(?:ed|ing)\b[^\n:!?]{{0,40}}\b{term_pattern}\b",
        rf"\b(?:bigger|better|stronger|cheaper|faster)\s+than\s+{term_pattern}\b",
        rf"\b{term_pattern}\s+(?:killer|alternative|competitor|rival)\b",
    )
    return any(re.search(pattern, title, re.I) for pattern in patterns)


def infer_call_meta(call: sqlite3.Row) -> dict[str, Any]:
    ticker = str(call["ticker"]).upper()
    text = str(call["text"] or "")
    summary = f"{call['summary_zh'] or ''} {call['summary_en'] or ''}"
    combined_text = f"{text}\n{summary}\n{call['evidence_span'] or ''}"
    tags = text_tickers(text)
    unique_tags = sorted(set(tags))
    tag_count = len(unique_tags)
    current_mentions = ticker_mentions(text, ticker)
    summary_mentions = ticker_mentions(summary, ticker)
    comparison_reference = is_comparison_reference(text, ticker)

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
    if comparison_reference:
        call_type = "context_mention"
        role = "comparison"

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
    if comparison_reference:
        relevance = min(relevance, 0.15)

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
    analysis_type = infer_analysis_type(combined_text, str(call["investor_style"] or "unknown"))
    call_structure, lifecycle_action, affected_direction, entry_status = infer_structure(
        combined_text,
        str(call["call_structure"] or ""),
        bool(call["is_actionable_call"]),
    )
    stored_lifecycle = str(call["lifecycle_action"] or "").lower()
    if stored_lifecycle in LIFECYCLE_ACTIONS and stored_lifecycle not in {"", "none"}:
        lifecycle_action = stored_lifecycle
    stored_affected = str(call["affected_direction"] or "unknown").lower()
    if stored_affected in {"bull", "bear"}:
        affected_direction = stored_affected
    stored_entry = str(call["entry_status"] or "").lower()
    if stored_entry in ENTRY_STATUSES and stored_entry:
        entry_status = stored_entry
    structure_mult = {
        "conviction_call": 1.00,
        "conditional_setup": 0.60 if analysis_type == "technical" else 0.70,
        "reversal_call": 0.85,
        "risk_update": 0.35,
        "watchlist": 0.15,
        "invalidation_call": 0.0,
        "retrospective": 0.0,
    }.get(call_structure, 1.0)
    return {
        "call_type": call_type,
        "ticker_role": role,
        "ticker_relevance": relevance,
        "target_price_owner": target_owner,
        "analysis_type": analysis_type,
        "call_structure": call_structure,
        "lifecycle_action": lifecycle_action,
        "affected_direction": affected_direction,
        "entry_status": entry_status,
        "weight_multiplier": type_mult * role_mult * relevance * structure_mult,
        "tag_count": tag_count,
    }


def post_weight_cap(n_calls: int) -> float:
    if n_calls <= 1:
        return 1.8
    return min(2.8, 1.15 + 0.35 * math.sqrt(n_calls))


def resolve_same_entry_day_calls(
    enriched: list[dict[str, Any]],
    prices: dict[str, list[tuple[str, float]]],
) -> dict[str, int]:
    """Net repeated or conflicting calls that share one daily entry price.

    Daily prices cannot distinguish intraday PnL. An explicit final reversal
    wins; otherwise opposite evidence is netted and an ambiguous day becomes
    neutral. Same-direction repetition shares a daily evidence cap.
    """
    groups: dict[tuple[str, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for item in enriched:
        call = item["call"]
        ticker = str(call["ticker"] or "").upper()
        investor = str(call["investor_id"] or "")
        series = prices.get(ticker) or []
        idx = first_idx_on_or_after(series, str(call["created_at"] or "")[:10]) if series else None
        if not investor or not ticker or idx is None:
            continue
        groups[(investor, ticker, series[idx][0])].append(item)

    stats = {"groups": 0, "capped": 0, "reversed": 0, "netted": 0, "neutralized": 0}
    for items in groups.values():
        if len(items) < 2:
            continue
        stats["groups"] += 1
        items.sort(
            key=lambda item: (
                str(item["call"]["created_at"] or ""),
                str(item["call"]["candidate_id"] or ""),
            )
        )
        directions = {
            str(item["call"]["direction"])
            for item in items
            if float(item.get("effective_weight") or 0) > 0
        }
        if len(directions) <= 1:
            total = sum(float(item.get("effective_weight") or 0) for item in items)
            if total > DAILY_CALL_EVIDENCE_CAP:
                scale = DAILY_CALL_EVIDENCE_CAP / total
                for item in items:
                    item["effective_weight"] = float(item.get("effective_weight") or 0) * scale
                    item["same_day_resolution"] = "same_direction_cap"
                stats["capped"] += 1
            continue

        final = items[-1]
        final_action = str(final["meta"].get("lifecycle_action") or "")
        final_direction = str(final["call"]["direction"] or "")
        if final_action == "reverse_call" and final_direction in {"bull", "bear"}:
            for item in items[:-1]:
                item["effective_weight"] = 0.0
                item["same_day_resolution"] = "void_same_day_reversed"
            final["effective_weight"] = min(
                DAILY_CALL_EVIDENCE_CAP,
                float(final.get("effective_weight") or 0),
            )
            final["same_day_resolution"] = "final_explicit_reversal"
            stats["reversed"] += 1
            continue

        totals = {
            direction: sum(
                float(item.get("effective_weight") or 0)
                for item in items
                if str(item["call"]["direction"]) == direction
            )
            for direction in ("bull", "bear")
        }
        total = totals["bull"] + totals["bear"]
        net = abs(totals["bull"] - totals["bear"])
        if total <= 0 or net / total < SAME_DAY_DIRECTION_THRESHOLD:
            for item in items:
                item["effective_weight"] = 0.0
                item["same_day_resolution"] = "neutral_same_day_conflict"
            stats["neutralized"] += 1
            continue

        dominant = "bull" if totals["bull"] > totals["bear"] else "bear"
        dominant_total = totals[dominant]
        retained = min(DAILY_CALL_EVIDENCE_CAP, net)
        scale = retained / dominant_total if dominant_total > 0 else 0.0
        for item in items:
            if str(item["call"]["direction"]) == dominant:
                item["effective_weight"] = float(item.get("effective_weight") or 0) * scale
                item["same_day_resolution"] = "net_same_day_dominant"
            else:
                item["effective_weight"] = 0.0
                item["same_day_resolution"] = "void_same_day_minority"
        stats["netted"] += 1
    return stats


def lifecycle_events(con: sqlite3.Connection) -> list[dict[str, Any]]:
    rows = con.execute(
        """SELECT c.*, cc.text AS text
             FROM sv_call c JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
            WHERE c.investor_id IS NOT NULL AND c.ticker IS NOT NULL"""
    ).fetchall()
    events: list[dict[str, Any]] = []
    for call in rows:
        meta = infer_call_meta(call)
        action = str(meta["lifecycle_action"])
        direction = str(call["direction"] or "neutral")
        if direction in {"bull", "bear"} or action in {"invalidate_prior_call", "close_prior_call", "reverse_call"}:
            events.append(
                {
                    "candidate_id": str(call["candidate_id"]),
                    "investor_id": str(call["investor_id"] or ""),
                    "ticker": str(call["ticker"] or "").upper(),
                    "created_at": str(call["created_at"] or ""),
                    "direction": direction,
                    "action": action,
                    "affected_direction": str(meta["affected_direction"]),
                }
            )
    return events


def annotate_supersessions(enriched: list[dict[str, Any]], events: list[dict[str, Any]]) -> int:
    """Mark calls closed by later lifecycle events on the same investor+ticker."""
    by_key: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    events_by_key: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for item in enriched:
        call = item["call"]
        investor = str(call["investor_id"] or "")
        ticker = str(call["ticker"] or "").upper()
        if investor and ticker:
            by_key[(investor, ticker)].append(item)
    for event in events:
        investor = str(event["investor_id"] or "")
        ticker = str(event["ticker"] or "").upper()
        if investor and ticker:
            events_by_key[(investor, ticker)].append(event)

    closed = 0
    for key, items in by_key.items():
        items.sort(key=lambda x: (str(x["call"]["created_at"] or ""), str(x["call"]["candidate_id"] or "")))
        key_events = sorted(events_by_key.get(key, []), key=lambda x: (x["created_at"], x["candidate_id"]))
        for i, item in enumerate(items):
            call = item["call"]
            direction = str(call["direction"])
            created = str(call["created_at"] or "")
            current_id = str(call["candidate_id"])
            for event in key_events:
                later_created = str(event["created_at"] or "")
                if later_created <= created:
                    continue
                if str(event["candidate_id"]) == current_id:
                    continue
                action = str(event["action"])
                affected = str(event["affected_direction"])
                later_direction = str(event["direction"])
                closes = False
                if action == "reverse_call" and later_direction in {"bull", "bear"} and later_direction != direction:
                    closes = True
                elif action in {"invalidate_prior_call", "close_prior_call"} and affected in {direction, "unknown"}:
                    closes = True
                elif later_direction in {"bull", "bear"} and later_direction != direction:
                    closes = True
                if not closes:
                    continue
                item["superseded_at"] = later_created
                item["superseded_by_candidate_id"] = str(event["candidate_id"])
                closed += 1
                break
    return closed


def path_score_components(
    series: list[tuple[str, float]],
    spy: list[tuple[str, float]],
    idx: int,
    spy_idx: int,
    exit_idx: int,
    exit_spy_idx: int,
    entry_px: float,
    spy_entry: float,
    direction: str,
    expected_hit: float,
    actual_hit: int,
    endpoint_directional_excess: float,
    normalizer: float,
) -> dict[str, Any]:
    """Score the full path inside a horizon window, not only the endpoint."""
    max_steps = min(exit_idx - idx, exit_spy_idx - spy_idx)
    path: list[tuple[int, str, float]] = []
    for step in range(1, max_steps + 1):
        day, px = series[idx + step]
        _, spx = spy[spy_idx + step]
        if entry_px <= 0 or spy_entry <= 0 or px <= 0 or spx <= 0:
            continue
        excess = (px / entry_px - 1) - (spx / spy_entry - 1)
        directional = excess if direction == "bull" else -excess
        path.append((step, day, directional))

    if not path:
        path = [(max(0, exit_idx - idx), series[exit_idx][0], endpoint_directional_excess)]

    peak_step, peak_day, max_favorable = max(path, key=lambda x: x[2])
    positive_day_share = sum(1 for _, _, v in path if v > 0) / len(path)
    avg_directional = sum(v for _, _, v in path) / len(path)
    endpoint_return_component = clamp(endpoint_directional_excess / normalizer, -1.0, 1.0)
    endpoint_component = 0.75 * (actual_hit - expected_hit) + 0.25 * endpoint_return_component
    opportunity_component = clamp(max_favorable / normalizer, -1.0, 1.0)
    persistence_component = positive_day_share - expected_hit
    retracement = max(0.0, max_favorable - endpoint_directional_excess)
    retracement_penalty = (
        clamp(retracement / max(max_favorable, normalizer * 0.5), 0.0, 1.0)
        if max_favorable > 0
        else 0.0
    )
    contribution_core = (
        PATH_SCORE_WEIGHTS["endpoint"] * endpoint_component
        + PATH_SCORE_WEIGHTS["opportunity"] * opportunity_component
        + PATH_SCORE_WEIGHTS["persistence"] * persistence_component
        - PATH_SCORE_WEIGHTS["retracement"] * retracement_penalty
    )
    return {
        "max_favorable_excess": max_favorable,
        "peak_day": peak_day,
        "time_to_peak_days": peak_step,
        "positive_day_share": positive_day_share,
        "avg_directional_excess": avg_directional,
        "retracement": retracement,
        "endpoint_component": endpoint_component,
        "opportunity_component": opportunity_component,
        "persistence_component": persistence_component,
        "retracement_penalty": retracement_penalty,
        "contribution_core": contribution_core,
    }


def _settle_calls_endpoint_legacy(con: sqlite3.Connection) -> int:
    ensure_tables(con)
    prices = load_prices(con)
    rates = base_rates(prices)
    spy = prices.get("SPY") or []
    if not spy:
        raise SystemExit("[sv-v0] missing SPY prices; run make sv-price-history first.")
    con.execute("DELETE FROM sv_call_settlement")
    youtube_evidence_filter = ""
    settlement_params: list[Any] = []
    if table_exists(con, "yt_author_pool") and table_exists(con, "yt_author_pool_run"):
        youtube_evidence_filter = (
            "AND (c.source <> 'youtube' OR c.investor_id IN ("
            "SELECT 'youtube:' || lower(p.channel_id) FROM yt_author_pool p "
            "WHERE p.pool_version=(SELECT pool_version FROM yt_author_pool_run "
            "ORDER BY created_at DESC LIMIT 1) AND p.selected=1))"
        )
    youtube_evidence_filter += (
        f" AND (c.source<>'youtube' OR {youtube_candidate_eligibility_predicate(con, 'cc')})"
    )
    if table_exists(con, "yt_channel_upload_ticker"):
        youtube_evidence_filter += (
            " AND (c.source <> 'youtube' OR COALESCE(cc.source_file, '') NOT LIKE '%mapping=%' "
            "OR cc.source_file LIKE '%mapping=legacy:%' OR EXISTS ("
            "SELECT 1 FROM yt_channel_upload_ticker ym "
            "WHERE ym.video_id=c.tweet_id AND ym.ticker=c.ticker "
            "AND ym.mapping_version=? AND ym.confidence>=?))"
        )
        settlement_params.extend(
            [YOUTUBE_UPLOAD_MAPPING_VERSION, YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE]
        )
    if table_exists(con, "yt_fulltext"):
        youtube_evidence_filter += (
            " AND (c.source <> 'youtube' OR (c.scoring_version=? "
            "AND c.transcript_version=? AND COALESCE(c.transcript_model,'')<>'' "
            "AND c.call_owner='channel_host' "
            "AND c.statement_mode IN ('prediction','position_action') "
            "AND EXISTS (SELECT 1 FROM yt_fulltext yf WHERE yf.video_id=c.tweet_id "
            "AND length(COALESCE(yf.content_en,'') || COALESCE(yf.content_zh,''))>=80)))"
        )
        settlement_params.extend(
            [SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION]
        )
    else:
        youtube_evidence_filter += " AND c.source <> 'youtube'"
    rows = con.execute(
        f"""SELECT c.*, cc.text AS text, cc.tweet_id AS source_tweet_id
             FROM sv_call c JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
            WHERE c.is_actionable_call=1 AND c.direction IN ('bull','bear') AND c.call_weight > 0
              {youtube_evidence_filter}""",
        settlement_params,
    ).fetchall()
    enriched: list[dict[str, Any]] = []
    by_post: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for call in rows:
        meta = infer_call_meta(call)
        raw_weight = float(call["call_weight"]) * float(meta["weight_multiplier"])
        if raw_weight <= 0:
            continue
        item = {"call": call, "meta": meta, "raw_weight": raw_weight, "effective_weight": raw_weight}
        enriched.append(item)
        by_post[f"{call['source'] or 'x'}:{call['tweet_id']}"].append(item)

    for items in by_post.values():
        if not items:
            continue
        cap = post_weight_cap(len(items))
        total = sum(float(x["raw_weight"]) for x in items)
        scale = min(1.0, cap / total) if total > 0 else 0.0
        for item in items:
            item["effective_weight"] = float(item["raw_weight"]) * scale

    same_day = resolve_same_entry_day_calls(enriched, prices)
    superseded = annotate_supersessions(enriched, lifecycle_events(con))
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
            weight = float(item["effective_weight"]) * horizon_factor(
                str(call["horizon_bucket"]),
                int(call["horizon_explicit"] or 0),
                h,
                str(item["meta"].get("analysis_type") or "unknown"),
            )
            if weight <= 0:
                continue
            status = "pending"
            values = [None] * 20
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
                path = path_score_components(
                    series,
                    spy,
                    idx,
                    spy_idx,
                    exit_idx,
                    exit_spy_idx,
                    entry_px,
                    spy_entry,
                    str(call["direction"]),
                    expected_hit,
                    actual_hit,
                    directional_excess,
                    RETURN_NORMALIZER[h],
                )
                contribution = weight * float(path["contribution_core"])
                status = "settled"
                values = [
                    exit_day, exit_px, spy_entry, spy_exit, ret, bret, excess, expected_hit, actual_hit, contribution,
                    path["max_favorable_excess"], path["peak_day"], path["time_to_peak_days"],
                    path["positive_day_share"], path["avg_directional_excess"], path["retracement"],
                    path["endpoint_component"], path["opportunity_component"], path["persistence_component"],
                    path["retracement_penalty"],
                ]
            else:
                expected_hit = expected if call["direction"] == "bull" else 1 - expected
                values = [None, None, spy_entry, None, None, None, None, expected_hit, None, None] + [None] * 10
            out.append(
                (
                    call["candidate_id"], h, ticker, call["investor_id"], call["created_at"],
                    entry_day, values[0], entry_px, values[1], values[2], values[3],
                    values[4], values[5], values[6], values[7], values[8], weight, values[9],
                    values[10], values[11], values[12], values[13], values[14], values[15],
                    values[16], values[17], values[18], values[19],
                    exit_reason, superseded_by, status,
                )
            )
    con.executemany(
        """INSERT OR REPLACE INTO sv_call_settlement
           (candidate_id,horizon,ticker,investor_id,created_at,entry_day,exit_day,entry_price,exit_price,
            benchmark_entry_price,benchmark_exit_price,return_pct,benchmark_return_pct,excess_return_pct,
            expected_hit,actual_hit,score_weight,contribution,max_favorable_excess,peak_day,time_to_peak_days,
            positive_day_share,avg_directional_excess,retracement,endpoint_component,opportunity_component,
            persistence_component,retracement_penalty,exit_reason,superseded_by_candidate_id,status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        out,
    )
    con.commit()
    print(
        f"[sv-v0] settled rows={len(out)} raw_calls={len(rows)} "
        f"effective_calls={len(enriched)} superseded_calls={superseded} "
        f"same_day_groups={same_day['groups']} capped={same_day['capped']} "
        f"reversed={same_day['reversed']} netted={same_day['netted']} "
        f"neutralized={same_day['neutralized']}",
        flush=True,
    )
    return len(out)


def settle_calls(
    con: sqlite3.Connection,
    sources: set[str] | None = None,
) -> int:
    """Settle calls as prefix integrals against SPY and an industry ETF."""
    ensure_tables(con)
    price_bars = load_price_bars(con)
    market_bars = price_bars.get("SPY") or []
    if not market_bars:
        raise SystemExit("[sv-v0] missing SPY prices; run make sv-price-history first.")
    legacy_prices = load_prices(con)
    sectors = {
        str(row["ticker"]).upper(): str(row["sector"] or "")
        for row in con.execute("SELECT ticker,sector FROM ticker_meta")
    } if table_exists(con, "ticker_meta") else {}

    evidence_filter = ""
    query_params: list[Any] = []
    selected_sources = sorted(sources or [])
    if selected_sources:
        source_slots = ",".join("?" for _ in selected_sources)
        evidence_filter += f" AND c.source IN ({source_slots})"
        query_params.extend(selected_sources)
    if table_exists(con, "yt_author_pool") and table_exists(con, "yt_author_pool_run"):
        evidence_filter += (
            "AND (c.source <> 'youtube' OR c.investor_id IN ("
            "SELECT 'youtube:' || lower(p.channel_id) FROM yt_author_pool p "
            "WHERE p.pool_version=(SELECT pool_version FROM yt_author_pool_run "
            "ORDER BY created_at DESC LIMIT 1) AND p.selected=1))"
        )
    evidence_filter += (
        f" AND (c.source<>'youtube' OR {youtube_candidate_eligibility_predicate(con, 'cc')})"
    )
    if table_exists(con, "yt_channel_upload_ticker"):
        evidence_filter += (
            " AND (c.source <> 'youtube' OR COALESCE(cc.source_file, '') NOT LIKE '%mapping=%' "
            "OR cc.source_file LIKE '%mapping=legacy:%' OR EXISTS ("
            "SELECT 1 FROM yt_channel_upload_ticker ym "
            "WHERE ym.video_id=c.tweet_id AND ym.ticker=c.ticker "
            "AND ym.mapping_version=? AND ym.confidence>=?))"
        )
        query_params.extend(
            [YOUTUBE_UPLOAD_MAPPING_VERSION, YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE]
        )
    if table_exists(con, "yt_fulltext"):
        evidence_filter += (
            " AND (c.source <> 'youtube' OR (c.scoring_version=? "
            "AND c.transcript_version=? AND COALESCE(c.transcript_model,'')<>'' "
            "AND c.call_owner='channel_host' "
            "AND c.statement_mode IN ('prediction','position_action') "
            "AND EXISTS (SELECT 1 FROM yt_fulltext yf WHERE yf.video_id=c.tweet_id "
            "AND length(COALESCE(yf.content_en,'') || COALESCE(yf.content_zh,''))>=80)))"
        )
        query_params.extend([SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION])
    else:
        evidence_filter += " AND c.source <> 'youtube'"

    calls = con.execute(
        f"""SELECT c.*,cc.text AS text,cc.tweet_id AS source_tweet_id
              FROM sv_call c
              JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
             WHERE c.is_actionable_call=1
               AND c.direction IN ('bull','bear')
               AND c.call_weight>0
               {evidence_filter}""",
        query_params,
    ).fetchall()

    enriched: list[dict[str, Any]] = []
    by_post: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for call in calls:
        meta = infer_call_meta(call)
        raw_weight = float(call["call_weight"]) * float(meta["weight_multiplier"])
        if raw_weight <= 0:
            continue
        item = {
            "call": call,
            "meta": meta,
            "raw_weight": raw_weight,
            "effective_weight": raw_weight,
        }
        enriched.append(item)
        by_post[f"{call['source'] or 'x'}:{call['tweet_id']}"].append(item)

    for items in by_post.values():
        cap = post_weight_cap(len(items))
        total = sum(float(item["raw_weight"]) for item in items)
        scale = min(1.0, cap / total) if total > 0 else 0.0
        for item in items:
            item["effective_weight"] = float(item["raw_weight"]) * scale

    same_day = resolve_same_entry_day_calls(enriched, legacy_prices)
    superseded = annotate_supersessions(enriched, lifecycle_events(con))
    output: list[dict[str, Any]] = []
    industry_mapped_calls: set[str] = set()
    primary_settled = 0

    for item in enriched:
        call = item["call"]
        meta = item["meta"]
        ticker = str(call["ticker"]).upper()
        stock_bars = price_bars.get(ticker) or []
        if not stock_bars:
            continue
        created_day = str(call["created_at"] or "")[:10]
        entry_index = first_bar_after(stock_bars, created_day)
        if entry_index is None:
            continue
        scoring_horizon = primary_horizon(
            call["horizon_bucket"],
            call["horizon_explicit"],
            meta.get("analysis_type"),
            HORIZONS,
        )
        benchmark_ticker, benchmark_method = industry_benchmark(
            ticker,
            sectors.get(ticker, ""),
            TICKER_NARRATIVE.get(ticker, ""),
            price_bars,
        )
        industry_bars = price_bars.get(benchmark_ticker or "") or []
        if benchmark_ticker and industry_bars:
            industry_mapped_calls.add(str(call["candidate_id"]))

        forced_exit_day = None
        superseded_at = item.get("superseded_at")
        if superseded_at:
            forced_index = first_bar_after(
                stock_bars,
                str(superseded_at)[:10],
            )
            if forced_index is not None:
                forced_exit_day = str(stock_bars[forced_index]["day"])

        for horizon, horizon_steps in HORIZONS.items():
            is_primary = horizon == scoring_horizon
            market = integral_path_for_benchmark(
                stock_bars,
                market_bars,
                entry_index,
                horizon_steps,
                str(call["direction"]),
                RETURN_NORMALIZER[horizon],
                forced_exit_day,
            )
            industry = (
                integral_path_for_benchmark(
                    stock_bars,
                    industry_bars,
                    entry_index,
                    horizon_steps,
                    str(call["direction"]),
                    RETURN_NORMALIZER[horizon],
                    forced_exit_day,
                )
                if industry_bars
                else None
            )
            market_settled = bool(market and market["complete"])
            industry_settled = bool(industry and industry["complete"])
            market_weight = (
                float(item["effective_weight"])
                if is_primary and market_settled
                else 0.0
            )
            industry_weight = (
                float(item["effective_weight"])
                if is_primary and industry_settled
                else 0.0
            )
            market_result = market["result"] if market else None
            industry_result = industry["result"] if industry else None
            market_contribution = (
                market_weight * float(market_result.score_core)
                if market_result
                else None
            )
            industry_contribution = (
                industry_weight * float(industry_result.score_core)
                if industry_result
                else None
            )
            if is_primary and market_settled:
                primary_settled += 1
            peak_day = None
            if market_result and market:
                path_days = market["path_days"]
                peak_index = min(len(path_days), market_result.peak_step) - 1
                if peak_index >= 0:
                    peak_day = path_days[peak_index]
            status = "settled" if market_settled else "pending"
            industry_status = (
                "settled"
                if industry_settled
                else ("pending" if industry else "unavailable")
            )
            output.append(
                {
                    "candidate_id": call["candidate_id"],
                    "horizon": horizon,
                    "ticker": ticker,
                    "investor_id": call["investor_id"],
                    "created_at": call["created_at"],
                    "entry_day": market["entry_day"] if market else None,
                    "exit_day": market["exit_day"] if market else None,
                    "entry_price": market["entry_price"] if market else None,
                    "exit_price": market["exit_price"] if market else None,
                    "benchmark_entry_price": (
                        market["benchmark_entry_price"] if market else None
                    ),
                    "benchmark_exit_price": (
                        market["benchmark_exit_price"] if market else None
                    ),
                    "return_pct": market["return_pct"] if market else None,
                    "benchmark_return_pct": (
                        market["benchmark_return_pct"] if market else None
                    ),
                    "excess_return_pct": (
                        market["excess_return_pct"] if market else None
                    ),
                    "expected_hit": 0.5,
                    "actual_hit": (
                        int(market_result.terminal_excess > 0)
                        if market_settled and market_result
                        else None
                    ),
                    "score_weight": market_weight,
                    "contribution": market_contribution,
                    "market_auc": (
                        market_result.cumulative_auc if market_result else None
                    ),
                    "market_mean_auc": (
                        market_result.mean_auc if market_result else None
                    ),
                    "market_integral_component": (
                        market_result.integral_component if market_result else None
                    ),
                    "market_terminal_component": (
                        market_result.terminal_component if market_result else None
                    ),
                    "market_positive_area": (
                        market_result.positive_area if market_result else None
                    ),
                    "market_negative_area": (
                        market_result.negative_area if market_result else None
                    ),
                    "market_adverse_area_share": (
                        market_result.adverse_area_share if market_result else None
                    ),
                    "industry_benchmark_ticker": benchmark_ticker,
                    "industry_benchmark_method": benchmark_method,
                    "industry_benchmark_entry_price": (
                        industry["benchmark_entry_price"] if industry else None
                    ),
                    "industry_benchmark_exit_price": (
                        industry["benchmark_exit_price"] if industry else None
                    ),
                    "industry_benchmark_return_pct": (
                        industry["benchmark_return_pct"] if industry else None
                    ),
                    "industry_excess_return_pct": (
                        industry["excess_return_pct"] if industry else None
                    ),
                    "industry_expected_hit": 0.5 if industry else None,
                    "industry_actual_hit": (
                        int(industry_result.terminal_excess > 0)
                        if industry_settled and industry_result
                        else None
                    ),
                    "industry_score_weight": industry_weight,
                    "industry_contribution": industry_contribution,
                    "industry_auc": (
                        industry_result.cumulative_auc if industry_result else None
                    ),
                    "industry_mean_auc": (
                        industry_result.mean_auc if industry_result else None
                    ),
                    "industry_integral_component": (
                        industry_result.integral_component if industry_result else None
                    ),
                    "industry_terminal_component": (
                        industry_result.terminal_component if industry_result else None
                    ),
                    "industry_positive_area": (
                        industry_result.positive_area if industry_result else None
                    ),
                    "industry_negative_area": (
                        industry_result.negative_area if industry_result else None
                    ),
                    "industry_adverse_area_share": (
                        industry_result.adverse_area_share if industry_result else None
                    ),
                    "industry_status": industry_status,
                    "max_favorable_excess": (
                        market_result.max_favorable_excess if market_result else None
                    ),
                    "peak_day": peak_day,
                    "time_to_peak_days": (
                        market_result.peak_step if market_result else None
                    ),
                    "positive_day_share": (
                        market_result.positive_day_share if market_result else None
                    ),
                    "avg_directional_excess": (
                        market_result.mean_auc if market_result else None
                    ),
                    "retracement": (
                        market_result.retracement if market_result else None
                    ),
                    "endpoint_component": (
                        market_result.terminal_component if market_result else None
                    ),
                    "opportunity_component": (
                        market_result.integral_component if market_result else None
                    ),
                    "persistence_component": (
                        market_result.positive_day_share - 0.5
                        if market_result
                        else None
                    ),
                    "retracement_penalty": (
                        min(
                            1.0,
                            market_result.retracement
                            / max(RETURN_NORMALIZER[horizon], 1e-9),
                        )
                        if market_result
                        else None
                    ),
                    "is_primary_horizon": int(is_primary),
                    "settlement_version": INTEGRAL_SCORING_VERSION,
                    "exit_reason": (
                        market["exit_reason"] if market else "horizon"
                    ),
                    "superseded_by_candidate_id": (
                        str(item.get("superseded_by_candidate_id") or "") or None
                    ),
                    "status": status,
                }
            )

    columns = [
        "candidate_id", "horizon", "ticker", "investor_id", "created_at",
        "entry_day", "exit_day", "entry_price", "exit_price",
        "benchmark_entry_price", "benchmark_exit_price", "return_pct",
        "benchmark_return_pct", "excess_return_pct", "expected_hit",
        "actual_hit", "score_weight", "contribution", "market_auc",
        "market_mean_auc", "market_integral_component",
        "market_terminal_component", "market_positive_area",
        "market_negative_area", "market_adverse_area_share",
        "industry_benchmark_ticker", "industry_benchmark_method",
        "industry_benchmark_entry_price", "industry_benchmark_exit_price",
        "industry_benchmark_return_pct", "industry_excess_return_pct",
        "industry_expected_hit", "industry_actual_hit",
        "industry_score_weight", "industry_contribution", "industry_auc",
        "industry_mean_auc", "industry_integral_component",
        "industry_terminal_component", "industry_positive_area",
        "industry_negative_area", "industry_adverse_area_share",
        "industry_status", "max_favorable_excess", "peak_day",
        "time_to_peak_days", "positive_day_share", "avg_directional_excess",
        "retracement", "endpoint_component", "opportunity_component",
        "persistence_component", "retracement_penalty",
        "is_primary_horizon", "settlement_version", "exit_reason",
        "superseded_by_candidate_id", "status",
    ]
    placeholders = ",".join("?" for _ in columns)
    if selected_sources:
        source_slots = ",".join("?" for _ in selected_sources)
        con.execute(
            f"""DELETE FROM sv_call_settlement
                 WHERE candidate_id IN (
                   SELECT candidate_id FROM sv_call
                    WHERE source IN ({source_slots})
                 )""",
            selected_sources,
        )
    else:
        con.execute("DELETE FROM sv_call_settlement")
    con.executemany(
        f"""INSERT INTO sv_call_settlement ({','.join(columns)})
            VALUES ({placeholders})""",
        [[row.get(column) for column in columns] for row in output],
    )
    con.commit()
    print(
        f"[sv-v0] integral settlements rows={len(output)} calls={len(calls)} "
        f"effective_calls={len(enriched)} primary_settled={primary_settled} "
        f"industry_mapped={len(industry_mapped_calls)} superseded={superseded} "
        f"same_day_groups={same_day['groups']} version={INTEGRAL_SCORING_VERSION}",
        flush=True,
    )
    return len(output)


def aggregate_stats(
    rows: list[sqlite3.Row],
    k: float = 30.0,
    *,
    as_of_day: str | dt.date | None = None,
    decay_config: SVTimeDecayConfig = DEFAULT_TIME_DECAY_CONFIG,
    ability: str = "market",
) -> dict[str, Any] | None:
    def value(row: Any, key: str, default: Any = None) -> Any:
        try:
            keys = row.keys()
        except AttributeError:
            keys = row
        if key not in keys:
            return default
        result = row[key]
        return default if result is None else result

    if ability == "industry":
        status_field = "industry_status"
        hit_field = "industry_actual_hit"
        contribution_field = "industry_contribution"
        weight_field = "industry_score_weight"
        expected_field = "industry_expected_hit"
    else:
        status_field = "status"
        hit_field = "actual_hit"
        contribution_field = "contribution"
        weight_field = "score_weight"
        expected_field = "expected_hit"
    vals = [
        row
        for row in rows
        if value(row, status_field, "unavailable") == "settled"
        and value(row, hit_field) is not None
        and float(value(row, weight_field, 0.0)) > 0
        and (
            not value(row, "settlement_version", "")
            or int(value(row, "is_primary_horizon", 1)) == 1
        )
    ]
    scoring_day = parse_day(as_of_day)
    if scoring_day is not None:
        vals = [r for r in vals if evidence_is_available(r["exit_day"], scoring_day)]
    if not vals:
        return None

    decay_weights = [
        evidence_decay_weight(r["exit_day"], r["horizon"], scoring_day, decay_config)
        if scoring_day is not None
        else 1.0
        for r in vals
    ]
    sum_contrib = sum(
        decay * float(value(r, contribution_field, 0.0))
        for r, decay in zip(vals, decay_weights)
    )
    # Decay is fractional evidence, so both contribution and Bernoulli
    # information are discounted once. Uniformly stale evidence therefore
    # loses significance instead of retaining the same z-score.
    variance = sum(
        decay
        * (float(value(r, weight_field, 0.0)) ** 2)
        * float(value(r, expected_field, 0.5))
        * (1 - float(value(r, expected_field, 0.5)))
        for r, decay in zip(vals, decay_weights)
    )
    z = sum_contrib / math.sqrt(variance) if variance > 1e-9 else 0.0
    weighted_evidence = [
        (float(value(r, weight_field, 0.0)), decay)
        for r, decay in zip(vals, decay_weights)
        if float(value(r, weight_field, 0.0)) > 0
    ]
    evidence_mass = sum(weight * decay for weight, decay in weighted_evidence)
    evidence_variance_mass = sum(
        weight * weight * decay for weight, decay in weighted_evidence
    )
    n_eff = (
        evidence_mass * evidence_mass / evidence_variance_mass
        if evidence_variance_mass > 1e-12
        else 0.0
    )
    lifetime_weights = [weight for weight, _ in weighted_evidence]
    lifetime_n_eff = (
        sum(lifetime_weights) ** 2 / sum(weight * weight for weight in lifetime_weights)
        if lifetime_weights
        else 0.0
    )
    ticker_weights: collections.Counter[str] = collections.Counter()
    ticker_positive_contrib: collections.Counter[str] = collections.Counter()
    for r, decay in zip(vals, decay_weights):
        ticker = str(r["ticker"])
        ticker_weights[ticker] += decay * float(value(r, weight_field, 0.0))
        ticker_positive_contrib[ticker] += decay * max(
            0.0, float(value(r, contribution_field, 0.0))
        )
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
    ages = [
        evidence_age_days(r["exit_day"], scoring_day)
        for r in vals
        if scoring_day is not None
    ]
    valid_ages = [age for age in ages if age is not None]
    latest_exit_day = max(
        (str(r["exit_day"])[:10] for r in vals if r["exit_day"]),
        default="",
    )
    return {
        "raw_z": z_shrunk,
        "ability": ability,
        "n_eff": n_eff,
        "lifetime_n_eff": lifetime_n_eff,
        "settled_calls": len({r["candidate_id"] for r in vals}),
        "active_days": len({str(r["created_at"])[:10] for r in vals}),
        "covered_tickers": len({r["ticker"] for r in vals}),
        "time_decay": {
            "version": TIME_DECAY_VERSION if scoring_day is not None else "disabled",
            "asOfDay": scoring_day.isoformat() if scoring_day is not None else None,
            "latestExitDay": latest_exit_day or None,
            "weightedEvidenceMass": round(evidence_mass, 4),
            "decayedNEff": round(n_eff, 4),
            "lifetimeNEff": round(lifetime_n_eff, 4),
            "meanAgeDays": (
                round(sum(valid_ages) / len(valid_ages), 1) if valid_ages else None
            ),
            "halfLifeDays": {
                key: int(value)
                for key, value in decay_config.half_life_days_by_horizon.items()
            },
        },
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


def primary_source_for_rows(rows: list[sqlite3.Row]) -> str:
    counts = collections.Counter(str(r["source"] or "x") for r in rows)
    if not counts:
        return "x"
    return counts.most_common(1)[0][0]


def platform_qualification(source: str) -> dict[str, float]:
    return PLATFORM_QUALIFICATION.get(source, PLATFORM_QUALIFICATION["x"])


def qualifies_for_platform(source: str, stats: dict[str, Any]) -> bool:
    rule = platform_qualification(source)
    return (
        float(stats.get("n_eff") or 0) >= float(rule["n_eff"])
        and int(stats.get("settled_calls") or 0) >= int(rule["settled_calls"])
    )


def confidence(n_eff: float, calls: int) -> str:
    if n_eff >= 60 and calls >= 80:
        return "high"
    if n_eff >= 25 and calls >= 35:
        return "medium"
    if n_eff >= 10 and calls >= 15:
        return "low"
    return "observing"


def confidence_factor(level: str) -> float:
    return {"high": 1.0, "medium": 0.85, "low": 0.65, "observing": 0.35}.get(level, 0.35)


def global_sv_from_platform(platform_sv: float, level: str) -> tuple[int, float]:
    """Convert platform-relative Score into global deviation ranking.

    Global Score measures how far an investor is from the median investor in the
    investor's own platform, with low-confidence evidence pulled toward 100.
    """
    deviation = ((platform_sv - 100.0) / 100.0) * confidence_factor(level)
    return int(round(clamp(100.0 + 100.0 * deviation, 40.0, 180.0))), deviation


def blend_dual_ability_scores(
    market_stats: dict[str, Any],
    industry_stats: dict[str, Any] | None,
    market_platform_sv: float,
    industry_platform_sv: float | None,
) -> dict[str, Any]:
    """Blend market and industry selection without penalizing missing mappings."""
    market_level = confidence(
        float(market_stats["n_eff"]),
        int(market_stats["settled_calls"]),
    )
    market_global_sv, _ = global_sv_from_platform(market_platform_sv, market_level)
    industry_n_eff = float(industry_stats["n_eff"]) if industry_stats else 0.0
    industry_calls = int(industry_stats["settled_calls"]) if industry_stats else 0
    industry_level = (
        confidence(industry_n_eff, industry_calls) if industry_stats else "unavailable"
    )
    industry_global_sv = (
        global_sv_from_platform(float(industry_platform_sv), industry_level)[0]
        if industry_stats and industry_platform_sv is not None
        else None
    )
    industry_blend = (
        0.5 * industry_n_eff / (industry_n_eff + 8.0)
        if industry_stats and industry_platform_sv is not None
        else 0.0
    )
    composite_platform_sv = (
        (1.0 - industry_blend) * market_platform_sv
        + industry_blend * float(industry_platform_sv or 100.0)
    )
    composite_raw_z = (
        (1.0 - industry_blend) * float(market_stats["raw_z"])
        + industry_blend * float(industry_stats["raw_z"] if industry_stats else 0.0)
    )
    coverage = min(
        1.0,
        industry_calls / max(1, int(market_stats["settled_calls"])),
    )
    return {
        "compositePlatformSv": composite_platform_sv,
        "compositeRawZ": composite_raw_z,
        "industryBlendWeight": industry_blend,
        "marketSelection": {
            "benchmark": "SPY",
            "svPlatform": int(round(market_platform_sv)),
            "svGlobal": market_global_sv,
            "rawZ": round(float(market_stats["raw_z"]), 4),
            "confidence": market_level,
            "nEff": round(float(market_stats["n_eff"]), 2),
            "settledCalls": int(market_stats["settled_calls"]),
        },
        "industrySelection": {
            "benchmark": "industry_etf",
            "svPlatform": (
                int(round(float(industry_platform_sv)))
                if industry_platform_sv is not None
                else None
            ),
            "svGlobal": industry_global_sv,
            "rawZ": (
                round(float(industry_stats["raw_z"]), 4)
                if industry_stats
                else None
            ),
            "confidence": industry_level,
            "nEff": round(industry_n_eff, 2),
            "settledCalls": industry_calls,
            "coverage": round(coverage, 4),
        },
    }


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


def row_analysis_type(row: sqlite3.Row) -> str:
    stored = str(row["investor_style"] or "unknown") if "investor_style" in row.keys() else "unknown"
    text = ""
    if "text" in row.keys():
        text = str(row["text"] or "")
    return infer_analysis_type(text, stored)


def score_investors(
    con: sqlite3.Connection,
    allow_partial_xueqiu: bool = False,
    xueqiu_pool_version: str = "",
    sources: set[str] | None = None,
) -> int:
    ensure_tables(con)
    scoring_as_of = dt.datetime.now(dt.timezone.utc).date()
    selected_sources = sorted(sources or [])
    source_filter = ""
    source_params: list[Any] = []
    if selected_sources:
        source_slots = ",".join("?" for _ in selected_sources)
        source_filter = f" AND c.source IN ({source_slots})"
        source_params.extend(selected_sources)
    youtube_pool_filter = ""
    score_params: list[Any] = []
    if table_exists(con, "yt_author_pool") and table_exists(con, "yt_author_pool_run"):
        youtube_pool_filter = (
            "AND (c.source <> 'youtube' OR c.investor_id IN ("
            "SELECT 'youtube:' || lower(p.channel_id) FROM yt_author_pool p "
            "WHERE p.pool_version=(SELECT pool_version FROM yt_author_pool_run "
            "ORDER BY created_at DESC LIMIT 1) AND p.selected=1))"
        )
    youtube_pool_filter += (
        f" AND (c.source<>'youtube' OR {youtube_candidate_eligibility_predicate(con, 'cc')})"
    )
    if table_exists(con, "yt_channel_upload_ticker"):
        youtube_pool_filter += (
            " AND (c.source <> 'youtube' OR COALESCE(cc.source_file, '') NOT LIKE '%mapping=%' "
            "OR cc.source_file LIKE '%mapping=legacy:%' OR EXISTS ("
            "SELECT 1 FROM yt_channel_upload_ticker ym "
            "WHERE ym.video_id=c.tweet_id AND ym.ticker=c.ticker "
            "AND ym.mapping_version=? AND ym.confidence>=?))"
        )
        score_params.extend(
            [YOUTUBE_UPLOAD_MAPPING_VERSION, YOUTUBE_UPLOAD_MIN_MAPPING_CONFIDENCE]
        )
    if table_exists(con, "yt_fulltext"):
        youtube_pool_filter += (
            " AND (c.source <> 'youtube' OR (c.scoring_version=? "
            "AND c.transcript_version=? AND COALESCE(c.transcript_model,'')<>'' "
            "AND c.call_owner='channel_host' "
            "AND c.statement_mode IN ('prediction','position_action') "
            "AND EXISTS (SELECT 1 FROM yt_fulltext yf WHERE yf.video_id=c.tweet_id "
            "AND length(COALESCE(yf.content_en,'') || COALESCE(yf.content_zh,''))>=80)))"
        )
        score_params.extend([SV_SCORING_VERSION, YOUTUBE_TRANSCRIPT_CALL_VERSION])
    else:
        youtube_pool_filter += " AND c.source <> 'youtube'"
    if table_exists(con, "xueqiu_author_pool") and table_exists(
        con, "xueqiu_author_crawl_job"
    ):
        pool_version = xueqiu_pool_version or latest_xueqiu_pool_version(con)
        if pool_version:
            total_authors, done_authors = xueqiu_pool_completion(con, pool_version)
            if total_authors == 0 or (
                done_authors < total_authors and not allow_partial_xueqiu
            ):
                youtube_pool_filter += " AND c.source <> 'xueqiu'"
                print(
                    f"[sv-v0] xueqiu scoring gated: {done_authors}/{total_authors} "
                    "selected author jobs done.",
                    flush=True,
                )
            else:
                if done_authors < total_authors:
                    print(
                        f"[sv-v0] xueqiu partial scoring enabled: "
                        f"{done_authors}/{total_authors} selected author jobs done.",
                        flush=True,
                    )
                youtube_pool_filter += (
                    " AND (c.source <> 'xueqiu' OR c.investor_id IN ("
                    "SELECT 'xueqiu:' || lower(p.user_id) FROM xueqiu_author_pool p "
                    "WHERE p.pool_version=? AND p.selected=1 AND p.author_type='creator' "
                    "AND EXISTS (SELECT 1 FROM xueqiu_author_crawl_job j "
                    "WHERE j.pool_version=p.pool_version AND j.user_id=p.user_id "
                    "AND j.status='done')))"
                )
                score_params.append(pool_version)
    joined = con.execute(
        f"""SELECT s.*, c.source, c.author_handle, c.language, c.direction, c.investor_style, c.call_structure, cc.text AS text
             FROM sv_call_settlement s
             JOIN sv_call c ON c.candidate_id=s.candidate_id
             JOIN sv_call_candidate cc ON cc.candidate_id=s.candidate_id
            WHERE s.status='settled' {source_filter} {youtube_pool_filter}""",
        source_params + score_params,
    ).fetchall()
    by_inv: dict[str, list[sqlite3.Row]] = collections.defaultdict(list)
    for r in joined:
        if r["investor_id"]:
            by_inv[str(r["investor_id"])].append(r)

    market_stats = {
        inv: aggregate_stats(rows, 30.0, as_of_day=scoring_as_of)
        for inv, rows in by_inv.items()
    }
    market_stats = {key: value for key, value in market_stats.items() if value}
    industry_stats = {
        inv: aggregate_stats(
            rows,
            20.0,
            as_of_day=scoring_as_of,
            ability="industry",
        )
        for inv, rows in by_inv.items()
        if inv in market_stats
    }
    industry_stats = {
        key: value for key, value in industry_stats.items() if value
    }
    primary_sources = {
        inv: primary_source_for_rows(rows)
        for inv, rows in by_inv.items()
        if inv in market_stats
    }
    market_raw_by_platform: dict[str, dict[str, float]] = collections.defaultdict(dict)
    industry_raw_by_platform: dict[str, dict[str, float]] = collections.defaultdict(dict)
    for inv, stats in market_stats.items():
        source = primary_sources.get(inv, "x")
        market_raw_by_platform[source][inv] = float(stats["raw_z"])
        if inv in industry_stats:
            industry_raw_by_platform[source][inv] = float(
                industry_stats[inv]["raw_z"]
            )

    market_platform_scores: dict[str, dict[str, int]] = {}
    market_fallback_scores: dict[str, dict[str, int]] = {}
    industry_platform_scores: dict[str, dict[str, int]] = {}
    industry_fallback_scores: dict[str, dict[str, int]] = {}
    platform_pool_sizes: dict[str, dict[str, int]] = {}
    for source, raw_map in market_raw_by_platform.items():
        qualified = {
            inv: raw
            for inv, raw in raw_map.items()
            if qualifies_for_platform(source, market_stats[inv])
        }
        if len(qualified) < 8:
            qualified = raw_map
        market_platform_scores[source] = robust_scores(qualified)
        market_fallback_scores[source] = robust_scores(raw_map)
        industry_raw = industry_raw_by_platform.get(source, {})
        industry_qualified = {
            inv: raw
            for inv, raw in industry_raw.items()
            if float(industry_stats[inv]["n_eff"]) >= 4.0
            and int(industry_stats[inv]["settled_calls"]) >= 5
        }
        if len(industry_qualified) < 8:
            industry_qualified = industry_raw
        industry_platform_scores[source] = robust_scores(industry_qualified)
        industry_fallback_scores[source] = robust_scores(industry_raw)
        platform_pool_sizes[source] = {
            "qualified": len(qualified),
            "total": len(raw_map),
            "industryQualified": len(industry_qualified),
            "industryTotal": len(industry_raw),
        }

    if selected_sources:
        source_slots = ",".join("?" for _ in selected_sources)
        con.execute(
            f"""DELETE FROM sv_segment_score
                 WHERE investor_id IN (
                   SELECT investor_id FROM sv_investor_score
                    WHERE source IN ({source_slots})
                 )""",
            selected_sources,
        )
        con.execute(
            f"DELETE FROM sv_investor_score WHERE source IN ({source_slots})",
            selected_sources,
        )
    else:
        con.execute("DELETE FROM sv_investor_score")
        con.execute("DELETE FROM sv_segment_score")

    rows_to_write = []
    segment_rows = []
    for inv, rows in by_inv.items():
        st = market_stats.get(inv)
        if not st:
            continue
        handle = next((r["author_handle"] for r in rows if r["author_handle"]), inv)
        source_counts = collections.Counter(str(r["source"] or "x") for r in rows)
        primary_source = primary_sources.get(inv) or (source_counts.most_common(1)[0][0] if source_counts else "x")
        source_label = SOURCE_LABELS.get(primary_source, {"zh": primary_source, "en": primary_source})
        if primary_source == "reddit":
            display_name = f"u/{handle}"
        elif primary_source == "youtube":
            display_name = handle or inv
        elif primary_source == "xueqiu":
            display_name = handle or inv
        else:
            display_name = f"@{handle}"
        lang_counts = collections.Counter(str(r["language"] or "en") for r in rows)
        top_lang = lang_counts.most_common(1)[0][0] if lang_counts else "en"
        ticker_counts = collections.Counter(str(r["ticker"]) for r in rows)
        top_tickers = [t for t, _ in ticker_counts.most_common(8)]
        narrative_counts = collections.Counter(TICKER_NARRATIVE.get(t, "other") for t in ticker_counts)
        top_narratives = [n for n, _ in narrative_counts.most_common(4)]
        analysis_counts = collections.Counter(row_analysis_type(r) for r in rows)
        top_analysis_type = analysis_counts.most_common(1)[0][0] if analysis_counts else "unknown"

        segment_scores: dict[tuple[str, str], int] = {}
        for h in HORIZONS:
            sub = [r for r in rows if r["horizon"] == h]
            ag = aggregate_stats(sub, 25.0, as_of_day=scoring_as_of)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("horizon", h)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("horizon", h, inv, segment_scores[("horizon", h)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for t, _ in ticker_counts.most_common(12):
            sub = [r for r in rows if r["ticker"] == t]
            ag = aggregate_stats(sub, 10.0, as_of_day=scoring_as_of)
            if ag and ag["n_eff"] >= 1.5:
                segment_scores[("ticker", t)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("ticker", t, inv, segment_scores[("ticker", t)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for n in set(TICKER_NARRATIVE.get(str(r["ticker"]), "other") for r in rows):
            sub = [r for r in rows if TICKER_NARRATIVE.get(str(r["ticker"]), "other") == n]
            ag = aggregate_stats(sub, 20.0, as_of_day=scoring_as_of)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("narrative", n)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("narrative", n, inv, segment_scores[("narrative", n)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for analysis_type in set(analysis_counts):
            sub = [r for r in rows if row_analysis_type(r) == analysis_type]
            ag = aggregate_stats(sub, 20.0, as_of_day=scoring_as_of)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("investor_type", analysis_type)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("investor_type", analysis_type, inv, segment_scores[("investor_type", analysis_type)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))
        for source in set(source_counts):
            sub = [r for r in rows if str(r["source"] or "x") == source]
            ag = aggregate_stats(sub, 20.0, as_of_day=scoring_as_of)
            if ag and ag["n_eff"] >= 2:
                segment_scores[("platform", source)] = int(round(clamp(100 + 10 * ag["raw_z"], 40, 180)))
                segment_rows.append(("platform", source, inv, segment_scores[("platform", source)], ag["raw_z"], ag["n_eff"], ag["settled_calls"]))

        horizon_json = {h: segment_scores.get(("horizon", h)) for h in HORIZONS}
        ticker_json = {t: segment_scores[("ticker", t)] for t in ticker_counts if ("ticker", t) in segment_scores}
        narrative_json = {n: segment_scores[("narrative", n)] for n in set(top_narratives) if ("narrative", n) in segment_scores}
        level = confidence(st["n_eff"], st["settled_calls"])
        market_platform_sv = market_platform_scores.get(primary_source, {}).get(
            inv,
            market_fallback_scores.get(primary_source, {}).get(inv, 100),
        )
        industry_st = industry_stats.get(inv)
        industry_platform_sv = (
            industry_platform_scores.get(primary_source, {}).get(
                inv,
                industry_fallback_scores.get(primary_source, {}).get(inv, 100),
            )
            if industry_st
            else None
        )
        ability_scores = blend_dual_ability_scores(
            st,
            industry_st,
            market_platform_sv,
            industry_platform_sv,
        )
        raw_platform_sv = float(ability_scores["compositePlatformSv"])
        combined_raw_z = float(ability_scores["compositeRawZ"])
        rel_cap = reliability_cap(level)
        conc_cap = concentration_cap(st)
        platform_sv = int(round(min(raw_platform_sv, rel_cap, conc_cap)))
        sv, global_deviation = global_sv_from_platform(platform_sv, level)
        concentration = dict(st.get("concentration") or {})
        concentration.update(
            {
                "timeDecay": st.get("time_decay") or {},
                "cap": conc_cap,
                "capApplied": conc_cap < raw_platform_sv,
                "rawSvBeforeConcentrationCap": raw_platform_sv,
                "svPlatform": platform_sv,
                "svPlatformRaw": raw_platform_sv,
                "svGlobal": sv,
                "svGlobalDeviation": round(global_deviation, 4),
                "confidenceFactor": confidence_factor(level),
                "platformBaseline": 100,
                "primaryPlatform": primary_source,
                "platformPool": platform_pool_sizes.get(primary_source, {"qualified": 0, "total": 0}),
                "dualBaseline": {
                    "version": INTEGRAL_SCORING_VERSION,
                    "industryBlendWeight": round(
                        float(ability_scores["industryBlendWeight"]), 4
                    ),
                },
                "dominantInvestorType": top_analysis_type,
                "investorTypeShare": {
                    k: round(v / max(1, sum(analysis_counts.values())), 4)
                    for k, v in analysis_counts.most_common()
                },
            }
        )
        rows_to_write.append(
            (
                inv, primary_source, display_name, handle, top_lang if top_lang in {"zh", "en", "ko", "ja"} else "en",
                sv, combined_raw_z, level, st["n_eff"], st["settled_calls"],
                st["active_days"], st["covered_tickers"], jdump(top_tickers), jdump(top_narratives),
                jdump({
                    source: (platform_sv if source == primary_source else segment_scores.get(("platform", source), sv))
                    for source in source_counts
                }),
                jdump(horizon_json), jdump(narrative_json), jdump(ticker_json),
                jdump(ability_scores),
                jdump(concentration),
                f"基于 {st['settled_calls']} 个已结算 {source_label['zh']} call 的积分路径；分别衡量相对 SPY 的市场选股能力和相对行业 ETF 的行业内选股能力，综合得到 SV_Platform={platform_sv}，再按样本置信度折算为 SV_Global={sv}。",
                f"Based on integral return paths from {st['settled_calls']} settled {source_label['en']} calls; market selection versus SPY and within-industry selection versus sector ETFs are blended into SV_Platform={platform_sv}, then adjusted for sample confidence to SV_Global={sv}.",
                utc_now(),
            )
        )

    con.executemany(
        """INSERT INTO sv_investor_score
           (investor_id,source,name,handle,language,sv,raw_z,confidence,n_eff,settled_calls,active_days,
            covered_tickers,top_tickers_json,top_narratives_json,platform_scores_json,horizon_scores_json,
            narrative_scores_json,ticker_scores_json,ability_scores_json,concentration_json,rationale_zh,rationale_en,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
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


def platform_score_value(row: Any, source: str) -> float:
    try:
        scores = json.loads(row["platform_scores_json"] or "{}")
    except (TypeError, json.JSONDecodeError, KeyError, IndexError):
        scores = {}
    value = scores.get(source) if isinstance(scores, dict) else None
    return norm_num(value, norm_num(row["sv"], 100.0))


def rank_platform_band_rows(rows: list[Any], source: str) -> dict[str, Any]:
    """Return deterministic qualified-platform percentile rows before serialization."""
    source_rows = [row for row in rows if str(row["source"] or "") == source]
    qualified = [
        row
        for row in source_rows
        if qualifies_for_platform(
            source,
            {"n_eff": row["n_eff"], "settled_calls": row["settled_calls"]},
        )
    ]
    ranked_rows = qualified if len(qualified) >= 8 else source_rows
    top_rows = sorted(
        ranked_rows,
        key=lambda row: (
            -platform_score_value(row, source),
            -norm_num(row["n_eff"]),
            -int(row["settled_calls"] or 0),
            str(row["investor_id"] or ""),
        ),
    )
    bottom_rows = sorted(
        ranked_rows,
        key=lambda row: (
            platform_score_value(row, source),
            -norm_num(row["n_eff"]),
            -int(row["settled_calls"] or 0),
            str(row["investor_id"] or ""),
        ),
    )
    observed_rows = sorted(
        source_rows,
        key=lambda row: (
            -platform_score_value(row, source),
            -norm_num(row["n_eff"]),
            -int(row["settled_calls"] or 0),
            str(row["investor_id"] or ""),
        ),
    )
    decile_count = max(1, math.ceil(len(ranked_rows) * 0.10)) if ranked_rows else 0
    quartile_count = max(1, math.ceil(len(ranked_rows) * 0.25)) if ranked_rows else 0
    return {
        "source": source,
        "totalCount": len(source_rows),
        "qualifiedCount": len(qualified),
        "rankedCount": len(ranked_rows),
        "population": "qualified" if ranked_rows is qualified else "all_scored_fallback",
        "rankedRows": top_rows,
        "observedRows": observed_rows,
        "top10Rows": top_rows[:decile_count],
        "bottom10Rows": bottom_rows[:decile_count],
        "top25Rows": top_rows[:quartile_count],
        "bottom25Rows": bottom_rows[:quartile_count],
    }


def investor_profile_assets(
    source: str,
    investor_id: str,
    handle: str,
) -> tuple[str | None, str | None]:
    """Return platform-native avatar and profile URLs for an exported investor."""
    if source == "reddit":
        avatar = "https://www.redditstatic.com/avatars/avatar_default_02_46A508.png"
        url = f"https://www.reddit.com/user/{handle}/" if handle else None
        return avatar, url
    if source == "youtube":
        channel_id = investor_id.split(":", 1)[1] if investor_id.startswith("youtube:") else investor_id
        yt_handle = handle if handle.startswith("@") else ""
        youtube_key = yt_handle.lstrip("@") or channel_id
        avatar = f"https://unavatar.io/youtube/{youtube_key}" if youtube_key else None
        url = (
            f"https://www.youtube.com/{yt_handle}"
            if yt_handle
            else (f"https://www.youtube.com/channel/{channel_id}" if channel_id else None)
        )
        return avatar, url
    if source == "xueqiu":
        user_id = investor_id.split(":", 1)[1] if investor_id.startswith("xueqiu:") else investor_id
        return None, f"https://xueqiu.com/u/{user_id}" if user_id else None
    if source == "x":
        avatar = f"https://unavatar.io/twitter/{handle}" if handle else None
        url = f"https://x.com/{handle}" if handle else None
        return avatar, url
    return None, None


def export_json(con: sqlite3.Connection) -> None:
    snapshot_created_at = utc_now()
    run_id = f"{SV_RANKING_VERSION}:{snapshot_created_at}"
    prev_run = con.execute(
        "SELECT run_id FROM sv_investor_score_snapshot GROUP BY run_id ORDER BY MAX(created_at) DESC LIMIT 1"
    ).fetchone()
    prev_by_investor: dict[str, sqlite3.Row] = {}
    if prev_run:
        prev_rows = con.execute(
            "SELECT investor_id, sv, rank_no, confidence, n_eff, settled_calls FROM sv_investor_score_snapshot WHERE run_id = ?",
            (prev_run["run_id"],),
        ).fetchall()
        prev_by_investor = {str(r["investor_id"]): r for r in prev_rows}

    all_rows = con.execute(
        """SELECT *,
                  RANK() OVER (
                    ORDER BY sv DESC,
                             raw_z DESC,
                             CASE confidence
                               WHEN 'high' THEN 4
                               WHEN 'medium' THEN 3
                               WHEN 'low' THEN 2
                               ELSE 1
                             END DESC,
                             n_eff DESC,
                             settled_calls DESC
                  ) AS rank_no
             FROM sv_investor_score
            ORDER BY sv DESC,
                     raw_z DESC,
                     CASE confidence
                       WHEN 'high' THEN 4
                       WHEN 'medium' THEN 3
                       WHEN 'low' THEN 2
                       ELSE 1
                     END DESC,
                     n_eff DESC,
                     settled_calls DESC"""
    ).fetchall()
    con.executemany(
        """INSERT OR REPLACE INTO sv_investor_score_snapshot
           (run_id,scoring_version,created_at,investor_id,source,name,handle,language,sv,raw_z,rank_no,confidence,n_eff,settled_calls,active_days,covered_tickers,horizon_scores_json,ticker_scores_json,ability_scores_json,concentration_json)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        [
            (
                run_id,
                (
                    SV_RANKING_VERSION
                    if r["ability_scores_json"]
                    else "v1.9-time-decay"
                ),
                snapshot_created_at,
                r["investor_id"],
                r["source"],
                r["name"],
                r["handle"],
                r["language"],
                r["sv"],
                r["raw_z"],
                r["rank_no"],
                r["confidence"],
                r["n_eff"],
                r["settled_calls"],
                r["active_days"],
                r["covered_tickers"],
                r["horizon_scores_json"],
                r["ticker_scores_json"],
                r["ability_scores_json"],
                r["concentration_json"],
            )
            for r in all_rows
        ],
    )
    con.commit()
    decile_count = max(1, math.ceil(len(all_rows) * 0.1)) if all_rows else 0
    rows = all_rows[: max(200, decile_count)]
    scores = sorted(float(r["sv"] or 0) for r in all_rows)

    def quantile(values: list[float], q: float) -> float:
        if not values:
            return 0.0
        pos = (len(values) - 1) * q
        lo = int(math.floor(pos))
        hi = int(math.ceil(pos))
        if lo == hi:
            return values[lo]
        return values[lo] * (hi - pos) + values[hi] * (pos - lo)

    def score_bins(values: list[float], bucket_count: int = 28) -> list[dict[str, float | int]]:
        if not values:
            return []
        lo = math.floor(min(values) / 5) * 5
        hi = math.ceil(max(values) / 5) * 5
        span = max(1.0, hi - lo)
        counts = [0 for _ in range(bucket_count)]
        for score in values:
            idx = min(bucket_count - 1, max(0, int((score - lo) / span * bucket_count)))
            counts[idx] += 1
        step = span / bucket_count
        return [
            {"from": round(lo + i * step, 1), "to": round(lo + (i + 1) * step, 1), "count": count}
            for i, count in enumerate(counts)
        ]

    def distribution_for(ranked_rows: list[Any], source: str | None = None) -> dict[str, Any]:
        values = sorted(
            platform_score_value(row, source) if source else norm_num(row["sv"])
            for row in ranked_rows
        )
        ranked_desc = sorted(
            ranked_rows,
            key=lambda row: (
                -(platform_score_value(row, source) if source else norm_num(row["sv"])),
                -norm_num(row["n_eff"]),
                -int(row["settled_calls"] or 0),
                str(row["investor_id"] or ""),
            ),
        )
        count = max(1, math.ceil(len(ranked_desc) * 0.1)) if ranked_desc else 0
        score_of = lambda row: platform_score_value(row, source) if source else norm_num(row["sv"])
        return {
            "count": len(values),
            "min": round(values[0], 1) if values else 0,
            "q25": round(quantile(values, 0.25), 1),
            "median": round(quantile(values, 0.5), 1),
            "q75": round(quantile(values, 0.75), 1),
            "max": round(values[-1], 1) if values else 0,
            "top10Threshold": round(score_of(ranked_desc[count - 1]), 1) if count else 0,
            "bottom10Threshold": round(score_of(ranked_desc[-count]), 1) if count else 0,
            "bins": score_bins(values),
        }

    distribution = distribution_for(all_rows)

    def serialize_investor(
        r: sqlite3.Row,
        platform_rank: int | None = None,
        *,
        compact: bool = False,
    ) -> dict[str, Any]:
        handle = str(r["handle"] or "")
        source = str(r["source"] or "x")
        investor_id = str(r["investor_id"] or "")
        public_id = investor_id
        if source != "x" and investor_id and not investor_id.startswith(f"{source}:"):
            public_id = f"{source}:{investor_id}"
        prev = prev_by_investor.get(str(r["investor_id"]))
        sv_delta = round(float(r["sv"] or 0) - float(prev["sv"] or 0), 1) if prev else None
        rank_delta = int(prev["rank_no"] or 0) - int(r["rank_no"] or 0) if prev else None
        n_eff_delta = round(float(r["n_eff"] or 0) - float(prev["n_eff"] or 0), 1) if prev else None
        settled_delta = int(r["settled_calls"] or 0) - int(prev["settled_calls"] or 0) if prev else None
        avatar, url = investor_profile_assets(source, investor_id, handle)
        concentration = json.loads(r["concentration_json"] or "{}")
        item = {
            "id": public_id,
            "rank": int(r["rank_no"] or 0),
            "platformRank": platform_rank,
            "svDelta": sv_delta,
            "rankDelta": rank_delta,
            "nEffDelta": n_eff_delta,
            "settledCallsDelta": settled_delta,
            "previousConfidence": prev["confidence"] if prev else None,
            "source": source,
            "name": r["name"] or f"@{handle}",
            "handle": handle,
            "avatar": avatar,
            "url": url,
            "language": r["language"] or "en",
            "sv": int(round(float(r["sv"] or 100))),
            "svKind": "global_platform_deviation",
            "confidence": r["confidence"] or "observing",
            "nEff": round(float(r["n_eff"] or 0), 1),
            "settledCalls": int(r["settled_calls"] or 0),
            "activeDays": int(r["active_days"] or 0),
            "coveredTickers": int(r["covered_tickers"] or 0),
            "topTickers": json.loads(r["top_tickers_json"] or "[]"),
            "platformScores": json.loads(r["platform_scores_json"] or "{}"),
            "abilities": json.loads(r["ability_scores_json"] or "{}"),
            "horizonScores": json.loads(r["horizon_scores_json"] or "{}"),
            "concentration": (
                {"dominantInvestorType": concentration.get("dominantInvestorType")}
                if compact
                else concentration
            ),
            "rationaleZh": r["rationale_zh"] or "",
            "rationaleEn": r["rationale_en"] or "",
        }
        if not compact:
            item.update(
                {
                    "topNarratives": json.loads(r["top_narratives_json"] or "[]"),
                    "narrativeScores": json.loads(r["narrative_scores_json"] or "{}"),
                    "tickerScores": json.loads(r["ticker_scores_json"] or "{}"),
                }
            )
        return item

    investor_index: dict[str, dict[str, Any]] = {}

    def index_investor(
        row: sqlite3.Row,
        platform_rank: int | None = None,
        observation_rank: int | None = None,
        *,
        compact: bool = False,
    ) -> str:
        item = serialize_investor(row, platform_rank, compact=compact)
        investor_id = str(item["id"])
        existing = investor_index.get(investor_id)
        if existing is None or not compact:
            if existing:
                item = {**existing, **item}
            investor_index[investor_id] = item
        if observation_rank is not None:
            investor_index[investor_id]["observationRank"] = observation_rank
        return investor_id

    investor_ids = [index_investor(r) for r in rows]
    bottom_investor_ids = [index_investor(r) for r in all_rows[-decile_count:]]
    platform_bands: dict[str, dict[str, Any]] = {}
    for source in ("x", "youtube", "reddit", "xueqiu", "toss"):
        band = rank_platform_band_rows(all_rows, source)
        ranked_rows = band.pop("rankedRows")
        if not ranked_rows:
            continue
        platform_ranks = {
            str(row["investor_id"]): index
            for index, row in enumerate(ranked_rows, 1)
        }
        observed_rows = band.pop("observedRows")
        observation_ranks = {
            str(row["investor_id"]): index
            for index, row in enumerate(observed_rows, 1)
        }

        def index_platform_rows(
            platform_rows: list[sqlite3.Row],
            *,
            compact_unqualified: bool = False,
        ) -> list[str]:
            indexed: list[str] = []
            for row in platform_rows:
                investor_id = str(row["investor_id"])
                indexed.append(
                    index_investor(
                        row,
                        platform_ranks.get(investor_id),
                        observation_ranks.get(investor_id),
                        compact=compact_unqualified and investor_id not in platform_ranks,
                    )
                )
            return indexed

        top25_rows = band.pop("top25Rows")
        bottom25_rows = band.pop("bottom25Rows")
        top10_rows = band.pop("top10Rows")
        bottom10_rows = band.pop("bottom10Rows")
        platform_bands[source] = {
            **band,
            "scoreKind": "SV_Platform",
            "distribution": distribution_for(ranked_rows, source),
            "top25Threshold": round(platform_score_value(top25_rows[-1], source), 1) if top25_rows else 0,
            "bottom25Threshold": round(platform_score_value(bottom25_rows[-1], source), 1) if bottom25_rows else 0,
            "rankedIds": index_platform_rows(ranked_rows),
            "observedIds": index_platform_rows(observed_rows, compact_unqualified=True),
            "top10Ids": index_platform_rows(top10_rows),
            "bottom10Ids": index_platform_rows(bottom10_rows),
            "top25Ids": index_platform_rows(top25_rows),
            "bottom25Ids": index_platform_rows(bottom25_rows),
        }
    source_top25_ids = {
        source: list(band["top25Ids"])
        for source, band in platform_bands.items()
    }
    platform_scoring_versions = {
        source: (
            SV_RANKING_VERSION
            if source_rows
            and all(row["ability_scores_json"] for row in source_rows)
            else "v1.9-time-decay"
        )
        for source in platform_bands
        for source_rows in [
            [row for row in all_rows if str(row["source"] or "") == source]
        ]
    }
    current = [
        {"key": "semis", **NARRATIVE_LABELS["semis"], "weight": 34},
        {"key": "ai_infra", **NARRATIVE_LABELS["ai_infra"], "weight": 24},
        {"key": "software", **NARRATIVE_LABELS["software"], "weight": 16},
        {"key": "crypto", **NARRATIVE_LABELS["crypto"], "weight": 10},
    ]
    payload = {
        "version": 9,
        "scoringVersion": SV_RANKING_VERSION,
        "platformScoringVersions": platform_scoring_versions,
        "callScoringVersion": SV_SCORING_VERSION,
        "scoreSemantics": {
            "sv": "SV_Global. It blends dual-baseline integral abilities and applies confidence adjustment.",
            "platformScores": "Composite SV_Platform, normalized inside that platform only.",
            "marketSelection": "Integral directional excess path versus SPY. It measures cross-market stock selection.",
            "industrySelection": "Integral directional excess path versus the mapped industry ETF. It measures within-industry stock selection.",
            "integralFormula": "70% normalized area under the cumulative directional excess-return path + 30% terminal directional excess return.",
            "horizonRule": "Configured horizon windows are cumulative integral snapshots; only the primary horizon contributes evidence.",
            "baseline": 100,
            "globalFormula": "SV_Global = 100 + (SV_Platform - 100) * confidence_factor",
        },
        "updatedAt": utc_now()[:10],
        "totalInvestors": len(all_rows),
        "exportedInvestors": len(investor_ids) + len(bottom_investor_ids),
        "distribution": distribution,
        "investorIndex": investor_index,
        "platformBands": platform_bands,
        "investorIds": investor_ids,
        "bottomInvestorIds": bottom_investor_ids,
        "sourceTop25Ids": source_top25_ids,
        "currentNarratives": current,
    }
    EXPORT.parent.mkdir(parents=True, exist_ok=True)
    EXPORT.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"[sv-v0] exported {len(investor_ids)} investors -> {EXPORT}", flush=True)


def run(args: argparse.Namespace) -> None:
    con = connect()
    ensure_tables(con)
    only = {x.strip().upper() for x in args.only.split(",") if x.strip()} if args.only else None
    sources = source_set(getattr(args, "source", "x"))
    tweet_dirs = [Path(p).expanduser() for p in args.tweet_dir] if args.tweet_dir else TWEET_DIRS
    stages = ["candidates", "transcripts", "extract", "settle", "score", "export"] if args.stage == "all" else [args.stage]
    if "candidates" in stages:
        if "x" in sources:
            build_candidates(con, tweet_dirs, args.candidate_limit, args.min_score, only)
        if "reddit" in sources:
            build_reddit_candidates(
                con,
                args.candidate_limit,
                args.min_score,
                only,
                args.reddit_author_limit,
                args.reddit_since_days,
                args.reddit_min_author_posts,
            )
        if "youtube" in sources:
            build_youtube_candidates(
                con,
                args.candidate_limit,
                args.min_score,
                only,
                args.youtube_min_subs,
                args.youtube_since_days,
            )
        if "xueqiu" in sources:
            build_xueqiu_candidates(
                con,
                args.candidate_limit,
                args.min_score,
                only,
                args.xueqiu_pool_version,
                args.xueqiu_since_days,
                not args.xueqiu_allow_partial,
            )
        pending_adapters = sorted((sources - SUPPORTED_SOURCES) & SV_PLATFORMS)
        if pending_adapters:
            print(
                f"[sv-v0] candidate adapters not implemented yet: {', '.join(pending_adapters)}; "
                "existing candidates for these sources can still be extracted/scored.",
                flush=True,
            )
    youtube_created_since = None
    if "youtube" in sources and args.youtube_since_days > 0:
        latest_youtube_candidate = con.execute(
            "SELECT MAX(created_at) AS mx FROM sv_call_candidate WHERE source='youtube'"
        ).fetchone()
        if latest_youtube_candidate and latest_youtube_candidate["mx"]:
            latest_day = dt.datetime.fromisoformat(
                str(latest_youtube_candidate["mx"])[:10]
            )
            youtube_created_since = (
                latest_day - dt.timedelta(days=max(1, args.youtube_since_days))
            ).strftime("%Y-%m-%d")
    reddit_created_since = None
    if "reddit" in sources and args.reddit_since_days > 0:
        reddit_created_since = (
            dt.datetime.utcnow() - dt.timedelta(days=max(1, args.reddit_since_days))
        ).strftime("%Y-%m-%d")
    if "transcripts" in stages and "youtube" in sources:
        generate_youtube_candidate_transcripts(
            con,
            args.extract_limit,
            args.workers,
            args.per_author_min,
            args.per_author_max,
            args.force,
            only,
            youtube_created_since,
        )
    if "extract" in stages:
        extract_calls(
            con,
            args.extract_limit,
            args.workers,
            args.force,
            args.extract_mode,
            args.per_author_min,
            args.per_author_max,
            sources,
            tickers=only,
            youtube_created_since=youtube_created_since,
            reddit_created_since=reddit_created_since,
        )
    if "audit" in stages:
        audit_x_calls(
            con,
            args.extract_limit,
            args.workers,
            args.force,
            tickers=only,
        )
    if "settle" in stages:
        settle_calls(con, sources)
    if "score" in stages:
        score_investors(
            con,
            allow_partial_xueqiu=args.xueqiu_allow_partial,
            xueqiu_pool_version=args.xueqiu_pool_version,
            sources=sources,
        )
    if "export" in stages:
        export_json(con)
    con.close()


def main() -> None:
    ap = argparse.ArgumentParser(description="Smart Account v0 hybrid scorer")
    ap.add_argument("--stage", choices=["candidates", "transcripts", "extract", "audit", "settle", "score", "export", "all"], default="all")
    ap.add_argument("--source", default="x", help="Comma-separated source subset: x,youtube,reddit,xueqiu,toss,all. Default keeps legacy X-only behavior.")
    ap.add_argument("--candidate-limit", type=int, default=50_000, help="0 means insert all recalled candidates.")
    ap.add_argument("--extract-limit", type=int, default=1_000, help="0 means all pending candidates.")
    ap.add_argument("--extract-mode", choices=["rank", "author-balanced"], default="rank")
    ap.add_argument("--per-author-min", type=int, default=20)
    ap.add_argument("--per-author-max", type=int, default=80)
    ap.add_argument("--min-score", type=float, default=12.0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--only", default="", help="Comma-separated ticker subset.")
    ap.add_argument("--tweet-dir", action="append", default=[], help="Override/add tweet JSONL directories.")
    ap.add_argument("--reddit-author-limit", type=int, default=1_000, help="Top Reddit author pool size for candidate recall; 0 means all authors.")
    ap.add_argument("--reddit-since-days", type=int, default=365, help="Reddit candidate lookback window.")
    ap.add_argument("--reddit-min-author-posts", type=int, default=8, help="Minimum ticker-mentioned Reddit posts for Reddit author-pool eligibility.")
    ap.add_argument("--youtube-min-subs", type=int, default=2_000, help="Minimum public YouTube subscribers for Score eligibility (shared product threshold).")
    ap.add_argument("--youtube-since-days", type=int, default=365, help="YouTube candidate lookback window.")
    ap.add_argument("--xueqiu-pool-version", default="", help="Versioned selected Xueqiu author pool; empty uses the latest pool.")
    ap.add_argument("--xueqiu-since-days", type=int, default=365, help="Xueqiu candidate lookback window.")
    ap.add_argument("--xueqiu-allow-partial", action="store_true", help="Allow candidate recall before every selected author job is done; disabled by default.")
    ap.add_argument("--force", action="store_true", help="Re-extract candidates already in sv_call.")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
