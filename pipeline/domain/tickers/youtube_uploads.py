"""Map YouTube author-pool uploads to US stock and ETF tickers."""
from __future__ import annotations

import datetime as dt
import json
import re
import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from ...common.ticker_extraction import ALIASES, BARE_RE, CASHTAG_RE, load_stoplist


MAPPING_VERSION = "youtube-title-v3"
LEGAL_SUFFIXES = {
    "inc", "incorporated", "corp", "corporation", "company", "co", "plc",
    "ltd", "limited", "holdings", "holding", "group", "llc", "lp", "sa",
    "nv", "common", "stock", "class", "ordinary", "shares",
}
GENERIC_COMPANY_NAMES = {
    "target", "gap", "best", "first", "global", "united", "american",
    "international", "digital", "core", "one", "up", "all", "now", "live", "news",
}
# These are valid symbols but also ordinary words, prepositions, product terms, or
# industry acronyms. A bare uppercase token is not enough evidence; cashtags and
# unambiguous company-name matches still map them normally.
CASHTAG_ONLY_BARE_TICKERS = {
    "APP", "CAR", "DE", "EAT", "EYE", "FUN", "GIS", "GOLD", "GPS", "HBM",
    "JOB", "NET", "NEXT", "NOTE", "ROAD", "RUN", "SAVE", "SMR", "SUN", "TALK",
    "TRUE", "VERY", "WTI", "YOU",
}
STRICT_CASHTAG_ONLY_BARE_TICKERS = {"GOLD", "HBM", "NEXT"}
CONTEXT_REQUIRED_BARE_TICKERS = {"ARM"}
FINANCE_CONTEXT_RE = re.compile(
    r"\b(stock|stocks|share|shares|equity|equities|ticker|earnings|revenue|eps|guidance|"
    r"valuation|price target|forecast|dividend|portfolio|invest(?:ing|ment|or)?|trading|"
    r"buy|sell|bullish|bearish|nasdaq|nyse|s&p|etf|options?|market cap|technical analysis|"
    r"fundamental analysis|undervalued|overvalued|upside|downside|surge|soar|rally|crash|"
    r"breakout|price prediction|worth buying)\b|"
    r"美股|股票|股价|财报|财報|业绩|業績|目标价|目標價|买入|買入|卖出|賣出|看多|看空|"
    r"投资|投資|估值|上涨|上漲|下跌|预测|預測|"
    r"주식|주가|실적|매수|매도|목표가|증시|전망|투자|상승|하락|"
    r"株式|株価|決算|買い|売り|目標株価|"
    r"acciones|bolsa|invertir|inversión|comprar|vender|"
    r"aktie|aktien|börse|kaufen|verkaufen",
    re.I,
)


@dataclass(frozen=True)
class MappingSummary:
    pool_version: str
    scanned_videos: int
    matched_videos: int
    mappings: int
    matched_authors: int


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS yt_channel_upload_relevance (
          video_id TEXT PRIMARY KEY,
          mapping_version TEXT NOT NULL,
          finance_relevance_score REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          mapped_ticker_count INTEGER NOT NULL DEFAULT 0,
          reasons_json TEXT NOT NULL DEFAULT '[]',
          mapped_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS yt_channel_upload_ticker (
          video_id TEXT NOT NULL,
          ticker TEXT NOT NULL,
          method TEXT NOT NULL,
          confidence REAL NOT NULL,
          title_match INTEGER NOT NULL DEFAULT 0,
          context_snippet TEXT NOT NULL DEFAULT '',
          mapping_version TEXT NOT NULL,
          mapped_at TEXT NOT NULL,
          PRIMARY KEY (video_id, ticker)
        );
        CREATE INDEX IF NOT EXISTS idx_yt_upload_ticker_symbol
          ON yt_channel_upload_ticker(ticker, confidence);
        CREATE INDEX IF NOT EXISTS idx_yt_upload_ticker_video
          ON yt_channel_upload_ticker(video_id);
        CREATE INDEX IF NOT EXISTS idx_yt_upload_relevance_status
          ON yt_channel_upload_relevance(status, finance_relevance_score);
        """
    )


def _latest_pool_version(con: sqlite3.Connection) -> str:
    row = con.execute(
        "SELECT pool_version FROM yt_author_pool_run ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if not row:
        raise RuntimeError("yt_author_pool_run is empty")
    return str(row[0])


def _normalize(value: str) -> str:
    value = unicodedata.normalize("NFKC", value or "").lower()
    value = re.sub(r"[^\w$]+", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


def _company_aliases(con: sqlite3.Connection, valid_tickers: set[str]) -> dict[str, str]:
    candidates: dict[str, set[str]] = {}

    def add(alias: str, ticker: str) -> None:
        normalized = _normalize(alias)
        if not normalized or ticker not in valid_tickers:
            return
        if len(normalized) < 4 or normalized in GENERIC_COMPANY_NAMES:
            return
        candidates.setdefault(normalized, set()).add(ticker)

    for alias, ticker in ALIASES.items():
        add(alias, ticker.upper())
    for row in con.execute(
        """
        SELECT ticker, company_name, aliases FROM ticker_meta
        WHERE COALESCE(is_active, 1) = 1
          AND (market = 'us' OR market IS NULL OR market = '')
        """
    ):
        ticker = str(row["ticker"] or "").upper()
        name = _normalize(str(row["company_name"] or ""))
        add(name, ticker)
        words = name.split()
        while len(words) > 1 and words[-1] in LEGAL_SUFFIXES:
            words.pop()
            add(" ".join(words), ticker)
        try:
            aliases = json.loads(row["aliases"] or "[]")
        except (TypeError, json.JSONDecodeError):
            aliases = []
        if isinstance(aliases, list):
            for alias in aliases:
                add(str(alias), ticker)
    return {alias: next(iter(tickers)) for alias, tickers in candidates.items() if len(tickers) == 1}


def _alias_pattern(aliases: dict[str, str]) -> re.Pattern[str] | None:
    if not aliases:
        return None
    ordered = sorted(aliases, key=lambda value: (-len(value), value))
    return re.compile(r"(?<!\w)(" + "|".join(re.escape(value) for value in ordered) + r")(?!\w)")


def _alias_matches(
    normalized_text: str,
    aliases: dict[str, str],
    alias_lengths: tuple[int, ...] | None = None,
) -> list[tuple[str, int]]:
    """Find normalized company phrases with bounded n-gram dictionary lookups."""
    words = normalized_text.split()
    if not words or not aliases:
        return []
    lengths = alias_lengths or tuple({len(alias.split()) for alias in aliases})
    offsets: list[int] = []
    offset = 0
    for word in words:
        offsets.append(offset)
        offset += len(word) + 1
    found: list[tuple[str, int]] = []
    for start in range(len(words)):
        for length in lengths:
            if start + length > len(words):
                continue
            phrase = " ".join(words[start : start + length])
            if phrase in aliases:
                found.append((phrase, offsets[start]))
    return found


def _snippet(text: str, start: int, span: int = 70) -> str:
    return re.sub(r"\s+", " ", text[max(0, start - span) : start + span]).strip()[:220]


def _map_video(
    title: str,
    description: str,
    *,
    valid_tickers: set[str],
    stoplist: set[str],
    aliases: dict[str, str],
    alias_pattern: re.Pattern[str] | None,
    max_tickers: int,
    alias_lengths: tuple[int, ...] | None = None,
) -> tuple[list[dict], float, list[str]]:
    title = title or ""
    description = (description or "")[:1200]
    title_finance_context = bool(FINANCE_CONTEXT_RE.search(title))
    matches: dict[str, dict] = {}
    reasons: set[str] = set()

    def add(ticker: str, method: str, confidence: float, title_match: bool, text: str, pos: int) -> None:
        ticker = ticker.upper().replace("-", ".")
        if ticker not in valid_tickers:
            return
        current = matches.get(ticker)
        if current is None or confidence > current["confidence"]:
            matches[ticker] = {
                "ticker": ticker,
                "method": method,
                "confidence": confidence,
                "title_match": int(title_match),
                "context_snippet": _snippet(text, pos),
            }
        reasons.add(method)

    for match in CASHTAG_RE.finditer(title):
        add(match.group(1), "title_cashtag", 0.99, True, title, match.start())
    for match in BARE_RE.finditer(title):
        token = match.group(1).upper()
        explicit_stock_symbol = bool(
            token not in STRICT_CASHTAG_ONLY_BARE_TICKERS
            and re.search(
                rf"\b{re.escape(token)}\s+(?:stock|shares?|ticker)\b|"
                rf"\b(?:ticker|symbol)\s+{re.escape(token)}\b",
                title,
                re.I,
            )
        )
        if (
            token not in stoplist
            and (token not in CASHTAG_ONLY_BARE_TICKERS or explicit_stock_symbol)
            and len(token) >= 2
            and (len(token) >= 3 or title_finance_context)
            and (token not in CONTEXT_REQUIRED_BARE_TICKERS or title_finance_context)
        ):
            add(token, "title_ticker", 0.93, True, title, match.start())
    normalized_title = _normalize(title)
    company_matches = _alias_matches(normalized_title, aliases, alias_lengths)
    company_tickers = {aliases[alias] for alias, _ in company_matches}
    if title_finance_context:
        for alias, start in company_matches:
            add(aliases[alias], "title_company", 0.90, True, normalized_title, start)

    # Descriptions often contain channel-wide sponsor text and unrelated stock lists.
    # Use only explicit cashtags near the start, and only when the title already proves
    # that the video is finance content but does not identify a ticker itself.
    if title_finance_context and not matches:
        description_head = description[:600]
        for match in CASHTAG_RE.finditer(description_head):
            add(
                match.group(1), "description_cashtag", 0.95, False,
                description_head, match.start(),
            )

    ordered = sorted(
        matches.values(),
        key=lambda item: (-item["title_match"], -item["confidence"], item["ticker"]),
    )[:max_tickers]
    if not title_finance_context:
        ordered = [
            item for item in ordered
            if item["method"] in {"title_cashtag", "title_ticker", "title_company"}
        ]
    relevance = max((item["confidence"] for item in ordered), default=0.0) * 100
    if title_finance_context and ordered:
        relevance = min(100.0, relevance + 3.0)
        reasons.add("title_finance_context")
    return ordered, round(relevance, 2), sorted(reasons)


def map_author_uploads(
    db_path: str | Path,
    *,
    pool_version: str | None = None,
    force: bool = False,
    limit: int | None = None,
    max_tickers: int = 6,
) -> MappingSummary:
    if max_tickers <= 0:
        raise ValueError("max_tickers must be positive")
    con = sqlite3.connect(str(db_path), timeout=60)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=60000")
    _ensure_schema(con)
    pool_version = pool_version or _latest_pool_version(con)
    valid_tickers = {
        str(row[0]).upper()
        for row in con.execute(
            """
            SELECT DISTINCT p.ticker FROM price_daily p
            JOIN ticker_meta t ON t.ticker = p.ticker
            WHERE COALESCE(t.is_active, 1) = 1
              AND (t.market = 'us' OR t.market IS NULL OR t.market = '')
            """
        )
    }
    aliases = _company_aliases(con, valid_tickers)
    alias_pattern = _alias_pattern(aliases)
    alias_lengths = tuple(sorted({len(alias.split()) for alias in aliases}, reverse=True))
    stoplist = load_stoplist()
    params: list[object] = [pool_version]
    where = ""
    if not force:
        where = "AND (r.video_id IS NULL OR r.mapping_version <> ?)"
        params.append(MAPPING_VERSION)
    sql = f"""
        SELECT u.video_id, u.channel_id, u.title, u.description
        FROM yt_channel_upload u
        JOIN yt_author_pool p
          ON p.channel_id = u.channel_id AND p.pool_version = ? AND p.selected = 1
        LEFT JOIN yt_channel_upload_relevance r ON r.video_id = u.video_id
        WHERE 1=1 {where}
        ORDER BY u.published_utc DESC, u.video_id
    """
    if limit is not None:
        sql += " LIMIT ?"
        params.append(max(0, limit))
    rows = con.execute(sql, params)
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    scanned = matched = mappings = 0
    matched_authors: set[str] = set()
    map_buffer: list[tuple] = []
    relevance_buffer: list[tuple] = []

    def flush() -> None:
        if map_buffer:
            con.executemany(
                """
                INSERT INTO yt_channel_upload_ticker (
                  video_id,ticker,method,confidence,title_match,context_snippet,mapping_version,mapped_at
                ) VALUES (?,?,?,?,?,?,?,?)
                ON CONFLICT(video_id,ticker) DO UPDATE SET
                  method=excluded.method, confidence=excluded.confidence,
                  title_match=excluded.title_match, context_snippet=excluded.context_snippet,
                  mapping_version=excluded.mapping_version, mapped_at=excluded.mapped_at
                """,
                map_buffer,
            )
            map_buffer.clear()
        if relevance_buffer:
            con.executemany(
                """
                INSERT INTO yt_channel_upload_relevance (
                  video_id,mapping_version,finance_relevance_score,status,
                  mapped_ticker_count,reasons_json,mapped_at
                ) VALUES (?,?,?,?,?,?,?)
                ON CONFLICT(video_id) DO UPDATE SET
                  mapping_version=excluded.mapping_version,
                  finance_relevance_score=excluded.finance_relevance_score,
                  status=excluded.status, mapped_ticker_count=excluded.mapped_ticker_count,
                  reasons_json=excluded.reasons_json, mapped_at=excluded.mapped_at
                """,
                relevance_buffer,
            )
            relevance_buffer.clear()
        con.commit()

    for row in rows:
        scanned += 1
        if force:
            con.execute("DELETE FROM yt_channel_upload_ticker WHERE video_id = ?", (row["video_id"],))
        found, relevance, reasons = _map_video(
            row["title"] or "", row["description"] or "",
            valid_tickers=valid_tickers, stoplist=stoplist, aliases=aliases,
            alias_pattern=alias_pattern, alias_lengths=alias_lengths,
            max_tickers=max_tickers,
        )
        if found:
            matched += 1
            matched_authors.add(str(row["channel_id"]))
        for item in found:
            map_buffer.append((
                row["video_id"], item["ticker"], item["method"], item["confidence"],
                item["title_match"], item["context_snippet"], MAPPING_VERSION, now,
            ))
            mappings += 1
        relevance_buffer.append((
            row["video_id"], MAPPING_VERSION, relevance,
            "matched" if found else "no_match", len(found),
            json.dumps(reasons, ensure_ascii=False), now,
        ))
        if len(relevance_buffer) >= 2_000:
            flush()
            if scanned % 20_000 == 0:
                print(
                    f"[yt-author-map] scanned={scanned} matched={matched} mappings={mappings}",
                    flush=True,
                )
    flush()
    con.close()
    return MappingSummary(
        pool_version=pool_version, scanned_videos=scanned, matched_videos=matched,
        mappings=mappings, matched_authors=len(matched_authors),
    )
