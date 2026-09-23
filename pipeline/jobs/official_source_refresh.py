"""Refresh first-party filing/news candidates; never attach them to opinions automatically."""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit

from ..domain.opinions.official_channels import ISSUERS, IssuerChannel
from ..platforms.source_documents.official import index_links, rss_items, sec_filings
from ..platforms.source_documents.web import CrawlError, WebCrawler

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "data/runtime/official-sources"
CONTACT = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\Z")


def _write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _candidate(item: dict, *, issuer: IssuerChannel, channel: str, now: datetime) -> dict:
    url = item["url"]
    return {"id": sha256(f"{issuer.ticker}:{url}".encode()).hexdigest()[:24],
            "ticker": issuer.ticker, "publisher": "SEC EDGAR" if channel == "sec" else issuer.publisher,
            "channel": channel, "url": url, "title": item["title"],
            "publishedAt": item.get("publishedAt"),
            "publishedPrecision": item.get("publishedPrecision"),
            "contentHash": item.get("contentHash"), "form": item.get("form"),
            "acceptedAt": item.get("acceptedAt"), "discoveredAt": now.isoformat(),
            "reviewStatus": "candidate"}


def _sec(crawler: WebCrawler, issuer: IssuerChannel) -> list[dict]:
    url = f"https://data.sec.gov/submissions/CIK{issuer.cik:010d}.json"
    final, body = crawler.fetch_payload(url, content_types=("application/json", "text/json"))
    if final != url:
        raise CrawlError("sec_redirected")
    return sec_filings(json.loads(body), ticker=issuer.ticker, cik=issuer.cik, limit=500)


def _publisher(crawler: WebCrawler, issuer: IssuerChannel) -> tuple[list[dict], list[dict]]:
    errors: list[dict] = []
    if issuer.feed_url:
        final, body = crawler.fetch_payload(issuer.feed_url, content_types=("text/xml", "application/xml", "application/rss+xml"))
        if final != issuer.feed_url:
            raise CrawlError("feed_redirected")
        links = rss_items(body, hosts=issuer.article_hosts, paths=issuer.article_paths)
    elif issuer.index_url:
        index = crawler.fetch(issuer.index_url)
        if index.url != issuer.index_url:
            raise CrawlError("index_redirected")
        links = index_links(index, hosts=issuer.article_hosts, paths=issuer.article_paths)
    else:
        return [], []
    if not links:
        raise CrawlError("no_first_party_articles")
    articles = []
    for link in links:
        try:
            article = crawler.fetch(link["url"])
            parsed = urlsplit(article.url)
            if (parsed.hostname not in issuer.article_hosts or
                    not any(parsed.path.startswith(path) for path in issuer.article_paths)):
                raise CrawlError("article_redirected_off_site")
            articles.append({"url": article.url, "title": article.title,
                             "publishedAt": article.published_values[0] if article.published_values else link.get("publishedAt"),
                             "publishedPrecision": "timestamp" if article.published_values else link.get("publishedPrecision"),
                             "contentHash": article.content_hash})
        except (CrawlError, OSError, ValueError) as error:
            errors.append({"url": link["url"], "error": str(error)})
    if not articles:
        raise CrawlError("no_readable_first_party_articles")
    return articles, errors


def _retain(candidate: dict, now: datetime) -> bool:
    value = candidate.get("publishedAt") or candidate.get("discoveredAt")
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if date.tzinfo is None:
            date = date.replace(tzinfo=timezone.utc)
        return date >= now - timedelta(days=366)
    except (AttributeError, ValueError):
        return False


def _stale(last_success: str | None, now: datetime) -> bool:
    if not last_success:
        return True
    try:
        return now - datetime.fromisoformat(last_success.replace("Z", "+00:00")) > timedelta(hours=48)
    except (TypeError, ValueError):
        return True


def run(*, output_dir: Path = OUTPUT, contact: str | None = None,
        issuers: tuple[IssuerChannel, ...] = ISSUERS, crawler: WebCrawler | None = None,
        now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    if contact and not CONTACT.fullmatch(contact):
        raise ValueError("BSMART_OFFICIAL_CONTACT must be a contact email address")
    crawler = crawler or WebCrawler(output_dir / "cache", request_limit=80, refresh=True,
                                    user_agent=f"bSmartEvidenceBot/0.1 ({contact})" if contact else "bSmartEvidenceBot/0.1")
    index_file = output_dir / "index.json"
    old = json.loads(index_file.read_text(encoding="utf-8")) if index_file.exists() else {}
    channels = {key: {**value, "items": [item for item in value.get("items", []) if _retain(item, now)]}
                for key, value in old.get("channels", {}).items()}
    results = []
    for issuer in issuers:
        for channel in ("sec", "issuer"):
            key = f"{issuer.ticker}:{channel}"
            previous = channels.get(key, {})
            if channel == "issuer" and not (issuer.feed_url or issuer.index_url):
                continue
            if channel == "sec" and not contact:
                results.append({"channel": key, "status": "not_configured", "lastSuccessAt": previous.get("lastSuccessAt"),
                                "stale": _stale(previous.get("lastSuccessAt"), now)})
                continue
            try:
                items, errors = (_sec(crawler, issuer), []) if channel == "sec" else _publisher(crawler, issuer)
                if not items and channel == "issuer":
                    raise CrawlError("empty_channel")
                fresh = [_candidate(item, issuer=issuer, channel=channel, now=now) for item in items]
                fresh = [item for item in fresh if _retain(item, now)]
                retained = {item["id"]: item for item in previous.get("items", []) if _retain(item, now)}
                for item in fresh:
                    if item["id"] in retained:
                        item["discoveredAt"] = retained[item["id"]]["discoveredAt"]
                    retained[item["id"]] = item
                channels[key] = {"lastSuccessAt": now.isoformat(),
                                 "items": sorted(retained.values(),
                                                 key=lambda item: item.get("publishedAt") or item.get("discoveredAt") or "",
                                                 reverse=True)[:500]}
                results.append({"channel": key, "status": "ok" if not errors else "partial",
                                "newCount": len(fresh), "retainedCount": len(channels[key]["items"]),
                                "errors": errors, "lastSuccessAt": now.isoformat(), "stale": False})
            except (CrawlError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
                # Do not overwrite the last good snapshot when a source is down or its schema changes.
                results.append({"channel": key, "status": "error", "error": str(error),
                                "lastSuccessAt": previous.get("lastSuccessAt"),
                                "stale": _stale(previous.get("lastSuccessAt"), now)})
    indexed = {"version": 1, "checkedAt": now.isoformat(), "channels": channels}
    covered = {issuer.ticker: any(item["channel"].startswith(issuer.ticker + ":") and
                                  (item["status"] in {"ok", "partial"} or
                                   (item.get("lastSuccessAt") and not item["stale"]))
                                  for item in results) for issuer in issuers}
    health = {"checkedAt": now.isoformat(), "requests": crawler.requests, "channels": results,
              "candidateCount": sum(len(value.get("items", [])) for value in channels.values()),
              "coveredTickers": [ticker for ticker, available in covered.items() if available],
              "uncoveredTickers": [ticker for ticker, available in covered.items() if not available],
              "degraded": any(result["status"] != "ok" for result in results)}
    _write_json(index_file, indexed)
    _write_json(output_dir / "health.json", health)
    return health


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    args = parser.parse_args()
    result = run(output_dir=args.output_dir, contact=os.environ.get("BSMART_OFFICIAL_CONTACT"))
    print(json.dumps(result, ensure_ascii=False))
    if result["degraded"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
