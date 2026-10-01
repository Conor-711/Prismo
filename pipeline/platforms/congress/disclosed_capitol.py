"""Bounded, incremental capture of Disclosed Capitol congressional trades.

The public trade schema does not expose the asset owner or original filing URL,
so these records remain source data and are not converted to CongressDisclosure.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import tempfile
from pathlib import Path
from typing import Callable

import requests


API_URL = "https://api.disclosedcapitol.com/trades"
USER_AGENT = "bSmart congress-data research/1.0"


def _api_page(
    api_key: str,
    *,
    since: dt.date,
    until: dt.date,
    limit: int,
    offset: int,
    getter: Callable = requests.get,
) -> list[dict]:
    params = {
        "date_from": since.isoformat(),
        "date_to": until.isoformat(),
        "days": min(3650, (until - since).days + 1),
        "limit": limit,
        "offset": offset,
        "sort_by": "disclosure_date",
        "sort_dir": "desc",
    }
    try:
        response = getter(
            API_URL,
            params=params,
            headers={"DC-API-Key": api_key, "Accept": "application/json", "User-Agent": USER_AGENT},
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
    except requests.HTTPError as exc:
        code = exc.response.status_code if exc.response is not None else "unknown"
        raise RuntimeError(f"Disclosed Capitol request failed: HTTP {code}") from exc
    if not isinstance(payload, list) or any(not isinstance(row, dict) for row in payload):
        raise ValueError("Disclosed Capitol returned an unexpected trades response")
    if any(row.get("id") is None for row in payload):
        raise ValueError("Disclosed Capitol returned a trade without an id")
    return payload


def fetch_trades(
    api_key: str,
    *,
    since: dt.date,
    until: dt.date,
    page_size: int = 50,
    max_pages: int = 1,
    credit_budget: int = 100,
    getter: Callable = requests.get,
) -> tuple[list[dict], int, bool]:
    """Fetch at most max_pages; report when the result may be incomplete."""
    if not api_key:
        raise ValueError("DISCLOSED_CAPITOL_API_KEY is required")
    if since > until:
        raise ValueError("since must not be later than until")
    if not 1 <= page_size <= 1000 or max_pages < 1:
        raise ValueError("page_size must be 1..1000 and max_pages must be positive")
    # Observed billing is 15 credits per call plus up to one per returned row.
    if max_pages * (15 + page_size) > credit_budget:
        raise ValueError("requested pages may exceed credit_budget; narrow the window or opt in")

    rows: list[dict] = []
    for page in range(max_pages):
        batch = _api_page(
            api_key,
            since=since,
            until=until,
            limit=page_size,
            offset=page * page_size,
            getter=getter,
        )
        rows.extend(batch)
        if len(batch) < page_size:
            return rows, page + 1, False
    return rows, max_pages, True


def save_snapshot(
    path: Path,
    rows: list[dict],
    *,
    since: dt.date,
    until: dt.date,
    pages: int,
    possibly_truncated: bool,
) -> dict:
    """Upsert by vendor ID without discarding previously captured history."""
    path = path.expanduser().resolve()
    previous: dict = {}
    if path.exists():
        previous = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(previous, dict) or not isinstance(previous.get("trades"), list):
            raise ValueError(f"Invalid existing snapshot: {path}")
    by_id = {str(row["id"]): row for row in previous.get("trades", [])}
    by_id.update({str(row["id"]): row for row in rows})
    ordered = sorted(
        by_id.values(),
        key=lambda row: (str(row.get("disclosure_date") or ""), str(row["id"])),
        reverse=True,
    )
    prior_complete = previous.get("complete_through") or (
        previous.get("query_until") if not previous.get("possibly_truncated") else ""
    )
    snapshot = {
        "source": "disclosed_capitol",
        "fetched_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "query_since": since.isoformat(),
        "query_until": until.isoformat(),
        "pages_fetched": pages,
        "possibly_truncated": possibly_truncated,
        "complete_through": (
            max(str(prior_complete or ""), until.isoformat())
            if not possibly_truncated else str(prior_complete or "")
        ),
        "fetched_count": len(rows),
        "total_count": len(ordered),
        "latest_disclosure_date": max(
            (str(row.get("disclosure_date") or "") for row in ordered), default=""
        ),
        "missing_owner_count": sum(not row.get("owner") for row in ordered),
        "missing_filing_url_count": sum(
            not (row.get("filing_url") or row.get("source_url") or row.get("evidence_url"))
            for row in ordered
        ),
        "trades": ordered,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        tmp_path = Path(handle.name)
        json.dump(snapshot, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    try:
        os.replace(tmp_path, path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise
    return snapshot
