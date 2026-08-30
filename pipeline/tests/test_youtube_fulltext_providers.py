from __future__ import annotations

import pytest

from pipeline.domain.opinions import youtube_analysis


VALID_SEGMENTS = '{"segments":[{"type":"speech","text":"完整译文"}]}'


def test_json3_transcript_joins_caption_events_without_duplicates() -> None:
    payload = {
        "events": [
            {"segs": [{"utf8": "Micron "}, {"utf8": "is strong"}]},
            {"segs": [{"utf8": "Micron is strong"}]},
            {"segs": [{"utf8": "Target is $150"}]},
        ]
    }

    assert youtube_analysis._json3_transcript(payload) == "Micron is strong Target is $150"


def test_transcript_processing_prefers_qwen(monkeypatch) -> None:
    calls: list[str] = []
    monkeypatch.setattr(youtube_analysis, "_transcript_provider_names", lambda: ["qwen", "gemini"])

    def fake_qwen(*_args, **_kwargs):
        calls.append("qwen")
        return VALID_SEGMENTS

    def fake_gemini(*_args, **_kwargs):
        calls.append("gemini")
        return VALID_SEGMENTS

    monkeypatch.setattr(youtube_analysis.qwen, "chat", fake_qwen)
    monkeypatch.setattr(youtube_analysis.gemini, "chat", fake_gemini)

    segments, model = youtube_analysis._transcript_chunk_segments("caption")

    assert segments == [{"type": "speech", "text": "完整译文"}]
    assert model == f"qwen:{youtube_analysis.settings.qwen_model_low}"
    assert calls == ["qwen"]


def test_transcript_processing_falls_back_to_gemini(monkeypatch) -> None:
    calls: list[str] = []
    monkeypatch.setattr(youtube_analysis, "_transcript_provider_names", lambda: ["qwen", "gemini"])

    def fake_qwen(*_args, **_kwargs):
        calls.append("qwen")
        raise RuntimeError("rate limited")

    def fake_gemini(*_args, **_kwargs):
        calls.append("gemini")
        return VALID_SEGMENTS

    monkeypatch.setattr(youtube_analysis.qwen, "chat", fake_qwen)
    monkeypatch.setattr(youtube_analysis.gemini, "chat", fake_gemini)

    segments, model = youtube_analysis._transcript_chunk_segments("caption")

    assert segments == [{"type": "speech", "text": "完整译文"}]
    assert model == f"gemini:{youtube_analysis.settings.gemini_model}"
    assert calls == ["qwen", "gemini"]


def test_transcript_processing_rejects_incomplete_provider_output(monkeypatch) -> None:
    monkeypatch.setattr(youtube_analysis, "_transcript_provider_names", lambda: ["qwen"])
    monkeypatch.setattr(youtube_analysis.qwen, "chat", lambda *_args, **_kwargs: '{"segments":[]}')

    with pytest.raises(RuntimeError, match="invalid_segments"):
        youtube_analysis._transcript_chunk_segments("caption")
