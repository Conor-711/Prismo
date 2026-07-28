from pipeline.domain.target_prices.kol_judgment import _enforce_price_anchor


def _judgment(**overrides):
    data = {
        "buy_lo": None,
        "buy_hi": None,
        "sell_lo": None,
        "sell_hi": None,
        "price_raw": "$100",
        "horizon_zh": "长期",
        "horizon_en": "long term",
        "horizon_bucket": "long",
    }
    data.update(overrides)
    return data


def test_price_anchor_rejects_outlier_side_and_keeps_horizon():
    result = _enforce_price_anchor(
        _judgment(sell_lo=16000.0, sell_hi=16000.0, price_raw="16000 puts"),
        25.77,
    )

    assert result["sell_lo"] is None
    assert result["sell_hi"] is None
    assert result["price_raw"] == ""
    assert result["horizon_bucket"] == "long"


def test_price_anchor_keeps_reasonable_range():
    result = _enforce_price_anchor(
        _judgment(buy_lo=50.0, buy_hi=60.0, sell_lo=180.0, sell_hi=200.0),
        100.0,
    )

    assert result["buy_lo"] == 50.0
    assert result["buy_hi"] == 60.0
    assert result["sell_lo"] == 180.0
    assert result["sell_hi"] == 200.0
    assert result["price_raw"] == "$100"


def test_price_anchor_rejects_only_invalid_side():
    result = _enforce_price_anchor(
        _judgment(buy_lo=90.0, buy_hi=95.0, sell_lo=8000.0, sell_hi=8000.0),
        100.0,
    )

    assert result["buy_lo"] == 90.0
    assert result["buy_hi"] == 95.0
    assert result["sell_lo"] is None
    assert result["sell_hi"] is None
    assert result["price_raw"] == "$100"
