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


def test_mr_collie_uses_explicit_deepseek_environment(monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-deepseek-key")
    monkeypatch.setenv("DEEPSEEK_BASE_URL", "https://deepseek.example.invalid")
    monkeypatch.setenv("BSMART_MR_COLLIE_MODEL", "deepseek-test")
    monkeypatch.setenv("BSMART_MR_COLLIE_TIMEOUT_SECONDS", "12")
    monkeypatch.setenv("BSMART_MR_COLLIE_REQUESTS_PER_MINUTE", "5")

    settings = ClientAPISettings.from_environment()

    assert settings.deepseek_api_key == "test-deepseek-key"
    assert settings.deepseek_base_url == "https://deepseek.example.invalid"
    assert settings.mr_collie_model == "deepseek-test"
    assert settings.mr_collie_timeout_seconds == 12
    assert settings.mr_collie_requests_per_minute == 5


def test_mr_collie_defaults_to_flash_independently_of_mid_model(monkeypatch):
    monkeypatch.delenv("BSMART_MR_COLLIE_MODEL", raising=False)
    monkeypatch.setenv("DEEPSEEK_MODEL_LOW", "deepseek-v4-flash")
    monkeypatch.setenv("DEEPSEEK_MODEL_MID", "deepseek-v4-pro")

    settings = ClientAPISettings.from_environment()

    assert settings.mr_collie_model == "deepseek-v4-flash"
