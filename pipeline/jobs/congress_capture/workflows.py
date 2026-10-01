"""Fetch a bounded disclosure window and update the local research snapshot."""
from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path

from dotenv import dotenv_values

from ...platforms.congress.disclosed_capitol import fetch_trades, save_snapshot


def capture_trades(
    *,
    root: Path,
    output: Path,
    since: str | None = None,
    until: str | None = None,
    page_size: int = 50,
    max_pages: int = 1,
    credit_budget: int = 100,
) -> dict:
    end_date = dt.date.fromisoformat(until) if until else dt.datetime.now(dt.timezone.utc).date()
    output = output.expanduser().resolve()
    if since:
        start_date = dt.date.fromisoformat(since)
    elif output.exists():
        previous = json.loads(output.read_text(encoding="utf-8"))
        watermark = previous.get("complete_through") or (
            previous.get("query_until") if not previous.get("possibly_truncated") else None
        )
        start_date = dt.date.fromisoformat(watermark) - dt.timedelta(days=7) if watermark else end_date - dt.timedelta(days=29)
    else:
        start_date = end_date - dt.timedelta(days=29)
    api_key = os.environ.get("DISCLOSED_CAPITOL_API_KEY") or dotenv_values(root / ".env").get(
        "DISCLOSED_CAPITOL_API_KEY"
    )
    rows, pages, possibly_truncated = fetch_trades(
        api_key or "", since=start_date, until=end_date,
        page_size=page_size, max_pages=max_pages, credit_budget=credit_budget,
    )
    return save_snapshot(
        output, rows, since=start_date, until=end_date,
        pages=pages, possibly_truncated=possibly_truncated,
    )
