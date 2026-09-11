"""Add roster JSONL posts to the existing local X archive without deleting history."""
from __future__ import annotations

import datetime as dt
import json
from collections import Counter
from pathlib import Path

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def opinion_rows(post: dict, tickers: set[str]) -> list[dict]:
    if str(post.get("tweet_type", "")).lower() == "retweet":
        return []
    tweet_id = str(post.get("tweet_id") or "")
    body = str(post.get("text") or "")
    created = str(post.get("created_at") or "")
    if not body:
        return []
    if not tweet_id or not created:
        raise ValueError("Missing tweet_id or created_at")
    dt.datetime.fromisoformat(created.replace("Z", "+00:00"))
    tags = {
        str(tag).strip().upper().lstrip("$").replace("-", ".")
        for tag in post.get("cashtags") or []
    } & tickers
    common = {
        "tweet_id": tweet_id, "handle": str(post.get("author_handle") or "").lstrip("@"),
        "text": body, "lang": str(post.get("lang") or ""),
        "created": created, "url": str(post.get("url") or ""),
    }
    for column, field in {
        "likes": "like_count", "retweets": "retweet_count", "replies": "reply_count",
        "quotes": "quote_count", "views": "view_count", "bookmarks": "bookmark_count",
    }.items():
        common[column] = max(0, int(post.get(field) or 0))
    return [{**common, "ticker": ticker} for ticker in sorted(tags)]


def import_archives(engine: Engine, folders: list[Path], *, dry_run: bool = False) -> dict:
    """Insert missing (ticker, tweet_id) rows only; existing evidence stays immutable."""
    if engine.dialect.name != "sqlite":
        raise ValueError("Roster archive import requires the local SQLite truth source")
    if not inspect(engine).has_table("x_opinion"):
        raise RuntimeError("Existing x_opinion schema is required; no DDL is performed")
    files = sorted({path.resolve() for folder in folders for path in folder.glob("tweets_*.jsonl")})
    if not files:
        raise FileNotFoundError("No tweets_*.jsonl files in the supplied directories")
    with engine.connect() as connection:
        tickers = set(connection.execute(text(
            "SELECT ticker FROM price_daily WHERE close IS NOT NULL "
            "GROUP BY ticker HAVING COUNT(*) >= 80"
        )).scalars())
    statement = text(
        "INSERT INTO x_opinion (tweet_id,ticker,handle,text,lang,likes,retweets,replies,"
        "quotes,views,bookmarks,created,url) VALUES (:tweet_id,:ticker,:handle,:text,:lang,"
        ":likes,:retweets,:replies,:quotes,:views,:bookmarks,:created,:url) "
        "ON CONFLICT(ticker,tweet_id) DO NOTHING"
    )
    counts = Counter(scanned=0, matched_pairs=0, inserted=0, invalid=0)
    file_counts = []
    batch: list[dict] = []

    def flush() -> None:
        if batch and not dry_run:
            with engine.begin() as connection:
                counts["inserted"] += connection.execute(statement, batch).rowcount
        batch.clear()

    for path in files:
        file_rows = 0
        with path.open(encoding="utf-8") as stream:
            for number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                counts["scanned"] += 1
                file_rows += 1
                try:
                    rows = opinion_rows(json.loads(line), tickers)
                except (ValueError, TypeError, AttributeError) as exc:
                    raise ValueError(f"Invalid archive row {path.name}:{number}: {type(exc).__name__}") from exc
                counts["matched_pairs"] += len(rows)
                batch.extend(rows)
                if len(batch) >= 2000:
                    flush()
        flush()
        file_counts.append({"path": str(path), "rows": file_rows})
        print(f"[x-archive] {path.parent.name}/{path.name}: rows={file_rows} inserted_total={counts['inserted']}", flush=True)
    return {**counts, "dry_run": dry_run, "files": file_counts, "price_tickers": len(tickers)}
