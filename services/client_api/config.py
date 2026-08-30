from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

from dotenv import load_dotenv


REPO_ROOT = Path(__file__).resolve().parents[2]


def normalize_database_url(value: str) -> str:
    if value.startswith("postgres://"):
        value = "postgresql+psycopg://" + value[len("postgres://") :]
    elif value.startswith("postgresql://"):
        value = "postgresql+psycopg://" + value[len("postgresql://") :]
    if value.startswith("postgresql+psycopg://") and "sslmode=" not in value:
        host = (urlsplit(value).hostname or "").lower()
        internal = (
            host in {"localhost", "127.0.0.1", "::1", "host.docker.internal"}
            or host.endswith(".railway.internal")
            or "." not in host
        )
        sslmode = "disable" if internal else "require"
        value += ("&" if "?" in value else "?") + f"sslmode={sslmode}"
    return value


@dataclass(frozen=True)
class ClientAPISettings:
    environment: str
    database_url: str
    read_model_mode: str
    fixture_root: Path
    read_model_database_url: str | None = None
    session_lifetime_days: int = 90
    telemetry_retention_days: int = 90
    deepseek_api_key: str = ""
    deepseek_base_url: str = "https://api.deepseek.com"
    mr_collie_model: str = "deepseek-v4-flash"
    mr_collie_timeout_seconds: float = 45.0
    mr_collie_requests_per_minute: int = 8

    @classmethod
    def from_environment(cls) -> "ClientAPISettings":
        # Local commands run the Client API directly, so load the repository's
        # uncommitted secrets without overriding deployment-provided variables.
        load_dotenv(REPO_ROOT / ".env", override=False)
        environment = os.environ.get("BSMART_ENV", "development").strip().lower()
        default_mode = "fixture" if environment in {"development", "test"} else "database"
        shared_database_url = os.environ.get("DATABASE_URL", "").strip()
        state_database_url = os.environ.get("BSMART_CLIENT_API_DATABASE_URL", "").strip()
        read_model_database_url = os.environ.get("BSMART_READ_MODEL_DATABASE_URL", "").strip()
        settings = cls(
            environment=environment,
            database_url=normalize_database_url(
                state_database_url
                or shared_database_url
                or f"sqlite:///{REPO_ROOT / 'data' / 'client_api.db'}"
            ),
            read_model_mode=os.environ.get("BSMART_READ_MODEL_MODE", default_mode).strip().lower(),
            fixture_root=Path(
                os.environ.get("BSMART_FIXTURE_ROOT", REPO_ROOT / "contracts" / "fixtures")
            ).resolve(),
            read_model_database_url=(
                normalize_database_url(read_model_database_url or shared_database_url)
                if read_model_database_url or shared_database_url
                else None
            ),
            session_lifetime_days=int(os.environ.get("BSMART_SESSION_LIFETIME_DAYS", "90")),
            telemetry_retention_days=int(os.environ.get("BSMART_TELEMETRY_RETENTION_DAYS", "90")),
            deepseek_api_key=os.environ.get("DEEPSEEK_API_KEY", "").strip(),
            deepseek_base_url=os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip(),
            mr_collie_model=os.environ.get(
                "BSMART_MR_COLLIE_MODEL",
                os.environ.get("DEEPSEEK_MODEL_LOW", "deepseek-v4-flash"),
            ).strip(),
            mr_collie_timeout_seconds=float(
                os.environ.get("BSMART_MR_COLLIE_TIMEOUT_SECONDS", "45")
            ),
            mr_collie_requests_per_minute=int(
                os.environ.get("BSMART_MR_COLLIE_REQUESTS_PER_MINUTE", "8")
            ),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if self.environment == "production" and self.read_model_mode == "fixture":
            raise RuntimeError("Production client API cannot run with fixture read models.")
        if self.read_model_mode not in {"fixture", "database"}:
            raise RuntimeError(f"Unsupported read model mode: {self.read_model_mode}")
        if self.read_model_mode == "fixture" and not self.fixture_root.is_dir():
            raise RuntimeError(f"Fixture directory does not exist: {self.fixture_root}")
        if self.session_lifetime_days < 1:
            raise RuntimeError("Session lifetime must be at least one day.")
        if not 1 <= self.telemetry_retention_days <= 365:
            raise RuntimeError("Telemetry retention must be between 1 and 365 days.")
        if not self.deepseek_base_url.startswith(("https://", "http://")):
            raise RuntimeError("DeepSeek base URL must be HTTP(S).")
        if not self.mr_collie_model:
            raise RuntimeError("Mr Collie model must not be empty.")
        if self.mr_collie_timeout_seconds <= 0:
            raise RuntimeError("Mr Collie timeout must be positive.")
        if not 1 <= self.mr_collie_requests_per_minute <= 60:
            raise RuntimeError("Mr Collie rate limit must be between 1 and 60 requests per minute.")
