from pipeline.jobs.congress_capture.cusip_tickers import choose_us_ticker, resolved_tickers


def test_openfigi_mapping_keeps_only_a_unique_us_equity_symbol():
    result = {"data": [
        {"ticker": "GOOGL", "exchCode": "US", "marketSector": "Equity",
         "securityType2": "Common Stock", "name": "ALPHABET INC-CL A", "figi": "BBG009S39JX6"},
        {"ticker": "ABEA", "exchCode": "GR", "marketSector": "Equity",
         "securityType2": "Common Stock"},
    ]}
    match, reason = choose_us_ticker(result)
    assert reason is None
    assert match["ticker"] == "GOOGL"
    result["data"].append({"ticker": "GOOG", "exchCode": "US",
                           "marketSector": "Equity", "securityType2": "Common Stock"})
    assert choose_us_ticker(result) == (None, "ambiguous")


def test_invalid_tickers_are_never_loaded_from_mapping_cache():
    cache = {"resolved": {"02079K305": {"ticker": "GOOGL"},
                          "123456789": {"ticker": "BAD/PAIR"},
                          "bad-cusip": {"ticker": "AAPL"}}}
    assert resolved_tickers(cache) == {"02079K305": "GOOGL"}
