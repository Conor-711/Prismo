from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from pipeline.domain.smart_voice.realtime_x import (
    RealtimePostInput,
    RealtimeXAnalyzer,
    _normalize_translation,
    _traceable_evidence_span,
)
from pipeline.jobs.smart_voice.x_realtime import XRealtimeJobs
from pipeline.platforms.x.realtime.normalizer import normalize_delivery, normalize_tweet
from pipeline.platforms.x.realtime.provider import ProviderRule
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from pipeline.platforms.x.realtime.rules import build_rules


def _tweet(post_id: str = "100", author_id: str = "author-1", handle: str = "alpha"):
    return {
        "id": post_id,
        "url": f"https://x.com/{handle}/status/{post_id}",
        "text": "I think $NVDA will reach $200 in 20 days.",
        "createdAt": "Wed Aug 05 12:00:00 +0000 2026",
        "lang": "en",
        "likeCount": 12,
        "replyCount": 3,
        "retweetCount": 2,
        "quoteCount": 1,
        "viewCount": 400,
        "bookmarkCount": 4,
        "author": {
            "id": author_id,
            "userName": handle,
            "name": "Alpha",
            "followers": 1234,
            "isBlueVerified": True,
            "profilePicture": "https://example.com/avatar.png",
        },
    }


def _repository(tmp_path) -> XRealtimeRepository:
    repository = XRealtimeRepository(f"sqlite:///{tmp_path / 'realtime.db'}")
    repository.initialize()
    with repository.engine.begin() as connection:
        connection.execute(
            text(
                """CREATE TABLE sv_investor_score (
                     investor_id TEXT PRIMARY KEY, source TEXT, name TEXT, handle TEXT,
                     sv REAL, n_eff REAL, settled_calls INTEGER,
                     platform_scores_json TEXT, updated_at TEXT)"""
            )
        )
        for index in range(1, 9):
            connection.execute(
                text(
                    """INSERT INTO sv_investor_score VALUES
                       (:id, 'x', :name, :handle, :sv, 20, 24, :scores, :updated)"""
                ),
                {
                    "id": f"author-{index}",
                    "name": f"Author {index}",
                    "handle": "alpha" if index == 1 else f"author{index}",
                    "sv": 121 - index,
                    "scores": f'{{"x": {121 - index}}}',
                    "updated": "2026-08-05T00:00:00Z",
                },
            )
    repository.refresh_top_quartile(datetime(2026, 8, 5, tzinfo=UTC))
    return repository


def _model_request(system: str, prompt: str, _max_tokens: int):
    if "translator" in system:
        return {
            "zh": "我认为 $NVDA 将在 20 天内达到 200 美元。",
            "en": "I think $NVDA will reach $200 in 20 days.",
        }, "fake-translation"
    evidence = "I think $NVDA will reach $200 in 20 days."
    return {
        "is_actionable_call": True,
        "direction": "bull",
        "horizon_bucket": "20D",
        "horizon_explicit": True,
        "target_price": 200,
        "target_price_owner": "NVDA",
        "conviction_score": 0.8,
        "evidence_score": 0.9,
        "specificity_score": 0.9,
        "call_type": "single_ticker_call",
        "ticker_role": "primary",
        "ticker_relevance": 1,
        "investor_style": "fundamental",
        "call_structure": "conviction_call",
        "lifecycle_action": "open_call",
        "entry_status": "active_entry",
        "evidence_span": evidence,
        "statement_mode": "prediction",
        "instrument_scope": "stock",
        "underlying_direction": "bull",
        "call_owner": "post_author",
        "summary_zh": "作者预计英伟达在 20 天内达到 200 美元。",
        "summary_en": "The author expects NVIDIA to reach $200 within 20 days.",
    }, "fake-extraction"


def test_rule_packing_is_deterministic_and_within_provider_limit():
    handles = [f"author_{index}" for index in range(67)]
    first = build_rules(handles, pool_version="pool-v1")
    second = build_rules(list(reversed(handles)), pool_version="pool-v1")

    assert first == second
    assert len(first) > 1
    assert all(len(rule.value) <= 255 for rule in first)
    assert sorted(handle for rule in first for handle in rule.handles) == sorted(handles)


def test_model_evidence_is_mapped_back_to_exact_source_whitespace() -> None:
    source = "Sell $PLTR $HIMS $NVDA\n\nAll in?"

    evidence = _traceable_evidence_span(source, "Sell $PLTR $HIMS $NVDA All in?")

    assert evidence == source
    assert evidence in source


def test_untraceable_model_evidence_falls_back_to_complete_source() -> None:
    source = "Long $NVDA while demand remains strong."

    assert _traceable_evidence_span(source, "invented evidence") == source


def test_normalizer_keeps_replies_and_quotes_but_filters_pure_retweets():
    quote = _tweet("101")
    quote["quoted_tweet"] = {"id": "90"}
    reply = _tweet("102")
    reply["isReply"] = True
    reply["inReplyToId"] = "80"
    retweet = _tweet("103")
    retweet["retweeted_tweet"] = {"id": "70"}

    tag, posts = normalize_delivery({"tag": "rule-a", "tweets": [quote, reply, retweet]})

    assert tag == "rule-a"
    assert [post.post_type for post in posts] == ["quote", "reply"]
    assert posts[1].parent_post_id == "80"
    assert posts[0].author_id == "author-1"


def test_normalizer_accepts_provider_webhook_snake_case_fields():
    payload = _tweet("104")
    payload["created_at"] = payload.pop("createdAt")
    payload["author"]["username"] = payload["author"].pop("userName")
    payload["author"]["followers_count"] = payload["author"].pop("followers")

    tag, posts = normalize_delivery({"rule_tag": "rule-b", "tweets": [payload]})

    assert tag == "rule-b"
    assert posts[0].author_handle == "alpha"
    assert posts[0].author_followers_count == 1234


def test_normalizer_keeps_valid_posts_when_one_delivery_item_is_malformed():
    tag, posts = normalize_delivery(
        {"rule_tag": "rule-c", "tweets": [{"id": "broken"}, _tweet("105")]}
    )

    assert tag == "rule-c"
    assert [post.post_id for post in posts] == ["105"]


def test_author_rename_preserves_stable_subscription_id(tmp_path):
    repository = _repository(tmp_path)
    with repository.engine.begin() as connection:
        connection.execute(
            text("UPDATE sv_investor_score SET handle='renamed_alpha' WHERE investor_id='author-1'")
        )
    repository.refresh_top_quartile(datetime(2026, 8, 6, tzinfo=UTC))

    subscription = repository.subscription("author-1")
    assert subscription is not None
    assert subscription.handle == "renamed_alpha"
    assert len(repository.active_subscriptions()) == 2


def test_duplicate_delivery_produces_one_ready_call_and_event(tmp_path):
    repository = _repository(tmp_path)
    post = normalize_tweet(_tweet())
    first = repository.ingest([post], delivery_source="webhook", delivery_tag="rule-a")
    second = repository.ingest([post], delivery_source="reconcile", delivery_tag="rule-a")

    assert first.inserted == 1
    assert second.duplicates == 1

    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request)
    jobs = XRealtimeJobs(repository, _FakeProvider(), analyzer)
    result = jobs.process(limit=10)
    updates = repository.ready_updates()

    assert result.ready_calls == 1
    assert len(updates) == 1
    assert updates[0]["sourcePostId"] == "100"
    assert updates[0]["originalText"] == post.original_text
    assert updates[0]["translatedText"] != updates[0]["thesis"]
    assert updates[0]["evidenceSpan"] in updates[0]["originalText"]
    with repository.engine.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM x_realtime_event_candidate")) == 1
    assert repository.mark_events_published([updates[0]["id"]]) == 1
    with repository.engine.connect() as connection:
        assert connection.scalar(
            text("SELECT status FROM x_realtime_event_candidate")
        ) == "published"


def test_version_reprocessing_preserves_first_processed_at(tmp_path):
    repository = _repository(tmp_path)
    repository.ingest([normalize_tweet(_tweet())], delivery_source="websocket")
    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request)
    XRealtimeJobs(repository, _FakeProvider(), analyzer).process(limit=10)

    with repository.engine.connect() as connection:
        first_processed_at = connection.scalar(
            text("SELECT processed_at FROM x_realtime_post WHERE post_id='100'")
        )

    reprocess_at = datetime(2026, 8, 7, tzinfo=UTC)
    assert repository.requeue_outdated_posts("next-version", now=reprocess_at) == 1
    repository.mark_post_terminal(
        "100",
        "no_actionable",
        processing_version="next-version",
        now=reprocess_at + timedelta(minutes=1),
    )

    with repository.engine.connect() as connection:
        assert connection.scalar(
            text("SELECT processed_at FROM x_realtime_post WHERE post_id='100'")
        ) == first_processed_at


def test_translation_that_drops_price_is_retried_not_published(tmp_path):
    repository = _repository(tmp_path)
    repository.ingest([normalize_tweet(_tweet())], delivery_source="webhook")

    def bad_translation(system: str, prompt: str, max_tokens: int):
        if "translator" in system:
            return {"zh": "作者看多英伟达。", "en": "The author is bullish."}, "bad"
        return _model_request(system, prompt, max_tokens)

    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=bad_translation)
    result = XRealtimeJobs(repository, _FakeProvider(), analyzer).process(limit=10)

    assert result.retry_posts == 1
    assert repository.ready_updates() == []


def test_translation_is_repaired_in_the_same_processing_attempt(tmp_path):
    repository = _repository(tmp_path)
    repository.ingest([normalize_tweet(_tweet())], delivery_source="webhook")
    translation_attempts = 0

    def repaired_translation(system: str, prompt: str, max_tokens: int):
        nonlocal translation_attempts
        if "translator" in system:
            translation_attempts += 1
            if translation_attempts == 1:
                return {"zh": "作者看多英伟达。", "en": "The author is bullish."}, "bad"
        return _model_request(system, prompt, max_tokens)

    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=repaired_translation)
    result = XRealtimeJobs(repository, _FakeProvider(), analyzer).process(limit=10)

    assert result.ready_calls == 1
    assert result.retry_posts == 0
    assert translation_attempts == 2
    assert repository.ready_updates()[0]["translatedTextZH"] == "我认为 $NVDA 将在 20 天内达到 200 美元。"


def test_translation_preserves_complete_source_language(tmp_path):
    repository = _repository(tmp_path)
    repository.ingest([normalize_tweet(_tweet())], delivery_source="webhook")

    def rewritten_source(system: str, prompt: str, max_tokens: int):
        if "translator" in system:
            return {
                "zh": "我认为 $NVDA 将在 20 天内达到 200 美元。",
                "en": "Shortened but still mentions $NVDA, 20, and 200.",
            }, "translation"
        return _model_request(system, prompt, max_tokens)

    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=rewritten_source)
    XRealtimeJobs(repository, _FakeProvider(), analyzer).process(limit=10)

    assert repository.ready_updates()[0]["translatedTextEN"] == _tweet()["text"]


def test_translation_accepts_equivalent_chinese_financial_units_and_year_digits():
    source = "Nvidia may reach $14M per MW by 2030."

    translated = _normalize_translation(
        {
            "zh": "英伟达可能在二〇三〇年前达到每兆瓦1400万美元。",
            "en": source,
        },
        source,
        "en",
    )

    assert "1400万美元" in translated["zh"]


def test_option_contract_corrects_underlying_direction_and_rejects_premium_target():
    source = "LOTTO PLAY $MU 14Aug $750p filled $3.77, PT $821 Scale target $10+"

    def option_request(system: str, _prompt: str, _max_tokens: int):
        if "translator" in system:
            return {"zh": source, "en": source}, "translation"
        return {
            "is_actionable_call": True,
            "direction": "bull",
            "horizon_bucket": "unknown",
            "target_price": 8.21,
            "target_price_owner": "MU",
            "ticker_role": "primary",
            "lifecycle_action": "open_call",
            "evidence_span": source,
            "statement_mode": "position_action",
            "call_owner": "post_author",
            "summary_zh": "错误的模型摘要",
            "summary_en": "Incorrect model summary",
        }, "extraction"

    result = RealtimeXAnalyzer(tickers=("MU",), request_json=option_request).analyze(
        RealtimePostInput(
            post_id="option-1",
            original_text=source,
            language="en",
            published_at=datetime(2026, 8, 6, tzinfo=UTC),
            post_type="original",
        )
    )

    assert len(result.calls) == 1
    assert result.calls[0]["direction"] == "bear"
    assert result.calls[0]["horizon"] == "20D"
    assert result.calls[0]["target_price"] is None


def test_portfolio_ticker_is_prioritized_before_newer_unrelated_posts(tmp_path):
    repository = _repository(tmp_path)
    priority = _tweet("200", author_id="author-1", handle="alpha")
    priority["text"] = "My updated $MU view has a six month horizon."
    priority["createdAt"] = "Tue Aug 04 12:00:00 +0000 2026"
    unrelated = _tweet("201", author_id="author-2", handle="author2")
    unrelated["createdAt"] = "Wed Aug 05 12:00:00 +0000 2026"
    repository.ingest(
        [normalize_tweet(unrelated), normalize_tweet(priority)],
        delivery_source="webhook",
    )

    claimed = repository.claim_posts(limit=1, priority_tickers={"MU"})

    assert [post.post_id for post in claimed] == ["200"]


def test_out_of_order_delivery_keeps_both_posts_and_claims_newest_first(tmp_path):
    repository = _repository(tmp_path)
    older = _tweet("300", author_id="author-1", handle="alpha")
    older["createdAt"] = "Tue Aug 04 12:00:00 +0000 2026"
    newer = _tweet("301", author_id="author-1", handle="alpha")
    newer["createdAt"] = "Wed Aug 05 12:00:00 +0000 2026"

    repository.ingest([normalize_tweet(newer)], delivery_source="webhook")
    repository.ingest([normalize_tweet(older)], delivery_source="webhook")
    claimed = repository.claim_posts(limit=2, priority_tickers=set())

    assert [post.post_id for post in claimed] == ["301", "300"]


def test_health_latency_excludes_reconciliation_backfill(tmp_path):
    repository = _repository(tmp_path)
    now = datetime(2026, 8, 6, 12, 0, tzinfo=UTC)
    live = _tweet("400", author_id="author-1", handle="alpha")
    live["createdAt"] = "Wed Aug 06 11:59:30 +0000 2026"
    backfill = _tweet("401", author_id="author-1", handle="alpha")
    backfill["createdAt"] = "Wed Aug 06 09:00:00 +0000 2026"

    repository.ingest(
        [normalize_tweet(live)],
        delivery_source="websocket",
        now=now,
    )
    repository.ingest(
        [normalize_tweet(backfill)],
        delivery_source="reconcile",
        now=now,
    )
    with repository.engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE x_realtime_post SET status='ready', processed_at=:processed "
                "WHERE post_id IN ('400','401')"
            ),
            {"processed": now.replace(tzinfo=None)},
        )

    snapshot = repository.health_snapshot(now=now)

    assert snapshot["postsReceived24h"] == 2
    assert snapshot["ingestionLatencyP95Seconds"] == 30.0
    assert snapshot["readyLatencyP95Seconds"] == 30.0


def test_health_reports_current_stream_state_and_content_freshness(tmp_path):
    repository = _repository(tmp_path)
    now = datetime(2026, 8, 6, 12, 0, tzinfo=UTC)
    repository.mark_transport_connected("websocket", now)
    repository.mark_transport_heartbeat("websocket", now + timedelta(seconds=40))
    repository.ingest(
        [normalize_tweet(_tweet("stream-health"))],
        delivery_source="websocket",
        now=now,
    )

    snapshot = repository.health_snapshot(now=now + timedelta(minutes=1))

    assert snapshot["streamConnected"] is True
    assert snapshot["streamConnectedAt"] == "2026-08-06T12:00:00Z"
    assert snapshot["lastStreamHeartbeatAt"] == "2026-08-06T12:00:40Z"
    assert snapshot["latestRawPostAt"] == "2026-08-05T12:00:00Z"
    assert snapshot["postStatusCounts24h"] == {"pending": 1}


def test_model_timeout_retries_without_publishing_partial_data(tmp_path):
    repository = _repository(tmp_path)
    repository.ingest([normalize_tweet(_tweet())], delivery_source="webhook")

    def timeout(*_args):
        raise TimeoutError("model timeout")

    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=timeout)
    result = XRealtimeJobs(repository, _FakeProvider(), analyzer).process(limit=10)

    assert result.retry_posts == 1
    assert repository.ready_updates() == []


class _FakeProvider:
    def __init__(self):
        self.rules: dict[str, dict] = {}
        self.search_rows: list[dict] = []
        self.existing_ids: set[str] = set()

    def list_rules(self):
        return [
            ProviderRule(
                rule_id=rule_id,
                tag=rule["tag"],
                value=rule["value"],
                interval_seconds=60,
                active=rule["active"],
            )
            for rule_id, rule in self.rules.items()
        ]

    def add_rule(self, *, tag, value, interval_seconds):
        rule_id = f"rule-{len(self.rules) + 1}"
        self.rules[rule_id] = {"tag": tag, "value": value, "active": False}
        return rule_id

    def activate_rule(self, *, rule_id, tag, value, interval_seconds):
        self.rules[rule_id]["active"] = True

    def deactivate_rule(self, *, rule_id, tag, value, interval_seconds):
        self.rules[rule_id]["active"] = False

    def delete_rule(self, rule_id):
        self.rules.pop(rule_id, None)

    def search_recent(self, *, query, since, until, max_pages=20):
        return list(self.search_rows)

    def get_posts(self, post_ids):
        return {post_id: _tweet(post_id) for post_id in post_ids if post_id in self.existing_ids}


def test_rule_sync_adopts_provider_rule_and_deletes_duplicates(tmp_path):
    repository = _repository(tmp_path)
    provider = _FakeProvider()
    pool_version = repository.active_subscriptions()[0].pool_version
    desired = build_rules(
        [item.handle for item in repository.active_subscriptions()],
        pool_version=pool_version,
    )[0]
    first = provider.add_rule(
        tag=desired.tag,
        value=desired.value,
        interval_seconds=60,
    )
    provider.activate_rule(
        rule_id=first,
        tag=desired.tag,
        value=desired.value,
        interval_seconds=60,
    )
    provider.add_rule(
        tag=desired.tag,
        value=desired.value,
        interval_seconds=60,
    )

    jobs = XRealtimeJobs(
        repository,
        provider,
        RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request),
    )
    result = jobs.refresh_pool_and_rules(datetime(2026, 8, 6, tzinfo=UTC))

    assert result.created == 0
    assert list(provider.rules) == [first]
    assert repository.list_rules()[0].provider_rule_id == first

    provider.rules[first]["active"] = False
    jobs.refresh_pool_and_rules(datetime(2026, 8, 6, 1, tzinfo=UTC))

    assert provider.rules[first]["active"] is True


def test_frozen_pool_sync_keeps_bootstrapped_authors_when_ranking_changes(tmp_path):
    repository = _repository(tmp_path)
    original = repository.active_subscriptions()[0]
    with repository.engine.begin() as connection:
        connection.execute(text("UPDATE sv_investor_score SET handle='recalculated'"))

    provider = _FakeProvider()
    jobs = XRealtimeJobs(
        repository,
        provider,
        RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request),
        freeze_author_pool=True,
    )
    result = jobs.refresh_pool_and_rules(datetime(2026, 8, 6, tzinfo=UTC))

    current = repository.active_subscriptions()[0]
    assert result.selected == len(repository.active_subscriptions())
    assert current.author_id == original.author_id
    assert current.handle == original.handle
    assert "from:recalculated" not in next(iter(provider.rules.values()))["value"]


def test_rule_sync_reconcile_and_compliance_are_idempotent(tmp_path):
    repository = _repository(tmp_path)
    provider = _FakeProvider()
    analyzer = RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request)
    jobs = XRealtimeJobs(repository, provider, analyzer)

    first_sync = jobs.refresh_pool_and_rules(datetime(2026, 8, 5, tzinfo=UTC))
    second_sync = jobs.refresh_pool_and_rules(datetime(2026, 8, 5, 1, tzinfo=UTC))
    assert first_sync.created == 1
    assert second_sync.created == 0

    provider.search_rows = [_tweet()]
    first = jobs.reconcile(datetime(2026, 8, 5, 12, 5, tzinfo=UTC))
    second = jobs.reconcile(datetime(2026, 8, 5, 12, 10, tzinfo=UTC))
    assert first.inserted == 1
    assert second.duplicates == 1

    jobs.process()
    assert len(repository.ready_updates()) == 1
    compliance = jobs.compliance_check()
    assert compliance["deleted"] == 1
    assert repository.ready_updates() == []


def test_failed_rule_activation_is_removed_from_provider(tmp_path):
    repository = _repository(tmp_path)

    class FailingProvider(_FakeProvider):
        def activate_rule(self, *, rule_id, tag, value, interval_seconds):
            raise RuntimeError("activation failed")

    provider = FailingProvider()
    jobs = XRealtimeJobs(
        repository,
        provider,
        RealtimeXAnalyzer(tickers=("NVDA",), request_json=_model_request),
    )

    try:
        jobs.refresh_pool_and_rules(datetime(2026, 8, 5, tzinfo=UTC))
    except RuntimeError as exc:
        assert str(exc) == "activation failed"
    else:
        raise AssertionError("rule activation should fail")

    assert provider.rules == {}
    assert repository.list_rules() == []
