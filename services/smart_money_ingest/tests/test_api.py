from __future__ import annotations

import json
import threading
import time

from fastapi.testclient import TestClient

from services.smart_money_ingest.config import SmartMoneyIngestSettings
from services.smart_money_ingest.main import create_app


def _settings(tmp_path, *, enabled: bool = True) -> SmartMoneyIngestSettings:
    data_dir = tmp_path / "smart-money"
    return SmartMoneyIngestSettings(
        environment="test",
        enabled=enabled,
        data_dir=data_dir,
        database_path=data_dir / "source.db",
        output_path=data_dir / "export.json",
        client_output_dir=data_dir / "client",
        health_output_path=data_dir / "health.json",
        read_model_database_url=None,
        refresh_seconds=1,
        publish_seconds=1,
        worker_restart_initial_seconds=0.1,
        worker_restart_max_seconds=0.2,
        shutdown_timeout_seconds=2,
    )


def test_service_starts_worker_exposes_health_and_stops_cleanly(tmp_path) -> None:
    settings = _settings(tmp_path)
    started = threading.Event()
    stopped = threading.Event()

    def runner(**kwargs):
        settings.health_output_path.write_text(
            json.dumps(
                {
                    "status": "healthy",
                    "running": True,
                    "readiness": {
                        "realtime": True,
                        "complete": True,
                        "ready": True,
                        "reasons": [],
                    },
                }
            ),
            encoding="utf-8",
        )
        started.set()
        kwargs["stop_event"].wait(2)
        stopped.set()
        return {}

    app = create_app(settings, runner=runner)
    with TestClient(app) as client:
        assert started.wait(1)
        health = client.get("/health")
        assert health.status_code == 200
        assert health.json()["workerAlive"] is True
        assert client.get("/ready").status_code == 200

    assert stopped.wait(1)
    assert app.state.controller.worker_thread is not None
    assert app.state.controller.worker_thread.is_alive() is False


def test_disabled_service_is_live_but_not_ready(tmp_path) -> None:
    app = create_app(_settings(tmp_path, enabled=False))
    with TestClient(app) as client:
        health = client.get("/health")
        assert health.status_code == 200
        assert health.json()["status"] == "disabled"
        assert client.get("/ready").status_code == 503


def test_service_restarts_failed_worker_without_stopping_process(tmp_path) -> None:
    settings = _settings(tmp_path)
    attempts = 0
    restarted = threading.Event()

    def runner(**kwargs):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("temporary upstream failure")
        settings.health_output_path.write_text(
            json.dumps(
                {
                    "status": "healthy",
                    "running": True,
                    "readiness": {
                        "realtime": True,
                        "complete": True,
                        "ready": True,
                        "reasons": [],
                    },
                }
            ),
            encoding="utf-8",
        )
        restarted.set()
        kwargs["stop_event"].wait(2)
        return {}

    app = create_app(settings, runner=runner)
    with TestClient(app) as client:
        assert restarted.wait(1)
        deadline = time.monotonic() + 1
        health = client.get("/health").json()
        while health["workerRestartCount"] < 1 and time.monotonic() < deadline:
            time.sleep(0.02)
            health = client.get("/health").json()
        assert health["status"] == "ok"
        assert health["workerRestartCount"] == 1
        assert health["workerLastErrorAt"] is not None
        assert health["workerError"] is None
        assert client.get("/ready").status_code == 200


def test_production_requires_postgres_read_model(tmp_path) -> None:
    settings = _settings(tmp_path)
    invalid = SmartMoneyIngestSettings(
        **{
            **settings.__dict__,
            "environment": "production",
            "read_model_database_url": "sqlite:///tmp/read.db",
        }
    )
    try:
        invalid.validate()
    except RuntimeError as exc:
        assert "PostgreSQL" in str(exc)
    else:
        raise AssertionError("production SQLite read model should be rejected")
