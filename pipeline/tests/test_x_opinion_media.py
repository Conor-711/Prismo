from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from pipeline.platforms.x.opinion_media import attach_media_to_release, enrich_posts, image_sources


class _Response:
    def __init__(self, location: str = "", body: str = "", content_type: str = "text/html"):
        self.status_code = 302 if location else 200
        self.headers = {"Location": location, "Content-Type": content_type}
        self.body = body

    def close(self):
        pass

    def raise_for_status(self):
        pass

    def iter_content(self, size):
        yield self.body.encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class _Session:
    def __init__(self, location: str):
        self.location = location

    def head(self, *args, **kwargs):
        return _Response(location=self.location)

    def get(self, *args, **kwargs):
        return _Response(body='<meta property="og:image" content="https://pbs.twimg.com/media/abc?format=jpg">')


def test_shortlink_only_accepts_photo_from_same_post():
    post = {"tweet_id": "123", "text": "Look https://t.co/abc123"}
    assert image_sources(post, _Session("https://x.com/user/status/123/photo/1")) == [
        "https://pbs.twimg.com/media/abc?format=jpg"
    ]
    assert image_sources(post, _Session("https://x.com/user/status/999/photo/1")) == []
    assert image_sources(post, _Session("https://x.com/user/status/123/video/1")) == []


def test_malformed_media_metadata_does_not_break_photo_lookup():
    post = {"tweet_id": "123", "media": [{"type": "photo", "url": None}], "text": "Look https://t.co/abc123"}
    assert image_sources(post, _Session("https://x.com/user/status/123/photo/1")) == [
        "https://pbs.twimg.com/media/abc?format=jpg"
    ]


def test_attach_only_x_documents_with_matching_post(tmp_path: Path):
    connection = sqlite3.connect(":memory:")
    connection.execute("CREATE TABLE x_post_media (tweet_id TEXT PRIMARY KEY, image_urls_json TEXT, checked_at TEXT)")
    connection.execute("INSERT INTO x_post_media VALUES ('123', ?, '')", (json.dumps(["https://example.com/a.jpg"]),))
    manifest = {"collections": {name: {"count": 2, "sha256": ""} for name in ("smart-account-updates", "smart-account-evidence")}}
    (tmp_path / "daily-x-manifest.json").write_text(json.dumps(manifest))
    for name in manifest["collections"]:
        (tmp_path / f"{name}.json").write_text(json.dumps([
            {"platform": "X", "sourcePostId": "123"},
            {"platform": "Reddit", "sourcePostId": "123"},
        ]))
    assert attach_media_to_release(connection, tmp_path) == {"smart-account-updates": 1, "smart-account-evidence": 1}
    documents = json.loads((tmp_path / "smart-account-updates.json").read_text())
    assert documents[0]["imageURLs"] == ["https://example.com/a.jpg"]
    assert "imageURLs" not in documents[1]


def test_failed_upload_is_not_cached(monkeypatch):
    connection = sqlite3.connect(":memory:")
    monkeypatch.setattr("pipeline.platforms.x.opinion_media.image_sources", lambda post, session: ["https://pbs.twimg.com/media/a"])
    monkeypatch.setattr("pipeline.platforms.x.opinion_media._photo_bytes", lambda session, url: (b"jpg", "jpg"))

    class FailedStore:
        def upload(self, *args):
            raise RuntimeError("temporary network error")

    result = enrich_posts(connection, [{"tweet_id": "123", "text": "photo"}], store=FailedStore(), session=_Session(""))
    assert result["failed"] == 1
    assert connection.execute("SELECT count(*) FROM x_post_media").fetchone()[0] == 0
