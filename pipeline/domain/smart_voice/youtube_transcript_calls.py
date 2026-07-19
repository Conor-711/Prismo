"""YouTube transcript adapter for Smart Voice calls.

Metadata is allowed to recall a candidate video, but only the complete
transcript may create a formal YouTube call.  The shared settlement and score
layers consume the normalized result produced by this adapter.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Callable


YOUTUBE_TRANSCRIPT_CALL_VERSION = "youtube-transcript-v2"
YOUTUBE_CALL_SYSTEM = (
    "Extract a structured public-equity call for the specified ticker from a complete YouTube transcript chunk. "
    "Use only transcript evidence; the title is context and is never sufficient evidence. "
    "A directional call requires an explicit forecast or an explicit position action in the underlying stock. "
    "Education, news narration, retrospective commentary, generic risk warnings, protective puts, covered calls, "
    "cash-secured puts, and other option-income or hedging strategies are non-actionable unless the speaker separately "
    "states a clear directional expectation for the underlying stock. Do not infer bearishness merely from a put and "
    "do not infer bullishness merely from a covered call. Judge only the specified ticker. Return strict JSON with: "
    "{\"is_actionable_call\":boolean,\"direction\":\"bull|bear|neutral\","
    "\"horizon_bucket\":\"1D|5D|20D|60D|90D|180D|unknown\",\"horizon_explicit\":boolean,"
    "\"target_price\":number|null,\"conviction_score\":number,\"evidence_score\":number,"
    "\"specificity_score\":number,\"call_type\":\"single_ticker_call|basket_call|pair_trade|sector_call|portfolio_update|retrospective|context_mention\","
    "\"ticker_role\":\"primary|basket_member|context|comparison|excluded\",\"ticker_relevance\":number,"
    "\"target_price_owner\":string,\"investor_style\":\"fundamental|technical|event_driven|macro|flow_momentum|mixed|unknown\","
    "\"call_structure\":\"conviction_call|conditional_setup|invalidation_call|watchlist|risk_update|reversal_call|retrospective\","
    "\"lifecycle_action\":\"open_call|reinforce_call|invalidate_prior_call|close_prior_call|reverse_call|no_trade_setup|retrospective|none\","
    "\"affected_direction\":\"bull|bear|unknown\",\"entry_status\":\"active_entry|conditional_setup|watchlist_only|not_applicable\","
    "\"trigger_condition\":string,\"invalidation_condition\":string,\"evidence_span\":string,"
    "\"evidence_segment_start\":number|null,\"evidence_segment_end\":number|null,"
    "\"statement_mode\":\"prediction|position_action|risk_management|education|news|retrospective|other\","
    "\"instrument_scope\":\"stock|options|portfolio|other\","
    "\"option_strategy\":\"none|covered_call|protective_put|cash_secured_put|speculative_call|speculative_put|spread|other\","
    "\"underlying_direction\":\"bull|bear|neutral|unknown\","
    "\"call_owner\":\"channel_host|named_guest|quoted_third_party|unknown\","
    "\"host_endorsement\":\"explicit|implicit|none|opposes\",\"exclusion_reason\":string}. "
    "A reported whale trade, analyst target, guest thesis, or third-party position is not the channel host's call. "
    "Only assign channel_host when the host personally states the forecast or position. A third-party call may be "
    "credited to the channel only when the host explicitly adopts the same direction. "
    "Scores are 0..1. The evidence span must be a short verbatim transcript excerpt."
)

THIRD_PARTY_EVIDENCE_RE = re.compile(
    r"\b(?:an?|the|this)\s+(?:investor|trader|whale|analyst)\b|"
    r"\b(?:he|she|they)\s+(?:bought|sold|expects?|believes?|predicts?|targets?)\b|"
    r"(?:该|这位|某位)(?:投资者|交易员|分析师|机构)|"
    r"分析师(?:们)?(?:认为|表示|预计|预测|给出|看好|看空)|"
    r"(?:他|她|他们)(?:买入|卖出|认为|预计|预测|目标)",
    re.I,
)
THIRD_PARTY_NEGATION_RE = re.compile(
    r"(?:而非|不是|并非|不属于)(?:由)?分析师(?:们)?(?:认为|表示|预计|预测|给出)?",
    re.I,
)
HOST_ENDORSEMENT_RE = re.compile(
    r"\bI\s+(?:think|believe|expect|predict|am buying|bought|own|hold|sold|am selling)\b|"
    r"\bwe\s+(?:think|believe|expect|predict|are buying|bought|own|hold)\b|"
    r"我(?:并不|不|仍|也|都|个人)?(?:认为|相信|预计|预测|看好|看空|买入|卖出|持有|目标)|"
    r"我们(?:并不|不|仍|也|都)?(?:认为|相信|预计|预测|看好|看空|买入|卖出|持有)",
    re.I,
)
FORWARD_CALL_RE = re.compile(
    r"\b(?:will|would|expect|believe|think|predict|target|could|should|going to|"
    r"upside|downside|buy|sell|long|short|bullish|bearish|breakout|breakdown)\b|"
    r"预计|认为|相信|预测|目标|将会|可能|应该|看好|看空|买入|卖出|做多|做空|"
    r"上涨|下跌|突破|跌破|回调|反弹|"
    r"予想|見込|目標|上昇|下落|買い|売り|強気|弱気|突破|反発|調整|可能性|"
    r"예상|전망|목표|상승|하락|매수|매도|강세|약세|돌파|반등|조정|가능성",
    re.I,
)


@dataclass(frozen=True)
class TranscriptDocument:
    video_id: str
    text: str
    segments: tuple[str, ...]
    model: str
    created_at: str


@dataclass(frozen=True)
class TranscriptChunk:
    text: str
    segment_start: int
    segment_end: int


def _speech_segments(raw: Any) -> list[str]:
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return []
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for item in raw:
        if not isinstance(item, dict) or item.get("type") != "speech":
            continue
        text = str(item.get("text") or "").strip()
        if text:
            out.append(text)
    return out


def transcript_document(row: Any) -> TranscriptDocument | None:
    segments = _speech_segments(row["segments"] if "segments" in row.keys() else "")
    fallback = str(row["content_en"] or row["content_zh"] or "").strip()
    text = "\n\n".join(segments).strip() or fallback
    if len(text) < 80:
        return None
    return TranscriptDocument(
        video_id=str(row["video_id"]),
        text=text,
        segments=tuple(segments or [text]),
        model=str(row["model"] or ""),
        created_at=str(row["created_at"] or ""),
    )


def transcript_chunks(
    document: TranscriptDocument,
    *,
    target_chars: int = 12_000,
    overlap_segments: int = 1,
) -> list[TranscriptChunk]:
    """Chunk complete speech without truncating the beginning or end."""
    segments = list(document.segments) or [document.text]
    chunks: list[TranscriptChunk] = []
    start = 0
    while start < len(segments):
        size = 0
        end = start
        while end < len(segments) and (size < target_chars or end == start):
            size += len(segments[end]) + 2
            end += 1
        body = "\n\n".join(
            f"[{index}] {segments[index]}" for index in range(start, end)
        )
        chunks.append(TranscriptChunk(body, start, end - 1))
        if end >= len(segments):
            break
        start = max(start + 1, end - max(0, overlap_segments))
    return chunks


def youtube_chunk_prompt(candidate: Any, chunk: TranscriptChunk, chunk_no: int, total: int) -> str:
    return (
        f"Ticker to judge: {candidate['ticker']}\n"
        f"Video id: {candidate['tweet_id']}\n"
        f"Video title (context only): {str(candidate['text'] or '').splitlines()[0][:240]}\n"
        f"Transcript chunk: {chunk_no}/{total}\n"
        f"Global segment range: {chunk.segment_start}-{chunk.segment_end}\n\n"
        "Complete transcript chunk:\n"
        f"{chunk.text}"
    )


def enforce_youtube_policy(call: dict[str, Any]) -> dict[str, Any]:
    """Reject metadata-like, educational, and option-only pseudo calls."""
    out = dict(call)
    mode = str(out.get("statement_mode") or "other")
    scope = str(out.get("instrument_scope") or "other")
    direction = str(out.get("direction") or "neutral")
    underlying = str(out.get("underlying_direction") or "unknown")
    owner = str(out.get("call_owner") or "unknown")
    endorsement = str(out.get("host_endorsement") or "none")
    allowed_mode = mode in {"prediction", "position_action"}
    directional = direction in {"bull", "bear"}
    option_directional = scope != "options" or underlying == direction
    owned = owner == "channel_host" or endorsement == "explicit"
    evidence = str(out.get("evidence_span") or "")
    reported_third_party = (
        bool(THIRD_PARTY_EVIDENCE_RE.search(evidence))
        and not bool(HOST_ENDORSEMENT_RE.search(evidence))
        and not bool(THIRD_PARTY_NEGATION_RE.search(evidence))
    )
    if reported_third_party:
        out["call_owner"] = "quoted_third_party"
        out["host_endorsement"] = "none"
    forward_evidence = mode != "prediction" or bool(FORWARD_CALL_RE.search(evidence))
    if not (
        bool(out.get("is_actionable_call"))
        and allowed_mode
        and directional
        and option_directional
        and owned
        and not reported_third_party
        and forward_evidence
    ):
        out["is_actionable_call"] = 0
        out["direction"] = "neutral"
        out["call_weight"] = 0.0
        if not str(out.get("exclusion_reason") or "").strip():
            out["exclusion_reason"] = "youtube_transcript_has_no_explicit_underlying_call"
    return out


def merge_chunk_calls(calls: list[dict[str, Any]]) -> dict[str, Any]:
    """Merge chunk-level labels into one video+ticker evidence unit."""
    if not calls:
        return {
            "is_actionable_call": 0,
            "direction": "neutral",
            "exclusion_reason": "youtube_transcript_extraction_empty",
        }
    actionable = [call for call in calls if call.get("is_actionable_call")]
    if not actionable:
        return max(calls, key=lambda call: float(call.get("evidence_score") or 0))
    directions = {str(call.get("direction")) for call in actionable}
    if len(directions) > 1:
        reversals = [
            call
            for call in actionable
            if str(call.get("lifecycle_action")) == "reverse_call"
        ]
        if reversals:
            return max(
                reversals,
                key=lambda call: int(call.get("evidence_segment_end") or -1),
            )
        best = max(actionable, key=lambda call: float(call.get("evidence_score") or 0))
        return {
            **best,
            "is_actionable_call": 0,
            "direction": "neutral",
            "call_weight": 0.0,
            "exclusion_reason": "conflicting_directions_inside_video",
        }

    best = max(
        actionable,
        key=lambda call: (
            float(call.get("evidence_score") or 0)
            + float(call.get("specificity_score") or 0)
            + float(call.get("conviction_score") or 0),
            int(call.get("evidence_segment_end") or -1),
        ),
    )
    explicit_horizon = next(
        (call for call in actionable if call.get("horizon_explicit")),
        None,
    )
    target = next(
        (call for call in actionable if call.get("target_price") is not None),
        None,
    )
    out = dict(best)
    if explicit_horizon is not None:
        out["horizon_bucket"] = explicit_horizon.get("horizon_bucket", "unknown")
        out["horizon_explicit"] = 1
    if target is not None:
        out["target_price"] = target.get("target_price")
        out["target_price_owner"] = target.get("target_price_owner", "")
    out["evidence_segment_start"] = min(
        int(call.get("evidence_segment_start") or 0) for call in actionable
    )
    out["evidence_segment_end"] = max(
        int(call.get("evidence_segment_end") or 0) for call in actionable
    )
    return out


def extract_from_transcript(
    candidate: Any,
    document: TranscriptDocument,
    *,
    request_json: Callable[[str, str], Any],
    normalize: Callable[[Any], dict[str, Any]],
) -> dict[str, Any]:
    chunks = transcript_chunks(document)
    calls: list[dict[str, Any]] = []
    for index, chunk in enumerate(chunks, 1):
        raw = request_json(
            YOUTUBE_CALL_SYSTEM,
            youtube_chunk_prompt(candidate, chunk, index, len(chunks)),
        )
        call = normalize(raw)
        call["evidence_segment_start"] = int(
            (raw or {}).get("evidence_segment_start")
            if isinstance(raw, dict) and (raw or {}).get("evidence_segment_start") is not None
            else chunk.segment_start
        )
        call["evidence_segment_end"] = int(
            (raw or {}).get("evidence_segment_end")
            if isinstance(raw, dict) and (raw or {}).get("evidence_segment_end") is not None
            else chunk.segment_end
        )
        calls.append(enforce_youtube_policy(call))
    out = merge_chunk_calls(calls)
    out["transcript_model"] = document.model
    out["transcript_created_at"] = document.created_at
    out["transcript_version"] = YOUTUBE_TRANSCRIPT_CALL_VERSION
    return out
