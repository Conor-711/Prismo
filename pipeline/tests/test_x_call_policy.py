from __future__ import annotations

from pipeline.domain.smart_voice.v0_impl import normalize_call
from pipeline.domain.smart_voice.x_call_policy import enforce_x_policy


def _normalized(**overrides):
    data = {
        "is_actionable_call": True,
        "direction": "bull",
        "statement_mode": "prediction",
        "call_owner": "post_author",
        "call_type": "single_ticker_call",
        "ticker_role": "primary",
        "ticker_relevance": 1,
        "instrument_scope": "stock",
        "underlying_direction": "bull",
        "evidence_span": "",
        "target_price": None,
        "target_price_owner": "",
    }
    data.update(overrides)
    call = normalize_call(data)
    call["ticker"] = "AMD"
    return call


def test_market_news_recap_is_not_an_author_call() -> None:
    text = (
        "Daily Stock Market Brief - October 6\n"
        "Major News & Events:\n"
        "Markets closed higher Friday with Nasdaq leading after AMD $AMD surged "
        "on OpenAI partnership."
    )
    call = _normalized(
        evidence_span=(
            "Markets closed higher Friday with Nasdaq leading after AMD $AMD "
            "surged on OpenAI partnership."
        ),
        target_price=208.28,
        target_price_owner="AMD",
    )

    result = enforce_x_policy(call, text)

    assert result["is_actionable_call"] == 0
    assert result["direction"] == "neutral"
    assert result["target_price"] is None
    assert result["exclusion_reason"] == "x_policy_no_forward_author_forecast"


def test_author_owned_forward_forecast_survives() -> None:
    text = "I think $AMD will reach $250 as data-center share expands."
    call = _normalized(
        evidence_span=text,
        target_price=250,
        target_price_owner="AMD",
    )

    result = enforce_x_policy(call, text)

    assert result["is_actionable_call"] == 1
    assert result["direction"] == "bull"
    assert result["target_price"] == 250
    assert result["exclusion_reason"] == ""


def test_third_party_analyst_target_is_not_credited_to_author() -> None:
    text = "Analysts expect $AMD to reach $250 after the product launch."
    call = _normalized(evidence_span=text, target_price=250, target_price_owner="AMD")

    result = enforce_x_policy(call, text)

    assert result["is_actionable_call"] == 0
    assert result["exclusion_reason"] == "x_policy_third_party_or_reported_claim"


def test_non_verbatim_model_evidence_is_rejected() -> None:
    text = "Watching $AMD around support today."
    call = _normalized(evidence_span="I expect AMD to rally from support.")

    result = enforce_x_policy(call, text)

    assert result["is_actionable_call"] == 0
    assert result["exclusion_reason"] == "x_policy_missing_verbatim_author_evidence"


def test_post_author_owner_is_preserved_by_normalizer() -> None:
    call = _normalized(evidence_span="I think $AMD will rally.")

    assert call["call_owner"] == "post_author"
