import requests

from pipeline.platforms.x.realtime.twitterapi_io import TwitterAPIIOProvider


class _Response:
    def __init__(self, status_code, payload, *, headers=None):
        self.status_code = status_code
        self._payload = payload
        self.headers = headers or {}
        self.text = str(payload)

    def json(self):
        return self._payload


class _Session:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        return self.responses.pop(0)


def test_provider_retries_rate_limit_and_uses_current_rule_endpoint(monkeypatch):
    provider = TwitterAPIIOProvider("test-key", max_retries=2)
    session = _Session(
        [
            _Response(429, {"message": "slow down"}, headers={"Retry-After": "1"}),
            _Response(200, {"rule_id": "rule-1"}),
        ]
    )
    provider.session = session
    sleeps = []
    monkeypatch.setattr("pipeline.platforms.x.realtime.twitterapi_io.time.sleep", sleeps.append)

    rule_id = provider.add_rule(tag="bsmart", value="from:alpha", interval_seconds=60)

    assert rule_id == "rule-1"
    assert sleeps == [1.0]
    assert session.calls[-1][1].endswith("/oapi/tweet_filter/add_rule")


def test_provider_retries_transient_server_error(monkeypatch):
    provider = TwitterAPIIOProvider("test-key", max_retries=2)
    session = _Session(
        [
            _Response(503, {"message": "unavailable"}),
            _Response(200, {"tweets": []}),
        ]
    )
    provider.session = session
    monkeypatch.setattr("pipeline.platforms.x.realtime.twitterapi_io.time.sleep", lambda _delay: None)

    assert provider.get_posts(["1"]) == {}
    assert len(session.calls) == 2


def test_provider_lists_existing_filter_rules():
    provider = TwitterAPIIOProvider("test-key")
    provider.session = _Session(
        [
            _Response(
                200,
                {
                    "rules": [
                        {
                            "rule_id": "rule-1",
                            "tag": "bsmart-x-pool-001",
                            "value": "from:alpha",
                            "interval_seconds": 60,
                            "is_effect": 1,
                        }
                    ]
                },
            )
        ]
    )

    rules = provider.list_rules()

    assert len(rules) == 1
    assert rules[0].rule_id == "rule-1"
    assert rules[0].active is True


def test_provider_can_deactivate_filter_rule():
    provider = TwitterAPIIOProvider("test-key")
    session = _Session([_Response(200, {"status": "success"})])
    provider.session = session

    provider.deactivate_rule(
        rule_id="rule-1",
        tag="bsmart-x-pool-001",
        value="from:alpha",
        interval_seconds=60,
    )

    assert session.calls[0][2]["json"]["is_effect"] == 0


def test_provider_retries_network_timeout(monkeypatch):
    provider = TwitterAPIIOProvider("test-key", max_retries=2)
    session = _Session(
        [
            requests.Timeout("timed out"),
            _Response(200, {"tweets": []}),
        ]
    )

    def request(method, url, **kwargs):
        response = session.responses.pop(0)
        session.calls.append((method, url, kwargs))
        if isinstance(response, Exception):
            raise response
        return response

    session.request = request
    provider.session = session
    monkeypatch.setattr("pipeline.platforms.x.realtime.twitterapi_io.time.sleep", lambda _delay: None)

    assert provider.get_posts(["1"]) == {}
    assert len(session.calls) == 2


def test_reconciliation_splits_saturated_time_windows_without_cursor():
    provider = TwitterAPIIOProvider("test-key", max_retries=1)
    session = _Session(
        [
            _Response(200, {"tweets": [{"id": str(index)} for index in range(20)], "has_next_page": True}),
            _Response(200, {"tweets": [{"id": "left"}], "has_next_page": False}),
            _Response(200, {"tweets": [{"id": "right"}], "has_next_page": False}),
        ]
    )
    provider.session = session
    from datetime import UTC, datetime

    rows = provider.search_recent(
        query="from:alpha",
        since=datetime(2026, 8, 6, 0, 0, tzinfo=UTC),
        until=datetime(2026, 8, 6, 0, 15, tzinfo=UTC),
        max_pages=3,
    )

    assert {row["id"] for row in rows} == {"left", "right"}
    assert all("since_time:" in call[2]["params"]["query"] for call in session.calls)
    assert all("cursor" not in call[2]["params"] for call in session.calls)


def test_reconciliation_does_not_split_sparse_window_with_false_next_page():
    provider = TwitterAPIIOProvider("test-key", max_retries=1)
    session = _Session(
        [
            _Response(
                200,
                {"tweets": [{"id": "only"}], "has_next_page": True},
            )
        ]
    )
    provider.session = session
    from datetime import UTC, datetime

    rows = provider.search_recent(
        query="from:alpha",
        since=datetime(2026, 8, 6, 0, 0, tzinfo=UTC),
        until=datetime(2026, 8, 6, 0, 15, tzinfo=UTC),
        max_pages=3,
    )

    assert [row["id"] for row in rows] == ["only"]
    assert len(session.calls) == 1
