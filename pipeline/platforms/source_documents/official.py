"""Parse bounded SEC and issuer feeds into review-only source metadata."""
from __future__ import annotations

from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import re
from urllib.parse import urlsplit
from xml.etree import ElementTree

from .web import CrawlError, Document, normalize_url

FORMS = {"8-K", "8-K/A", "10-Q", "10-Q/A", "10-K", "10-K/A", "6-K", "6-K/A", "20-F", "20-F/A"}
SEC_COLUMNS = ("form", "accessionNumber", "primaryDocument", "filingDate", "acceptanceDateTime")
SAFE_FILE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,200}\Z")
ACCESSION = re.compile(r"\d{10}-\d{2}-\d{6}\Z")


def sec_filings(payload: dict, *, ticker: str, cik: int, limit: int = 500) -> list[dict]:
    if int(payload.get("cik", -1)) != cik or ticker not in payload.get("tickers", []):
        raise CrawlError("sec_issuer_mismatch")
    recent = payload.get("filings", {}).get("recent", {})
    if not all(isinstance(recent.get(key), list) for key in SEC_COLUMNS):
        raise CrawlError("sec_schema_changed")
    lengths = {len(recent[key]) for key in SEC_COLUMNS}
    if len(lengths) != 1:
        raise CrawlError("sec_columns_misaligned")
    items = []
    for form, accession, primary, date, accepted in zip(*(recent[key] for key in SEC_COLUMNS)):
        if form not in FORMS or not isinstance(accession, str) or not ACCESSION.fullmatch(accession):
            continue
        if not isinstance(primary, str) or not SAFE_FILE.fullmatch(primary):
            continue
        try:
            filed = datetime.fromisoformat(date).date().isoformat()
        except (ValueError, TypeError):
            continue
        url = f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession.replace('-', '')}/{primary}"
        items.append({"url": url, "title": f"{ticker} Form {form}", "publishedAt": filed,
                      "publishedPrecision": "date", "form": form, "acceptedAt": accepted or None})
        if len(items) >= limit:
            break
    return items


def _feed_date(value: str) -> str | None:
    try:
        parsed = parsedate_to_datetime(value)
        if parsed.tzinfo is None:
            return None
        return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except (TypeError, ValueError):
        return None


def rss_items(data: bytes, *, hosts: tuple[str, ...], paths: tuple[str, ...], limit: int = 8) -> list[dict]:
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise CrawlError("xml_external_entity")
    try:
        root = ElementTree.fromstring(data)
    except ElementTree.ParseError as error:
        raise CrawlError("invalid_feed") from error
    if root.tag.lower() not in ("rss", "{http://www.w3.org/2005/atom}feed"):
        raise CrawlError("unsupported_feed")
    result = []
    atom = "{http://www.w3.org/2005/atom}"
    for item in list(root.findall("./channel/item")) + list(root.findall(f"./{atom}entry")):
        link = item.findtext("link")
        if not link:
            link_node = item.find(f"{atom}link")
            link = link_node.get("href") if link_node is not None else None
        try:
            url = normalize_url(link or "")
        except CrawlError:
            continue
        parsed = urlsplit(url)
        if parsed.hostname not in hosts or not any(parsed.path.startswith(prefix) for prefix in paths):
            continue
        title = (item.findtext("title") or item.findtext(f"{atom}title") or "").strip()
        if not title:
            continue
        published = _feed_date(item.findtext("pubDate") or item.findtext(f"{atom}published") or "")
        result.append({"url": url, "title": title[:300], "publishedAt": published,
                       "publishedPrecision": "timestamp" if published else None})
        if len(result) >= limit:
            break
    return result


def index_links(document: Document, *, hosts: tuple[str, ...], paths: tuple[str, ...],
                limit: int = 8) -> list[dict]:
    found = []
    for link in document.links:
        try:
            url = normalize_url(link["url"])
        except (CrawlError, KeyError):
            continue
        parsed = urlsplit(url)
        if parsed.hostname not in hosts or not any(parsed.path.startswith(prefix) for prefix in paths):
            continue
        if url == document.url or url in found or not link.get("title", "").strip():
            continue
        found.append(url)
        if len(found) >= limit:
            break
    return [{"url": url} for url in found]
