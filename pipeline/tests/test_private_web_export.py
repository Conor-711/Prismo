import json
import sqlite3

from pipeline.domain.smart_voice.private_web_export import write_private_web_export


def test_private_web_export_is_compact_and_uses_camel_case(tmp_path):
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE ticker_meta (
          ticker TEXT PRIMARY KEY,
          company_name TEXT,
          sector TEXT
        );
        CREATE TABLE price_daily (
          ticker TEXT,
          day TEXT,
          close REAL,
          adj_close REAL
        );
        INSERT INTO ticker_meta VALUES ('NVDA', 'NVIDIA', 'Technology');
        INSERT INTO price_daily VALUES ('NVDA', '2025-01-02', 100, 50);
        INSERT INTO price_daily VALUES ('NVDA', '2025-01-03', 104, 52);
        """
    )
    case = {
        "candidate_id": "telegram:test:1:NVDA",
        "ticker": "NVDA",
        "direction": "bull",
        "published_at": "2025-01-01T12:00:00+00:00",
        "horizon": "20D",
        "entry_day": "2025-01-02",
        "exit_day": "2025-01-03",
        "stock_return_pct": 4.0,
        "directional_spy_excess_pct": 2.0,
        "hit": True,
        "score_contribution": 0.4,
        "industry_benchmark": "SMH",
        "industry_directional_excess_pct": 1.5,
        "summary_zh": "看好人工智能需求。",
        "summary_en": "Bullish on AI demand.",
        "evidence": "I am buying NVDA",
        "original_text": "This full source body must not enter the web payload.",
        "url": "https://t.me/test/1",
        "style": "fundamental",
        "views": 100,
        "reactions": 5,
    }
    report = {
        "generated_at": "2026-07-29T00:00:00+00:00",
        "report_version": "report-v1",
        "scoring_version": "score-v1",
        "settlement_version": "settle-v1",
        "channel": {
            "handle": "test",
            "title": "Test Channel",
            "description": "",
            "public_url": "https://t.me/s/test",
            "subscriber_count": 1000,
            "message_count": 500,
            "first_message_at": "2024-01-01T00:00:00+00:00",
            "last_message_at": "2025-01-01T00:00:00+00:00",
        },
        "score": {
            "sv": 110,
            "confidence": "medium",
            "n_eff": 20,
            "settled_calls": 40,
            "active_days": 30,
            "covered_tickers": 5,
            "reference_percentile": 20,
            "calibration": {"population": 500},
            "explanation_zh": "测试解释",
        },
        "style": {
            "dominant": "fundamental",
            "distribution": {"fundamental": 1},
        },
        "performance": {
            "calls": 1,
            "bull_calls": 1,
            "bear_calls": 0,
            "spy_excess_hit_rate": 1.0,
            "mean_directional_spy_excess_pct": 2.0,
            "median_directional_spy_excess_pct": 2.0,
            "average_positive_excess_pct": 2.0,
            "average_negative_excess_pct": None,
            "payoff_ratio": None,
            "profit_factor": None,
            "industry_calls": 1,
            "industry_excess_hit_rate": 1.0,
            "mean_directional_industry_excess_pct": 1.5,
            "calls_by_year": {"2025": 1},
        },
        "data_quality": {
            "messages": 500,
            "forwarded_excluded": 3,
            "candidate_ticker_pairs": 20,
            "extracted_pairs": 20,
            "actionable_calls": 1,
            "settled_primary_calls": 1,
        },
        "portfolio_backtest": {
            "version": "test-v1",
            "methodology": {},
            "base": {},
            "costSensitivity": [],
        },
        "ticker_report": [
            {
                "ticker": "NVDA",
                "settled_calls": 1,
                "bull_calls": 1,
                "bear_calls": 0,
                "hit_rate": 1.0,
                "mean_directional_spy_excess_pct": 2.0,
                "score_contribution": 0.4,
                "latest_direction": "bull",
                "latest_at": case["published_at"],
                "latest_url": case["url"],
            }
        ],
        "best_cases": [case],
        "weak_cases": [],
        "calls": [case],
    }

    destination = tmp_path / "private.json"
    result = write_private_web_export(con, report, destination)
    payload = json.loads(destination.read_text())

    assert result["calls"] == 1
    assert payload["performance"]["spyExcessHitRate"] == 1.0
    assert payload["dataQuality"]["candidateTickerPairs"] == 20
    assert payload["tickers"][0]["prices"] == [
        ["2025-01-02", 50.0],
        ["2025-01-03", 52.0],
    ]
    assert "original_text" not in destination.read_text()
