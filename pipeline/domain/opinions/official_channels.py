"""Explicit issuer identities and first-party publication surfaces."""
from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import urlsplit


@dataclass(frozen=True)
class IssuerChannel:
    ticker: str
    cik: int
    publisher: str
    index_url: str | None = None
    feed_url: str | None = None
    article_hosts: tuple[str, ...] = ()
    article_paths: tuple[str, ...] = ()


# Each new ticker requires a reviewed CIK and a first-party article allowlist.
ISSUERS = (
    IssuerChannel("AAPL", 320193, "Apple"),
    IssuerChannel("COIN", 1679788, "Coinbase"),
    IssuerChannel("CRCL", 1876042, "Circle Internet Group"),
    IssuerChannel("CRDO", 1807794, "Credo Technology Group"),
    IssuerChannel("CRWD", 1535527, "CrowdStrike"),
    IssuerChannel("GOLD", 1591588, "Gold.com"),
    IssuerChannel("INTC", 50863, "Intel"),
    IssuerChannel("NVDA", 1045810, "NVIDIA", feed_url="https://nvidianews.nvidia.com/cats/press_release.xml",
                  article_hosts=("nvidianews.nvidia.com",), article_paths=("/news/",)),
    IssuerChannel("MU", 723125, "Micron Technology", index_url="https://www.micron.com/about/press/news",
                  article_hosts=("www.micron.com",), article_paths=("/about/press/news/",)),
    # Strategy's press robots endpoint returns 403; SEC filings remain available.
    IssuerChannel("MSTR", 1050446, "Strategy"),
    IssuerChannel("NBIS", 1513845, "Nebius Group", index_url="https://nebius.com/newsroom",
                  article_hosts=("nebius.com",), article_paths=("/newsroom/",)),
)


def candidates_for_rule(index: dict, spec: dict, *, limit: int = 4) -> list[str]:
    """Suggest only same-date, same-publisher candidates for a reviewed claim rule."""
    found = []
    issuer = next((item for item in ISSUERS if item.ticker == spec["ticker"]), None)
    if issuer is None:
        return found
    for channel in ("issuer", "sec"):
        for candidate in index.get("channels", {}).get(f"{spec['ticker']}:{channel}", {}).get("items", []):
            url = candidate.get("url", "")
            try:
                parsed = urlsplit(url)
                port = parsed.port
            except ValueError:
                continue
            allowed = (parsed.scheme == "https" and parsed.username is None and parsed.password is None
                       and port in (None, 443) and
                       ((channel == "sec" and parsed.hostname == "www.sec.gov" and
                         parsed.path.startswith(f"/Archives/edgar/data/{issuer.cik}/")) or
                        (channel == "issuer" and parsed.hostname in issuer.article_hosts and
                         any(parsed.path.startswith(path) for path in issuer.article_paths))))
            if not allowed:
                continue
            expected_type = "company" if channel == "issuer" else "regulatory"
            if (spec.get("sourceType") != expected_type or
                    spec.get("publisher", "").casefold() != candidate.get("publisher", "").casefold() or
                    not (candidate.get("publishedAt") or "").startswith(spec.get("sourceDate", "\0")) or
                    not all(term.casefold() in candidate.get("title", "").casefold()
                            for term in spec.get("titleTerms", []))):
                continue
            if url not in found:
                found.append(url)
            if len(found) >= limit:
                return found
    return found
