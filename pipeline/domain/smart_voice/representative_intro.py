"""Lightweight discovery evidence from existing ranked works and collected calls."""
from __future__ import annotations

import math
import sqlite3
import uuid
from datetime import datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")


def _date(value: str | None) -> datetime | None:
    try:
        result = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return result.replace(tzinfo=timezone.utc) if result.tzinfo is None else result
    except (ValueError, TypeError):
        return None


def _number(value: Any) -> float | None:
    return float(value) if isinstance(value, (int, float)) and math.isfinite(value) else None


def _source(value: str) -> str:
    return {"twitter": "x", "雪球": "xueqiu"}.get(value.lower(), value.lower())


def _evidence_id(candidate_id: str) -> str:
    try:
        return str(uuid.UUID(candidate_id))
    except ValueError:
        return str(uuid.uuid5(uuid.UUID("6f86d8e3-19b2-4d33-9f06-403a3b034330"), candidate_id))


def _key(document: dict) -> tuple[str, str, str]:
    return (_source(document["platform"]), document["authorId"],
            document["ticker"].upper())


def _first_opinions(connection: sqlite3.Connection, keys: set[tuple], as_of: datetime) -> dict:
    cursor = connection.cursor()
    cursor.row_factory = sqlite3.Row
    tables = {row[0] for row in cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if not {"sv_call", "sv_call_candidate", "sv_call_settlement"}.issubset(tables):
        return {}
    authors = sorted({key[1] for key in keys})
    first: dict[tuple, dict] = {}
    for offset in range(0, len(authors), 200):
        batch = authors[offset:offset + 200]
        rows = cursor.execute(f"""
            WITH settled AS (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY candidate_id
                    ORDER BY is_primary_horizon DESC,
                    CASE horizon WHEN '20D' THEN 0 WHEN '60D' THEN 1 WHEN '5D' THEN 2
                      WHEN '1D' THEN 3 WHEN '90D' THEN 4 WHEN '180D' THEN 5 ELSE 9 END) AS position
                FROM sv_call_settlement
            )
            SELECT call.source, call.investor_id, call.ticker, call.direction, call.candidate_id,
                   call.created_at, call.tweet_id, candidate.url, settled.horizon, settled.return_pct,
                   settled.entry_day, settled.entry_price, settled.exit_day
              FROM sv_call call
              LEFT JOIN sv_call_candidate candidate ON candidate.candidate_id=call.candidate_id
              JOIN settled ON settled.candidate_id=call.candidate_id AND settled.position=1
             WHERE call.investor_id IN ({','.join('?' for _ in batch)})
               AND call.is_actionable_call=1 AND call.direction IN ('bull', 'bear')
               AND call.lifecycle_action IN ('open_call', 'reinforce_call', 'reverse_call', 'close_prior_call', 'invalidate_prior_call')
               AND settled.status='settled' AND settled.contribution > 0
               AND settled.entry_day IS NOT NULL AND settled.entry_price > 0
             ORDER BY datetime(call.created_at), settled.contribution DESC, call.candidate_id
        """, batch).fetchall()
        for row in rows:
            direction = "bullish" if row["direction"] == "bull" else "bearish"
            key = (_source(row["source"]), row["investor_id"], row["ticker"].upper())
            published = _date(row["created_at"])
            if key not in keys or key in first or published is None or published > as_of:
                continue
            first[key] = {
                "publishedAt": published.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
                "direction": direction, "sourcePostId": row["tweet_id"], "evidenceURL": row["url"],
                "price": None, "priceDay": None, "priceSource": None,
                "priceBasis": "last_completed_daily_close",
                "_selected": {"evidenceId": _evidence_id(row["candidate_id"]),
                              "horizon": row["horizon"],
                              "stockReturnPercent": round(row["return_pct"] * 100, 2) if _number(row["return_pct"]) is not None else None,
                              "entryDay": row["entry_day"], "entryPrice": row["entry_price"], "exitDay": row["exit_day"]},
            }

    for key, opinion in first.items():
        if "price_daily" not in tables:
            break
        local = _date(opinion["publishedAt"]).astimezone(EASTERN)
        # Early-close sessions conservatively use the prior close until 16:00.
        cutoff = local.date() if local.time() >= time(16) else local.date() - timedelta(days=1)
        price = cursor.execute("""
            SELECT day, close, source FROM price_daily
             WHERE ticker=? AND day BETWEEN ? AND ? AND close > 0
             ORDER BY day DESC LIMIT 1
        """, (key[2], (local.date() - timedelta(days=7)).isoformat(), cutoff.isoformat())).fetchone()
        if price is not None and _number(price["close"]) is not None:
            opinion.update(price=round(float(price["close"]), 4), priceDay=price["day"],
                           priceSource=price["source"])
    return first


def enrich_representative_intros(
    connection: sqlite3.Connection, profiles: list[dict], evidence: list[dict], *, as_of: datetime,
) -> dict[str, int]:
    """Add optional metadata only. Preserve source documents, score and work ordering."""
    eligible = []
    for work in evidence:
        work.pop("firstOpinion", None)
        settlement = work.get("settlement") or {}
        published = _date(work.get("publishedAt"))
        if (work.get("evidenceRole") == "representative" and settlement.get("status") == "settled"
                and (_number(work.get("representativeTickerContribution")) or 0) > 0
                and work.get("direction") in ("bullish", "bearish")
                and published is not None and published <= as_of):
            eligible.append(work)
    first = _first_opinions(connection, {_key(work) for work in eligible}, as_of)
    by_author: dict[tuple, list[dict]] = {}
    for work in eligible:
        opinion = first.get(_key(work))
        if opinion is not None and _date(opinion["publishedAt"]) <= _date(work["publishedAt"]):
            work["firstOpinion"] = {key: value for key, value in opinion.items() if key != "_selected"}
        by_author.setdefault((_source(work["platform"]), work["authorId"]), []).append(work)
    count = 0
    for profile in profiles:
        works = by_author.get((_source(profile["platform"]), profile["id"]), [])
        if not works:
            profile.pop("representativeWork", None)
            continue
        work = min(works, key=lambda w: (w.get("representativeTickerRank") or 999,
                                        -w["representativeTickerContribution"], w["ticker"]))
        summary = {key: work[key] for key in ("authorId", "platform", "ticker", "direction", "publishedAt")}
        summary.update(evidenceId=work["id"], horizon=work["settlement"]["horizon"],
                       stockReturnPercent=_number(work["settlement"].get("tickerReturnPercent")))
        opinion = first.get(_key(work))
        if opinion:
            summary.update(opinion["_selected"])
            summary.update(publishedAt=opinion["publishedAt"], direction=opinion["direction"])
            summary["firstOpinion"] = {key: value for key, value in opinion.items() if key != "_selected"}
        profile["representativeWork"] = summary
        count += 1
    return {"profiles": len(profiles), "withRepresentative": count,
            "withFirstOpinion": sum(bool(p.get("representativeWork", {}).get("firstOpinion")) for p in profiles),
            "withFirstPrice": sum(p.get("representativeWork", {}).get("firstOpinion", {}).get("price") is not None for p in profiles)}
