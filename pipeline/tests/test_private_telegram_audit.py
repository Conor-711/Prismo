from pipeline.domain.smart_voice.private_audit import (
    PROMOTION_RE,
    _direction_supported,
    _verbatim,
)


def test_private_audit_rejects_broker_reward_mechanics():
    assert PROMOTION_RE.search(
        "Deposit $2000 and wait for free MSFT shares to be credited"
    )


def test_private_audit_requires_verbatim_evidence():
    text = "My plan is to buy NVDA below $100 and hold for the long term."
    assert _verbatim("buy NVDA below $100", text)
    assert not _verbatim("buy NVDA below $90", text)


def test_private_audit_checks_direction_in_local_context():
    buy_range = "These are attractive Buy Ranges: CRWD <$240, NET <$110."
    assert _direction_supported("bull", "CRWD <$240", buy_range)
    assert not _direction_supported(
        "bear",
        "New trade parameters",
        "Short Trade Update: closed an old trade. New trade parameters.",
    )
    assert _direction_supported(
        "bear",
        "I am considering taking profits on this tranche",
        "I am considering taking profits on this tranche.",
    )
