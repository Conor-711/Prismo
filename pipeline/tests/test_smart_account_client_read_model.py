from __future__ import annotations

import sqlite3
from datetime import datetime, timezone

from pipeline.domain.smart_voice.client_read_model import build_smart_account_client_collections


def _database() -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.executescript(
        """
        CREATE TABLE sv_investor_score (
          investor_id TEXT PRIMARY KEY,
          source TEXT,
          name TEXT,
          handle TEXT,
          sv REAL,
          confidence TEXT,
          n_eff REAL,
          settled_calls INTEGER,
          active_days INTEGER,
          covered_tickers INTEGER,
          top_tickers_json TEXT,
          top_narratives_json TEXT,
          horizon_scores_json TEXT,
          platform_scores_json TEXT,
          concentration_json TEXT,
          rationale_en TEXT,
          updated_at TEXT
        );
        CREATE TABLE sv_investor_score_snapshot (
          run_id TEXT,
          created_at TEXT,
          investor_id TEXT,
          sv REAL,
          PRIMARY KEY (run_id, investor_id)
        );
        CREATE TABLE sv_call (
          candidate_id TEXT PRIMARY KEY,
          tweet_id TEXT,
          investor_id TEXT,
          author_handle TEXT,
          ticker TEXT,
          source TEXT,
          created_at TEXT,
          is_actionable_call INTEGER,
          direction TEXT,
          lifecycle_action TEXT,
          horizon_bucket TEXT,
          target_price REAL,
          summary_en TEXT,
          evidence_span TEXT,
          invalidation_condition TEXT,
          call_weight REAL,
          tagged_at TEXT,
          scoring_version TEXT
        );
        CREATE TABLE sv_call_candidate (
          candidate_id TEXT PRIMARY KEY,
          inserted_at TEXT,
          text TEXT,
          url TEXT
        );
        CREATE TABLE kol_refined (
          source TEXT, item_id TEXT, ticker TEXT, trans_zh TEXT, trans_en TEXT,
          PRIMARY KEY (source, item_id, ticker)
        );
        CREATE TABLE sv_call_settlement (
          candidate_id TEXT,
          horizon TEXT,
          status TEXT,
          is_primary_horizon INTEGER,
          entry_day TEXT,
          exit_day TEXT,
          entry_price REAL,
          exit_price REAL,
          return_pct REAL,
          benchmark_return_pct REAL,
          excess_return_pct REAL,
          actual_hit INTEGER,
          contribution REAL,
          industry_benchmark_ticker TEXT,
          industry_benchmark_return_pct REAL,
          industry_excess_return_pct REAL,
          industry_actual_hit INTEGER,
          settlement_version TEXT,
          PRIMARY KEY (candidate_id, horizon)
        );
        CREATE TABLE gr_ticker (ticker TEXT PRIMARY KEY, name_en TEXT, name_zh TEXT);
        CREATE TABLE price_daily (
          ticker TEXT NOT NULL,
          day TEXT NOT NULL,
          open REAL,
          high REAL,
          low REAL,
          close REAL,
          volume INTEGER,
          source TEXT,
          PRIMARY KEY (ticker, day)
        );
        """
    )
    for index, score in enumerate((120, 110, 100, 90), start=1):
        connection.execute(
            """INSERT INTO sv_investor_score VALUES (
                 ?, 'x', ?, ?, ?, 'high', 20, 24, 18, 7, '["NVDA", "MU"]', ?, ?, ?,
                 '{"dominantInvestorType":"fundamental"}', 'Historical ranking rationale.',
                 '2026-08-03T00:00:00Z'
               )""",
            (
                f"author-{index}",
                f"Author {index}",
                f"author{index}",
                score,
                '["semis"]' if index == 1 else '["other"]',
                '{"5D": 101, "20D": 112}' if index == 1 else '{}',
                f'{{"x": {score}}}',
            ),
        )
        connection.execute(
            "INSERT INTO sv_investor_score_snapshot VALUES ('previous', '2026-08-01T00:00:00Z', ?, ?)",
            (f"author-{index}", score - index),
        )
        connection.execute(
            "INSERT INTO sv_investor_score_snapshot VALUES ('current', '2026-08-03T00:00:00Z', ?, ?)",
            (f"author-{index}", score),
        )
    connection.execute("INSERT INTO gr_ticker VALUES ('NVDA', 'NVIDIA', '英伟达')")
    connection.execute(
        """INSERT INTO sv_call VALUES (
             'x-post-1', 'post-1', 'author-1', 'author1', 'NVDA', 'x', '2026-08-04T12:00:00Z',
             1, 'bull', 'open_call', '20D', 190, 'Complete translated thesis.',
             'Original evidence.', 'Close below 150.', 0.9, '2026-08-04T12:05:00Z', 'v2'
           )"""
    )
    connection.execute(
        "INSERT INTO sv_call_candidate VALUES ('x-post-1', '2026-08-04T12:01:00Z', 'Original post.', 'https://x.com/author1/status/1')"
    )
    connection.execute(
        "INSERT INTO kol_refined VALUES ('x', 'post-1', 'NVDA', '完整译文。', 'Original post.')"
    )
    connection.execute(
        """INSERT INTO sv_call_settlement VALUES (
             'x-post-1', '20D', 'settled', 1, '2026-08-04', '2026-08-05',
             182, 188, 0.032967, 0.01, 0.022967, 1, 0.42,
             'SMH', 0.012, 0.020967, 1, 'integral-v2'
           )"""
    )
    connection.executemany(
        "INSERT INTO price_daily VALUES ('NVDA', ?, ?, ?, ?, ?, ?, 'nasdaq')",
        [
            ("2026-08-03", 175, 181, 174, 180, 1_000),
            ("2026-08-04", 180, 184, 178, 182, 1_200),
            ("2026-08-05", 182, 189, 181, 188, 1_500),
        ],
    )
    connection.commit()
    return connection


def test_existing_rankings_project_into_client_contracts() -> None:
    connection = _database()
    try:
        result = build_smart_account_client_collections(
            connection,
            as_of=datetime(2026, 8, 5, tzinfo=timezone.utc),
        )
    finally:
        connection.close()

    profiles = result["smart-accounts"]
    assert len(profiles) == 4
    assert profiles[0] == {
        "id": "author-1",
        "name": "Author 1",
        "handle": "@author1",
        "platform": "X",
        "score": 120.0,
        "scoreChange": 1.0,
        "specialty": "Semiconductors",
        "horizon": "Medium term",
        "recentTicker": "NVDA",
        "rank": 1,
        "platformRank": 1,
        "platformPercentile": 0.25,
        "confidence": "high",
        "effectiveSamples": 20.0,
        "settledCalls": 24,
        "activeDays": 18,
        "coveredTickers": 7,
        "topTickers": ["NVDA", "MU"],
        "style": "Fundamental",
        "marketSelectionScore": None,
        "industrySelectionScore": None,
        "rationale": "Historical ranking rationale.",
        "avatarURL": None,
        "profileURL": "https://x.com/author1",
        "followersCount": None,
        "postsCount": None,
        "verified": None,
        "description": None,
    }

    updates = result["smart-account-updates"]
    assert len(updates) == 1
    assert updates[0]["authorId"] == "author-1"
    assert updates[0]["companyName"] == "NVIDIA"
    assert updates[0]["platformPercentile"] == 0.25
    assert updates[0]["direction"] == "bullish"
    assert updates[0]["lifecycle"] == "new"
    assert updates[0]["thesis"] == "Complete translated thesis."
    assert updates[0]["invalidation"] == "Close below 150."
    assert updates[0]["evidenceURL"] == "https://x.com/author1/status/1"
    assert updates[0]["publishedAt"] == "2026-08-04T12:00:00Z"
    assert updates[0]["originalText"] == "Original post."
    assert updates[0]["authorAvatarURL"] is None
    assert updates[0]["sourcePostId"] == "post-1"
    assert updates[0]["translatedTextZH"] == "完整译文。"
    assert updates[0]["evidenceSpan"] == "Original evidence."
    assert updates[0]["activityTitleZH"] == "NVDA：完整译文。"
    assert updates[0]["activityTitleEN"] == "NVDA: Complete translated thesis."
    assert updates[0]["authorScoreAsOf"] == "2026-08-03T00:00:00Z"
    assert updates[0]["callScoringVersion"] == "v2"
    assert updates[0]["priceEvidence"] == {
        "ticker": "NVDA",
        "viewDay": "2026-08-04",
        "viewPrice": 182.0,
        "latestDay": "2026-08-05",
        "latestPrice": 188.0,
        "responsePercent": 3.3,
        "source": "NASDAQ",
        "candles": [
            {
                "day": "2026-08-03",
                "open": 175.0,
                "high": 181.0,
                "low": 174.0,
                "close": 180.0,
                "volume": 1000,
            },
            {
                "day": "2026-08-04",
                "open": 180.0,
                "high": 184.0,
                "low": 178.0,
                "close": 182.0,
                "volume": 1200,
            },
            {
                "day": "2026-08-05",
                "open": 182.0,
                "high": 189.0,
                "low": 181.0,
                "close": 188.0,
                "volume": 1500,
            },
        ],
    }

    evidence = result["smart-account-evidence"]
    assert len(evidence) == 1
    assert evidence[0]["authorId"] == "author-1"
    assert evidence[0]["evidenceRole"] == "representative"
    assert evidence[0]["representativeTickerContribution"] == 0.42
    assert evidence[0]["representativeCallCount"] == 1
    assert evidence[0]["representativeTickerRank"] == 1
    assert evidence[0]["priceEvidence"]["opinionMarkers"] == [
        {
            "id": evidence[0]["id"],
            "publishedAt": "2026-08-04T12:00:00Z",
            "viewDay": "2026-08-04",
            "viewPrice": 182.0,
            "direction": "bullish",
            "contribution": 0.42,
            "horizon": "20D",
            "thesis": "Complete translated thesis.",
            "evidenceURL": "https://x.com/author1/status/1",
        }
    ]
    assert evidence[0]["settlement"] == {
        "status": "settled",
        "horizon": "20D",
        "entryDay": "2026-08-04",
        "exitDay": "2026-08-05",
        "entryPrice": 182.0,
        "exitPrice": 188.0,
        "tickerReturnPercent": 3.3,
        "marketBenchmarkReturnPercent": 1.0,
        "marketExcessReturnPercent": 2.3,
        "actualHit": True,
        "contribution": 0.42,
        "industryBenchmarkTicker": "SMH",
        "industryBenchmarkReturnPercent": 1.2,
        "industryExcessReturnPercent": 2.1,
        "industryActualHit": True,
        "settlementVersion": "integral-v2",
    }


def test_representative_evidence_uses_three_highest_contributing_tickers() -> None:
    connection = _database()
    calls = [
        ("mu-best", "MU", 0.90, 1),
        ("mu-duplicate", "MU", 0.10, 1),
        ("pltr-best", "PLTR", 0.80, 1),
        ("tsla-best", "TSLA", 0.70, 1),
        ("aapl-fourth", "AAPL", 0.60, 1),
        ("amzn-miss", "AMZN", -9.00, 0),
    ]
    for index, (candidate_id, ticker, contribution, actual_hit) in enumerate(calls, start=1):
        connection.execute(
            """INSERT INTO sv_call VALUES (
                 ?, ?, 'author-1', 'author1', ?, 'x', '2026-08-04T12:00:00Z',
                 1, 'bull', 'open_call', '20D', NULL, ?, ?, NULL, 0.8,
                 '2026-08-04T12:05:00Z', 'v2'
               )""",
            (candidate_id, f"post-{index + 1}", ticker, f"{ticker} thesis", f"{ticker} evidence"),
        )
        connection.execute(
            "INSERT INTO sv_call_candidate VALUES (?, '2026-08-04T12:01:00Z', ?, ?)",
            (candidate_id, f"{ticker} original post", f"https://x.com/author1/status/{index + 1}"),
        )
        connection.execute(
            """INSERT INTO sv_call_settlement VALUES (
                 ?, '20D', 'settled', 1, '2026-08-04', '2026-08-05',
                 100, 110, 0.10, 0.01, 0.09, ?, ?,
                 'SPY', 0.01, 0.09, ?, 'integral-v2'
               )""",
            (candidate_id, actual_hit, contribution, actual_hit),
        )
        connection.executemany(
            "INSERT OR REPLACE INTO price_daily VALUES (?, ?, ?, ?, ?, ?, ?, 'nasdaq')",
            [
                (ticker, "2026-08-04", 99, 102, 98, 100, 1_000),
                (ticker, "2026-08-05", 100, 112, 99, 110, 1_500),
            ],
        )
    connection.commit()

    try:
        result = build_smart_account_client_collections(
            connection,
            as_of=datetime(2026, 8, 5, tzinfo=timezone.utc),
        )
    finally:
        connection.close()

    evidence = [row for row in result["smart-account-evidence"] if row["authorId"] == "author-1"]
    assert [row["ticker"] for row in evidence] == ["MU", "PLTR", "TSLA"]
    assert [row["representativeTickerContribution"] for row in evidence] == [1.0, 0.8, 0.7]
    assert [row["representativeCallCount"] for row in evidence] == [2, 1, 1]
    assert [row["representativeTickerRank"] for row in evidence] == [1, 2, 3]
    assert len(evidence[0]["priceEvidence"]["opinionMarkers"]) == 2
    assert len({row["ticker"] for row in evidence}) == 3
    assert all(row["evidenceRole"] == "representative" for row in evidence)
    assert all(row["priceEvidence"] is not None for row in evidence)
    assert all(row["settlement"]["contribution"] > 0 for row in evidence)


def test_update_only_projection_skips_profiles_and_historical_evidence() -> None:
    connection = _database()
    try:
        result = build_smart_account_client_collections(
            connection,
            as_of=datetime(2026, 8, 5, tzinfo=timezone.utc),
            include_profiles=False,
        )
    finally:
        connection.close()

    assert result["smart-accounts"] == []
    assert len(result["smart-account-updates"]) == 1
    assert result["smart-account-evidence"] == []
