"""Normalize provider payloads into stable X post records."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from typing import Any


@dataclass(frozen=True)
class NormalizedPost:
    post_id: str
    author_id: str
    author_handle: str
    author_name: str
    author_avatar_url: str | None
    author_followers_count: int | None
    author_verified: bool | None
    source_url: str
    original_text: str
    language: str
    post_type: str
    is_reply: bool
    is_quote: bool
    is_retweet: bool
    parent_post_id: str | None
    conversation_id: str | None
    like_count: int
    reply_count: int
    retweet_count: int
    quote_count: int
    view_count: int
    bookmark_count: int
    published_at: datetime
    raw_payload: dict[str, Any]


def _integer(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


def _optional_integer(value: Any) -> int | None:
    return None if value is None else _integer(value)


def _datetime(value: Any) -> datetime:
    raw = str(value or "").strip()
    if not raw:
        raise ValueError("tweet has no createdAt")
    try:
        parsed = parsedate_to_datetime(raw)
    except (TypeError, ValueError):
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC).replace(tzinfo=None)


def normalize_tweet(payload: dict[str, Any]) -> NormalizedPost:
    post_id = str(payload.get("id") or payload.get("tweetId") or "").strip()
    author = payload.get("author") if isinstance(payload.get("author"), dict) else {}
    author_id = str(
        author.get("id") or payload.get("authorId") or payload.get("author_id") or ""
    ).strip()
    handle = str(author.get("userName") or author.get("username") or "").strip().lstrip("@")
    text = str(payload.get("text") or "").strip()
    if not post_id or not author_id or not handle or not text:
        raise ValueError("tweet is missing id, stable author id, handle, or text")

    retweeted = payload.get("retweeted_tweet") or payload.get("retweetedTweet")
    quoted = payload.get("quoted_tweet") or payload.get("quotedTweet")
    is_retweet = bool(retweeted) or text.startswith("RT @")
    is_quote = bool(quoted)
    is_reply = bool(
        payload.get("isReply")
        or payload.get("is_reply")
        or payload.get("inReplyToId")
        or payload.get("in_reply_to_id")
    )
    post_type = "retweet" if is_retweet else "quote" if is_quote else "reply" if is_reply else "original"
    return NormalizedPost(
        post_id=post_id,
        author_id=author_id,
        author_handle=handle,
        author_name=str(author.get("name") or handle).strip(),
        author_avatar_url=str(
            author.get("profilePicture") or author.get("profile_picture") or ""
        ).strip() or None,
        author_followers_count=_optional_integer(
            author.get("followers")
            if author.get("followers") is not None
            else author.get("followers_count")
        ),
        author_verified=(
            bool(author.get("isBlueVerified"))
            if author.get("isBlueVerified") is not None
            else bool(author.get("is_blue_verified"))
            if author.get("is_blue_verified") is not None
            else None
        ),
        source_url=str(payload.get("url") or f"https://x.com/{handle}/status/{post_id}"),
        original_text=text,
        language=str(payload.get("lang") or "").strip().lower(),
        post_type=post_type,
        is_reply=is_reply,
        is_quote=is_quote,
        is_retweet=is_retweet,
        parent_post_id=str(
            payload.get("inReplyToId") or payload.get("in_reply_to_id") or ""
        ).strip() or None,
        conversation_id=str(
            payload.get("conversationId") or payload.get("conversation_id") or ""
        ).strip() or None,
        like_count=_integer(payload.get("likeCount", payload.get("like_count"))),
        reply_count=_integer(payload.get("replyCount", payload.get("reply_count"))),
        retweet_count=_integer(payload.get("retweetCount", payload.get("retweet_count"))),
        quote_count=_integer(payload.get("quoteCount", payload.get("quote_count"))),
        view_count=_integer(payload.get("viewCount", payload.get("view_count"))),
        bookmark_count=_integer(payload.get("bookmarkCount", payload.get("bookmark_count"))),
        published_at=_datetime(payload.get("createdAt") or payload.get("created_at")),
        raw_payload=payload,
    )


def normalize_delivery(payload: Any) -> tuple[str, list[NormalizedPost]]:
    """Accept webhook, search and direct tweet response shapes."""
    if not isinstance(payload, dict):
        raise ValueError("provider delivery must be a JSON object")
    tag = str(payload.get("tag") or payload.get("rule_tag") or "")
    if isinstance(payload.get("tweet"), dict):
        candidates = [payload["tweet"]]
    elif isinstance(payload.get("tweets"), list):
        candidates = payload["tweets"]
    elif payload.get("id") and payload.get("author"):
        candidates = [payload]
    else:
        candidates = []
    posts: list[NormalizedPost] = []
    invalid = 0
    for candidate in candidates:
        if not isinstance(candidate, dict):
            invalid += 1
            continue
        try:
            post = normalize_tweet(candidate)
        except ValueError:
            invalid += 1
            continue
        if not post.is_retweet:
            posts.append(post)
    if candidates and invalid == len(candidates):
        raise ValueError("provider delivery contains no valid tweets")
    return tag, posts
