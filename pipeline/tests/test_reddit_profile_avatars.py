from copy import deepcopy

from pipeline.platforms.author_assets.reddit_profile_avatars import avatar_url, verified_records
from scripts.sync_reddit_profile_avatars import enrich


def test_exact_profile_and_queries_are_preserved():
    url = "https://styles.redditmedia.com/t5_example/avatar.png?width=256&amp;s=signature"
    rows = {"profiles": {"alice": {"profileURL": "https://www.reddit.com/user/Alice/", "avatarURL": url}}}
    assert verified_records(rows) == {"alice": url.replace("&amp;", "&")}
    rows["profiles"]["alice"]["profileURL"] = "https://www.reddit.com/user/bob/"
    assert verified_records(rows) == {}


def test_untrusted_urls_and_unknown_identities_are_not_substituted():
    assert avatar_url("reddit:missing-account") is None
    assert avatar_url("u/SMART_MONEY_HQ") == avatar_url("reddit:smart_money_hq")
    for url in ("http://i.redd.it/avatar.png", "https://example.com/avatar.png", "https://secret@i.redd.it/avatar.png"):
        assert verified_records({"profiles": {"alice": {
            "profileURL": "https://www.reddit.com/user/alice/", "avatarURL": url}}}) == {}


def test_projection_changes_only_missing_reddit_avatars():
    rows = [
        {"id": "reddit:alice", "platform": "Reddit", "avatarURL": None, "score": 42},
        {"authorId": "reddit:alice", "platform": "Reddit", "authorAvatarURL": None, "originalText": "Keep this."},
        {"id": "reddit:alice", "platform": "Reddit", "avatarURL": "https://i.redd.it/new.png"},
        {"id": "x:alice", "platform": "X", "avatarURL": None},
        {"id": "reddit:bob", "platform": "Reddit", "avatarURL": None},
    ]
    before = deepcopy(rows)
    url = "https://i.redd.it/alice.png"
    assert enrich(rows, {"alice": url}) == 2
    assert rows[0] == {**before[0], "avatarURL": url}
    assert rows[1] == {**before[1], "authorAvatarURL": url}
    assert rows[2:] == before[2:]
    assert enrich(rows, {"alice": url}) == 0
