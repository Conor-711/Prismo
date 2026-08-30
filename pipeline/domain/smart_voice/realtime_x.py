"""Product-ready processing for realtime X Smart Account posts."""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Callable

from ...common.ticker_extraction import (
    ALIASES,
    TickerDict,
    extract_mentions,
    load_stoplist,
)
from .v0_impl import (
    SV_SCORING_VERSION,
    SV_SYSTEM,
    normalize_call,
    sv_extract_messages_json,
    sv_extract_model_label,
    sv_extract_provider_available,
    sv_extract_provider_order,
)
from .x_call_policy import X_CALL_POLICY_VERSION, enforce_x_policy


DEFAULT_POPULAR_TICKERS = ("AVGO", "HOOD", "MSTR", "MU", "NVDA", "PLTR")
REALTIME_CALL_VERSION = f"{SV_SCORING_VERSION}+{X_CALL_POLICY_VERSION}+realtime-v2"
NUMBER_OR_TICKER_RE = re.compile(
    r"\$[A-Za-z]{1,5}\b|\d+(?:\.\d+)?%?"
)
SCALED_NUMBER_RE = re.compile(r"\$?(\d+(?:\.\d+)?)([KMBT])\b", re.I)
SEMANTIC_UNIT_RE = re.compile(r"[\u3400-\u9fff]|[A-Za-z]+(?:['’-][A-Za-z]+)*")
CHINESE_DIGITS = str.maketrans("〇零一二三四五六七八九", "00123456789")
OPTION_ACTION_RE = re.compile(
    r"\b(?:bought|buy|buying|filled|long|lotto\s+play|added|add|limit|"
    r"sold|sell|selling|short|wrote|writing)\b",
    re.I,
)
OPTION_SELL_RE = re.compile(r"\b(?:sold|sell|selling|short|wrote|writing)\b", re.I)
OPTION_EXPIRY_RE = re.compile(
    r"\b(?P<day>\d{1,2})(?P<month>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b",
    re.I,
)
TRANSLATION_SYSTEM = (
    "You are a faithful financial-post translator, not a summarizer. Translate the complete X post "
    "sentence by sentence into natural Chinese and English. Preserve every claim, qualifier, number, "
    "ticker, target, date, tone, and paragraph. Do not shorten, explain, analyze, add a TLDR, or replace "
    "the post with an investment conclusion. If the source is already Chinese or English, return the "
    "cleaned complete source in that language field. Return strict JSON only: "
    '{"zh":"complete Chinese translation","en":"complete English translation"}'
)


JsonRequest = Callable[[str, str, int], tuple[dict[str, Any], str]]


@dataclass(frozen=True)
class RealtimePostInput:
    post_id: str
    original_text: str
    language: str
    published_at: datetime
    post_type: str


@dataclass(frozen=True)
class PostAnalysis:
    tickers: tuple[str, ...]
    calls: tuple[dict[str, Any], ...]


class RealtimeXAnalyzer:
    processing_version = REALTIME_CALL_VERSION

    def __init__(
        self,
        tickers: tuple[str, ...] = DEFAULT_POPULAR_TICKERS,
        request_json: JsonRequest | None = None,
    ):
        self.tickers = tuple(sorted({ticker.upper() for ticker in tickers if ticker.strip()}))
        self.request_json = request_json or _request_json
        self.ticker_dict = _ticker_dict(self.tickers)

    def analyze(self, post: RealtimePostInput) -> PostAnalysis:
        mentions = extract_mentions(post.original_text, self.ticker_dict, min_confidence=0.5)
        tickers = tuple(sorted({str(item["ticker"]).upper() for item in mentions}))
        if not tickers:
            return PostAnalysis(tickers=(), calls=())

        actionable: list[dict[str, Any]] = []
        for ticker in tickers:
            prompt = _extraction_prompt(
                ticker=ticker,
                text=post.original_text,
                language=post.language,
                published_at=str(post.published_at),
                post_type=post.post_type,
            )
            raw, model = self.request_json(SV_SYSTEM, prompt, 1_200)
            normalized = normalize_call(raw)
            normalized["ticker"] = ticker
            normalized = enforce_x_policy(normalized, post.original_text)
            normalized = _apply_derivative_evidence_rules(
                normalized,
                ticker=ticker,
                source_text=post.original_text,
                published_at=post.published_at,
            )
            normalized["evidence_span"] = _traceable_evidence_span(
                post.original_text,
                str(normalized.get("evidence_span") or ""),
            )
            normalized.pop("ticker", None)
            if normalized["is_actionable_call"]:
                actionable.append(
                    _call_payload(ticker=ticker, normalized=normalized, extraction_model=model)
                )
        if not actionable:
            return PostAnalysis(tickers=tickers, calls=())

        translation, translation_model = _translate_complete(
            self.request_json,
            source=post.original_text,
            language=post.language,
        )
        for item in actionable:
            item["translated_text_zh"] = translation["zh"]
            item["translated_text_en"] = translation["en"]
            item["translation_model"] = translation_model
        return PostAnalysis(tickers=tickers, calls=tuple(actionable))


def _ticker_dict(tickers: tuple[str, ...]) -> TickerDict:
    universe = set(tickers)
    aliases = {phrase: ticker for phrase, ticker in ALIASES.items() if ticker in universe}
    aliases.update(
        {
            "micron": "MU",
            "micron technology": "MU",
            "microstrategy": "MSTR",
            "strategy": "MSTR",
            "nvidia": "NVDA",
            "broadcom": "AVGO",
            "robinhood": "HOOD",
            "palantir": "PLTR",
        }
    )
    return TickerDict(
        tickers=universe,
        stop=load_stoplist(),
        aliases={phrase: ticker for phrase, ticker in aliases.items() if ticker in universe},
    )


def _request_json(system: str, prompt: str, max_tokens: int) -> tuple[dict[str, Any], str]:
    providers = [provider for provider in sv_extract_provider_order() if sv_extract_provider_available(provider)]
    if not providers:
        raise RuntimeError("no configured provider for realtime X processing")
    errors: list[str] = []
    for provider in providers:
        for _ in range(2):
            try:
                data = sv_extract_messages_json(provider, system, prompt, max_tokens)
            except Exception as exc:  # noqa: BLE001 - provider fallback
                errors.append(f"{provider}:{exc}")
                continue
            if isinstance(data, dict):
                return data, sv_extract_model_label(provider)
        errors.append(f"{provider}:invalid-json")
    raise RuntimeError("all realtime X model providers failed: " + "; ".join(errors[-6:]))


def _extraction_prompt(
    *,
    ticker: str,
    text: str,
    language: str,
    published_at: str,
    post_type: str,
) -> str:
    return (
        f"Ticker to judge: {ticker}\n"
        "Source: x\n"
        f"Created at: {published_at}\n"
        f"Tweet type: {post_type}\n"
        f"Language: {language or 'unknown'}\n"
        "Tweet text:\n"
        f"{text[:4000]}"
    )


def _apply_derivative_evidence_rules(
    normalized: dict[str, Any],
    *,
    ticker: str,
    source_text: str,
    published_at: datetime,
) -> dict[str, Any]:
    """Correct option direction and prevent option premiums becoming stock targets."""
    out = dict(normalized)
    if not bool(out.get("is_actionable_call")):
        return out
    option = re.search(
        rf"(?<![A-Za-z])\$?{re.escape(ticker)}\b.{{0,80}}?\$?\d+(?:\.\d+)?\s*(?P<side>[pc])\b",
        source_text,
        re.I | re.S,
    )
    if option is None:
        return out
    evidence = str(out.get("evidence_span") or source_text)
    if not OPTION_ACTION_RE.search(evidence):
        return out

    side = option.group("side").lower()
    sold = bool(OPTION_SELL_RE.search(evidence))
    out["direction"] = (
        "bull"
        if (side == "c" and not sold) or (side == "p" and sold)
        else "bear"
    )
    out["instrument_scope"] = "option"

    # Option posts frequently contain strike, premium and scale targets. None is
    # a stock target unless the author explicitly labels the underlying/share.
    explicit_underlying_target = re.search(
        rf"(?:underlying|stock|shares?|\$?{re.escape(ticker)})\s+"
        r"(?:price\s+)?target|(?:price\s+)?target\s+(?:for\s+)?"
        rf"(?:the\s+)?(?:underlying|stock|shares?|\$?{re.escape(ticker)})",
        source_text,
        re.I,
    )
    if explicit_underlying_target is None:
        out["target_price"] = None
        out["target_price_owner"] = ""

    if str(out.get("horizon_bucket") or "unknown") == "unknown":
        horizon = _option_expiry_horizon(source_text, published_at)
        if horizon:
            out["horizon_bucket"] = horizon
            out["horizon_explicit"] = True
    return out


def _option_expiry_horizon(source_text: str, published_at: datetime) -> str | None:
    match = OPTION_EXPIRY_RE.search(source_text)
    if match is None:
        return None
    month = datetime.strptime(match.group("month")[:3].title(), "%b").month
    reference = published_at.replace(tzinfo=None) if published_at.tzinfo else published_at
    expiry = datetime(reference.year, month, int(match.group("day")))
    if expiry.date() < reference.date():
        expiry = expiry.replace(year=expiry.year + 1)
    days = max(1, (expiry.date() - reference.date()).days)
    for upper, bucket in ((1, "1D"), (5, "5D"), (20, "20D"), (60, "60D"), (90, "90D")):
        if days <= upper:
            return bucket
    return "180D"


def _call_payload(*, ticker: str, normalized: dict[str, Any], extraction_model: str) -> dict[str, Any]:
    evidence = str(normalized.get("evidence_span") or "").strip()
    if not evidence:
        raise ValueError("actionable call has no evidence span")
    return {
        "ticker": ticker,
        "direction": normalized["direction"],
        "horizon": normalized.get("horizon_bucket") or "unknown",
        "target_price": normalized.get("target_price"),
        "lifecycle": normalized.get("lifecycle_action") or "open_call",
        "invalidation": normalized.get("invalidation_condition") or "",
        "evidence_span": evidence,
        "thesis_zh": normalized.get("summary_zh") or "",
        "thesis_en": normalized.get("summary_en") or "",
        "extraction_model": extraction_model,
        "call_scoring_version": REALTIME_CALL_VERSION,
        "call_policy_version": X_CALL_POLICY_VERSION,
    }


def _traceable_evidence_span(source_text: str, evidence_span: str) -> str:
    """Map whitespace-normalized model evidence back to an exact source slice."""
    evidence = evidence_span.strip()
    if evidence and evidence in source_text:
        return evidence
    if evidence:
        normalized_source: list[str] = []
        source_positions: list[int] = []
        previous_space = False
        for index, character in enumerate(source_text):
            if character.isspace():
                if previous_space:
                    continue
                normalized_source.append(" ")
                source_positions.append(index)
                previous_space = True
            else:
                normalized_source.append(character)
                source_positions.append(index)
                previous_space = False
        normalized_evidence = re.sub(r"\s+", " ", evidence).strip()
        offset = "".join(normalized_source).find(normalized_evidence)
        if offset >= 0:
            start = source_positions[offset]
            end = source_positions[offset + len(normalized_evidence) - 1] + 1
            return source_text[start:end]
    return source_text.strip()


def _normalize_translation(data: dict[str, Any], source: str, language: str) -> dict[str, str]:
    zh = str(data.get("zh") or "").strip()
    en = str(data.get("en") or "").strip()
    normalized_language = (language or "").lower()
    if normalized_language.startswith("zh"):
        zh = source
    if normalized_language.startswith("en"):
        en = source
    if not zh or not en:
        raise ValueError("complete translation is missing a language")

    source_units = len(SEMANTIC_UNIT_RE.findall(source))
    minimum_units = max(4, int(source_units * 0.55))
    for label, translated in (("zh", zh), ("en", en)):
        if len(SEMANTIC_UNIT_RE.findall(translated)) < minimum_units:
            raise ValueError(f"{label} translation is too short and may be a summary")
    source_tokens = {token.upper() for token in NUMBER_OR_TICKER_RE.findall(source)}
    for label, translated in (("zh", zh), ("en", en)):
        token_text = translated.translate(CHINESE_DIGITS)
        translated_tokens = {
            token.upper() for token in NUMBER_OR_TICKER_RE.findall(token_text)
        }
        missing = sorted(
            token
            for token in source_tokens - translated_tokens
            if not _scaled_number_is_preserved(token, source, token_text)
        )
        if missing:
            raise ValueError(f"{label} translation lost numbers or tickers: {missing[:6]}")
    return {"zh": zh, "en": en}


def _scaled_number_is_preserved(token: str, source: str, translated: str) -> bool:
    if not token.rstrip("%").replace(".", "", 1).isdigit():
        return False
    source_scales = {
        suffix.upper()
        for number, suffix in SCALED_NUMBER_RE.findall(source)
        if number == token.rstrip("%")
    }
    if not source_scales:
        return False
    value = float(token.rstrip("%"))
    compact = translated.replace(",", "").replace(" ", "").upper()

    def rendered(number: float) -> str:
        return str(int(number)) if number.is_integer() else f"{number:g}"

    equivalents: list[str] = []
    if "K" in source_scales:
        equivalents.extend((rendered(value * 1_000), rendered(value / 10) + "万"))
    if "M" in source_scales:
        equivalents.extend((rendered(value * 1_000_000), rendered(value * 100) + "万"))
    if "B" in source_scales:
        equivalents.extend((rendered(value * 1_000_000_000), rendered(value * 10) + "亿"))
    if "T" in source_scales:
        equivalents.extend((rendered(value * 1_000_000_000_000), rendered(value) + "万亿"))
    return any(equivalent in compact for equivalent in equivalents)


def _translate_complete(
    request_json: JsonRequest,
    *,
    source: str,
    language: str,
) -> tuple[dict[str, str], str]:
    required_tokens = sorted(
        {token.upper() for token in NUMBER_OR_TICKER_RE.findall(source)},
        key=lambda item: (len(item), item),
    )
    prompt = (
        f"Source language: {language or 'unknown'}\n"
        f"Required literal numbers and tickers: {', '.join(required_tokens)}\n"
        f"Complete source post:\n{source}"
    )
    errors: list[str] = []
    attempts = 0
    while attempts < 6:
        if request_json is _request_json:
            providers = [
                provider
                for provider in sv_extract_provider_order()
                if sv_extract_provider_available(provider)
            ]
            if not providers:
                raise RuntimeError("no configured provider for realtime X translation")
            provider = providers[min(attempts // 2, len(providers) - 1)]
            translated = sv_extract_messages_json(provider, TRANSLATION_SYSTEM, prompt, 1_600)
            model = sv_extract_model_label(provider)
            if not isinstance(translated, dict):
                errors.append(f"{provider}:invalid-json")
                attempts += 1
                if attempts >= len(providers) * 2:
                    break
                continue
        else:
            translated, model = request_json(TRANSLATION_SYSTEM, prompt, 1_600)
        attempts += 1
        try:
            return _normalize_translation(translated, source, language), model
        except ValueError as exc:
            errors.append(f"{model}:{exc}")
            prompt = (
                f"Source language: {language or 'unknown'}\n"
                f"Required literal numbers and tickers: {', '.join(required_tokens)}\n"
                f"Validation error to repair: {exc}\n"
                "Translate the complete source again. Do not omit or summarize any sentence.\n"
                f"Complete source post:\n{source}"
            )
            if request_json is not _request_json and attempts >= 3:
                break
    raise ValueError("complete translation failed after repairs: " + "; ".join(errors))


__all__ = [
    "DEFAULT_POPULAR_TICKERS",
    "PostAnalysis",
    "REALTIME_CALL_VERSION",
    "RealtimePostInput",
    "RealtimeXAnalyzer",
    "TRANSLATION_SYSTEM",
]
