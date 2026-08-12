from __future__ import annotations

import json
from contextlib import asynccontextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

import httpx
import pytest

from services.client_api.config import ClientAPISettings, REPO_ROOT
from services.client_api.main import create_app
from services.client_api.mr_collie import MrCollieConfig, MrCollieService
from services.client_api.schemas import MrCollieQuery


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


async def _register(client: httpx.AsyncClient) -> str:
    response = await client.post(
        "/v1/installations",
        json={
            "installationId": str(uuid4()),
            "platform": "ios",
            "appVersion": "1.0",
            "locale": "zh_CN",
            "timeZone": "Asia/Shanghai",
        },
    )
    return response.json()["accessToken"]


@asynccontextmanager
async def _client(directory: str, answer: dict):
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["model"] == "deepseek-test"
        assert body["thinking"] == {"type": "disabled"}
        assert body["response_format"] == {"type": "json_object"}
        assert "evidence_catalog" in body["messages"][1]["content"]
        prompt = json.loads(body["messages"][1]["content"])
        intelligence = prompt["context"]["ticker_intelligence"]
        assert intelligence
        assert all(item["citation_ids"] for item in intelligence)
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(answer)}}]},
        )

    deepseek_client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler),
        base_url="https://deepseek.test",
    )
    service = MrCollieService(
        MrCollieConfig(
            api_key="test-key",
            base_url="https://deepseek.test",
            model="deepseek-test",
        ),
        client=deepseek_client,
    )
    settings = ClientAPISettings(
        environment="test",
        database_url=f"sqlite:///{Path(directory) / 'mr-collie.db'}",
        read_model_mode="fixture",
        fixture_root=REPO_ROOT / "contracts" / "fixtures",
        mr_collie_requests_per_minute=8,
    )
    app = create_app(settings, mr_collie_service=service)
    transport = httpx.ASGITransport(app=app)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client
    await deepseek_client.aclose()


@pytest.mark.anyio
async def test_mr_collie_returns_only_server_validated_evidence() -> None:
    fixture_signals = json.loads(
        (REPO_ROOT / "contracts" / "fixtures" / "portfolio-signals.json").read_text()
    )
    signal = fixture_signals[0]
    valid_evidence = signal["evidence"][0]["id"]
    with TemporaryDirectory() as directory:
        async with _client(directory, {
            "title": "HOOD 证据出现变化",
            "summary": "现有证据显示需要继续核对。",
            "context": "与你的观察列表相关",
            "next_step": "查看原始观点。",
            "ticker": "HOOD",
            "signal_id": signal["id"],
            "citation_ids": [valid_evidence, "hallucinated-id"],
        }) as client:
            token = await _register(client)
            response = await client.post(
                "/v1/mr-collie/query",
                headers={"Authorization": f"Bearer {token}"},
                json={"question": "HOOD 有什么变化？", "locale": "zh-Hans"},
            )
            body = response.json()

            assert response.status_code == 200
            assert response.headers["cache-control"] == "no-store"
            assert body["ticker"] == "HOOD"
            assert body["signalId"] == signal["id"]
            assert [item["id"] for item in body["evidence"]] == [valid_evidence]
            assert body["contextVersion"].startswith("sha256:")
            assert body["model"] == "deepseek-test"


@pytest.mark.anyio
async def test_mr_collie_rejects_uncited_factual_answer() -> None:
    with TemporaryDirectory() as directory:
        async with _client(directory, {
            "title": "Unsupported claim",
            "summary": "An author changed direction.",
            "context": None,
            "next_step": "Buy immediately.",
            "ticker": "NVDA",
            "signal_id": None,
            "citation_ids": ["made-up"],
        }) as client:
            token = await _register(client)
            response = await client.post(
                "/v1/mr-collie/query",
                headers={"Authorization": f"Bearer {token}"},
                json={"question": "What should I do?", "locale": "en"},
            )
            body = response.json()

            assert response.status_code == 200
            assert body["title"] == "Insufficient current evidence"
            assert body["evidence"] == []
            assert body["signalId"] is None


@pytest.mark.anyio
async def test_mr_collie_requires_deepseek_configuration() -> None:
    with TemporaryDirectory() as directory:
        settings = ClientAPISettings(
            environment="test",
            database_url=f"sqlite:///{Path(directory) / 'mr-collie-unavailable.db'}",
            read_model_mode="fixture",
            fixture_root=REPO_ROOT / "contracts" / "fixtures",
        )
        app = create_app(settings)
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                token = await _register(client)
                response = await client.post(
                    "/v1/mr-collie/query",
                    headers={"Authorization": f"Bearer {token}"},
                    json={"question": "What changed?", "locale": "en"},
                )

                assert response.status_code == 503


@pytest.mark.anyio
async def test_mr_collie_retries_empty_json_content_once() -> None:
    attempts = 0
    fixture_signals = json.loads(
        (REPO_ROOT / "contracts" / "fixtures" / "portfolio-signals.json").read_text()
    )
    valid_evidence = fixture_signals[0]["evidence"][0]["id"]

    def handler(_: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        content = "" if attempts == 1 else json.dumps({
            "title": "Grounded answer",
            "summary": "The current evidence supports a review.",
            "context": None,
            "next_step": "Open the source evidence.",
            "ticker": "HOOD",
            "signal_id": fixture_signals[0]["id"],
            "citation_ids": [valid_evidence],
        })
        return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    service = MrCollieService(
        MrCollieConfig("test-key", "https://deepseek.test", "deepseek-test"),
        client=client,
    )
    try:
        response = await service.answer(
            MrCollieQuery(question="What changed for HOOD?", locale="en"),
            portfolio=[],
            signals=fixture_signals,
            intelligence=[],
        )
    finally:
        await client.aclose()

    assert attempts == 2
    assert response.ticker == "HOOD"
    assert [item.id for item in response.evidence] == [valid_evidence]
