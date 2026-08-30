from __future__ import annotations

import hmac
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, Request, status

from pipeline.platforms.x.realtime.normalizer import normalize_delivery
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from services.x_ingest.config import XIngestSettings


def create_app(
    settings: XIngestSettings | None = None,
    repository: XRealtimeRepository | None = None,
) -> FastAPI:
    settings = settings or XIngestSettings.from_environment()
    repository = repository or XRealtimeRepository(settings.database_url)
    repository.initialize()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        try:
            yield
        finally:
            repository.dispose()

    app = FastAPI(title="bSmart X Ingest", version="1.0.0", lifespan=lifespan)

    @app.get("/health")
    def health() -> dict[str, Any]:
        snapshot = repository.health_snapshot()
        sla = {
            "ingestionP95UnderTwoMinutes": snapshot["ingestionLatencyP95Seconds"] <= 120,
            "readyP95UnderFifteenMinutes": snapshot["readyLatencyP95Seconds"] <= 900,
            "monthlyCostWithinLimit": (
                snapshot["estimatedMonthCostUSD"] < settings.monthly_cost_limit_usd
            ),
            "activePoolAndRules": (
                snapshot["activeSubscriptions"] > 0 and snapshot["activeRules"] > 0
            ),
            "providerReachable": (
                snapshot["streamConnected"]
                if settings.stream_enabled
                else bool(snapshot["lastSuccessfulRuns"].get("reconcile"))
            ),
        }
        healthy = all(sla.values()) and snapshot["oldestQueueAgeSeconds"] <= 900
        snapshot.update(
            {
                "status": "ok" if settings.enabled and healthy else (
                    "disabled" if not settings.enabled else "degraded"
                ),
                "enabled": settings.enabled,
                "costLimitUSD": settings.monthly_cost_limit_usd,
                "costLimitExceeded": snapshot["estimatedMonthCostUSD"] >= settings.monthly_cost_limit_usd,
                "sla": sla,
            }
        )
        return snapshot

    @app.post(
        "/webhooks/twitterapi-io/{token}",
        status_code=status.HTTP_202_ACCEPTED,
        include_in_schema=False,
    )
    async def twitterapi_io_webhook(token: str, request: Request) -> dict[str, int]:
        if not settings.enabled:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "X ingestion is disabled")
        if not hmac.compare_digest(token, settings.webhook_token):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
        try:
            payload = await request.json()
            tag, posts = normalize_delivery(payload)
        except (ValueError, TypeError) as exc:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
        result = repository.ingest(
            posts,
            delivery_source="webhook",
            delivery_tag=tag,
        )
        repository.record_delivery(
            source="webhook",
            received=_provider_item_count(payload),
            inserted=result.inserted,
            estimated_cost_usd=_provider_item_count(payload) * 0.00015,
        )
        return {
            "received": result.received,
            "inserted": result.inserted,
            "duplicates": result.duplicates,
            "ignored": result.ignored,
        }

    return app


def _provider_item_count(payload: Any) -> int:
    if not isinstance(payload, dict):
        return 0
    if isinstance(payload.get("tweets"), list):
        return len(payload["tweets"])
    return 1 if isinstance(payload.get("tweet"), dict) else 0
