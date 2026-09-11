import json
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import pytest
import requests

from pipeline.common import kimi, llm
from pipeline.common.kimi_budget import BudgetExceeded, BudgetLedger, UNIT


def test_concurrent_reservations_respect_shared_cap(tmp_path):
    ledger = BudgetLedger(tmp_path / "ledger.json", "3")

    def reserve(_):
        try:
            return ledger.reserve(UNIT)
        except BudgetExceeded:
            return None

    with ThreadPoolExecutor(max_workers=10) as pool:
        ids = list(pool.map(reserve, range(10)))
    assert sum(value is not None for value in ids) == 3


def test_usage_releases_unused_reservation_and_cap_cannot_change(tmp_path):
    path = tmp_path / "ledger.json"
    ledger = BudgetLedger(path, "1")
    request = ledger.reserve(UNIT)
    ledger.finish(request, UNIT // 4, {"model": "test"})
    ledger.reserve(UNIT * 3 // 4)
    with pytest.raises(BudgetExceeded):
        ledger.reserve(1)
    with pytest.raises(ValueError):
        BudgetLedger(path, "2").reserve(1)


def test_uncertain_request_keeps_full_cost(tmp_path):
    ledger = BudgetLedger(tmp_path / "ledger.json", "1")
    request = ledger.reserve(UNIT)
    ledger.abandon(request, uncertain=True)
    with pytest.raises(BudgetExceeded):
        ledger.reserve(1)


def test_cache_usage_cost():
    assert kimi.usage_cost({"prompt_tokens": 1000, "completion_tokens": 100,
                            "prompt_tokens_details": {"cached_tokens": 800}}) == 4_880_000


@pytest.fixture
def configured(monkeypatch, tmp_path):
    monkeypatch.setenv("KIMI_BUDGET_FILE", str(tmp_path / "ledger.json"))
    monkeypatch.setenv("KIMI_BUDGET_CNY", "1")
    monkeypatch.setattr(kimi, "settings", SimpleNamespace(
        kimi_api_key="test-secret", kimi_model="kimi-k2.6", kimi_base_url="https://example.invalid/v1",
    ))
    return tmp_path / "ledger.json"


def test_timeout_is_not_retried_or_reported_with_secret(monkeypatch, configured):
    def timeout(*args, **kwargs):
        raise requests.Timeout("sensitive transport details")

    monkeypatch.setattr(kimi.requests, "post", timeout)
    with pytest.raises(RuntimeError, match="reserved maximum retained"):
        kimi.chat("System", "Input", max_tokens=100)
    state = json.loads(configured.read_text())
    assert state["spent_nanoyuan"] > 0
    assert len(state["requests"]) == 1
    assert "test-secret" not in configured.read_text()


def test_valid_json_is_billed_and_non_thinking(monkeypatch, configured):
    class Response:
        status_code = 200

        def json(self):
            return {"usage": {"prompt_tokens": 20, "completion_tokens": 5},
                    "choices": [{"finish_reason": "stop", "message": {"content": '{"ok":true}'}}]}

    def post(*args, **kwargs):
        assert kwargs["json"]["thinking"] == {"type": "disabled"}
        assert "temperature" not in kwargs["json"]
        return Response()

    monkeypatch.setattr(kimi.requests, "post", post)
    monkeypatch.setenv("LLM_PROVIDER", "kimi")
    assert llm.messages_json(llm.LOW, "JSON", "Input", max_tokens=100) == {"ok": True}
    assert json.loads(configured.read_text())["spent_nanoyuan"] == 265000


def test_missing_budget_never_sends_request(monkeypatch, configured):
    monkeypatch.delenv("KIMI_BUDGET_CNY")
    monkeypatch.setattr(kimi.requests, "post", lambda *a, **kw: pytest.fail("Unexpected request"))
    with pytest.raises(ValueError, match="required"):
        kimi.chat("System", "Input")
