"""Attach reviewed, claim-scoped factual context without changing opinions or Score."""
from __future__ import annotations

import ipaddress
import json
import logging
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit

CATALOGUE = Path(__file__).with_name("data") / "supporting_sources.json"
COLLECTIONS = {"smart-account-updates", "smart-account-evidence"}
SOURCE_TYPES = {"company", "regulatory", "news", "research", "data", "other"}
RELATIONSHIPS = {"cited", "related", "follow_up"}
TEXT_FIELDS = ("id", "eventId", "ticker", "publisher", "title", "summary", "claim", "excerpt", "locator")
OPTIONAL_FIELDS = ("titleZH", "summaryZH", "contextNote", "contextNoteZH")
LOGGER = logging.getLogger(__name__)


def _date(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return result.astimezone(timezone.utc) if result.tzinfo else None
    except ValueError:
        return None


def public_source_url(value: Any) -> str | None:
    if not isinstance(value, str) or any(c.isspace() for c in value):
        return None
    try:
        url = urlsplit(value)
        host = (url.hostname or "").lower()
        if (url.scheme != "https" or url.username is not None or url.password is not None
                or url.port not in (None, 443) or "." not in host
                or host.endswith((".local", ".localhost", ".internal"))
                or "\\" in value or not any(c.isalpha() for c in host)):
            return None
        try:
            ipaddress.ip_address(host)
            return None
        except ValueError:
            pass
        return urlunsplit(("https", host, url.path or "/", url.query, ""))
    except ValueError:
        return None


@lru_cache(maxsize=4)
def _load(path: str, modified: int, size: int) -> list[dict[str, Any]]:
    del modified, size  # The file signature invalidates the cache on review updates.
    with Path(path).open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("Supporting source catalogue must be an array")
    return [entry for entry in data if isinstance(entry, dict)]


def load_catalogue(path: Path = CATALOGUE, *, include_crawled: bool = True) -> list[dict[str, Any]]:
    entries = _catalogue_file(path)
    crawled = CATALOGUE.with_name("crawled_sources.json")
    if include_crawled and path == CATALOGUE and crawled.is_file():
        entries = [*entries, *_catalogue_file(crawled)]
    return entries


def _catalogue_file(path: Path) -> list[dict[str, Any]]:
    try:
        stat = path.stat()
        return _load(str(path), stat.st_mtime_ns, stat.st_size)
    except (OSError, ValueError):
        LOGGER.warning("Supporting source catalogue unavailable; publishing opinions without context")
        return []


def _identity(item: dict[str, Any]) -> tuple[str, str, str, str]:
    return (str(item.get("platform") or "").casefold(), str(item.get("authorId") or ""),
            str(item.get("sourcePostId") or ""), str(item.get("ticker") or "").upper())


def _source(entry: dict[str, Any], opinion: dict[str, Any], now: datetime) -> dict[str, Any] | None:
    source = entry.get("source")
    if entry.get("reviewed") is not True or not isinstance(source, dict):
        return None
    if (source.get("status") != "ready" or not isinstance(source.get("sourceType"), str)
            or not isinstance(source.get("relationship"), str)
            or source["sourceType"] not in SOURCE_TYPES or source["relationship"] not in RELATIONSHIPS):
        return None
    if any(not isinstance(source.get(key), str) or not source[key].strip() for key in TEXT_FIELDS):
        return None
    original = opinion.get("originalText")
    if (not isinstance(original, str) or source["claim"] not in original
            or source["ticker"].upper() != str(opinion.get("ticker", "")).upper()):
        return None
    published, opinion_date = _date(source.get("publishedAt")), _date(opinion.get("publishedAt"))
    updated = _date(source.get("updatedAt")) if source.get("updatedAt") is not None else None
    url = public_source_url(source.get("sourceURL"))
    if not published or not opinion_date or not url or published > now:
        return None
    if source.get("updatedAt") is not None and (not updated or updated < published or updated > now):
        return None
    if (source["relationship"] == "follow_up") != (max(published, updated or published) > opinion_date):
        return None
    # Explicit citation is a reviewed property, never inferred from a matching ticker.
    if source["relationship"] == "cited" and entry.get("citationVerified") is not True:
        return None
    result = {key: source[key] for key in TEXT_FIELDS}
    result.update({key: source[key] for key in ("sourceType", "relationship", "status", "publishedAt")})
    result["sourceURL"] = url
    if updated:
        result["updatedAt"] = source["updatedAt"]
    result.update({key: source[key] for key in OPTIONAL_FIELDS
                   if isinstance(source.get(key), str) and source[key].strip()})
    return result


def enrich_collection(
    name: str, opinions: list[dict[str, Any]], *,
    catalogue: list[dict[str, Any]] | None = None, now: datetime | None = None,
) -> list[dict[str, Any]]:
    if name not in COLLECTIONS:
        return opinions
    index: dict[tuple[str, str, str, str], list[dict[str, Any]]] = {}
    for entry in catalogue if catalogue is not None else load_catalogue():
        if isinstance(entry, dict) and all(_identity(entry)):
            index.setdefault(_identity(entry), []).append(entry)
    result = []
    for opinion in opinions:
        updated = {key: value for key, value in opinion.items() if key != "supportingSources"}
        sources, ids, urls = [], set(), set()
        for entry in index.get(_identity(opinion), []):
            source = _source(entry, opinion, now or datetime.now(timezone.utc))
            if source is None or source["id"] in ids or source["sourceURL"] in urls:
                continue
            ids.add(source["id"])
            urls.add(source["sourceURL"])
            sources.append(source)
        if sources:
            updated["supportingSources"] = sources
        result.append(updated)
    return result
