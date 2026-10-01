"""Backfill feed securities with split-adjusted Massive daily bars.

Run with MASSIVE_API_KEY in the environment, or with the local macOS Keychain
item ``bsmart.massive.api-key``. The API key is sent only in an HTTP header.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from .price_history import DB, ROOT, ensure_schema, row_tuple, upsert_rows
from .subject_price_feed import TICKER, feed_tickers


API_ROOT = "https://api.massive.com"
KEYCHAIN_SERVICE = "bsmart.massive.api-key"


def api_key() -> str:
    key = os.environ.get("MASSIVE_API_KEY", "").strip()
    if key:
        return key
    if sys.platform == "darwin":
        result = subprocess.run(
            ["security", "find-generic-password", "-a", "bsmart", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    raise RuntimeError("Set MASSIVE_API_KEY (or add the local macOS Keychain item)")


def fetch_daily_bars(ticker: str, start: date, end: date, *, key: str) -> list[tuple]:
    if not TICKER.fullmatch(ticker) or start > end:
        raise ValueError("Invalid ticker or date range")
    query = urlencode({"adjusted": "true", "sort": "asc", "limit": 50000})
    url = (f"{API_ROOT}/v2/aggs/ticker/{quote(ticker, safe='')}/range/1/day/"
           f"{start.isoformat()}/{end.isoformat()}?{query}")
    rows: list[tuple] = []
    while url:
        if not url.startswith(API_ROOT + "/"):
            raise ValueError("Unexpected Massive pagination URL")
        request = Request(url, headers={"Authorization": f"Bearer {key}", "Accept": "application/json"})
        try:
            with urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except HTTPError as exc:
            raise RuntimeError(f"Massive HTTP {exc.code} for {ticker}") from None
        if payload.get("status") not in {"OK", "DELAYED"} or payload.get("adjusted") is not True:
            raise RuntimeError(f"Unexpected Massive response for {ticker}: {payload.get('status')}")
        for bar in payload.get("results") or []:
            day = datetime.fromtimestamp(bar["t"] / 1000, tz=timezone.utc).date().isoformat()
            close = float(bar["c"])
            if close <= 0 or not start.isoformat() <= day <= end.isoformat():
                continue
            rows.append(row_tuple(ticker, day, bar["o"], bar["h"], bar["l"], close,
                                  int(bar.get("v") or 0), close, "massive_split"))
        url = payload.get("next_url")
    return rows


def run(*, db: Path, feed_path: Path, tickers: str, start: date | None,
        end: date, limit: int, sleep_seconds: float) -> dict:
    feed = json.loads(feed_path.read_text())
    first_days = feed_tickers(feed)
    key = api_key()
    connection = sqlite3.connect(db)
    try:
        ensure_schema(connection)
        missing = Counter(
            str(event.get("ticker") or "").upper()
            for event in feed.get("events", [])
            if not event.get("eventDayAdjustedClose") and not event.get("isSample")
        )
        selected = ([t.strip().upper() for t in tickers.split(",") if t.strip()]
                    if tickers else [t for t in first_days if missing[t] > 0])
        if any(t not in first_days for t in selected):
            raise ValueError("Requested ticker is absent from the subject feed")
        needs: list[tuple[int, date, str]] = []
        for ticker in selected:
            first = max(start or first_days[ticker], first_days[ticker])
            if first <= end:
                needs.append((missing[ticker], first, ticker))
        needs.sort(key=lambda item: (item[0], item[1]), reverse=True)
        if limit > 0:
            needs = needs[:limit]
        result = {"requested": len(needs), "updated": 0, "rows": 0, "empty": [], "failed": []}
        for index, (_, first, ticker) in enumerate(needs):
            if index and sleep_seconds:
                time.sleep(sleep_seconds)
            try:
                bars = fetch_daily_bars(ticker, first, end, key=key)
                if bars:
                    upsert_rows(connection, bars)
                    connection.commit()
                    result["updated"] += 1
                    result["rows"] += len(bars)
                else:
                    result["empty"].append(ticker)
            except (RuntimeError, ValueError, OSError) as exc:
                result["failed"].append({"ticker": ticker, "reason": str(exc)})
                if "HTTP 429" in str(exc) or "HTTP 403" in str(exc) or "HTTP 401" in str(exc):
                    break
        return result
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB)
    parser.add_argument("--feed", type=Path, default=ROOT / "ios/BSmart/Resources/subject-activity.json")
    parser.add_argument("--tickers", default="", help="Comma-separated subset from the subject feed")
    parser.add_argument("--start", type=date.fromisoformat, help="Optional lower bound")
    parser.add_argument("--end", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    parser.add_argument("--limit", type=int, default=5, help="Maximum tickers per run; 0 means all")
    parser.add_argument("--sleep", type=float, default=13, help="Seconds between requests")
    args = parser.parse_args()
    print(json.dumps(run(db=args.db, feed_path=args.feed, tickers=args.tickers,
                         start=args.start, end=args.end, limit=args.limit,
                         sleep_seconds=args.sleep), indent=2))


if __name__ == "__main__":
    main()
