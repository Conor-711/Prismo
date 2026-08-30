"""Build concise, localized headlines for product Smart Account activity."""
from __future__ import annotations

import re
from typing import Any


_SENTENCE_BREAK = re.compile(r"(?<=[。！？!?])|(?<=\.)\s+")
_SPACE = re.compile(r"\s+")
_ZH_AUTHOR_PREFIX = re.compile(r"^(?:该)?(?:作者|博主)[：:，,\s]*")
_EN_AUTHOR_PREFIX = re.compile(r"^(?:the\s+)?(?:author|creator)\s+", re.I)


def build_smart_account_activity_titles(
    *,
    ticker: str,
    direction: str,
    lifecycle: str,
    horizon: str,
    target_price: float | None,
    thesis_zh: str | None,
    thesis_en: str | None,
) -> dict[str, str]:
    """Return decision-useful titles without repeating the author/source boilerplate."""
    symbol = ticker.strip().upper()
    return {
        "activityTitleZH": _title(
            language="zh",
            ticker=symbol,
            direction=direction,
            lifecycle=lifecycle,
            horizon=horizon,
            target_price=target_price,
            thesis=thesis_zh,
        ),
        "activityTitleEN": _title(
            language="en",
            ticker=symbol,
            direction=direction,
            lifecycle=lifecycle,
            horizon=horizon,
            target_price=target_price,
            thesis=thesis_en,
        ),
    }


def _title(
    *,
    language: str,
    ticker: str,
    direction: str,
    lifecycle: str,
    horizon: str,
    target_price: float | None,
    thesis: str | None,
) -> str:
    insight = _concise(thesis, language=language)
    if insight:
        insight = _strip_author_prefix(insight, language=language)
        if lifecycle in {"reverse_call", "reversed"}:
            return _limit(
                f"{ticker} 观点反转：{insight}" if language == "zh"
                else f"{ticker} view reversed: {insight}",
                language=language,
            )
        if lifecycle in {"reinforce_call", "strengthened"}:
            return _limit(
                f"加强 {ticker} 判断：{insight}" if language == "zh"
                else f"Strengthens {ticker} view: {insight}",
                language=language,
            )
        if lifecycle in {"close_prior_call", "closed"}:
            return _limit(
                f"结束 {ticker} 观点：{insight}" if language == "zh"
                else f"Closes {ticker} view: {insight}",
                language=language,
            )
        if lifecycle in {"invalidate_prior_call", "invalidated"}:
            return _limit(
                f"{ticker} 观点失效：{insight}" if language == "zh"
                else f"{ticker} view invalidated: {insight}",
                language=language,
            )
        prefix = "" if _mentions_ticker(insight, ticker) else f"{ticker}{'：' if language == 'zh' else ': '}"
        return _limit(prefix + insight, language=language)

    if target_price is not None:
        price = _price(target_price, language=language)
        if language == "zh":
            return f"{ticker} 目标价 {price}（{horizon or '周期未说明'}）"
        return f"Targets {price} for {ticker} over {horizon or 'an unspecified horizon'}"

    bullish = direction in {"bull", "bullish"}
    if language == "zh":
        return f"{ticker} 最新判断：{'看多' if bullish else '看空'}，周期 {horizon or '未说明'}"
    return f"Latest {ticker} view: {'bullish' if bullish else 'bearish'} over {horizon or 'an unspecified horizon'}"


def _concise(value: Any, *, language: str) -> str:
    text = _SPACE.sub(" ", str(value or "").replace("\n", " ")).strip()
    if not text:
        return ""
    sentence = _SENTENCE_BREAK.split(text, maxsplit=1)[0].strip()
    return _limit(sentence, language=language)


def _strip_author_prefix(value: str, *, language: str) -> str:
    if language == "zh":
        return _ZH_AUTHOR_PREFIX.sub("", value).strip()
    cleaned = _EN_AUTHOR_PREFIX.sub("", value).strip()
    return cleaned[:1].upper() + cleaned[1:] if cleaned else value


def _mentions_ticker(value: str, ticker: str) -> bool:
    return re.search(rf"(?<![A-Z0-9])\$?{re.escape(ticker)}(?![A-Z0-9])", value, re.I) is not None


def _limit(value: str, *, language: str) -> str:
    limit = 42 if language == "zh" else 78
    normalized = value.strip(" ：:")
    return normalized if len(normalized) <= limit else normalized[: limit - 1].rstrip() + "…"


def _price(value: float, *, language: str) -> str:
    formatted = f"{value:,.0f}" if float(value).is_integer() else f"{value:,.2f}".rstrip("0").rstrip(".")
    return f"US${formatted}" if language == "zh" else f"${formatted}"
