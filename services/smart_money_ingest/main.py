from __future__ import annotations

import datetime as dt
import json
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Callable

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from pipeline.jobs.smart_voice.hyperdash_live import run_hyperdash_live
from pipeline.jobs.smart_voice.hyperliquid_live import run_hyperliquid_live
from services.client_api.publish_realtime_smart_money import _load
from services.client_api.read_models import RealtimeReadModelPublisher
from services.smart_money_ingest.config import SmartMoneyIngestSettings


Runner = Callable[..., dict[str, Any]]


def run_smart_money_live(*, primary_source: str = "hyperdash", **kwargs: Any) -> dict[str, Any]:
    if primary_source == "hyperliquid":
        for key in (
            "hyperdash_graphql_url",
            "hyperdash_group_id",
            "hyperdash_max_wallets",
            "hyperdash_position_limit",
            "hyperdash_max_stale_seconds",
            "smart_account_updates_path",
        ):
            kwargs.pop(key, None)
        return run_hyperliquid_live(**kwargs)
    return run_hyperdash_live(**kwargs)


class SmartMoneyServiceController:
    def __init__(
        self,
        settings: SmartMoneyIngestSettings,
        *,
        runner: Runner = run_smart_money_live,
        publisher_factory: Callable[[str], RealtimeReadModelPublisher] = RealtimeReadModelPublisher,
    ) -> None:
        self.settings = settings
        self.runner = runner
        self.publisher_factory = publisher_factory
        self.stop_event = threading.Event()
        self.worker_thread: threading.Thread | None = None
        self.publisher_thread: threading.Thread | None = None
        self.worker_error: str | None = None
        self.worker_last_error_at: str | None = None
        self.worker_restart_count = 0
        self.publisher_error: str | None = None
        self.publisher_last_at: str | None = None
        self.publisher_last_hash: str | None = None
        self.publisher_counts: dict[str, int] = {}

    def start(self) -> None:
        if not self.settings.enabled or self.worker_thread is not None:
            return
        self.settings.data_dir.mkdir(parents=True, exist_ok=True)
        self.settings.client_output_dir.mkdir(parents=True, exist_ok=True)
        self.worker_thread = threading.Thread(
            target=self._run_worker,
            name="smart-money-source-indexer",
            daemon=True,
        )
        self.worker_thread.start()
        if self.settings.read_model_database_url:
            self.publisher_thread = threading.Thread(
                target=self._run_publisher,
                name="smart-money-read-model-publisher",
                daemon=True,
            )
            self.publisher_thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        timeout = float(self.settings.shutdown_timeout_seconds)
        if self.worker_thread is not None:
            self.worker_thread.join(timeout=timeout)
        if self.publisher_thread is not None:
            self.publisher_thread.join(timeout=timeout)

    def _run_worker(self) -> None:
        restart_delay = self.settings.worker_restart_initial_seconds
        while not self.stop_event.is_set():
            started_at = time.monotonic()
            try:
                self.worker_error = None
                self.runner(
                    primary_source=self.settings.primary_source,
                    db_path=str(self.settings.database_path),
                    output_path=str(self.settings.output_path),
                    client_output_dir=str(self.settings.client_output_dir),
                    health_output_path=str(self.settings.health_output_path),
                    lookback_days=self.settings.lookback_days,
                    refresh_seconds=self.settings.refresh_seconds,
                    publish_seconds=self.settings.publish_seconds,
                    candidate_backfill_per_cycle=self.settings.candidate_backfill,
                    max_active_wallets=self.settings.max_active_wallets,
                    max_profile_wallets=self.settings.max_profile_wallets,
                    profile_refresh_minutes=self.settings.profile_refresh_minutes,
                    instrument_refresh_minutes=self.settings.instrument_refresh_minutes,
                    hyperdash_graphql_url=self.settings.hyperdash_graphql_url,
                    hyperdash_group_id=self.settings.hyperdash_group_id,
                    hyperdash_max_wallets=self.settings.hyperdash_max_wallets,
                    hyperdash_position_limit=self.settings.hyperdash_position_limit,
                    hyperdash_max_stale_seconds=self.settings.hyperdash_max_stale_seconds,
                    smart_account_updates_path=(
                        str(self.settings.smart_account_updates_path)
                        if self.settings.smart_account_updates_path
                        else ""
                    ),
                    stop_event=self.stop_event,
                )
                if self.stop_event.is_set():
                    return
                self.worker_error = "Smart Money source worker exited unexpectedly"
            except Exception as exc:
                self.worker_error = str(exc)[:1_000]

            self.worker_last_error_at = _utc_now()
            self.worker_restart_count += 1
            if time.monotonic() - started_at >= self.settings.worker_restart_max_seconds:
                restart_delay = self.settings.worker_restart_initial_seconds
            if self.stop_event.wait(restart_delay):
                return
            restart_delay = min(
                restart_delay * 2,
                self.settings.worker_restart_max_seconds,
            )

    def _run_publisher(self) -> None:
        database_url = self.settings.read_model_database_url
        if not database_url:
            return
        publisher = self.publisher_factory(database_url)
        try:
            while not self.stop_event.is_set():
                try:
                    collections, content_hash = _load(self.settings.client_output_dir)
                    if content_hash != self.publisher_last_hash:
                        worker_health = _read_json(self.settings.health_output_path)
                        active_source = str(worker_health.get("activeSource") or self.settings.primary_source)
                        result = publisher.publish_partitioned(
                            collections,
                            producer=f"{active_source}-live",
                            source_version=f"{active_source}-live:{content_hash}",
                        )
                        self.publisher_counts = dict(result.counts)
                        self.publisher_last_hash = content_hash
                        self.publisher_last_at = dt.datetime.now(dt.timezone.utc).replace(
                            microsecond=0
                        ).isoformat()
                        self.publisher_error = None
                except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
                    self.publisher_error = str(exc)[:1_000]
                self.stop_event.wait(self.settings.publisher_poll_seconds)
        finally:
            publisher.dispose()

    def snapshot(self) -> dict[str, Any]:
        worker_health = _read_json(self.settings.health_output_path)
        worker_alive = bool(self.worker_thread and self.worker_thread.is_alive())
        publisher_alive = bool(self.publisher_thread and self.publisher_thread.is_alive())
        if not self.settings.enabled:
            status = "disabled"
        elif self.worker_error or (self.settings.read_model_database_url and self.publisher_error):
            status = "degraded"
        elif worker_alive:
            status = "ok"
        else:
            status = "stopped"
        return {
            "status": status,
            "enabled": self.settings.enabled,
            "workerAlive": worker_alive,
            "workerError": self.worker_error,
            "workerLastErrorAt": self.worker_last_error_at,
            "workerRestartCount": self.worker_restart_count,
            "worker": worker_health,
            "publisher": {
                "configured": bool(self.settings.read_model_database_url),
                "alive": publisher_alive,
                "lastPublishedAt": self.publisher_last_at,
                "lastContentHash": self.publisher_last_hash,
                "lastCounts": self.publisher_counts,
                "lastError": self.publisher_error,
            },
        }


def _read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def create_app(
    settings: SmartMoneyIngestSettings | None = None,
    *,
    runner: Runner = run_smart_money_live,
    publisher_factory: Callable[[str], RealtimeReadModelPublisher] = RealtimeReadModelPublisher,
) -> FastAPI:
    settings = settings or SmartMoneyIngestSettings.from_environment()
    controller = SmartMoneyServiceController(
        settings,
        runner=runner,
        publisher_factory=publisher_factory,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        controller.start()
        try:
            yield
        finally:
            controller.stop()

    app = FastAPI(title="bSmart Smart Money Ingest", version="1.0.0", lifespan=lifespan)
    app.state.controller = controller

    @app.get("/health")
    def health() -> dict[str, Any]:
        return controller.snapshot()

    @app.get("/ready")
    def ready() -> JSONResponse:
        snapshot = controller.snapshot()
        readiness = (snapshot.get("worker") or {}).get("readiness") or {}
        is_ready = bool(readiness.get("ready")) and not snapshot.get("workerError")
        return JSONResponse(snapshot, status_code=200 if is_ready else 503)

    return app
