"""ticker 抽取器离线单测（不依赖 DB，用 fallback 字典）。"""
from pipeline.ingest.ticker_extract import (
    extract_mentions,
    load_ticker_dict_from_fallback,
)

TD = load_ticker_dict_from_fallback()


def tickers(text) -> set[str]:
    return {m["ticker"] for m in extract_mentions(text, TD)}


def by_ticker(text) -> dict:
    return {m["ticker"]: m for m in extract_mentions(text, TD)}


def test_cashtag_dict_and_stoplist():
    t = "Just bought $AAPL and NVDA. My DD on GME is bullish. The CEO is great. I love IT."
    got = tickers(t)
    assert got == {"AAPL", "NVDA", "GME"}, got
    # 停用词/黑话/单字母不应混入
    assert "DD" not in got and "CEO" not in got and "IT" not in got and "I" not in got


def test_company_aliases():
    t = "I think Nvidia and Tesla and Palantir will outperform Microsoft this year."
    assert tickers(t) == {"NVDA", "TSLA", "PLTR", "MSFT"}


def test_single_letter_requires_cashtag():
    assert "F" not in tickers("F is a great car company")  # 裸单字母不认
    assert "F" in tickers("$F looks cheap here")            # cashtag 认


def test_confidence_and_method():
    d = by_ticker("$AAPL NVDA GME GM")
    assert d["AAPL"]["method"] == "cashtag" and d["AAPL"]["confidence"] >= 0.95
    assert d["NVDA"]["method"] == "dict" and d["NVDA"]["confidence"] == 0.9
    assert d["GME"]["confidence"] == 0.82   # 3 字母
    assert d["GM"]["confidence"] == 0.65    # 2 字母


def test_dedupe_keeps_best():
    # NVDA 同时以 cashtag 和裸词出现，应只留一条且取最高置信
    ms = extract_mentions("$NVDA is great, NVDA NVDA", TD)
    nvda = [m for m in ms if m["ticker"] == "NVDA"]
    assert len(nvda) == 1 and nvda[0]["method"] == "cashtag"


def test_empty_and_noise():
    assert tickers("") == set()
    assert tickers("YOLO this is the way, no tickers here at all") == set()
