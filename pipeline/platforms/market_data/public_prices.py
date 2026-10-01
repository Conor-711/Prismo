"""Maintain local subject-feed daily prices from public historical quote endpoints."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, timedelta
import json
from pathlib import Path
import sqlite3
import time

from .price_history import (DB, ROOT, ensure_schema, fetch_nasdaq_history,
                            fetch_yahoo_history, is_candidate_tag, row_tuple, upsert_rows)
from .subject_price_feed import feed_tickers


def recent_smart_update_tickers(connection: sqlite3.Connection, end: date) -> dict[str, date]:
    if connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sv_call'"
    ).fetchone() is None:
        return {}
    start = (end - timedelta(days=30)).isoformat()
    rows = connection.execute(
        "SELECT upper(ticker), min(substr(created_at, 1, 10)) FROM sv_call "
        "WHERE is_actionable_call=1 AND substr(created_at, 1, 10) BETWEEN ? AND ? "
        "GROUP BY upper(ticker)",
        (start, end.isoformat()),
    )
    return {ticker: date.fromisoformat(day) for ticker, day in rows
            if ticker and day and is_candidate_tag(ticker)}


def last_trading_day(end: date) -> date:
    while end.weekday() >= 5:
        end -= timedelta(days=1)
    return end


def fetch_public_history(ticker: str, start: date, end: date) -> list[tuple]:
    try:
        yahoo = fetch_yahoo_history(ticker, start, end + timedelta(days=1))
    except (OSError, ValueError, KeyError, TypeError):
        yahoo = []
    yahoo = [row for row in yahoo if start.isoformat() <= row[1] <= end.isoformat()
             and row[7] is not None and row[7] > 0]
    if yahoo and (end - date.fromisoformat(yahoo[-1][1])).days <= 1:
        return yahoo

    try:
        nasdaq = fetch_nasdaq_history(ticker, start, end)
    except (OSError, ValueError, KeyError, TypeError):
        nasdaq = []
    if not yahoo:
        return [(*row[:8], "nasdaq_raw", row[9]) for row in nasdaq]
    if not nasdaq:
        return yahoo

    yahoo_by_day = {row[1]: row for row in yahoo}
    common = [row for row in nasdaq if row[1] in yahoo_by_day]
    if not common:
        return yahoo
    raw = common[-1]
    reference = yahoo_by_day[raw[1]]
    if raw[5] <= 0 or abs(reference[5] / raw[5] - 1) > 0.03:
        return yahoo
    factor = reference[7] / raw[5]
    latest_yahoo_day = yahoo[-1][1]
    bridged = [row_tuple(ticker, row[1], row[2], row[3], row[4], row[5], row[6],
                         row[5] * factor, "nasdaq_yahoo_bridge")
               for row in nasdaq if row[1] > latest_yahoo_day]
    return yahoo + bridged


def run(*, db: Path, feed_path: Path, tickers: str, end: date,
        limit: int, sleep_seconds: float) -> dict:
    feed = json.loads(feed_path.read_text())
    first_days = feed_tickers(feed)
    missing = Counter(
        str(event.get("ticker") or "").upper()
        for event in feed.get("events", [])
        if not event.get("eventDayAdjustedClose") and not event.get("isSample")
    )
    connection = sqlite3.connect(db)
    try:
        ensure_schema(connection)
        social_days = recent_smart_update_tickers(connection, end)
        for ticker, day in social_days.items():
            first_days[ticker] = min(day, first_days.get(ticker, day))
        expected_day = last_trading_day(end).isoformat()
        stale_social = {
            ticker for ticker in social_days
            if (latest := connection.execute(
                "SELECT max(day) FROM price_daily WHERE ticker=?", (ticker,)
            ).fetchone()[0]) is None or latest < expected_day
        }
        selected = ([t.strip().upper() for t in tickers.split(",") if t.strip()]
                    if tickers else [ticker for ticker in first_days
                                     if missing[ticker] > 0 or ticker in stale_social])
        if any(t not in first_days for t in selected):
            raise ValueError("Requested ticker is absent from recent updates or the subject feed")
        selected.sort(key=lambda ticker: (missing[ticker], first_days[ticker]), reverse=True)
        if limit > 0:
            selected = selected[:limit]
        result = {"requested": len(selected), "updated": 0, "rows": 0, "empty": [], "failed": []}
        for index, ticker in enumerate(selected):
            if index and sleep_seconds:
                time.sleep(sleep_seconds)
            try:
                rows = fetch_public_history(ticker, first_days[ticker], end)
                if not rows:
                    result["empty"].append(ticker)
                    continue
                if rows[0][8] == "nasdaq_raw":
                    existing = {
                        day for day, in connection.execute(
                            "SELECT day FROM price_daily WHERE ticker=? AND source='massive_split'",
                            (ticker,),
                        )
                    }
                    rows = [row for row in rows if row[1] not in existing]
                upsert_rows(connection, rows)
                connection.commit()
                result["updated"] += 1
                result["rows"] += len(rows)
            except (OSError, ValueError, sqlite3.Error) as exc:
                result["failed"].append({"ticker": ticker, "reason": str(exc)})
        return result
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB)
    parser.add_argument("--feed", type=Path, default=ROOT / "ios/BSmart/Resources/subject-activity.json")
    parser.add_argument("--tickers", default="", help="Comma-separated subset from the subject feed")
    parser.add_argument("--end", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    parser.add_argument("--limit", type=int, default=0, help="Maximum missing tickers per run; 0 means all")
    parser.add_argument("--sleep", type=float, default=0.75, help="Seconds between tickers")
    args = parser.parse_args()
    print(json.dumps(run(db=args.db, feed_path=args.feed, tickers=args.tickers,
                         end=args.end, limit=args.limit, sleep_seconds=args.sleep), indent=2))


if __name__ == "__main__":
    main()
