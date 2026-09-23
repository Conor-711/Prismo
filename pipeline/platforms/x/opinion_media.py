"""Best-effort photo enrichment for ranked X posts; never block opinion delivery."""
from __future__ import annotations

import hashlib
import io
import json
import os
import re
import sqlite3
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import getproxies

import requests
from PIL import Image, ImageOps, UnidentifiedImageError

ROOT = Path(__file__).resolve().parents[3]
BUCKET = "bsmart-opinion-media"
MAX_SOURCE_BYTES = 8 * 1024 * 1024
MAX_IMAGE_BYTES = 4 * 1024 * 1024
MAX_PIXELS = 24_000_000
MAX_IMAGES = 4
SHORT_LINK = re.compile(r"https://t\.co/[A-Za-z0-9]+")
DIRECT_IMAGE = re.compile(r"https://pbs\.twimg\.com/media/[^\s<>\"']+")
POST_PHOTO = re.compile(r"^/[^/]+/status/(\d+)/photo/\d+/?$")


class _OpenGraphImage(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.url: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "meta" or self.url:
            return
        values = dict(attrs)
        if values.get("property") == "og:image":
            self.url = values.get("content")


def _image_url(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urlparse(value.rstrip(".,);]"))
    if parsed.scheme != "https" or parsed.hostname != "pbs.twimg.com" or not parsed.path.startswith("/media/"):
        return None
    return parsed.geturl()


def _read_limited(response: requests.Response, limit: int) -> bytes:
    chunks: list[bytes] = []
    size = 0
    for chunk in response.iter_content(64 * 1024):
        size += len(chunk)
        if size > limit:
            raise ValueError("Media response exceeds size limit")
        chunks.append(chunk)
    return b"".join(chunks)


def _shortlink_image(session: requests.Session, short_url: str, tweet_id: str) -> str | None:
    response = session.head(short_url, allow_redirects=False, timeout=12)
    if response.status_code == 405:
        response = session.get(short_url, allow_redirects=False, timeout=12, stream=True)
    location = response.headers.get("Location", "")
    response.close()
    parsed = urlparse(location)
    if parsed.scheme != "https" or parsed.hostname not in {"x.com", "twitter.com", "www.x.com", "www.twitter.com"}:
        return None
    match = POST_PHOTO.fullmatch(parsed.path)
    if not match or match.group(1) != tweet_id:
        return None
    with session.get(location, timeout=18, stream=True) as page:
        page.raise_for_status()
        if "text/html" not in page.headers.get("Content-Type", ""):
            return None
        parser = _OpenGraphImage()
        parser.feed(_read_limited(page, 3 * 1024 * 1024).decode("utf-8", "replace"))
    return _image_url(parser.url or "")


def image_sources(post: dict, session: requests.Session) -> list[str]:
    tweet_id = str(post.get("tweet_id") or "")
    if not tweet_id.isdigit():
        return []
    result: list[str] = []
    for field in ("media", "media_urls", "images"):
        raw = post.get(field)
        if not isinstance(raw, list):
            continue
        for item in raw:
            if isinstance(item, dict) and item.get("type", "photo") not in {"photo", "image"}:
                continue
            value = item if isinstance(item, str) else item.get("url", "") if isinstance(item, dict) else ""
            url = _image_url(value)
            if url and url not in result:
                result.append(url)
    text = str(post.get("text") or "")
    for value in DIRECT_IMAGE.findall(text):
        url = _image_url(value)
        if url and url not in result:
            result.append(url)
    for value in SHORT_LINK.findall(text):
        if len(result) >= MAX_IMAGES:
            break
        try:
            url = _shortlink_image(session, value, tweet_id)
        except requests.RequestException:
            continue
        if url and url not in result:
            result.append(url)
    return result[:MAX_IMAGES]


def _photo_bytes(session: requests.Session, url: str) -> tuple[bytes, str]:
    with session.get(url, timeout=20, stream=True) as response:
        response.raise_for_status()
        if not response.headers.get("Content-Type", "").lower().startswith("image/"):
            raise ValueError("Media URL did not return an image")
        raw = _read_limited(response, MAX_SOURCE_BYTES)
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.width * image.height > MAX_PIXELS or image.width < 1 or image.height < 1:
                raise ValueError("Image dimensions out of range")
            image = ImageOps.exif_transpose(image)
            image.thumbnail((2400, 2400), Image.Resampling.LANCZOS)
            alpha = image.mode in {"RGBA", "LA"} or (image.mode == "P" and "transparency" in image.info)
            output = io.BytesIO()
            if alpha:
                image.save(output, format="PNG", optimize=True)
                extension = "png"
            else:
                image.convert("RGB").save(output, format="JPEG", quality=88, optimize=True)
                extension = "jpg"
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("Invalid image response") from exc
    value = output.getvalue()
    if len(value) > MAX_IMAGE_BYTES:
        raise ValueError("Processed image exceeds size limit")
    return value, extension


class SupabaseMediaStore:
    def __init__(self, *, project_url: str | None = None, workdir: Path | None = None) -> None:
        self.workdir = workdir or ROOT / "supabase/ios-account"
        configured_url = project_url or os.environ.get("BSMART_SUPABASE_URL")
        if configured_url:
            self.base_url = configured_url.rstrip("/")
        else:
            project_ref = (self.workdir / "supabase/.temp/project-ref").read_text().strip()
            self.base_url = f"https://{project_ref}.supabase.co"
        if urlparse(self.base_url).scheme != "https" or not self.base_url.endswith(".supabase.co"):
            raise ValueError("Invalid Supabase project URL")

    def upload(self, tweet_id: str, index: int, value: bytes, extension: str) -> str:
        digest = hashlib.sha256(value).hexdigest()
        object_path = f"{tweet_id}/{index}-{digest}.{extension}"
        public_url = f"{self.base_url}/storage/v1/object/public/{BUCKET}/{object_path}"
        with tempfile.TemporaryDirectory(prefix="bsmart-opinion-media-") as directory:
            source = Path(directory) / f"image.{extension}"
            source.write_bytes(value)
            environment = os.environ.copy()
            system_proxies = getproxies()
            for scheme in ("http", "https"):
                if system_proxies.get(scheme):
                    environment.setdefault(f"{scheme.upper()}_PROXY", system_proxies[scheme])
            for attempt in range(3):
                try:
                    result = subprocess.run([
                        "supabase", "storage", "cp", str(source), f"ss:///{BUCKET}/{object_path}",
                        "--experimental", "--workdir", str(self.workdir),
                        "--content-type", "image/png" if extension == "png" else "image/jpeg",
                        "--cache-control", "max-age=31536000, immutable",
                    ], capture_output=True, text=True, timeout=90, check=False, env=environment)
                    if result.returncode == 0:
                        return public_url
                except subprocess.TimeoutExpired:
                    pass
                try:
                    if requests.head(public_url, timeout=12).status_code == 200:
                        return public_url
                except requests.RequestException:
                    pass
                if attempt < 2:
                    time.sleep(attempt + 1)
            raise RuntimeError("Supabase Storage upload failed")


def ensure_table(connection: sqlite3.Connection) -> None:
    connection.execute("""
        CREATE TABLE IF NOT EXISTS x_post_media (
          tweet_id TEXT PRIMARY KEY,
          image_urls_json TEXT NOT NULL,
          checked_at TEXT NOT NULL
        )
    """)
    connection.commit()


def enrich_posts(connection: sqlite3.Connection, posts: list[dict], *,
                 store: SupabaseMediaStore | None = None,
                 session: requests.Session | None = None) -> dict[str, int]:
    ensure_table(connection)
    store = store or SupabaseMediaStore()
    session = session or requests.Session()
    result = {"posts": 0, "withImages": 0, "images": 0, "failed": 0}
    seen: set[str] = set()
    for post in posts:
        tweet_id = str(post.get("tweet_id") or "")
        if not tweet_id.isdigit() or tweet_id in seen:
            continue
        seen.add(tweet_id)
        result["posts"] += 1
        existing = connection.execute("SELECT image_urls_json FROM x_post_media WHERE tweet_id = ?", (tweet_id,)).fetchone()
        if existing:
            try:
                urls = json.loads(existing[0])
            except (TypeError, json.JSONDecodeError):
                urls = []
            if isinstance(urls, list):
                result["withImages"] += bool(urls)
                result["images"] += len(urls)
                continue
        try:
            sources = image_sources(post, session)
            urls = []
            for index, source in enumerate(sources):
                try:
                    urls.append(store.upload(tweet_id, index, *_photo_bytes(session, source)))
                except (requests.RequestException, OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
                    result["failed"] += 1
        except (requests.RequestException, OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
            result["failed"] += 1
            continue
        if not urls:
            continue
        connection.execute("INSERT INTO x_post_media(tweet_id,image_urls_json,checked_at) VALUES(?,?,?)",
                           (tweet_id, json.dumps(urls), datetime.now(timezone.utc).isoformat()))
        connection.commit()
        result["withImages"] += bool(urls)
        result["images"] += len(urls)
    return result


def attach_media_to_release(connection: sqlite3.Connection, release: Path) -> dict[str, int]:
    """Decorate existing X documents without changing calls or rankings."""
    counts: dict[str, int] = {}
    manifest_path = release / "daily-x-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for name in ("smart-account-updates", "smart-account-evidence"):
        path = release / f"{name}.json"
        documents = json.loads(path.read_text())
        attached = 0
        for document in documents:
            if document.get("platform") != "X" or not document.get("sourcePostId"):
                continue
            row = connection.execute("SELECT image_urls_json FROM x_post_media WHERE tweet_id = ?",
                                     (document["sourcePostId"],)).fetchone()
            if row:
                urls = json.loads(row[0])
                if urls:
                    document["imageURLs"] = urls
                    attached += 1
        if attached:
            path.write_text(json.dumps(documents, ensure_ascii=False, indent=2) + "\n")
            manifest["collections"][name]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        counts[name] = attached
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return counts
