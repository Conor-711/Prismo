from __future__ import annotations

import sqlite3

import pytest

from pipeline.domain.smart_voice.v0_impl import (
    ensure_tables,
    normalize_call,
    resolve_same_entry_day_calls,
    write_call,
)
from pipeline.domain.smart_voice.youtube_transcript_calls import (
    TranscriptDocument,
    enforce_youtube_policy,
    merge_chunk_calls,
    transcript_chunks,
)


def _call(candidate_id: str, direction: str, created_at: str, weight: float, action: str = "open_call"):
    return {
        "call": {
            "candidate_id": candidate_id,
            "investor_id": "youtube:channel-1",
            "ticker": "MU",
            "direction": direction,
            "created_at": created_at,
        },
        "meta": {"lifecycle_action": action},
        "effective_weight": weight,
    }


def test_complete_transcript_is_chunked_without_truncating_tail() -> None:
    document = TranscriptDocument(
        video_id="video-1",
        text="",
        segments=("a" * 70, "b" * 70, "TAIL"),
        model="gemini:test",
        created_at="2026-07-11T00:00:00Z",
    )

    chunks = transcript_chunks(document, target_chars=100, overlap_segments=1)

    assert len(chunks) == 2
    assert chunks[0].segment_start == 0
    assert chunks[-1].segment_end == 2
    assert "TAIL" in chunks[-1].text


def test_option_risk_management_is_not_a_directional_call() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bear",
            "statement_mode": "risk_management",
            "instrument_scope": "options",
            "option_strategy": "protective_put",
            "underlying_direction": "unknown",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"
    assert result["call_weight"] == 0


def test_reported_third_party_trade_is_not_credited_to_channel() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "options",
            "option_strategy": "speculative_call",
            "underlying_direction": "bull",
            "call_owner": "quoted_third_party",
            "host_endorsement": "none",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"


def test_third_party_wording_overrides_incorrect_host_label() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "options",
            "option_strategy": "speculative_call",
            "underlying_direction": "bull",
            "call_owner": "channel_host",
            "host_endorsement": "explicit",
            "evidence_span": "该投资者买入了650美元看涨期权并卖出了700美元看涨期权。",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"


def test_chinese_analyst_consensus_is_not_credited_to_channel() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bull",
            "call_owner": "channel_host",
            "host_endorsement": "implicit",
            "evidence_span": "许多分析师对该股持极度看涨态度，分析师们认为它有望冲向580至600美元。",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"
    assert result["call_owner"] == "quoted_third_party"


def test_denial_of_analyst_forecast_does_not_trigger_third_party_guard() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bull",
            "call_owner": "channel_host",
            "host_endorsement": "explicit",
            "evidence_span": "这是管理层给出的官方指引，而非分析师预测，股价可能继续上涨。",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 1
    assert result["direction"] == "bull"


def test_retrospective_profit_without_forward_view_is_not_prediction() -> None:
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bull",
            "call_owner": "channel_host",
            "host_endorsement": "explicit",
            "evidence_span": "我们很早就介入并一路乘势而上，获得了大约30%的收益。",
        }
    )

    result = enforce_youtube_policy(call)

    assert result["is_actionable_call"] == 0


def test_conflicting_video_chunks_are_non_actionable_without_explicit_reversal() -> None:
    bull = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bull",
            "evidence_score": 0.8,
        }
    )
    bear = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bear",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bear",
            "evidence_score": 0.7,
        }
    )

    result = merge_chunk_calls([bull, bear])

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"
    assert result["exclusion_reason"] == "conflicting_directions_inside_video"


def test_same_entry_day_opposite_calls_are_neutralized() -> None:
    items = [
        _call("bear", "bear", "2026-07-10T01:00:00Z", 1.0),
        _call("bull", "bull", "2026-07-10T12:00:00Z", 1.0),
    ]

    stats = resolve_same_entry_day_calls(items, {"MU": [("2026-07-10", 100.0)]})

    assert stats["neutralized"] == 1
    assert [item["effective_weight"] for item in items] == [0.0, 0.0]


def test_same_entry_day_explicit_reversal_keeps_only_final_call() -> None:
    items = [
        _call("bear", "bear", "2026-07-10T01:00:00Z", 1.2),
        _call("bull", "bull", "2026-07-10T12:00:00Z", 1.1, "reverse_call"),
    ]

    stats = resolve_same_entry_day_calls(items, {"MU": [("2026-07-10", 100.0)]})

    assert stats["reversed"] == 1
    assert items[0]["effective_weight"] == 0
    assert items[1]["effective_weight"] == pytest.approx(1.1)


def test_write_call_persists_transcript_provenance() -> None:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    ensure_tables(con)
    con.execute(
        """INSERT INTO sv_call_candidate
           (candidate_id,tweet_id,ticker,source,author_id,author_handle,created_at,lang)
           VALUES ('youtube:video-1:MU','video-1','MU','youtube','youtube:channel-1','@one',
                   '2026-07-10T00:00:00Z','en')"""
    )
    candidate = con.execute(
        "SELECT * FROM sv_call_candidate WHERE candidate_id='youtube:video-1:MU'"
    ).fetchone()
    call = normalize_call(
        {
            "is_actionable_call": True,
            "direction": "bull",
            "statement_mode": "prediction",
            "instrument_scope": "stock",
            "underlying_direction": "bull",
            "call_owner": "channel_host",
            "transcript_model": "gemini:test",
            "transcript_created_at": "2026-07-11T00:00:00Z",
            "transcript_version": "youtube-transcript-v2",
            "evidence_segment_start": 3,
            "evidence_segment_end": 4,
        }
    )

    write_call(con, candidate, call, "qwen:test")
    row = con.execute(
        "SELECT * FROM sv_call WHERE candidate_id='youtube:video-1:MU'"
    ).fetchone()

    assert row["transcript_model"] == "gemini:test"
    assert row["transcript_version"] == "youtube-transcript-v2"
    assert row["evidence_segment_start"] == 3
    assert row["statement_mode"] == "prediction"
