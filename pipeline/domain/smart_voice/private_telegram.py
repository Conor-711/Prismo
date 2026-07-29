"""Telegram candidate and market-data preparation for the Private SV MVP."""
from __future__ import annotations

import json
import math
import sqlite3
from pathlib import Path
from typing import Any

from ...common.ticker_extraction import (
    ALIASES,
    TickerDict,
    extract_mentions,
    load_stoplist,
)
from .v0_impl import (
    NON_CALL_TAGS,
    ensure_tables,
    heuristic,
    insert_candidates,
    investor_key,
    utc_now,
)


def _reference_ticker_dict(reference: sqlite3.Connection) -> TickerDict:
    tickers: set[str] = set()
    aliases = dict(ALIASES)
    try:
        rows = reference.execute(
            "SELECT ticker,company_name,aliases FROM ticker_meta"
        ).fetchall()
    except sqlite3.OperationalError:
        rows = []
    for row in rows:
        ticker = str(row["ticker"] or "").upper()
        if not ticker:
            continue
        tickers.add(ticker)
        company_name = str(row["company_name"] or "").strip().lower()
        if len(company_name) >= 4:
            aliases[company_name] = ticker
        try:
            row_aliases = json.loads(str(row["aliases"] or "[]"))
        except (TypeError, ValueError, json.JSONDecodeError):
            row_aliases = []
        for alias in row_aliases if isinstance(row_aliases, list) else []:
            normalized = str(alias or "").strip().lower()
            if len(normalized) >= 3:
                aliases[normalized] = ticker
    try:
        tickers.update(
            str(row["ticker"]).upper()
            for row in reference.execute("SELECT DISTINCT ticker FROM price_daily")
            if row["ticker"]
        )
    except sqlite3.OperationalError:
        pass
    return TickerDict(
        tickers=tickers - NON_CALL_TAGS,
        stop=load_stoplist(),
        aliases=aliases,
    )


def _normalized_name(value: object) -> str:
    return "".join(
        character.lower()
        for character in str(value or "")
        if character.isalnum() or character.isspace()
    ).strip()


def _owner_attributed(author_name: object, channel_title: object) -> bool:
    author = _normalized_name(author_name)
    title = _normalized_name(channel_title)
    return bool(author and title and (author == title or author in title or title in author))


def _interaction_score(row: sqlite3.Row) -> float:
    return (
        max(0.0, float(row["reaction_count"] or 0)) * 2.0
        + max(0.0, float(row["reply_count"] or 0)) * 2.0
        + math.log1p(max(0.0, float(row["view_count"] or 0))) * 0.5
    )


def build_telegram_candidates(
    con: sqlite3.Connection,
    *,
    reference_db_path: str | Path,
    handle: str,
    limit: int = 0,
    min_score: float = 0.0,
) -> dict[str, Any]:
    """Map owner-authored Telegram messages into the shared SV candidate table."""
    ensure_tables(con)
    normalized_handle = handle.strip().lstrip("@").lower()
    reference = sqlite3.connect(str(reference_db_path))
    reference.row_factory = sqlite3.Row
    ticker_dict = _reference_ticker_dict(reference)
    reference.close()
    if not ticker_dict.tickers:
        raise RuntimeError("reference database has no ticker universe")

    channel = con.execute(
        "SELECT * FROM telegram_public_channel WHERE handle=?",
        (normalized_handle,),
    ).fetchone()
    if not channel:
        raise RuntimeError(f"Telegram channel @{normalized_handle} has not been crawled")
    messages = con.execute(
        """
        SELECT *
          FROM telegram_public_message
         WHERE channel_handle=?
         ORDER BY published_at, message_id
        """,
        (normalized_handle,),
    ).fetchall()

    ranked: list[tuple[float, tuple]] = []
    owner_messages = forwarded = mentioned_messages = 0
    for row in messages:
        if int(row["is_forwarded"] or 0):
            forwarded += 1
            continue
        if not _owner_attributed(row["author_name"], channel["title"]):
            continue
        owner_messages += 1
        text = str(row["text"] or "").strip()
        if len(text) < 16:
            continue
        mentions = extract_mentions(text, ticker_dict, min_confidence=0.65)
        if not mentions:
            continue
        mentioned_messages += 1
        interaction = _interaction_score(row)
        h_score, h_reason = heuristic(text)
        for mention in mentions:
            ticker = str(mention["ticker"]).upper()
            mention_confidence = float(mention["confidence"])
            score = (
                h_score
                + mention_confidence * 10.0
                + min(10.0, math.log1p(interaction) * 1.6)
                + (3.0 if len(text) >= 160 else 0.0)
            )
            if score < min_score:
                continue
            message_id = int(row["message_id"])
            reason_parts = [part for part in h_reason.split(",") if part]
            reason_parts.extend(
                [
                    f"mention={mention['method']}:{mention_confidence:.2f}",
                    "owner_attributed",
                ]
            )
            candidate = (
                f"telegram:{normalized_handle}:{message_id}:{ticker}",
                f"{normalized_handle}:{message_id}",
                ticker,
                "telegram",
                investor_key("telegram", normalized_handle),
                normalized_handle,
                str(row["published_at"] or ""),
                str(row["published_at"] or "")[:10],
                "telegram_channel_post",
                str(row["language"] or "en"),
                text,
                str(row["url"] or ""),
                int(row["reaction_count"] or 0),
                0,
                int(row["reply_count"] or 0),
                0,
                int(row["view_count"] or 0),
                0,
                interaction,
                score,
                ",".join(reason_parts),
                0,
                f"telegram-public:@{normalized_handle}",
                utc_now(),
            )
            ranked.append((score * 10.0 + interaction, candidate))

    ranked.sort(key=lambda item: (-item[0], item[1][0]))
    if limit > 0:
        ranked = ranked[:limit]
    rows_to_insert: list[tuple] = []
    for rank, (_, candidate) in enumerate(ranked, 1):
        values = list(candidate)
        values[21] = rank
        rows_to_insert.append(tuple(values))

    before = con.total_changes
    insert_candidates(con, rows_to_insert)
    con.commit()
    inserted = con.total_changes - before
    return {
        "messages": len(messages),
        "owner_messages": owner_messages,
        "forwarded_excluded": forwarded,
        "mentioned_messages": mentioned_messages,
        "candidate_pairs": len(rows_to_insert),
        "inserted": inserted,
        "tickers": len({row[2] for row in rows_to_insert}),
    }


def candidate_tickers(con: sqlite3.Connection, handle: str) -> set[str]:
    investor_id = investor_key("telegram", handle.strip().lstrip("@").lower())
    return {
        str(row["ticker"]).upper()
        for row in con.execute(
            "SELECT DISTINCT ticker FROM sv_call_candidate WHERE source='telegram' AND author_id=?",
            (investor_id,),
        )
    }
