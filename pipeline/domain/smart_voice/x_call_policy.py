"""Ownership and evidence policy for X Smart Account calls.

The extraction model may recall market news correctly while still assigning the
reported move to the post author.  This module is the deterministic gate after
LLM extraction: an X call only survives when the author owns a directional
statement and the cited evidence is present verbatim in the post.
"""
from __future__ import annotations

import re
from typing import Any


X_CALL_POLICY_VERSION = "x-owned-evidence-v1"

_SPACE_RE = re.compile(r"\s+")
_FORWARD_RE = re.compile(
    r"\b(?:i|we)\s+(?:think|believe|expect|predict|forecast|remain|am|are|would|will|"
    r"plan|intend|see|like)\b|"
    r"\b(?:will|would|should|could|expect(?:s|ed)?|predict(?:s|ed)?|forecast(?:s|ed)?|"
    r"target(?:s|ed)?|headed|going|upside|downside|bullish|bearish|long|short|"
    r"buy|sell|add(?:ing|ed)?|trim(?:ming|med)?|exit(?:ing|ed)?|hold(?:ing|s)?)\b|"
    r"我(?:们)?(?:认为|相信|预计|预测|看好|看空|买入|卖出|加仓|减仓|持有|目标)|"
    r"(?:将|会|可能|应该|预计|目标|看好|看空|买入|卖出|加仓|减仓|做多|做空|止损|止盈)|"
    r"(?:予想|見込|目標|強気|弱気|買い|売り|ロング|ショート)|"
    r"(?:예상|전망|목표|강세|약세|매수|매도|롱|숏)",
    re.I,
)
_POSITION_RE = re.compile(
    r"\b(?:i|we)\s+(?:bought|sold|added|trimmed|exited|closed|own|hold|am buying|"
    r"are buying|am selling|are selling|went long|went short)\b|"
    r"\b(?:my|our)\s+(?:position|trade|entry|stop|target)\b|"
    r"我(?:们)?(?:买入|卖出|加仓|减仓|清仓|持有|做多|做空|止损|止盈)|"
    r"(?:建仓|加仓|减仓|清仓|开多|开空|平仓)",
    re.I,
)
_THIRD_PARTY_RE = re.compile(
    r"\b(?:according to|analysts?|wall street|the company|the ceo|the cfo|"
    r"\breuters\b|\bbloomberg\b|reportedly|reports? that|said that|says that)\b|"
    r"分析师(?:们)?(?:认为|表示|预计|预测|给出|上调|下调)|"
    r"(?:公司|首席执行官|CEO|CFO|机构)(?:表示|称|预计|宣布)|"
    r"(?:据|援引)(?:报道|消息|数据)",
    re.I,
)
_PAST_MOVE_RE = re.compile(
    r"\b(?:surged|jumped|rose|rallied|gained|fell|dropped|declined|slid|"
    r"closed|finished|was up|was down|is up|is down)\b|"
    r"(?:上涨|大涨|走高|下跌|大跌|收涨|收跌|涨幅|跌幅|盘前涨|盘前跌)",
    re.I,
)
_NEWS_CONTEXT_RE = re.compile(
    r"\b(?:daily stock market brief|major news(?:\s*&\s*events)?|market recap|"
    r"top premarket gainers|top gainers|top losers|breaking news|news recap)\b|"
    r"(?:每日市场简报|重大新闻|市场回顾|盘前涨幅榜|涨幅榜|跌幅榜)",
    re.I,
)


def _compact(value: str) -> str:
    return _SPACE_RE.sub(" ", value or "").strip().casefold()


def evidence_is_verbatim(evidence: str, source_text: str) -> bool:
    """Require a meaningful exact quote after whitespace normalization."""
    needle = _compact(evidence)
    haystack = _compact(source_text)
    return len(needle) >= 8 and needle in haystack


def _reject(out: dict[str, Any], reason: str) -> dict[str, Any]:
    out["is_actionable_call"] = 0
    out["direction"] = "neutral"
    out["call_weight"] = 0.0
    out["target_price"] = None
    out["target_price_owner"] = ""
    out["affected_direction"] = "unknown"
    out["entry_status"] = "not_applicable"
    out["lifecycle_action"] = "none"
    out["exclusion_reason"] = reason
    return out


def enforce_x_policy(call: dict[str, Any], source_text: str) -> dict[str, Any]:
    """Reject news recaps, third-party claims, and unsupported X pseudo-calls."""
    out = dict(call)
    if not bool(out.get("is_actionable_call")):
        return out

    direction = str(out.get("direction") or "neutral").lower()
    mode = str(out.get("statement_mode") or "other").lower()
    owner = str(out.get("call_owner") or "unknown").lower()
    role = str(out.get("ticker_role") or "").lower()
    evidence = str(out.get("evidence_span") or "").strip()

    if direction not in {"bull", "bear"}:
        return _reject(out, "x_policy_missing_direction")
    if mode not in {"prediction", "position_action", "risk_management"}:
        return _reject(out, "x_policy_not_author_directional_statement")
    if owner != "post_author":
        return _reject(out, "x_policy_call_not_owned_by_post_author")
    if role in {"context", "comparison", "excluded"}:
        return _reject(out, "x_policy_ticker_is_context_only")
    if not evidence_is_verbatim(evidence, source_text):
        return _reject(out, "x_policy_missing_verbatim_author_evidence")
    if _THIRD_PARTY_RE.search(evidence):
        return _reject(out, "x_policy_third_party_or_reported_claim")

    if mode == "prediction":
        if not _FORWARD_RE.search(evidence):
            return _reject(out, "x_policy_no_forward_author_forecast")
        if _PAST_MOVE_RE.search(evidence) and not _FORWARD_RE.search(evidence):
            return _reject(out, "x_policy_past_price_move_is_not_forecast")
    elif mode in {"position_action", "risk_management"}:
        if not (_POSITION_RE.search(evidence) or _FORWARD_RE.search(evidence)):
            return _reject(out, "x_policy_no_author_position_action")

    # A market-brief heading is contextual evidence, never the thesis itself.
    if _NEWS_CONTEXT_RE.search(evidence):
        return _reject(out, "x_policy_market_news_recap")

    if out.get("target_price") is not None:
        target_owner = str(out.get("target_price_owner") or "").upper().lstrip("$")
        ticker = str(out.get("ticker") or "").upper().lstrip("$")
        if not target_owner or (ticker and target_owner != ticker):
            out["target_price"] = None
            out["target_price_owner"] = ""

    out["exclusion_reason"] = ""
    return out
