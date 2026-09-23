"""Bounded HTML crawler: robots, public-IP pinning, TLS and per-host throttling."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
import ipaddress
import json
from pathlib import Path
import socket
import time
from urllib.parse import urljoin, urlsplit, urlunsplit
from urllib.robotparser import RobotFileParser

from bs4 import BeautifulSoup
import certifi
import urllib3

USER_AGENT = "bSmartEvidenceBot/0.1"
MAX_BYTES = 2_000_000


class CrawlError(RuntimeError):
    pass


def normalize_url(value: str) -> str:
    if not isinstance(value, str) or "\\" in value or any(c.isspace() for c in value):
        raise CrawlError("invalid_url")
    try:
        url = urlsplit(value)
        host = (url.hostname or "").lower().rstrip(".")
        if (url.scheme != "https" or url.port not in (None, 443) or url.username is not None or url.password is not None
                or "." not in host or host.endswith((".local", ".localhost", ".internal"))):
            raise CrawlError("unsafe_url")
        try:
            ipaddress.ip_address(host)
        except ValueError:
            return urlunsplit(("https", host, url.path or "/", url.query, ""))
        raise CrawlError("ip_literal")
    except ValueError as error:
        raise CrawlError("invalid_url") from error


def public_addresses(host: str) -> list[str]:
    addresses = sorted({item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
    if not addresses or any(not ipaddress.ip_address(value).is_global for value in addresses):
        raise CrawlError("non_public_dns")
    return addresses


def clean_text(text: str) -> str:
    return " ".join(text.split())


@dataclass
class Document:
    url: str
    title: str
    text: str
    published_values: list[str]
    modified_values: list[str]
    links: list[dict[str, str]]
    content_hash: str


def parse_html(url: str, html: bytes) -> Document:
    soup = BeautifulSoup(html, "html.parser")
    published, modified = [], []
    for node in soup.find_all("meta"):
        key = str(node.get("property") or node.get("name") or node.get("itemprop") or "").lower()
        value = str(node.get("content") or "").strip()
        if key in {"article:published_time", "datepublished", "date", "pubdate", "publishdate"} and value:
            published.append(value)
        if key in {"article:modified_time", "datemodified", "last-modified"} and value:
            modified.append(value)

    def dates(item):
        if isinstance(item, list):
            for value in item:
                dates(value)
        if isinstance(item, dict):
            for key, value in item.items():
                if key == "datePublished" and isinstance(value, str):
                    published.append(value)
                elif key == "dateModified" and isinstance(value, str):
                    modified.append(value)
                elif isinstance(value, (list, dict)):
                    dates(value)

    for script in soup.find_all("script", type="application/ld+json"):
        try:
            dates(json.loads(script.get_text()))
        except (ValueError, TypeError):
            continue
    for node in soup.find_all("time"):
        value = node.get("datetime") or node.get_text(" ", strip=True)
        if value:
            published.append(str(value))
    title = soup.find("h1") or soup.find("title")
    title_text = clean_text(title.get_text(" ", strip=True)) if title else ""
    links = []
    for node in soup.find_all("a", href=True):
        try:
            link = normalize_url(urljoin(url, node["href"]))
        except CrawlError:
            continue
        links.append({"url": link, "title": clean_text(node.get_text(" ", strip=True))})
    for node in soup.select("script,style,noscript,nav,footer,form,[hidden],[aria-hidden=true]"):
        node.decompose()
    # Some newsrooms use <article> only for related-story teasers.
    body = soup.find("main") or soup.body or soup
    text = clean_text(body.get_text(" ", strip=True))
    if len(text) < 100:
        raise CrawlError("insufficient_body")
    return Document(url, title_text, text, list(dict.fromkeys(published)),
                    list(dict.fromkeys(modified)), links, sha256(html).hexdigest())


class WebCrawler:
    def __init__(self, cache_dir: Path, *, request_limit: int = 30, refresh: bool = False,
                 user_agent: str = USER_AGENT):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.request_limit = request_limit
        self.requests = 0
        self.refresh = refresh
        self.user_agent = user_agent
        self.robots: dict[str, RobotFileParser] = {}
        self.last_request: dict[str, float] = {}
        self.host_delay: dict[str, float] = {}

    def _get(self, url: str) -> tuple[int, dict[str, str], bytes]:
        url = normalize_url(url)
        host = urlsplit(url).hostname
        addresses = public_addresses(host)
        if self.requests >= self.request_limit:
            raise CrawlError("request_budget_exhausted")
        self.requests += 1
        delay = self.host_delay.get(host, 1.0)
        time.sleep(max(0.0, delay - (time.monotonic() - self.last_request.get(host, 0))))
        self.last_request[host] = time.monotonic()
        # Connect to the already-validated IP, retaining host verification and SNI.
        pool = urllib3.HTTPSConnectionPool(
            addresses[0], port=443, server_hostname=host, assert_hostname=host,
            cert_reqs="CERT_REQUIRED", ca_certs=certifi.where(),
            timeout=urllib3.Timeout(connect=8, read=12), maxsize=1,
        )
        response = None
        try:
            parsed = urlsplit(url)
            path = parsed.path + ("?" + parsed.query if parsed.query else "")
            response = pool.urlopen("GET", path, headers={"Host": host, "User-Agent": self.user_agent,
                                    "Accept": "text/html,application/json,application/xml,text/xml,text/plain",
                                    "Accept-Encoding": "identity"},
                                    redirect=False, retries=False, preload_content=False)
            headers = {key.lower(): value for key, value in response.headers.items()}
            if int(headers.get("content-length", "0")) > MAX_BYTES:
                raise CrawlError("document_too_large")
            chunks, size, deadline = [], 0, time.monotonic() + 25
            for chunk in response.stream(32768, decode_content=True):
                size += len(chunk)
                if size > MAX_BYTES or time.monotonic() > deadline:
                    raise CrawlError("document_read_limit")
                chunks.append(chunk)
            return response.status, headers, b"".join(chunks)
        except (urllib3.exceptions.HTTPError, OSError, ValueError) as error:
            raise CrawlError(type(error).__name__) from None
        finally:
            if response:
                response.close()
            pool.close()

    def _allowed(self, url: str) -> bool:
        origin = "https://" + urlsplit(url).netloc
        if origin not in self.robots:
            status, _, content = self._get(origin + "/robots.txt")
            parser = RobotFileParser()
            if status == 404:
                parser.parse(["User-agent: *", "Disallow:"])
            elif status == 200:
                parser.parse(content.decode("utf-8", "replace").splitlines())
            else:
                raise CrawlError(f"robots_unavailable_{status}")
            delay = parser.crawl_delay(self.user_agent) or 1
            rate = parser.request_rate(self.user_agent)
            if rate:
                delay = max(delay, rate.seconds / max(1, rate.requests))
            if delay > 15:
                raise CrawlError("crawl_delay_exceeds_local_batch_limit")
            self.host_delay[urlsplit(url).hostname] = max(1.0, delay)
            self.robots[origin] = parser
        return self.robots[origin].can_fetch(self.user_agent, url)

    def fetch_payload(self, url: str, *, content_types: tuple[str, ...]) -> tuple[str, bytes]:
        """Read a small non-HTML feed through the same SSRF/robots/redirect controls."""
        url = normalize_url(url)
        for _ in range(4):
            if not self._allowed(url):
                raise CrawlError("robots_disallowed")
            status, headers, content = self._get(url)
            if status in (301, 302, 303, 307, 308):
                url = normalize_url(urljoin(url, headers.get("location", "")))
                continue
            if status != 200:
                raise CrawlError(f"http_{status}")
            if not any(value in headers.get("content-type", "").lower() for value in content_types):
                raise CrawlError("unsupported_content_type")
            return url, content
        raise CrawlError("redirect_limit")

    def fetch(self, url: str) -> Document:
        url = normalize_url(url)
        path = self.cache_dir / (sha256(url.encode()).hexdigest() + ".json")
        if not self.refresh and path.is_file() and time.time() - path.stat().st_mtime < 86400:
            return Document(**json.loads(path.read_text(encoding="utf-8")))
        for _ in range(4):
            if not self._allowed(url):
                raise CrawlError("robots_disallowed")
            status, headers, content = self._get(url)
            if status in (301, 302, 303, 307, 308):
                url = normalize_url(urljoin(url, headers.get("location", "")))
                continue
            if status != 200:
                raise CrawlError(f"http_{status}")
            if not any(value in headers.get("content-type", "").lower()
                       for value in ("text/html", "application/xhtml+xml")):
                raise CrawlError("unsupported_content_type")
            document = parse_html(url, content)
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(asdict(document), ensure_ascii=False), encoding="utf-8")
            temporary.replace(path)
            return document
        raise CrawlError("redirect_limit")

    def discover(self, index_url: str, terms: list[str], *, limit: int = 3) -> list[str]:
        document = self.fetch(index_url)
        matches = []
        host = urlsplit(document.url).hostname
        for link in document.links:
            if urlsplit(link["url"]).hostname != host:
                continue
            text = (link["title"] + " " + link["url"]).casefold().replace("-", " ")
            if all(term.casefold() in text for term in terms) and link["url"] not in matches:
                matches.append(link["url"])
        return matches[:limit]
