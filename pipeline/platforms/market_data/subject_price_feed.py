"""Price lookup dates for the subject activity feed."""
from __future__ import annotations

from datetime import date
import re


TICKER = re.compile(r"^[A-Z][A-Z0-9.]{0,9}$")
NON_STOCK_SYMBOLS = {"US.TBILL"}


def feed_tickers(feed: dict) -> dict[str, date]:
    earliest: dict[str, date] = {}
    for event in feed.get("events", []):
        ticker = str(event.get("ticker") or "").upper().strip()
        if not TICKER.fullmatch(ticker) or ticker in NON_STOCK_SYMBOLS or event.get("isSample"):
            continue
        raw_day = event.get("displayDay") if event.get("type") == "opinion" else event.get("occurredDay")
        try:
            day = date.fromisoformat(raw_day)
        except (TypeError, ValueError):
            continue
        earliest[ticker] = min(day, earliest.get(ticker, day))
    return earliest
