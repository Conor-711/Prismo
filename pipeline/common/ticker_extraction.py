"""Shared ticker mention extraction primitives."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

from .config import PKG_DATA_DIR

# 精选、低歧义的公司名/别名 → ticker（仅收录在散文中出现也基本不会误判的）
ALIASES: dict[str, str] = {
    "nvidia": "NVDA",
    "tesla": "TSLA",
    "microsoft": "MSFT",
    "amazon": "AMZN",
    "google": "GOOGL",
    "alphabet": "GOOGL",
    "facebook": "META",
    "meta platforms": "META",
    "netflix": "NFLX",
    "palantir": "PLTR",
    "gamestop": "GME",
    "coinbase": "COIN",
    "robinhood": "HOOD",
    "microstrategy": "MSTR",
    "broadcom": "AVGO",
    "qualcomm": "QCOM",
    "supermicro": "SMCI",
    "super micro": "SMCI",
    "taiwan semiconductor": "TSM",
    "eli lilly": "LLY",
    "novo nordisk": "NVO",
    "moderna": "MRNA",
    "pfizer": "PFE",
    "salesforce": "CRM",
    "snowflake": "SNOW",
    "cloudflare": "NET",
    "crowdstrike": "CRWD",
    "datadog": "DDOG",
    "shopify": "SHOP",
    "spotify": "SPOT",
    "roblox": "RBLX",
    "rivian": "RIVN",
    "lucid": "LCID",
    "chipotle": "CMG",
    "starbucks": "SBUX",
    "costco": "COST",
    "walmart": "WMT",
    "berkshire": "BRK.B",
    "alibaba": "BABA",
    "rocket lab": "RKLB",
    "spacex": "SPCX",
    "space exploration technologies": "SPCX",
    "soundhound": "SOUN",
    "draftkings": "DKNG",
    "celsius": "CELH",
    "enphase": "ENPH",
    "first solar": "FSLR",
    "constellation energy": "CEG",
    "nuscale": "SMR",
    "intuitive machines": "LUNR",
    "archer aviation": "ACHR",
    "s&p 500": "SPY",
    "spdr s&p 500": "SPY",
    "nasdaq 100": "QQQ",
    "invesco qqq": "QQQ",
    "iris energy": "IREN",
    "iren ltd": "IREN",
    "nebius": "NBIS",
    "nebius group": "NBIS",
    "ast spacemobile": "ASTS",
    "space mobile": "ASTS",
}

CASHTAG_RE = re.compile(r"\$([A-Za-z]{1,5}(?:\.[A-Za-z])?)")
BARE_RE = re.compile(r"\b([A-Z]{1,5})\b")
CN_CODE_RE = re.compile(r"(?<![\w])(\d{3,6})(\.(?:HK|SS|SZ|SH))?\b", re.IGNORECASE)


@dataclass
class TickerDict:
    tickers: set[str] = field(default_factory=set)
    stop: set[str] = field(default_factory=set)
    aliases: dict[str, str] = field(default_factory=dict)
    cn_codes: dict[str, str] = field(default_factory=dict)


def _build_cn_codes(tickers: set[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    pat = re.compile(r"^(\d{3,6})\.(HK|SS|SZ)$")
    for tk in tickers:
        match = pat.match(tk)
        if not match:
            continue
        digits, suffix = match.group(1), match.group(2)
        out[f"{digits}.{suffix}"] = tk
        out[digits] = tk
        without_zero = digits.lstrip("0")
        if without_zero and without_zero != digits:
            out[without_zero] = tk
    return out


def load_stoplist() -> set[str]:
    path = PKG_DATA_DIR / "ticker_stoplist.txt"
    out: set[str] = set()
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                out.add(line.upper())
    return out


def load_ticker_dict(session) -> TickerDict:
    """Build extraction dictionary from ticker metadata, stoplist, and aliases."""
    from sqlalchemy import select

    from .models import TickerMeta

    tickers: set[str] = set()
    aliases: dict[str, str] = dict(ALIASES)
    for ticker, row_aliases in session.execute(select(TickerMeta.ticker, TickerMeta.aliases)).all():
        tickers.add(ticker.upper())
        for alias in row_aliases or []:
            aliases[str(alias).lower()] = ticker.upper()
    return TickerDict(
        tickers=tickers,
        stop=load_stoplist(),
        aliases=aliases,
        cn_codes=_build_cn_codes(tickers),
    )


def load_ticker_dict_from_fallback() -> TickerDict:
    """Build an offline test dictionary from fallback_tickers.json."""
    with open(PKG_DATA_DIR / "fallback_tickers.json", "r", encoding="utf-8") as handle:
        rows = json.load(handle)
    tickers = {row["ticker"].upper() for row in rows}
    return TickerDict(tickers=tickers, stop=load_stoplist(), aliases=dict(ALIASES))


def _snippet(text: str, pos: int, span: int = 36) -> str:
    start, end = max(0, pos - span), min(len(text), pos + span)
    return text[start:end].replace("\n", " ").strip()


def extract_mentions(text: str, tdict: TickerDict, min_confidence: float = 0.5) -> list[dict]:
    """Return deduplicated ticker mentions with confidence metadata."""
    if not text:
        return []
    best: dict[str, dict] = {}

    def consider(ticker: str, method: str, confidence: float, pos: int) -> None:
        ticker = ticker.upper()
        if ticker not in tdict.tickers or confidence < min_confidence:
            return
        current = best.get(ticker)
        if current is None or confidence > current["confidence"]:
            best[ticker] = {
                "ticker": ticker,
                "method": method,
                "confidence": confidence,
                "context_snippet": _snippet(text, pos),
            }

    for match in CASHTAG_RE.finditer(text):
        consider(match.group(1), "cashtag", 0.98, match.start())

    for match in BARE_RE.finditer(text):
        token = match.group(1)
        if token in tdict.stop or len(token) < 2:
            continue
        confidence = 0.9 if len(token) >= 4 else 0.82 if len(token) == 3 else 0.65
        consider(token, "dict", confidence, match.start())

    if tdict.cn_codes:
        for match in CN_CODE_RE.finditer(text):
            digits, suffix = match.group(1), match.group(2) or ""
            if suffix:
                suffix = suffix.upper().replace(".SH", ".SS")
                canonical = (
                    tdict.cn_codes.get(digits + suffix)
                    or tdict.cn_codes.get(digits)
                    or tdict.cn_codes.get(digits.lstrip("0"))
                )
                confidence = 0.95
            else:
                canonical = tdict.cn_codes.get(digits) if len(digits) >= 4 else None
                confidence = 0.9
            if canonical:
                consider(canonical, "cncode", confidence, match.start())

    lowercase = text.lower()
    for phrase, ticker in tdict.aliases.items():
        idx = lowercase.find(phrase)
        if idx == -1:
            continue
        left_ok = idx == 0 or not lowercase[idx - 1].isalnum()
        end = idx + len(phrase)
        right_ok = end >= len(lowercase) or not lowercase[end].isalnum()
        if left_ok and right_ok:
            consider(ticker, "company", 0.75, idx)

    return list(best.values())


def extract_for_posts(reextract: bool = False, limit: int | None = None) -> int:
    """Extract ticker mentions from stored posts and write Mention rows."""
    from sqlalchemy import select

    from .db import session_scope
    from .models import Mention, Post

    written = 0
    with session_scope() as session:
        tdict = load_ticker_dict(session)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")

        existing: set[str] = set()
        if not reextract:
            existing = {
                post_id
                for (post_id,) in session.execute(
                    select(Mention.item_id).where(Mention.item_type == "post").distinct()
                ).all()
            }

        stmt = select(Post)
        if limit:
            stmt = stmt.limit(limit)
        posts = session.execute(stmt).scalars().all()

        for post in posts:
            if not reextract and post.id in existing:
                continue
            text = f"{post.title}\n{post.selftext or ''}"
            for mention in extract_mentions(text, tdict):
                session.merge(
                    Mention(
                        ticker=mention["ticker"],
                        item_id=post.id,
                        item_type="post",
                        subreddit_id=post.subreddit_id,
                        author_id=post.author_id,
                        context_snippet=mention["context_snippet"],
                        confidence=mention["confidence"],
                        method=mention["method"],
                        created_utc=post.created_utc,
                    )
                )
                written += 1
    print(f"[extract] 写入 mentions：{written} 条。")
    return written
