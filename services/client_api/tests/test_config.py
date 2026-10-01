from __future__ import annotations

from services.client_api.config import ClientAPISettings, normalize_database_url


def test_shared_postgres_database_configures_state_and_read_models(monkeypatch):
    monkeypatch.setenv("BSMART_ENV", "production")
    monkeypatch.setenv("DATABASE_URL", "postgresql://user:pass@example.invalid/bsmart")
    monkeypatch.delenv("BSMART_CLIENT_API_DATABASE_URL", raising=False)
    monkeypatch.delenv("BSMART_READ_MODEL_DATABASE_URL", raising=False)

    settings = ClientAPISettings.from_environment()

    assert settings.read_model_mode == "database"
    assert settings.database_url.startswith("postgresql+psycopg://")
    assert settings.database_url.endswith("sslmode=require")
    assert settings.read_model_database_url == settings.database_url


def test_local_postgres_disables_ssl_by_default(monkeypatch):
    monkeypatch.setenv("BSMART_ENV", "production")
    monkeypatch.setenv("DATABASE_URL", "postgresql://user:pass@127.0.0.1:5432/bsmart")
    monkeypatch.delenv("BSMART_CLIENT_API_DATABASE_URL", raising=False)
    monkeypatch.delenv("BSMART_READ_MODEL_DATABASE_URL", raising=False)

    settings = ClientAPISettings.from_environment()

    assert settings.database_url.endswith("sslmode=disable")


def test_railway_private_postgres_disables_ssl_by_default(monkeypatch):
    monkeypatch.setenv("BSMART_ENV", "production")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://user:pass@postgres.railway.internal:5432/bsmart",
    )
    monkeypatch.delenv("BSMART_CLIENT_API_DATABASE_URL", raising=False)
    monkeypatch.delenv("BSMART_READ_MODEL_DATABASE_URL", raising=False)

    settings = ClientAPISettings.from_environment()

    assert settings.database_url.endswith("sslmode=disable")


def test_docker_service_postgres_disables_ssl_by_default():
    value = normalize_database_url(
        "postgresql://user:pass@postgres:5432/bsmart"
    )

    assert value.endswith("sslmode=disable")
