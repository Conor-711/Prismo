from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def _boolean(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class SmartMoneyIngestSettings:
    environment: str
    enabled: bool
    data_dir: Path
    database_path: Path
    output_path: Path
    client_output_dir: Path
    health_output_path: Path
    read_model_database_url: str | None
    lookback_days: int = 30
    refresh_seconds: int = 30
    publish_seconds: int = 60
    candidate_backfill: int = 4
    max_active_wallets: int = 8
    max_profile_wallets: int = 8
    profile_refresh_minutes: int = 5
    instrument_refresh_minutes: int = 60
    publisher_poll_seconds: float = 2.0
    worker_restart_initial_seconds: float = 5.0
    worker_restart_max_seconds: float = 60.0
    shutdown_timeout_seconds: int = 120
    primary_source: str = "hyperdash"
    hyperdash_graphql_url: str = "https://api.hyperdash.com/graphql"
    hyperdash_group_id: str = "equities"
    hyperdash_max_wallets: int = 100
    hyperdash_position_limit: int = 12
    hyperdash_max_stale_seconds: int = 1800
    smart_account_updates_path: Path | None = None

    @classmethod
    def from_environment(cls) -> "SmartMoneyIngestSettings":
        environment = os.environ.get("BSMART_ENV", "development").strip().lower()
        data_dir = Path(
            os.environ.get(
                "BSMART_SMART_MONEY_DATA_DIR",
                str(REPO_ROOT / "data" / "runtime" / "smart-money-service"),
            )
        ).expanduser().resolve()
        settings = cls(
            environment=environment,
            enabled=_boolean("BSMART_SMART_MONEY_ENABLED"),
            data_dir=data_dir,
            database_path=Path(
                os.environ.get("BSMART_SMART_MONEY_DATABASE", str(data_dir / "smart-money.db"))
            ).expanduser().resolve(),
            output_path=Path(
                os.environ.get("BSMART_SMART_MONEY_OUTPUT", str(data_dir / "hyperliquidSmartMoney.json"))
            ).expanduser().resolve(),
            client_output_dir=Path(
                os.environ.get("BSMART_SMART_MONEY_CLIENT_OUTPUT", str(data_dir / "client"))
            ).expanduser().resolve(),
            health_output_path=Path(
                os.environ.get("BSMART_SMART_MONEY_HEALTH_OUTPUT", str(data_dir / "health.json"))
            ).expanduser().resolve(),
            read_model_database_url=(
                os.environ.get("BSMART_READ_MODEL_DATABASE_URL", "").strip() or None
            ),
            lookback_days=min(
                30,
                int(os.environ.get("BSMART_SMART_MONEY_LOOKBACK_DAYS", "30")),
            ),
            refresh_seconds=int(os.environ.get("BSMART_SMART_MONEY_REFRESH_SECONDS", "600")),
            publish_seconds=int(os.environ.get("BSMART_SMART_MONEY_PUBLISH_SECONDS", "60")),
            candidate_backfill=int(os.environ.get("BSMART_SMART_MONEY_CANDIDATE_BACKFILL", "4")),
            max_active_wallets=int(os.environ.get("BSMART_SMART_MONEY_MAX_ACTIVE_WALLETS", "8")),
            max_profile_wallets=int(os.environ.get("BSMART_SMART_MONEY_MAX_PROFILE_WALLETS", "8")),
            profile_refresh_minutes=int(
                os.environ.get("BSMART_SMART_MONEY_PROFILE_REFRESH_MINUTES", "5")
            ),
            instrument_refresh_minutes=int(
                os.environ.get("BSMART_SMART_MONEY_INSTRUMENT_REFRESH_MINUTES", "60")
            ),
            publisher_poll_seconds=float(
                os.environ.get("BSMART_SMART_MONEY_PUBLISHER_POLL_SECONDS", "2")
            ),
            worker_restart_initial_seconds=float(
                os.environ.get("BSMART_SMART_MONEY_RESTART_INITIAL_SECONDS", "5")
            ),
            worker_restart_max_seconds=float(
                os.environ.get("BSMART_SMART_MONEY_RESTART_MAX_SECONDS", "60")
            ),
            shutdown_timeout_seconds=int(
                os.environ.get("BSMART_SMART_MONEY_SHUTDOWN_TIMEOUT_SECONDS", "120")
            ),
            primary_source=os.environ.get(
                "BSMART_SMART_MONEY_PRIMARY_SOURCE",
                "hyperdash",
            ).strip().lower(),
            hyperdash_graphql_url=os.environ.get(
                "BSMART_HYPERDASH_GRAPHQL_URL",
                "https://api.hyperdash.com/graphql",
            ).strip(),
            hyperdash_group_id=os.environ.get(
                "BSMART_HYPERDASH_GROUP_ID",
                "equities",
            ).strip(),
            hyperdash_max_wallets=int(
                os.environ.get("BSMART_HYPERDASH_MAX_WALLETS", "100")
            ),
            hyperdash_position_limit=int(
                os.environ.get("BSMART_HYPERDASH_POSITION_LIMIT", "12")
            ),
            hyperdash_max_stale_seconds=int(
                os.environ.get("BSMART_HYPERDASH_MAX_STALE_SECONDS", "1800")
            ),
            smart_account_updates_path=(
                Path(raw_updates_path).expanduser().resolve()
                if (raw_updates_path := os.environ.get(
                    "BSMART_SMART_ACCOUNT_UPDATES_PATH", ""
                ).strip())
                else None
            ),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        positive = {
            "lookback_days": self.lookback_days,
            "refresh_seconds": self.refresh_seconds,
            "publish_seconds": self.publish_seconds,
            "max_active_wallets": self.max_active_wallets,
            "profile_refresh_minutes": self.profile_refresh_minutes,
            "instrument_refresh_minutes": self.instrument_refresh_minutes,
            "shutdown_timeout_seconds": self.shutdown_timeout_seconds,
        }
        invalid = [name for name, value in positive.items() if value < 1]
        if invalid:
            raise ValueError(f"Smart Money settings must be positive: {', '.join(invalid)}")
        if self.candidate_backfill < 0 or self.max_profile_wallets < 0:
            raise ValueError("Smart Money batch sizes must not be negative")
        if self.primary_source not in {"hyperdash", "hyperliquid"}:
            raise ValueError(
                "BSMART_SMART_MONEY_PRIMARY_SOURCE must be hyperdash or hyperliquid"
            )
        if not self.hyperdash_graphql_url or not self.hyperdash_group_id:
            raise ValueError("Hyperdash endpoint and group id must not be empty")
        if self.hyperdash_max_wallets < 1 or self.hyperdash_position_limit < 1:
            raise ValueError("Hyperdash wallet and position limits must be positive")
        if self.hyperdash_max_stale_seconds < 60:
            raise ValueError("BSMART_HYPERDASH_MAX_STALE_SECONDS must be at least 60")
        if self.publisher_poll_seconds < 0.25:
            raise ValueError("BSMART_SMART_MONEY_PUBLISHER_POLL_SECONDS must be at least 0.25")
        if self.worker_restart_initial_seconds < 0.1:
            raise ValueError("BSMART_SMART_MONEY_RESTART_INITIAL_SECONDS must be at least 0.1")
        if self.worker_restart_max_seconds < self.worker_restart_initial_seconds:
            raise ValueError(
                "BSMART_SMART_MONEY_RESTART_MAX_SECONDS must be greater than or equal to "
                "BSMART_SMART_MONEY_RESTART_INITIAL_SECONDS"
            )
        if self.environment == "production" and self.enabled:
            if not self.read_model_database_url:
                raise RuntimeError(
                    "Production Smart Money ingestion requires BSMART_READ_MODEL_DATABASE_URL"
                )
            if self.read_model_database_url.startswith("sqlite"):
                raise RuntimeError("Production Smart Money read models must use PostgreSQL")
