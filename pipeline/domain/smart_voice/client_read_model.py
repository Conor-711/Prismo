"""Project the existing Smart Account ranking truth into client contracts."""
from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from ...common.smart_account_titles import build_smart_account_activity_titles


SMART_ACCOUNT_NAMESPACE = uuid.UUID("6f86d8e3-19b2-4d33-9f06-403a3b034330")

PLATFORM_LABELS = {
    "x": "X",
    "youtube": "YouTube",
    "reddit": "Reddit",
    "xueqiu": "Xueqiu",
    "toss": "Toss",
}

SPECIALTY_LABELS = {
    "ai_infra": "AI infrastructure",
    "crypto": "Crypto-linked equities",
    "fintech": "Fintech",
    "semis": "Semiconductors",
    "software": "Software",
    "consumer": "Consumer",
    "healthcare": "Healthcare",
    "energy": "Energy",
    "financials": "Financials",
    "industrials": "Industrials",
}

LIFECYCLE_LABELS = {
    "open_call": "new",
    "reinforce_call": "strengthened",
    "close_prior_call": "closed",
    "invalidate_prior_call": "invalidated",
    "reverse_call": "reversed",
}

QUALIFIED_FILTER = """
       (source = 'x' AND n_eff >= 8 AND settled_calls >= 10)
    OR (source = 'youtube' AND n_eff >= 4 AND settled_calls >= 5)
    OR (source = 'reddit' AND n_eff >= 3 AND settled_calls >= 4)
    OR (source IN ('xueqiu', 'toss') AND n_eff >= 5 AND settled_calls >= 8)
"""


def _json_object(raw: str | None) -> dict[str, Any]:
    if not raw:
        return {}
    try:
        value = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _json_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        value = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return []
    return [str(item) for item in value] if isinstance(value, list) else []


def _specialty(raw: str | None) -> str:
    for key in _json_list(raw):
        if key in SPECIALTY_LABELS:
            return SPECIALTY_LABELS[key]
    return "Cross-sector equities"


def _horizon(raw: str | None) -> str:
    scores = _json_object(raw)
    ranked = [
        (str(key), float(value))
        for key, value in scores.items()
        if value is not None and isinstance(value, (int, float))
    ]
    if not ranked:
        return "Mixed horizon"
    bucket = max(ranked, key=lambda item: item[1])[0]
    if bucket in {"1D", "5D"}:
        return "Short term"
    if bucket in {"20D", "60D"}:
        return "Medium term"
    return "Long term"


def _style(raw: str | None) -> str:
    value = str(_json_object(raw).get("dominantInvestorType") or "mixed")
    return value.replace("_", " ").title()


def _score(raw: str | None, *path: str) -> float | None:
    value: Any = _json_object(raw)
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return round(float(value), 2) if isinstance(value, (int, float)) else None


def _stable_update_id(candidate_id: str) -> str:
    try:
        return str(uuid.UUID(candidate_id))
    except (ValueError, AttributeError):
        return str(uuid.uuid5(SMART_ACCOUNT_NAMESPACE, candidate_id))


def _iso(value: str) -> str:
    normalized = value.strip().replace(" ", "T")
    if normalized.endswith("Z") or "+" in normalized[10:]:
        return normalized
    return normalized + "Z"


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None


def _column_exists(connection: sqlite3.Connection, table: str, column: str) -> bool:
    return any(row[1] == column for row in connection.execute(f"PRAGMA table_info({table})"))


def _call_thesis_zh_expression(connection: sqlite3.Connection) -> str:
    if _column_exists(connection, "sv_call", "summary_zh"):
        return (
            "COALESCE(NULLIF(call.summary_zh, ''), NULLIF(call.summary_en, ''), "
            "NULLIF(call.evidence_span, ''), '')"
        )
    return (
        "COALESCE(NULLIF(refined.trans_zh, ''), NULLIF(call.summary_en, ''), "
        "NULLIF(call.evidence_span, ''), '')"
    )


def _full_translation_expressions(connection: sqlite3.Connection) -> tuple[str, str, str]:
    if _table_exists(connection, "yt_fulltext"):
        joins = "LEFT JOIN yt_fulltext youtube_text ON youtube_text.video_id = call.tweet_id"
        return (
            "COALESCE(NULLIF(refined.trans_zh, ''), NULLIF(youtube_text.content_zh, ''))",
            "COALESCE(NULLIF(refined.trans_en, ''), NULLIF(youtube_text.content_en, ''))",
            joins,
        )
    return "NULLIF(refined.trans_zh, '')", "NULLIF(refined.trans_en, '')", ""


def _price_evidence(
    connection: sqlite3.Connection,
    *,
    ticker: str,
    published_at: str,
) -> dict[str, Any] | None:
    """Attach a compact, real OHLC window to a time-stamped public view."""
    if not _table_exists(connection, "price_daily"):
        return None

    published_day = published_at[:10]
    rows = connection.execute(
        """
        SELECT day, open, high, low, close, volume, source
          FROM price_daily
         WHERE upper(ticker)=upper(?)
           AND day BETWEEN date(?, '-90 days') AND date(?, '+30 days')
           AND open IS NOT NULL
           AND high IS NOT NULL
           AND low IS NOT NULL
           AND close IS NOT NULL
         ORDER BY day ASC
        """,
        (ticker, published_day, published_day),
    ).fetchall()
    if not rows:
        return None

    view_index = next(
        (index - 1 for index, row in enumerate(rows) if row["day"] > published_day),
        len(rows) - 1,
    )
    view_index = max(0, view_index)
    start = max(0, view_index - 29)
    end = min(len(rows), view_index + 11)
    window = rows[start:end]
    view_row = rows[view_index]
    latest_row = window[-1]
    view_price = float(view_row["close"])
    latest_price = float(latest_row["close"])
    response_percent = (
        round(((latest_price / view_price) - 1) * 100, 2)
        if view_price and latest_row["day"] > view_row["day"]
        else None
    )
    return {
        "ticker": ticker.upper(),
        "viewDay": view_row["day"],
        "viewPrice": round(view_price, 4),
        "latestDay": latest_row["day"],
        "latestPrice": round(latest_price, 4),
        "responsePercent": response_percent,
        "source": str(view_row["source"] or "market").upper(),
        "candles": [
            {
                "day": row["day"],
                "open": round(float(row["open"]), 4),
                "high": round(float(row["high"]), 4),
                "low": round(float(row["low"]), 4),
                "close": round(float(row["close"]), 4),
                "volume": int(row["volume"] or 0),
            }
            for row in window
        ],
    }


def _representative_price_evidence(
    connection: sqlite3.Connection,
    *,
    ticker: str,
    markers: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """Return real OHLC covering every Score-contributing view for one ticker."""
    if not markers or not _table_exists(connection, "price_daily"):
        return None
    valid_markers = [
        marker
        for marker in markers
        if marker.get("viewDay") and marker.get("viewPrice") is not None
    ]
    if not valid_markers:
        return None

    first_day = min(str(marker["viewDay"]) for marker in valid_markers)
    last_day = max(str(marker["viewDay"]) for marker in valid_markers)
    rows = connection.execute(
        """
        SELECT day, open, high, low, close, volume, source
          FROM price_daily
         WHERE upper(ticker)=upper(?)
           AND day BETWEEN date(?, '-30 days') AND date(?, '+30 days')
           AND open IS NOT NULL
           AND high IS NOT NULL
           AND low IS NOT NULL
           AND close IS NOT NULL
         ORDER BY day ASC
        """,
        (ticker, first_day, last_day),
    ).fetchall()
    if not rows:
        return None

    primary = valid_markers[0]
    latest_row = rows[-1]
    view_price = float(primary["viewPrice"])
    latest_price = float(latest_row["close"])
    response_percent = (
        round(((latest_price / view_price) - 1) * 100, 2)
        if view_price and latest_row["day"] > primary["viewDay"]
        else None
    )
    return {
        "ticker": ticker.upper(),
        "viewDay": primary["viewDay"],
        "viewPrice": round(view_price, 4),
        "latestDay": latest_row["day"],
        "latestPrice": round(latest_price, 4),
        "responsePercent": response_percent,
        "source": str(rows[0]["source"] or "market").upper(),
        "candles": [
            {
                "day": row["day"],
                "open": round(float(row["open"]), 4),
                "high": round(float(row["high"]), 4),
                "low": round(float(row["low"]), 4),
                "close": round(float(row["close"]), 4),
                "volume": int(row["volume"] or 0),
            }
            for row in rows
        ],
        "opinionMarkers": valid_markers,
    }


def _profile_url(source: str, investor_id: str, handle: str) -> str | None:
    clean_handle = handle.lstrip("@")
    if source == "x" and clean_handle:
        return f"https://x.com/{clean_handle}"
    if source == "reddit" and clean_handle:
        return f"https://www.reddit.com/user/{clean_handle}"
    if source == "youtube":
        channel_id = investor_id.removeprefix("youtube:")
        if channel_id:
            return f"https://www.youtube.com/channel/{channel_id}"
    return None


def _profile_metadata(
    connection: sqlite3.Connection,
    *,
    source: str,
    investor_id: str,
    handle: str,
) -> dict[str, Any]:
    clean_handle = handle.lstrip("@")
    metadata: dict[str, Any] = {
        "name": None,
        "handle": clean_handle,
        "avatar_url": None,
        "followers_count": None,
        "posts_count": None,
        "verified": None,
        "description": None,
        "profile_url": _profile_url(source, investor_id, handle),
    }
    if _table_exists(connection, "author_profile"):
        row = connection.execute(
            """
            SELECT name, handle, avatar_url, followers_count, posts_count,
                   verified, description, profile_url
              FROM author_profile
             WHERE source=?
               AND (author_id=? OR lower(handle)=lower(?))
             ORDER BY CASE WHEN author_id=? THEN 0 ELSE 1 END
             LIMIT 1
            """,
            (source, investor_id, clean_handle, investor_id),
        ).fetchone()
        if row:
            metadata.update(
                {
                    "name": row[0],
                    "handle": row[1] or clean_handle,
                    "avatar_url": row[2] or None,
                    "followers_count": row[3],
                    "posts_count": row[4],
                    "verified": bool(row[5]),
                    "description": row[6] or None,
                    "profile_url": row[7] or metadata["profile_url"],
                }
            )

    if source == "youtube" and _table_exists(connection, "yt_platform_channel"):
        channel_id = investor_id.removeprefix("youtube:")
        row = connection.execute(
            """
            SELECT title, handle, thumbnail, subscriber_count, video_count, description
              FROM yt_platform_channel
             WHERE lower(channel_id)=lower(?)
             LIMIT 1
            """,
            (channel_id,),
        ).fetchone()
        if row:
            metadata.update(
                {
                    "name": row[0] or metadata["name"],
                    "handle": (row[1] or metadata["handle"] or "").lstrip("@"),
                    "avatar_url": row[2] or metadata["avatar_url"],
                    "followers_count": row[3],
                    "posts_count": row[4],
                    "description": row[5] or metadata["description"],
                }
            )

    if not metadata["avatar_url"] and _table_exists(connection, "author_avatar"):
        asset_handle = investor_id.removeprefix("youtube:") if source == "youtube" else clean_handle
        row = connection.execute(
            """
            SELECT url FROM author_avatar
             WHERE source=? AND lower(handle)=lower(?) AND url<>''
             LIMIT 1
            """,
            (source, asset_handle),
        ).fetchone()
        if row:
            metadata["avatar_url"] = row[0]
    return metadata


def _profile_rows(connection: sqlite3.Connection, limit: int) -> list[sqlite3.Row]:
    limit_clause = " LIMIT ?" if limit > 0 else ""
    parameters: tuple[Any, ...] = (limit,) if limit > 0 else ()
    return connection.execute(
        f"""
        WITH run_order AS (
          SELECT run_id,
                 ROW_NUMBER() OVER (ORDER BY MAX(created_at) DESC, run_id DESC) AS run_order
            FROM sv_investor_score_snapshot
           GROUP BY run_id
        ),
        previous AS (
          SELECT snapshot.investor_id, snapshot.sv
            FROM sv_investor_score_snapshot snapshot
            JOIN run_order ON run_order.run_id = snapshot.run_id
           WHERE run_order.run_order = 2
        ),
        qualified AS (
          SELECT score.*,
                 COALESCE(json_extract(score.platform_scores_json, '$.' || score.source), score.sv, 100) AS platform_sv
            FROM sv_investor_score score
           WHERE {QUALIFIED_FILTER}
        ),
        ranked AS (
          SELECT qualified.*,
                 ROW_NUMBER() OVER (
                   ORDER BY sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
                 ) AS global_rank,
                 ROW_NUMBER() OVER (
                   PARTITION BY source
                   ORDER BY platform_sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
                 ) AS platform_rank,
                 COUNT(*) OVER (PARTITION BY source) AS platform_population
            FROM qualified
        )
        SELECT ranked.investor_id,
               ranked.source,
               COALESCE(NULLIF(ranked.name, ''), NULLIF(ranked.handle, ''), ranked.investor_id) AS name,
               COALESCE(NULLIF(ranked.handle, ''), NULLIF(ranked.name, ''), ranked.investor_id) AS handle,
               COALESCE(ranked.sv, 100) AS sv,
               COALESCE(ranked.sv - previous.sv, 0) AS score_change,
               ranked.global_rank,
               ranked.platform_rank,
               CAST(ranked.platform_rank AS REAL) / ranked.platform_population AS platform_percentile,
               ranked.confidence,
               ranked.n_eff,
               ranked.settled_calls,
               ranked.active_days,
               ranked.covered_tickers,
               ranked.top_tickers_json,
               ranked.top_narratives_json,
               ranked.horizon_scores_json,
               ranked.concentration_json,
               ranked.rationale_en,
               (SELECT upper(call.ticker)
                  FROM sv_call call
                 WHERE call.investor_id = ranked.investor_id
                   AND call.is_actionable_call = 1
                 ORDER BY call.created_at DESC, call.candidate_id DESC
                 LIMIT 1) AS recent_ticker
          FROM ranked
          LEFT JOIN previous ON previous.investor_id = ranked.investor_id
         ORDER BY ranked.sv DESC, ranked.n_eff DESC, ranked.settled_calls DESC, ranked.investor_id ASC
         {limit_clause}
        """,
        parameters,
    ).fetchall()


def _update_rows(
    connection: sqlite3.Connection,
    *,
    as_of: datetime,
    days: int,
    limit: int,
    tickers: tuple[str, ...] = (),
) -> list[sqlite3.Row]:
    ticker_filter = ""
    thesis_zh_expression = _call_thesis_zh_expression(connection)
    translated_zh_expression, translated_en_expression, translation_join = _full_translation_expressions(connection)
    if tickers:
        ticker_filter = f" AND upper(call.ticker) IN ({','.join('?' for _ in tickers)})"
    limit_clause = "LIMIT ?" if limit > 0 else ""
    return connection.execute(
        f"""
        WITH qualified AS (
          SELECT investor_id, source, sv, name, handle, n_eff, settled_calls, updated_at,
                 COALESCE(json_extract(platform_scores_json, '$.' || source), sv, 100) AS platform_sv
            FROM sv_investor_score
           WHERE {QUALIFIED_FILTER}
        ),
        ranked AS (
          SELECT *,
                 ROW_NUMBER() OVER (
                   PARTITION BY source
                   ORDER BY platform_sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
                 ) AS platform_rank,
                 COUNT(*) OVER (PARTITION BY source) AS platform_population
            FROM qualified
        )
        SELECT call.candidate_id,
               upper(call.ticker) AS ticker,
               COALESCE(NULLIF(ticker.name_en, ''), NULLIF(ticker.name_zh, ''), upper(call.ticker)) AS company_name,
               call.investor_id,
               COALESCE(NULLIF(ranked.name, ''), NULLIF(ranked.handle, ''), call.author_handle, call.investor_id) AS author_name,
               call.source,
               COALESCE(ranked.sv, 100) AS sv,
               CAST(ranked.platform_rank AS REAL) / ranked.platform_population AS platform_percentile,
               call.direction,
               call.lifecycle_action,
               COALESCE(NULLIF(call.horizon_bucket, ''), 'unknown') AS horizon,
               call.target_price,
               COALESCE(NULLIF(call.summary_en, ''), NULLIF(call.evidence_span, ''), NULLIF(candidate.text, ''), '') AS thesis,
               {thesis_zh_expression} AS thesis_zh,
               NULLIF(call.invalidation_condition, '') AS invalidation,
               call.created_at,
               NULLIF(candidate.url, '') AS evidence_url,
               NULLIF(candidate.text, '') AS original_text,
               NULLIF(call.tweet_id, '') AS source_post_id,
               NULLIF(candidate.inserted_at, '') AS ingested_at,
               NULLIF(call.tagged_at, '') AS processed_at,
               {translated_zh_expression} AS translated_text_zh,
               {translated_en_expression} AS translated_text_en,
               NULLIF(call.evidence_span, '') AS evidence_span,
               NULLIF(ranked.updated_at, '') AS author_score_as_of,
               NULLIF(call.scoring_version, '') AS call_scoring_version
          FROM sv_call call
          JOIN ranked ON ranked.investor_id = call.investor_id
          LEFT JOIN sv_call_candidate candidate ON candidate.candidate_id = call.candidate_id
          LEFT JOIN kol_refined refined
            ON refined.source = call.source
           AND refined.item_id = call.tweet_id
           AND upper(refined.ticker) = upper(call.ticker)
          {translation_join}
          LEFT JOIN gr_ticker ticker ON upper(ticker.ticker) = upper(call.ticker)
         WHERE call.is_actionable_call = 1
           AND call.direction IN ('bull', 'bear')
           AND call.lifecycle_action IN ({','.join('?' for _ in LIFECYCLE_LABELS)})
           AND ranked.platform_rank <= CAST((ranked.platform_population + 3) / 4 AS INTEGER)
           {ticker_filter}
           AND datetime(call.created_at) >= datetime(?, ?)
         ORDER BY datetime(call.created_at) DESC, call.call_weight DESC, call.candidate_id ASC
         {limit_clause}
        """,
        (
            *LIFECYCLE_LABELS.keys(),
            *(ticker.upper() for ticker in tickers),
            as_of.astimezone(timezone.utc).isoformat(),
            f"-{max(1, days)} days",
            *((limit,) if limit > 0 else ()),
        ),
    ).fetchall()


def _evidence_rows(
    connection: sqlite3.Connection,
    *,
    per_author_limit: int,
) -> list[sqlite3.Row]:
    """Return the three tickers that added the most Score for each author."""
    if not _table_exists(connection, "sv_call_settlement"):
        return []
    thesis_zh_expression = _call_thesis_zh_expression(connection)
    translated_zh_expression, translated_en_expression, translation_join = _full_translation_expressions(connection)
    return connection.execute(
        f"""
        WITH qualified AS (
          SELECT investor_id, source, sv, name, handle, n_eff, settled_calls, updated_at,
                 COALESCE(json_extract(platform_scores_json, '$.' || source), sv, 100) AS platform_sv
            FROM sv_investor_score
           WHERE {QUALIFIED_FILTER}
        ),
        ranked AS (
          SELECT *,
                 ROW_NUMBER() OVER (
                   PARTITION BY source
                   ORDER BY platform_sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
                 ) AS platform_rank,
                 COUNT(*) OVER (PARTITION BY source) AS platform_population
            FROM qualified
        ),
        settlement_ranked AS (
          SELECT settlement.*,
                 ROW_NUMBER() OVER (
                   PARTITION BY settlement.candidate_id
                   ORDER BY settlement.is_primary_horizon DESC,
                            CASE settlement.horizon
                              WHEN '20D' THEN 0 WHEN '60D' THEN 1 WHEN '5D' THEN 2
                              WHEN '1D' THEN 3 WHEN '90D' THEN 4 WHEN '180D' THEN 5
                              ELSE 9 END
                 ) AS settlement_rank
            FROM sv_call_settlement settlement
        ),
        calls AS (
          SELECT call.candidate_id,
                 upper(call.ticker) AS ticker,
                 COALESCE(NULLIF(ticker.name_en, ''), NULLIF(ticker.name_zh, ''), upper(call.ticker)) AS company_name,
                 call.investor_id,
                 COALESCE(NULLIF(ranked.name, ''), NULLIF(ranked.handle, ''), call.author_handle, call.investor_id) AS author_name,
                 call.source,
                 COALESCE(ranked.sv, 100) AS sv,
                 CAST(ranked.platform_rank AS REAL) / ranked.platform_population AS platform_percentile,
                 call.direction,
                 call.lifecycle_action,
                 COALESCE(NULLIF(call.horizon_bucket, ''), 'unknown') AS horizon,
                 call.target_price,
                 COALESCE(NULLIF(call.summary_en, ''), NULLIF(call.evidence_span, ''), NULLIF(candidate.text, ''), '') AS thesis,
                 {thesis_zh_expression} AS thesis_zh,
                 NULLIF(call.invalidation_condition, '') AS invalidation,
                 call.created_at,
                 NULLIF(candidate.url, '') AS evidence_url,
                 NULLIF(candidate.text, '') AS original_text,
                 NULLIF(call.tweet_id, '') AS source_post_id,
                 NULLIF(candidate.inserted_at, '') AS ingested_at,
                 NULLIF(call.tagged_at, '') AS processed_at,
                 {translated_zh_expression} AS translated_text_zh,
                 {translated_en_expression} AS translated_text_en,
                 NULLIF(call.evidence_span, '') AS evidence_span,
                 NULLIF(ranked.updated_at, '') AS author_score_as_of,
                 NULLIF(call.scoring_version, '') AS call_scoring_version,
                 settlement.status AS settlement_status,
                 settlement.horizon AS settlement_horizon,
                 settlement.entry_day,
                 settlement.exit_day,
                 settlement.entry_price,
                 settlement.exit_price,
                 settlement.return_pct,
                 settlement.benchmark_return_pct,
                 settlement.excess_return_pct,
                 settlement.actual_hit,
                 settlement.contribution,
                 settlement.industry_benchmark_ticker,
                 settlement.industry_benchmark_return_pct,
                 settlement.industry_excess_return_pct,
                 settlement.industry_actual_hit,
                 NULLIF(settlement.settlement_version, '') AS settlement_version,
                 ROW_NUMBER() OVER (
                   PARTITION BY call.investor_id, upper(call.ticker)
                   ORDER BY COALESCE(settlement.contribution, -999) DESC,
                            MAX(
                              ABS(COALESCE(settlement.excess_return_pct, 0)),
                              ABS(COALESCE(settlement.industry_excess_return_pct, 0))
                            ) DESC,
                            datetime(call.created_at) DESC,
                            call.candidate_id
                 ) AS ticker_call_rank
            FROM sv_call call
            JOIN ranked ON ranked.investor_id = call.investor_id
            LEFT JOIN sv_call_candidate candidate ON candidate.candidate_id = call.candidate_id
            LEFT JOIN kol_refined refined
              ON refined.source = call.source
             AND refined.item_id = call.tweet_id
             AND upper(refined.ticker) = upper(call.ticker)
            {translation_join}
            LEFT JOIN gr_ticker ticker ON upper(ticker.ticker) = upper(call.ticker)
            LEFT JOIN settlement_ranked settlement
              ON settlement.candidate_id = call.candidate_id
             AND settlement.settlement_rank = 1
           WHERE call.is_actionable_call = 1
             AND call.direction IN ('bull', 'bear')
             AND call.lifecycle_action IN ({','.join('?' for _ in LIFECYCLE_LABELS)})
        ),
        contributing AS (
          SELECT calls.*,
                 SUM(contribution) OVER (
                   PARTITION BY investor_id, ticker
                 ) AS representative_ticker_contribution,
                 COUNT(*) OVER (
                   PARTITION BY investor_id, ticker
                 ) AS representative_call_count,
                 ROW_NUMBER() OVER (
                   PARTITION BY investor_id, ticker
                   ORDER BY contribution DESC,
                            MAX(
                              ABS(COALESCE(excess_return_pct, 0)),
                              ABS(COALESCE(industry_excess_return_pct, 0))
                            ) DESC,
                            datetime(created_at) DESC,
                            candidate_id
                 ) AS positive_ticker_call_rank
            FROM calls
           WHERE settlement_status='settled'
             AND contribution > 0
             AND entry_day IS NOT NULL
             AND entry_price IS NOT NULL
        ),
        ranked_tickers AS (
          SELECT investor_id,
                 ticker,
                 representative_ticker_contribution,
                 representative_call_count,
                 ROW_NUMBER() OVER (
                   PARTITION BY investor_id
                   ORDER BY representative_ticker_contribution DESC,
                            representative_call_count DESC,
                            ticker ASC
                 ) AS representative_ticker_rank
            FROM contributing
           WHERE positive_ticker_call_rank=1
        ),
        limited_calls AS (
          SELECT contributing.*,
                 ranked_tickers.representative_ticker_rank
            FROM contributing
            JOIN ranked_tickers
              ON ranked_tickers.investor_id=contributing.investor_id
             AND ranked_tickers.ticker=contributing.ticker
           WHERE ranked_tickers.representative_ticker_rank <= ?
             AND contributing.positive_ticker_call_rank <= 10
        ),
        marked AS (
          SELECT limited_calls.*,
                 json_group_array(
                   json_object(
                     'id', candidate_id,
                     'publishedAt', created_at,
                     'viewDay', entry_day,
                     'viewPrice', entry_price,
                     'direction', direction,
                     'contribution', contribution,
                     'horizon', settlement_horizon,
                     'thesis', thesis,
                     'evidenceURL', evidence_url
                   )
                 ) OVER (
                   PARTITION BY investor_id, ticker
                   ORDER BY contribution DESC, datetime(created_at) DESC, candidate_id
                   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                 ) AS representative_markers_json
            FROM limited_calls
        ),
        selected AS (
          SELECT marked.*,
                 'representative' AS evidence_role
            FROM marked
           WHERE positive_ticker_call_rank=1
        )
        SELECT *
          FROM selected
         ORDER BY investor_id, representative_ticker_rank
        """,
        (*LIFECYCLE_LABELS.keys(), max(1, per_author_limit)),
    ).fetchall()


def _representative_markers(row: sqlite3.Row) -> list[dict[str, Any]]:
    raw = row["representative_markers_json"]
    if not raw:
        return []
    try:
        values = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return []
    markers: list[dict[str, Any]] = []
    for value in values if isinstance(values, list) else []:
        if not isinstance(value, dict) or value.get("contribution") is None:
            continue
        markers.append(
            {
                "id": _stable_update_id(str(value.get("id") or "")),
                "publishedAt": _iso(value.get("publishedAt")),
                "viewDay": value.get("viewDay"),
                "viewPrice": value.get("viewPrice"),
                "direction": "bullish" if value.get("direction") == "bull" else "bearish",
                "contribution": round(float(value["contribution"]), 4),
                "horizon": value.get("horizon") or "unknown",
                "thesis": value.get("thesis") or "",
                "evidenceURL": value.get("evidenceURL"),
            }
        )
    return markers


def _settlement_payload(row: sqlite3.Row) -> dict[str, Any] | None:
    if not row["settlement_status"]:
        return None
    return {
        "status": row["settlement_status"],
        "horizon": row["settlement_horizon"] or row["horizon"],
        "entryDay": row["entry_day"],
        "exitDay": row["exit_day"],
        "entryPrice": row["entry_price"],
        "exitPrice": row["exit_price"],
        "tickerReturnPercent": _percent(row["return_pct"]),
        "marketBenchmarkReturnPercent": _percent(row["benchmark_return_pct"]),
        "marketExcessReturnPercent": _percent(row["excess_return_pct"]),
        "actualHit": None if row["actual_hit"] is None else bool(row["actual_hit"]),
        "contribution": row["contribution"],
        "industryBenchmarkTicker": row["industry_benchmark_ticker"],
        "industryBenchmarkReturnPercent": _percent(row["industry_benchmark_return_pct"]),
        "industryExcessReturnPercent": _percent(row["industry_excess_return_pct"]),
        "industryActualHit": (
            None if row["industry_actual_hit"] is None else bool(row["industry_actual_hit"])
        ),
        "settlementVersion": row["settlement_version"],
    }


def _percent(value: Any) -> float | None:
    return None if value is None else round(float(value) * 100, 2)


def _call_document(
    row: sqlite3.Row,
    *,
    metadata: dict[str, Any],
    price_evidence: dict[str, Any] | None,
    include_settlement: bool = False,
) -> dict[str, Any]:
    activity_titles = build_smart_account_activity_titles(
        ticker=row["ticker"],
        direction=row["direction"],
        lifecycle=row["lifecycle_action"],
        horizon=row["horizon"],
        target_price=row["target_price"],
        thesis_zh=row["thesis_zh"],
        thesis_en=row["thesis"],
    )
    document = {
        "id": _stable_update_id(row["candidate_id"]),
        "ticker": row["ticker"],
        "companyName": row["company_name"],
        "authorId": row["investor_id"],
        "authorName": metadata["name"] or row["author_name"],
        "platform": PLATFORM_LABELS.get(row["source"], row["source"].title()),
        "score": round(float(row["sv"]), 2),
        "platformPercentile": round(float(row["platform_percentile"]), 6),
        "direction": "bullish" if row["direction"] == "bull" else "bearish",
        "lifecycle": LIFECYCLE_LABELS[row["lifecycle_action"]],
        "horizon": row["horizon"],
        "targetPrice": row["target_price"],
        "thesis": row["thesis"],
        "invalidation": row["invalidation"],
        "publishedAt": _iso(row["created_at"]),
        "evidenceURL": row["evidence_url"],
        "authorAvatarURL": metadata["avatar_url"],
        "authorFollowersCount": metadata["followers_count"],
        "authorVerified": metadata["verified"],
        "originalText": row["original_text"],
        "priceEvidence": price_evidence,
        "sourcePostId": row["source_post_id"],
        "sourceURL": row["evidence_url"],
        "ingestedAt": _iso(row["ingested_at"]) if row["ingested_at"] else None,
        "processedAt": _iso(row["processed_at"]) if row["processed_at"] else None,
        "translatedTextZH": row["translated_text_zh"],
        "translatedTextEN": row["translated_text_en"],
        "evidenceSpan": row["evidence_span"],
        "authorScoreAsOf": _iso(row["author_score_as_of"]) if row["author_score_as_of"] else None,
        "callScoringVersion": row["call_scoring_version"],
        **activity_titles,
    }
    if include_settlement:
        document["evidenceRole"] = row["evidence_role"]
        document["settlement"] = _settlement_payload(row)
        if row["evidence_role"] == "representative":
            document["representativeTickerContribution"] = round(
                float(row["representative_ticker_contribution"]), 4
            )
            document["representativeCallCount"] = int(row["representative_call_count"])
            document["representativeTickerRank"] = int(row["representative_ticker_rank"])
    return document


def build_smart_account_client_collections(
    connection: sqlite3.Connection,
    *,
    as_of: datetime | None = None,
    update_days: int = 30,
    update_limit: int = 500,
    profile_limit: int = 0,
    update_tickers: tuple[str, ...] = (),
    include_profiles: bool = True,
    evidence_per_author: int = 3,
) -> dict[str, list[dict[str, Any]]]:
    """Return client projections without changing ranking or Call semantics."""
    connection.row_factory = sqlite3.Row
    profiles = []
    profile_rows = _profile_rows(connection, profile_limit) if include_profiles else ()
    for row in profile_rows:
        metadata = _profile_metadata(
            connection,
            source=row["source"],
            investor_id=row["investor_id"],
            handle=row["handle"],
        )
        profiles.append(
            {
            "id": row["investor_id"],
            "name": metadata["name"] or row["name"],
            "handle": "@" + (metadata["handle"] or row["handle"]).lstrip("@"),
            "platform": PLATFORM_LABELS.get(row["source"], row["source"].title()),
            "score": round(float(row["sv"]), 2),
            "scoreChange": round(float(row["score_change"]), 2),
            "specialty": _specialty(row["top_narratives_json"]),
            "horizon": _horizon(row["horizon_scores_json"]),
            "recentTicker": row["recent_ticker"],
            "rank": int(row["global_rank"]),
            "platformRank": int(row["platform_rank"]),
            "platformPercentile": round(float(row["platform_percentile"]), 6),
            "confidence": row["confidence"] or "observing",
            "effectiveSamples": round(float(row["n_eff"] or 0), 2),
            "settledCalls": int(row["settled_calls"] or 0),
            "activeDays": int(row["active_days"] or 0),
            "coveredTickers": int(row["covered_tickers"] or 0),
            "topTickers": _json_list(row["top_tickers_json"]),
            "style": _style(row["concentration_json"]),
            "marketSelectionScore": _score(row["concentration_json"], "abilities", "marketSelection", "svPlatform"),
            "industrySelectionScore": _score(row["concentration_json"], "abilities", "industrySelection", "svPlatform"),
            "rationale": row["rationale_en"],
            "avatarURL": metadata["avatar_url"],
            "profileURL": metadata["profile_url"],
            "followersCount": metadata["followers_count"],
            "postsCount": metadata["posts_count"],
            "verified": metadata["verified"],
            "description": metadata["description"],
            }
        )

    updates = []
    price_evidence_cache: dict[tuple[str, ...], dict[str, Any] | None] = {}
    priced_authors: set[str] = set()
    for row in _update_rows(
        connection,
        as_of=as_of or datetime.now(timezone.utc),
        days=update_days,
        limit=update_limit,
        tickers=update_tickers,
    ):
        metadata = _profile_metadata(
            connection,
            source=row["source"],
            investor_id=row["investor_id"],
            handle=row["author_name"],
        )
        cache_key = (row["ticker"], row["created_at"][:10])
        if cache_key not in price_evidence_cache:
            price_evidence_cache[cache_key] = _price_evidence(
                connection,
                ticker=row["ticker"],
                published_at=row["created_at"],
            )
        price_evidence = None
        if row["investor_id"] not in priced_authors:
            price_evidence = price_evidence_cache[cache_key]
            if price_evidence is not None:
                priced_authors.add(row["investor_id"])
        updates.append(
            _call_document(
                row,
                metadata=metadata,
                price_evidence=price_evidence,
            )
        )

    evidence = []
    if include_profiles:
        for row in _evidence_rows(connection, per_author_limit=evidence_per_author):
            metadata = _profile_metadata(
                connection,
                source=row["source"],
                investor_id=row["investor_id"],
                handle=row["author_name"],
            )
            markers = _representative_markers(row)
            cache_key = ("representative", row["investor_id"], row["ticker"])
            if cache_key not in price_evidence_cache:
                price_evidence_cache[cache_key] = _representative_price_evidence(
                    connection,
                    ticker=row["ticker"],
                    markers=markers,
                )
            price_evidence = price_evidence_cache[cache_key]
            evidence.append(
                _call_document(
                    row,
                    metadata=metadata,
                    price_evidence=price_evidence,
                    include_settlement=True,
                )
            )

    return {
        "smart-accounts": profiles,
        "smart-account-updates": updates,
        "smart-account-evidence": evidence,
    }
