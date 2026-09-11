"""Verified public profile avatar associations; never invent an author's image."""
from functools import lru_cache
from html import unescape
import json
from pathlib import Path
from urllib.parse import urlsplit

CATALOGUE = Path(__file__).resolve().parents[1] / "platforms/author_assets/reddit_profile_avatars.json"
HOSTS = {"www.redditstatic.com", "styles.redditmedia.com", "i.redd.it"}


def username(identity: str) -> str:
    return identity.strip().lower().removeprefix("reddit:").removeprefix("u/")


def verified_records(document: dict) -> dict[str, str]:
    result = {}
    for handle, row in document.get("profiles", {}).items():
        profile = urlsplit(row.get("profileURL", ""))
        url = unescape(row.get("avatarURL", ""))
        avatar = urlsplit(url)
        if (profile.scheme == "https" and profile.hostname == "www.reddit.com"
                and profile.path.rstrip("/").lower() == f"/user/{handle.lower()}"
                and not profile.username and not profile.password
                and avatar.scheme == "https" and avatar.hostname in HOSTS
                and not avatar.username and not avatar.password):
            result[username(handle)] = url
    return result


@lru_cache(maxsize=1)
def records() -> dict[str, str]:
    return verified_records(json.loads(CATALOGUE.read_text()))


def avatar_url(identity: str) -> str | None:
    return records().get(username(identity))
