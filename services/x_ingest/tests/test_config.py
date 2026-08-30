from __future__ import annotations

import pytest

from services.x_ingest.config import XIngestSettings


def test_production_rejects_sqlite_and_missing_client_state(monkeypatch):
    monkeypatch.setenv("BSMART_ENV", "production")
    monkeypatch.setenv("X_INGEST_ENABLED", "true")
    monkeypatch.setenv("TWITTERAPI_IO_KEY", "provider-key")
    monkeypatch.setenv("BSMART_X_WEBHOOK_TOKEN", "a" * 32)
    monkeypatch.setenv("BSMART_X_DATABASE_URL", "sqlite:///x.db")
    monkeypatch.setenv("BSMART_READ_MODEL_DATABASE_URL", "sqlite:///read.db")

    with pytest.raises(RuntimeError, match="must use PostgreSQL"):
        XIngestSettings.from_environment()


def test_rule_interval_must_match_provider_limits(monkeypatch):
    monkeypatch.setenv("BSMART_X_RULE_INTERVAL_SECONDS", "0.01")

    with pytest.raises(ValueError, match="between 0.05 and 86400"):
        XIngestSettings.from_environment()


def test_shared_database_url_is_used_for_all_production_stores(monkeypatch):
    shared = "postgresql://example.invalid/bsmart"
    monkeypatch.setenv("DATABASE_URL", shared)
    monkeypatch.setenv("BSMART_ENV", "production")
    monkeypatch.setenv("X_INGEST_ENABLED", "true")
    monkeypatch.setenv("TWITTERAPI_IO_KEY", "provider-key")
    monkeypatch.setenv("BSMART_X_WEBHOOK_TOKEN", "a" * 32)
    monkeypatch.delenv("BSMART_X_DATABASE_URL", raising=False)
    monkeypatch.delenv("BSMART_READ_MODEL_DATABASE_URL", raising=False)
    monkeypatch.delenv("BSMART_CLIENT_API_DATABASE_URL", raising=False)

    settings = XIngestSettings.from_environment()

    assert settings.database_url == shared
    assert settings.read_model_database_url == shared
    assert settings.priority_database_url == shared
    assert settings.freeze_author_pool is True


def test_author_pool_recalculation_can_be_explicitly_enabled(monkeypatch):
    monkeypatch.setenv("BSMART_X_FREEZE_AUTHOR_POOL", "false")

    settings = XIngestSettings.from_environment()

    assert settings.freeze_author_pool is False
