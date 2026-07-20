import datetime as dt

from pipeline.domain.authors.xueqiu_pool import classify_author_type
from pipeline.platforms.xueqiu.author_timeline import _author_job_key


def test_classify_known_publisher_name() -> None:
    kind, reason = classify_author_type(
        screen_name="每日经济新闻",
        statuses_count=1_000_000,
        sampled_posts=20,
        sampled_tickers=8,
        snapshot_raw={},
    )
    assert kind == "publisher"
    assert reason.startswith("publisher_name:")


def test_classify_verified_official_account() -> None:
    kind, reason = classify_author_type(
        screen_name="某机构",
        statuses_count=2_000,
        sampled_posts=3,
        sampled_tickers=2,
        snapshot_raw={"verified_description": "某公司官方账号"},
    )
    assert kind == "publisher"
    assert reason == "verified_text:官方账号"


def test_classify_individual_creator() -> None:
    kind, reason = classify_author_type(
        screen_name="长期投资者甲",
        statuses_count=3_200,
        sampled_posts=7,
        sampled_tickers=4,
        snapshot_raw={"description": "记录自己的美股投资判断"},
    )
    assert kind == "creator"
    assert reason == "creator_default"


def test_classify_automated_high_volume_publisher() -> None:
    kind, reason = classify_author_type(
        screen_name="市场播报",
        statuses_count=150_000,
        sampled_posts=25,
        sampled_tickers=9,
        snapshot_raw={},
    )
    assert kind == "publisher"
    assert reason == "publisher_volume"


def test_author_job_key_isolated_by_pool_version() -> None:
    since = dt.datetime(2025, 7, 10)
    until = dt.datetime(2026, 7, 10)
    first = _author_job_key("pool-v1", "123", since, until)
    second = _author_job_key("pool-v2", "123", since, until)
    assert first != second
    assert "pool-v1" in first
    assert "pool-v2" in second
