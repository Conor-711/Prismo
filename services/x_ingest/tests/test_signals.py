from services.x_ingest.signals import build_portfolio_signals


def test_ready_update_becomes_traceable_account_leads_signal() -> None:
    update = {
        "id": "11111111-1111-4111-8111-111111111111",
        "ticker": "NVDA",
        "companyName": "NVIDIA",
        "authorName": "Investor A",
        "score": 123.4,
        "platformPercentile": 0.08,
        "direction": "bullish",
        "lifecycle": "new",
        "publishedAt": "2026-08-06T00:00:00Z",
        "ingestedAt": "2026-08-06T00:01:00Z",
        "processedAt": "2026-08-06T00:10:00Z",
        "thesis": "Demand remains stronger than expected.",
        "originalText": "$NVDA demand remains stronger than expected.",
        "evidenceSpan": "$NVDA demand remains stronger",
        "sourceURL": "https://x.com/investor/status/1",
    }

    signal = build_portfolio_signals([update])[0]

    assert signal["kind"] == "account_leads"
    assert signal["priority"] == "critical"
    assert signal["dataStatus"] == "current"
    assert signal["smartMoneyCoverage"] == "unavailable"
    assert "no current public on-chain capital verification" in signal["conclusion"]
    assert signal["evidence"][0]["referenceId"] == update["id"]
    assert signal["evidence"][0]["detail"] == update["evidenceSpan"]


def test_signal_is_delayed_after_fifteen_minutes() -> None:
    update = {
        "id": "22222222-2222-4222-8222-222222222222",
        "ticker": "MU",
        "companyName": "Micron",
        "authorName": "Investor B",
        "score": 109,
        "platformPercentile": 0.20,
        "direction": "bearish",
        "lifecycle": "new",
        "publishedAt": "2026-08-06T00:00:00Z",
        "processedAt": "2026-08-06T00:16:00Z",
        "thesis": "Margins may weaken.",
        "evidenceSpan": "$MU margins may weaken.",
    }

    signal = build_portfolio_signals([update])[0]

    assert signal["priority"] == "important"
    assert signal["dataStatus"] == "delayed"
