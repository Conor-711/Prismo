"""股票 ticker 抽取器。

精度优先策略（每个命中带 confidence 与 method）：
  - cashtag  `$AAPL`         → 0.98（即使在停用表也算）
  - dict     裸大写词命中字典  → 0.9/0.82/0.65（按长度），单字母不认
  - company  精选公司名别名    → 0.75
停用表里的歧义 token（A/ON/DD/IT/CEO/YOLO…）必须以 cashtag 出现才算。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from ..common.config import PKG_DATA_DIR

# 精选、低歧义的公司名/别名 → ticker（仅收录在散文中出现也基本不会误判的）
ALIASES: dict[str, str] = {
    "nvidia": "NVDA", "tesla": "TSLA", "microsoft": "MSFT", "amazon": "AMZN",
    "google": "GOOGL", "alphabet": "GOOGL", "facebook": "META", "meta platforms": "META",
    "netflix": "NFLX", "palantir": "PLTR", "gamestop": "GME", "coinbase": "COIN",
    "robinhood": "HOOD", "microstrategy": "MSTR", "broadcom": "AVGO", "qualcomm": "QCOM",
    "supermicro": "SMCI", "super micro": "SMCI", "taiwan semiconductor": "TSM",
    "eli lilly": "LLY", "novo nordisk": "NVO", "moderna": "MRNA", "pfizer": "PFE",
    "salesforce": "CRM", "snowflake": "SNOW", "cloudflare": "NET", "crowdstrike": "CRWD",
    "datadog": "DDOG", "shopify": "SHOP", "spotify": "SPOT", "roblox": "RBLX",
    "rivian": "RIVN", "lucid": "LCID", "chipotle": "CMG", "starbucks": "SBUX",
    "costco": "COST", "walmart": "WMT", "berkshire": "BRK.B", "alibaba": "BABA",
    "rocket lab": "RKLB", "spacex": "SPCX", "space exploration technologies": "SPCX",
    "soundhound": "SOUN", "draftkings": "DKNG", "celsius": "CELH",
    "enphase": "ENPH", "first solar": "FSLR", "constellation energy": "CEG",
    "nuscale": "SMR", "intuitive machines": "LUNR", "archer aviation": "ACHR",
}

CASHTAG_RE = re.compile(r"\$([A-Za-z]{1,5}(?:\.[A-Za-z])?)")
BARE_RE = re.compile(r"\b([A-Z]{1,5})\b")
# 港股/A 股数字代码：0700 / 0700.HK / 9988 / 600519.SS / 300750.SZ。
# 仅当规范化后命中「策划的闭集」(cn_codes) 才记为提及 → 几乎零误报。
CN_CODE_RE = re.compile(r"(?<![\w])(\d{3,6})(\.(?:HK|SS|SZ|SH))?\b", re.IGNORECASE)


@dataclass
class TickerDict:
    tickers: set[str] = field(default_factory=set)
    stop: set[str] = field(default_factory=set)
    aliases: dict[str, str] = field(default_factory=dict)
    cn_codes: dict[str, str] = field(default_factory=dict)  # 数字代码各种写法 → 规范 ticker


def _build_cn_codes(tickers: set[str]) -> dict[str, str]:
    """从 ticker_meta 里形如 `0700.HK` / `600519.SS` 的代码构建闭集查找表。
    登记三种写法：带后缀(0700.HK)、裸数字(0700)、去前导零(700)，都映射回规范 ticker。"""
    out: dict[str, str] = {}
    pat = re.compile(r"^(\d{3,6})\.(HK|SS|SZ)$")
    for tk in tickers:
        m = pat.match(tk)
        if not m:
            continue
        digits, suf = m.group(1), m.group(2)
        out[f"{digits}.{suf}"] = tk
        out[digits] = tk
        dz = digits.lstrip("0")
        if dz and dz != digits:
            out[dz] = tk
    return out


def load_stoplist() -> set[str]:
    path = PKG_DATA_DIR / "ticker_stoplist.txt"
    out: set[str] = set()
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.add(line.upper())
    return out


def load_ticker_dict(session) -> TickerDict:
    """从 DB 的 ticker_meta + 停用表 + 别名表构建抽取字典。"""
    from sqlalchemy import select

    from ..common.models import TickerMeta

    tickers: set[str] = set()
    aliases: dict[str, str] = dict(ALIASES)
    for tk, al in session.execute(select(TickerMeta.ticker, TickerMeta.aliases)).all():
        tickers.add(tk.upper())
        for a in (al or []):
            aliases[str(a).lower()] = tk.upper()
    return TickerDict(tickers=tickers, stop=load_stoplist(), aliases=aliases,
                      cn_codes=_build_cn_codes(tickers))


def load_ticker_dict_from_fallback() -> TickerDict:
    """离线/单测用：直接从 fallback_tickers.json 构建。"""
    import json

    with open(PKG_DATA_DIR / "fallback_tickers.json", "r", encoding="utf-8") as f:
        rows = json.load(f)
    tickers = {r["ticker"].upper() for r in rows}
    return TickerDict(tickers=tickers, stop=load_stoplist(), aliases=dict(ALIASES))


def _snippet(text: str, pos: int, span: int = 36) -> str:
    a, b = max(0, pos - span), min(len(text), pos + span)
    return text[a:b].replace("\n", " ").strip()


def extract_mentions(text: str, tdict: TickerDict, min_confidence: float = 0.5) -> list[dict]:
    """返回去重后的提及列表：[{ticker, method, confidence, context_snippet}]。"""
    if not text:
        return []
    best: dict[str, dict] = {}

    def consider(ticker: str, method: str, conf: float, pos: int):
        ticker = ticker.upper()
        if ticker not in tdict.tickers or conf < min_confidence:
            return
        cur = best.get(ticker)
        if cur is None or conf > cur["confidence"]:
            best[ticker] = {
                "ticker": ticker,
                "method": method,
                "confidence": conf,
                "context_snippet": _snippet(text, pos),
            }

    # 1) cashtag（最高置信，停用表也认）
    for m in CASHTAG_RE.finditer(text):
        consider(m.group(1), "cashtag", 0.98, m.start())

    # 2) 裸大写词（需在字典、不在停用表、长度>=2）
    for m in BARE_RE.finditer(text):
        tok = m.group(1)
        if tok in tdict.stop or len(tok) < 2:
            continue
        conf = 0.9 if len(tok) >= 4 else 0.82 if len(tok) == 3 else 0.65
        consider(tok, "dict", conf, m.start())

    # 2.5) 港股/A 股数字代码（闭集，几乎零误报）
    if tdict.cn_codes:
        for m in CN_CODE_RE.finditer(text):
            digits, suf = m.group(1), (m.group(2) or "")
            if suf:
                suf = suf.upper().replace(".SH", ".SS")
                canon = (tdict.cn_codes.get(digits + suf) or tdict.cn_codes.get(digits)
                         or tdict.cn_codes.get(digits.lstrip("0")))
                conf = 0.95
            else:
                # 裸数字：至少 4 位才认（避免把 "700 million" 之类当代码）
                canon = tdict.cn_codes.get(digits) if len(digits) >= 4 else None
                conf = 0.9
            if canon:
                consider(canon, "cncode", conf, m.start())

    # 3) 公司名/别名（精选、低歧义）
    low = text.lower()
    for phrase, ticker in tdict.aliases.items():
        idx = low.find(phrase)
        if idx == -1:
            continue
        # 词边界校验，避免子串误命中
        left_ok = idx == 0 or not low[idx - 1].isalnum()
        end = idx + len(phrase)
        right_ok = end >= len(low) or not low[end].isalnum()
        if left_ok and right_ok:
            consider(ticker, "company", 0.75, idx)

    return list(best.values())


# ----------------------------- 写入 DB -----------------------------
def extract_for_posts(reextract: bool = False, limit: int | None = None) -> int:
    """对库中帖子抽取 ticker 并写入 mentions。返回新增 mention 数。"""
    from sqlalchemy import select

    from ..common.db import session_scope
    from ..common.models import Mention, Post

    written = 0
    with session_scope() as s:
        tdict = load_ticker_dict(s)
        if not tdict.tickers:
            raise RuntimeError("ticker_meta 为空，请先 `make seed`。")

        existing: set[str] = set()
        if not reextract:
            existing = {
                pid for (pid,) in s.execute(
                    select(Mention.item_id).where(Mention.item_type == "post").distinct()
                ).all()
            }

        stmt = select(Post)
        if limit:
            stmt = stmt.limit(limit)
        posts = s.execute(stmt).scalars().all()

        for p in posts:
            if not reextract and p.id in existing:
                continue
            text = f"{p.title}\n{p.selftext or ''}"
            for mt in extract_mentions(text, tdict):
                s.merge(
                    Mention(
                        ticker=mt["ticker"],
                        item_id=p.id,
                        item_type="post",
                        subreddit_id=p.subreddit_id,
                        author_id=p.author_id,
                        context_snippet=mt["context_snippet"],
                        confidence=mt["confidence"],
                        method=mt["method"],
                        created_utc=p.created_utc,
                    )
                )
                written += 1
    print(f"[extract] 写入 mentions：{written} 条。")
    return written


if __name__ == "__main__":
    import sys

    extract_for_posts(reextract="--reextract" in sys.argv)
