import sqlite3

from pipeline.domain.smart_voice.private_portfolio import (
    build_private_portfolio_backtest,
)


def test_private_portfolio_replaces_overlapping_same_ticker_calls():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.execute(
        """
        CREATE TABLE price_daily (
          ticker TEXT,
          day TEXT,
          open REAL,
          close REAL,
          adj_close REAL
        )
        """
    )
    for index, day in enumerate(
        ["2025-01-02", "2025-01-03", "2025-01-06", "2025-01-07", "2025-01-08"]
    ):
        con.execute(
            "INSERT INTO price_daily VALUES (?,?,?,?,?)",
            ("NVDA", day, 100 + index * 2, 102 + index * 2, 102 + index * 2),
        )
        con.execute(
            "INSERT INTO price_daily VALUES (?,?,?,?,?)",
            ("SPY", day, 100, 100, 100),
        )
    cases = [
        {
            "candidate_id": "first",
            "ticker": "NVDA",
            "direction": "bull",
            "published_at": "2025-01-01T10:00:00+00:00",
            "entry_day": "2025-01-02",
            "exit_day": "2025-01-08",
        },
        {
            "candidate_id": "refresh",
            "ticker": "NVDA",
            "direction": "bull",
            "published_at": "2025-01-05T10:00:00+00:00",
            "entry_day": "2025-01-06",
            "exit_day": "2025-01-08",
        },
    ]

    result = build_private_portfolio_backtest(con, cases)
    base = result["base"]

    assert base["tradeCount"] == 2
    assert result["methodology"]["overlappingCallsReplaced"] == 1
    assert base["totalReturn"] > 0
    assert base["benchmarkTotalReturn"] == 0
    assert len(base["equityCurve"]) == 5
    assert [item["costBps"] for item in result["costSensitivity"]] == [0, 10, 25]
