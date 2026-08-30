from pipeline.common.config import normalize_db_url


def test_normalize_db_url_requires_ssl_for_remote_postgres() -> None:
    assert (
        normalize_db_url("postgres://user:pass@example.com:5432/bsmart")
        == "postgresql+psycopg://user:pass@example.com:5432/bsmart?sslmode=require"
    )


def test_normalize_db_url_disables_ssl_for_local_postgres() -> None:
    assert (
        normalize_db_url("postgresql://user:pass@127.0.0.1:5432/bsmart")
        == "postgresql+psycopg://user:pass@127.0.0.1:5432/bsmart?sslmode=disable"
    )


def test_normalize_db_url_disables_ssl_for_container_host() -> None:
    value = "postgresql://user:pass@host.docker.internal:5432/bsmart"
    assert normalize_db_url(value).endswith("sslmode=disable")


def test_normalize_db_url_disables_ssl_for_railway_private_network() -> None:
    value = "postgresql://user:pass@postgres.railway.internal:5432/bsmart"
    assert normalize_db_url(value).endswith("sslmode=disable")


def test_normalize_db_url_preserves_explicit_ssl_mode() -> None:
    value = "postgresql://user:pass@localhost:5432/bsmart?sslmode=verify-full"
    assert normalize_db_url(value).endswith("sslmode=verify-full")
