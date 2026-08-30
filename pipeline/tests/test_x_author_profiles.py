from __future__ import annotations

import sqlite3
from pathlib import Path

from pipeline.platforms.author_assets.x_profiles import refresh_x_profiles


def test_x_profiles_materialize_current_snapshot_and_avatar(tmp_path: Path) -> None:
    database = tmp_path / "profiles.db"
    connection = sqlite3.connect(database)
    connection.execute(
        """
        CREATE TABLE sv_investor_score (
          investor_id TEXT PRIMARY KEY, source TEXT, name TEXT, handle TEXT,
          sv REAL, n_eff REAL, settled_calls INTEGER
        )
        """
    )
    connection.execute(
        "INSERT INTO sv_investor_score VALUES ('123', 'x', '@example', '@example', 110, 12, 16)"
    )
    connection.commit()
    connection.close()

    def fetcher(handle: str) -> dict[str, object]:
        assert handle == "example"
        return {
            "id": "123",
            "screen_name": "example",
            "name": "Example Investor",
            "avatar_url": "https://pbs.twimg.com/profile_images/1/photo_normal.jpg",
            "followers": 12500,
            "following": 120,
            "tweets": 900,
            "media_count": 42,
            "description": "Public investing account",
            "url": "https://x.com/example",
            "verification": {"verified": True, "type": "individual"},
        }

    result = refresh_x_profiles(db_path=database, fetcher=fetcher, workers=1)

    assert result["fetched"] == 1
    connection = sqlite3.connect(database)
    current = connection.execute(
        "SELECT name, avatar_url, followers_count, verified FROM author_profile"
    ).fetchone()
    snapshot_count = connection.execute("SELECT COUNT(*) FROM author_profile_snapshot").fetchone()[0]
    avatar = connection.execute("SELECT handle, url FROM author_avatar WHERE source='x'").fetchone()
    connection.close()

    assert current == (
        "Example Investor",
        "https://pbs.twimg.com/profile_images/1/photo_400x400.jpg",
        12500,
        1,
    )
    assert snapshot_count == 1
    assert avatar == ("example", "https://pbs.twimg.com/profile_images/1/photo_400x400.jpg")
