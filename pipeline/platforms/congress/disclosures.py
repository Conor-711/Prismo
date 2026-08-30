"""Normalize House and Senate STOCK Act disclosures from a public dataset.

The upstream project parses the official House Clerk and Senate eFD filings and
keeps the original government document URL on every transaction. This adapter
intentionally preserves both the normalized fields and that evidence link.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Iterator

from ...common.congress import CongressDisclosure, CongressMember

DEFAULT_DATASET_URL = (
    "https://codeload.github.com/kadoa-org/congress-trading-monitor/"
    "zip/refs/heads/main"
)
USER_AGENT = "bSmart Congress Score research/1.0"


def _parse_date(value: object) -> dt.date | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return dt.date.fromisoformat(text[:10])
    except ValueError:
        return None


def _optional_int(value: object) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _normalize_ticker(value: object) -> str | None:
    ticker = str(value or "").strip().upper()
    if not ticker:
        return None
    return ticker.replace(":US", "").replace("-", ".")


def download_dataset(url: str, destination: Path, *, force: bool = False) -> Path:
    """Download the upstream static dataset atomically."""
    destination = destination.expanduser().resolve()
    if destination.exists() and not force:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        with tempfile.NamedTemporaryFile(
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            tmp_path = Path(handle.name)
            shutil.copyfileobj(response, handle)
    try:
        os.replace(tmp_path, destination)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise
    return destination


def dataset_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _iter_filer_payloads(path: Path) -> Iterator[dict]:
    with zipfile.ZipFile(path) as archive:
        names = sorted(
            name
            for name in archive.namelist()
            if "/public/data/filer/" in name and name.endswith(".json")
        )
        for name in names:
            try:
                payload = json.loads(archive.read(name))
            except (KeyError, json.JSONDecodeError, UnicodeDecodeError):
                continue
            if isinstance(payload, dict):
                yield payload


def load_disclosures(
    path: Path,
    *,
    start_date: dt.date,
    end_date: dt.date,
) -> tuple[list[CongressMember], list[CongressDisclosure]]:
    """Load congressional transactions in the inclusive date window."""
    members: dict[str, CongressMember] = {}
    disclosures: dict[str, CongressDisclosure] = {}
    for payload in _iter_filer_payloads(path):
        filer = payload.get("filer") or {}
        if filer.get("branch") != "congress":
            continue
        chamber = str(filer.get("chamber") or "").lower()
        if chamber not in {"house", "senate"}:
            continue
        member_id = str(filer.get("id") or "").strip()
        name = str(filer.get("full_name") or "").strip()
        if not member_id or not name:
            continue
        member = CongressMember(
            member_id=member_id,
            name=name,
            chamber=chamber,
            party=str(filer.get("party") or "").strip() or None,
            state=str(filer.get("state") or "").strip() or None,
            office=str(filer.get("office") or "").strip() or None,
            photo_url=str(filer.get("photo_url") or "").strip() or None,
        )
        for raw in payload.get("trades") or []:
            transaction_date = _parse_date(raw.get("transaction_date"))
            if transaction_date is None or not (start_date <= transaction_date <= end_date):
                continue
            trade_id = str(raw.get("id") or "").strip()
            if not trade_id:
                continue
            members[member_id] = member
            disclosures[trade_id] = CongressDisclosure(
                trade_id=trade_id,
                member=member,
                source_id=str(raw.get("source_id") or "").strip(),
                transaction_date=transaction_date,
                filing_date=_parse_date(raw.get("filing_date")),
                notification_date=_parse_date(raw.get("notification_date")),
                owner=str(raw.get("owner") or "").strip() or None,
                ticker=_normalize_ticker(raw.get("ticker")),
                asset_name=str(raw.get("asset_name") or "").strip(),
                asset_type=str(raw.get("asset_type") or "").strip() or None,
                transaction_type=str(raw.get("transaction_type") or "").strip(),
                amount_low=_optional_int(raw.get("amount_range_low")),
                amount_high=_optional_int(raw.get("amount_range_high")),
                days_to_file=_optional_int(raw.get("days_to_file")),
                is_late=(bool(raw.get("is_late")) if raw.get("is_late") is not None else None),
                filing_type=str(raw.get("filing_type") or "").strip() or None,
                evidence_url=str(raw.get("doc_url") or "").strip() or None,
            )
    return sorted(members.values(), key=lambda item: item.name), list(disclosures.values())
