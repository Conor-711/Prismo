"""Crawl a public Telegram broadcast channel through its public preview pages."""
from __future__ import annotations

import datetime as dt
import json
import re
import sqlite3
import time
from dataclasses import dataclass
from typing import Any

import requests
from bs4 import BeautifulSoup, Tag


BASE_URL = "https://t.me/s/{handle}"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
)
NUMBER_RE = re.compile(r"(-?\d+(?:[.,]\d+)?)\s*([KMB]?)", re.IGNORECASE)


@dataclass(frozen=True)
class TelegramMessage:
    channel_handle: str
    message_id: int
    author_name: str
    text: str
    language: str
    url: str
    view_count: int
    reaction_count: int
    reply_count: int
    is_forwarded: bool
    forwarded_from: str
    published_at: str
    raw: dict[str, Any]


def ensure_schema(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS telegram_public_channel (
          handle TEXT PRIMARY KEY,
          title TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          public_url TEXT NOT NULL DEFAULT '',
          subscriber_count INTEGER NOT NULL DEFAULT 0,
          message_count INTEGER NOT NULL DEFAULT 0,
          first_message_at TEXT,
          last_message_at TEXT,
          fetched_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS telegram_public_message (
          channel_handle TEXT NOT NULL,
          message_id INTEGER NOT NULL,
          author_name TEXT NOT NULL DEFAULT '',
          text TEXT NOT NULL DEFAULT '',
          language TEXT NOT NULL DEFAULT 'en',
          url TEXT NOT NULL DEFAULT '',
          view_count INTEGER NOT NULL DEFAULT 0,
          reaction_count INTEGER NOT NULL DEFAULT 0,
          reply_count INTEGER NOT NULL DEFAULT 0,
          is_forwarded INTEGER NOT NULL DEFAULT 0,
          forwarded_from TEXT NOT NULL DEFAULT '',
          published_at TEXT NOT NULL,
          raw TEXT,
          first_seen_at TEXT NOT NULL,
          last_seen_at TEXT NOT NULL,
          PRIMARY KEY(channel_handle, message_id)
        );
        CREATE INDEX IF NOT EXISTS ix_telegram_public_message_channel_published
          ON telegram_public_message(channel_handle, published_at);
        CREATE INDEX IF NOT EXISTS ix_telegram_public_message_forwarded
          ON telegram_public_message(is_forwarded);
        """
    )
    con.commit()


def parse_compact_number(value: object) -> int:
    text = str(value or "").strip().replace("\u00a0", " ")
    match = NUMBER_RE.search(text)
    if not match:
        return 0
    number = float(match.group(1).replace(",", "."))
    multiplier = {"": 1, "K": 1_000, "M": 1_000_000, "B": 1_000_000_000}
    return max(0, int(round(number * multiplier.get(match.group(2).upper(), 1))))


def _text(node: Tag | None) -> str:
    return node.get_text(" ", strip=True) if node else ""


def _parse_reactions(node: Tag) -> int:
    total = 0
    for reaction in node.select(".tgme_reaction"):
        amount = parse_compact_number(_text(reaction))
        total += amount if amount > 0 else 1
    return total


def _message_from_node(node: Tag, expected_handle: str) -> TelegramMessage | None:
    native = str(node.get("data-post") or "")
    if "/" not in native:
        return None
    channel_handle, raw_id = native.rsplit("/", 1)
    if channel_handle.lower() != expected_handle.lower() or not raw_id.isdigit():
        return None
    time_node = node.select_one("time[datetime]")
    published_at = str(time_node.get("datetime") or "") if time_node else ""
    if not published_at:
        return None
    message_id = int(raw_id)
    forwarded_node = node.select_one(
        ".tgme_widget_message_forwarded_from, .tgme_widget_message_forwarded_from_name"
    )
    author_name = _text(node.select_one(".tgme_widget_message_author"))
    text_node = node.select_one(".js-message_text")
    message_text = _text(text_node)
    reactions_node = node.select_one(".js-message_reactions")
    reply_node = node.select_one(
        ".tgme_widget_message_reply, .tgme_widget_message_comments"
    )
    forwarded_from = _text(forwarded_node)
    return TelegramMessage(
        channel_handle=channel_handle.lower(),
        message_id=message_id,
        author_name=author_name,
        text=message_text,
        language="en",
        url=f"https://t.me/{channel_handle}/{message_id}",
        view_count=parse_compact_number(
            _text(node.select_one(".tgme_widget_message_views"))
        ),
        reaction_count=_parse_reactions(reactions_node) if reactions_node else 0,
        reply_count=parse_compact_number(_text(reply_node)),
        is_forwarded=bool(forwarded_node),
        forwarded_from=forwarded_from,
        published_at=published_at,
        raw={
            "data_post": native,
            "html": str(node),
        },
    )


def parse_preview_page(
    html: str,
    expected_handle: str,
) -> tuple[list[TelegramMessage], str | None, dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")
    messages = [
        parsed
        for node in soup.select(".js-widget_message[data-post]")
        if (parsed := _message_from_node(node, expected_handle)) is not None
    ]
    older = soup.select_one("a.tme_messages_more[data-before]")
    before = str(older.get("data-before") or "") if older else ""

    title = _text(soup.select_one(".tgme_channel_info_header_title"))
    description = _text(soup.select_one(".tgme_channel_info_description"))
    subscriber_count = 0
    for counter in soup.select(".tgme_channel_info_counter"):
        label = _text(counter.select_one(".counter_type")).lower()
        if "subscriber" in label or "member" in label:
            subscriber_count = parse_compact_number(
                _text(counter.select_one(".counter_value"))
            )
            break
    metadata = {
        "title": title,
        "description": description,
        "subscriber_count": subscriber_count,
    }
    return messages, before or None, metadata


def _request_page(
    session: requests.Session,
    url: str,
    before: str | None,
    timeout: float,
    retries: int,
) -> str:
    params = {"before": before} if before else None
    last_error: Exception | None = None
    for attempt in range(max(1, retries)):
        try:
            response = session.get(url, params=params, timeout=timeout)
            response.raise_for_status()
            if "tgme_widget_message" not in response.text:
                raise RuntimeError("Telegram preview returned no message markup")
            return response.text
        except (requests.RequestException, RuntimeError) as exc:
            last_error = exc
            if attempt + 1 < max(1, retries):
                time.sleep(min(8.0, 0.8 * (2**attempt)))
    raise RuntimeError(f"failed to fetch Telegram preview: {last_error}")


def _upsert_messages(
    con: sqlite3.Connection,
    messages: list[TelegramMessage],
    fetched_at: str,
) -> None:
    con.executemany(
        """
        INSERT INTO telegram_public_message (
          channel_handle,message_id,author_name,text,language,url,view_count,
          reaction_count,reply_count,is_forwarded,forwarded_from,published_at,
          raw,first_seen_at,last_seen_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(channel_handle,message_id) DO UPDATE SET
          author_name=excluded.author_name,
          text=excluded.text,
          language=excluded.language,
          url=excluded.url,
          view_count=excluded.view_count,
          reaction_count=excluded.reaction_count,
          reply_count=excluded.reply_count,
          is_forwarded=excluded.is_forwarded,
          forwarded_from=excluded.forwarded_from,
          published_at=excluded.published_at,
          raw=excluded.raw,
          last_seen_at=excluded.last_seen_at
        """,
        [
            (
                item.channel_handle,
                item.message_id,
                item.author_name,
                item.text,
                item.language,
                item.url,
                item.view_count,
                item.reaction_count,
                item.reply_count,
                int(item.is_forwarded),
                item.forwarded_from,
                item.published_at,
                json.dumps(item.raw, ensure_ascii=False),
                fetched_at,
                fetched_at,
            )
            for item in messages
        ],
    )


def crawl_public_channel(
    con: sqlite3.Connection,
    *,
    handle: str,
    max_pages: int = 0,
    sleep_seconds: float = 0.2,
    timeout_seconds: float = 30.0,
    retries: int = 4,
) -> dict[str, Any]:
    """Fetch all public preview history and upsert it into the raw layer."""
    ensure_schema(con)
    normalized_handle = handle.strip().lstrip("@").lower()
    if not re.fullmatch(r"[A-Za-z0-9_]{5,80}", normalized_handle):
        raise ValueError(f"invalid public Telegram handle: {handle!r}")

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.9"})
    url = BASE_URL.format(handle=normalized_handle)
    before: str | None = None
    seen_cursors: set[str] = set()
    seen_ids: set[int] = set()
    metadata: dict[str, Any] = {}
    pages = 0
    fetched_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()

    while True:
        html = _request_page(session, url, before, timeout_seconds, retries)
        messages, next_before, page_metadata = parse_preview_page(
            html,
            normalized_handle,
        )
        if not messages:
            break
        pages += 1
        metadata = {**metadata, **{key: value for key, value in page_metadata.items() if value}}
        _upsert_messages(con, messages, fetched_at)
        con.commit()
        seen_ids.update(message.message_id for message in messages)

        if not next_before or next_before in seen_cursors:
            break
        seen_cursors.add(next_before)
        before = next_before
        if max_pages > 0 and pages >= max_pages:
            break
        if sleep_seconds > 0:
            time.sleep(sleep_seconds)

    bounds = con.execute(
        """
        SELECT COUNT(*) AS n, MIN(published_at) AS first_at,
               MAX(published_at) AS last_at
          FROM telegram_public_message
         WHERE channel_handle=?
        """,
        (normalized_handle,),
    ).fetchone()
    message_count = int(bounds["n"] or 0)
    con.execute(
        """
        INSERT INTO telegram_public_channel (
          handle,title,description,public_url,subscriber_count,message_count,
          first_message_at,last_message_at,fetched_at
        ) VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(handle) DO UPDATE SET
          title=excluded.title,
          description=excluded.description,
          public_url=excluded.public_url,
          subscriber_count=excluded.subscriber_count,
          message_count=excluded.message_count,
          first_message_at=excluded.first_message_at,
          last_message_at=excluded.last_message_at,
          fetched_at=excluded.fetched_at
        """,
        (
            normalized_handle,
            str(metadata.get("title") or normalized_handle),
            str(metadata.get("description") or ""),
            url,
            int(metadata.get("subscriber_count") or 0),
            message_count,
            str(bounds["first_at"] or ""),
            str(bounds["last_at"] or ""),
            fetched_at,
        ),
    )
    con.commit()
    return {
        "handle": normalized_handle,
        "pages": pages,
        "fetched_messages": len(seen_ids),
        "stored_messages": message_count,
        "first_message_at": str(bounds["first_at"] or ""),
        "last_message_at": str(bounds["last_at"] or ""),
        "subscriber_count": int(metadata.get("subscriber_count") or 0),
    }
