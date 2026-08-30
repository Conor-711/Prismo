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


def _items(name: str, default: str) -> tuple[str, ...]:
    return tuple(
        dict.fromkeys(
            item.strip().upper()
            for item in os.environ.get(name, default).split(",")
            if item.strip()
        )
    )


@dataclass(frozen=True)
class XIngestSettings:
    environment: str
    enabled: bool
    database_url: str
    read_model_database_url: str
    priority_database_url: str | None
    twitterapi_io_key: str
    twitterapi_io_base_url: str
    webhook_token: str
    tickers: tuple[str, ...]
    priority_tickers: tuple[str, ...]
    pool_limit: int
    process_batch_size: int
    process_workers: int
    process_interval_seconds: int
    reconcile_interval_seconds: int
    publish_interval_seconds: int
    rule_interval_seconds: float
    reconciliation_max_pages: int
    monthly_cost_limit_usd: float
    freeze_author_pool: bool = True
    estimated_model_cost_per_post_usd: float = 0.0003
    stream_enabled: bool = False
    twitterapi_io_stream_url: str = "wss://ws.twitterapi.io/twitter/tweet/websocket"
    stream_reconnect_seconds: int = 90

    @classmethod
    def from_environment(cls) -> "XIngestSettings":
        environment = os.environ.get("BSMART_ENV", "development").strip().lower()
        shared_database_url = os.environ.get("DATABASE_URL", "").strip()
        database_url = os.environ.get(
            "BSMART_X_DATABASE_URL",
            shared_database_url or f"sqlite:///{REPO_ROOT / 'data' / 'x_realtime.db'}",
        )
        read_model_database_url = os.environ.get("BSMART_READ_MODEL_DATABASE_URL", "").strip()
        client_database_url = os.environ.get("BSMART_CLIENT_API_DATABASE_URL", "").strip()
        settings = cls(
            environment=environment,
            enabled=_boolean("X_INGEST_ENABLED"),
            database_url=database_url,
            read_model_database_url=(
                read_model_database_url
                or shared_database_url
                or f"sqlite:///{REPO_ROOT / 'data' / 'client_api.db'}"
            ),
            priority_database_url=client_database_url or shared_database_url or None,
            twitterapi_io_key=os.environ.get("TWITTERAPI_IO_KEY", "").strip(),
            twitterapi_io_base_url=os.environ.get(
                "TWITTERAPI_IO_BASE_URL", "https://api.twitterapi.io"
            ).strip(),
            webhook_token=os.environ.get("BSMART_X_WEBHOOK_TOKEN", "").strip(),
            tickers=_items("BSMART_X_TICKERS", "AVGO,HOOD,MSTR,MU,NVDA,PLTR"),
            priority_tickers=_items("BSMART_X_PRIORITY_TICKERS", ""),
            pool_limit=int(os.environ.get("BSMART_X_POOL_LIMIT", "0")),
            freeze_author_pool=_boolean("BSMART_X_FREEZE_AUTHOR_POOL", True),
            process_batch_size=int(os.environ.get("BSMART_X_PROCESS_BATCH_SIZE", "25")),
            process_workers=int(os.environ.get("BSMART_X_PROCESS_WORKERS", "4")),
            process_interval_seconds=int(os.environ.get("BSMART_X_PROCESS_INTERVAL_SECONDS", "10")),
            reconcile_interval_seconds=int(os.environ.get("BSMART_X_RECONCILE_INTERVAL_SECONDS", "900")),
            publish_interval_seconds=int(os.environ.get("BSMART_X_PUBLISH_INTERVAL_SECONDS", "60")),
            rule_interval_seconds=float(os.environ.get("BSMART_X_RULE_INTERVAL_SECONDS", "60")),
            reconciliation_max_pages=int(os.environ.get("BSMART_X_RECONCILE_MAX_PAGES", "40")),
            monthly_cost_limit_usd=float(os.environ.get("BSMART_X_MONTHLY_COST_LIMIT_USD", "100")),
            estimated_model_cost_per_post_usd=float(
                os.environ.get("BSMART_X_ESTIMATED_MODEL_COST_PER_POST_USD", "0.0003")
            ),
            stream_enabled=_boolean("BSMART_X_STREAM_ENABLED"),
            twitterapi_io_stream_url=os.environ.get(
                "TWITTERAPI_IO_STREAM_URL",
                "wss://ws.twitterapi.io/twitter/tweet/websocket",
            ).strip(),
            stream_reconnect_seconds=int(
                os.environ.get("BSMART_X_STREAM_RECONNECT_SECONDS", "90")
            ),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if self.process_batch_size < 1:
            raise ValueError("BSMART_X_PROCESS_BATCH_SIZE must be positive")
        if self.pool_limit < 0:
            raise ValueError("BSMART_X_POOL_LIMIT must not be negative")
        if not 1 <= self.process_workers <= 16:
            raise ValueError("BSMART_X_PROCESS_WORKERS must be between 1 and 16")
        if self.reconcile_interval_seconds < 60:
            raise ValueError("BSMART_X_RECONCILE_INTERVAL_SECONDS must be at least 60")
        if self.process_interval_seconds < 1 or self.publish_interval_seconds < 1:
            raise ValueError("X process and publish intervals must be positive")
        if not 0.05 <= self.rule_interval_seconds <= 86_400:
            raise ValueError("BSMART_X_RULE_INTERVAL_SECONDS must be between 0.05 and 86400")
        if self.estimated_model_cost_per_post_usd < 0:
            raise ValueError("BSMART_X_ESTIMATED_MODEL_COST_PER_POST_USD must not be negative")
        if self.stream_reconnect_seconds < 90:
            raise ValueError("BSMART_X_STREAM_RECONNECT_SECONDS must be at least 90")
        if self.stream_enabled and not self.twitterapi_io_stream_url.startswith("wss://"):
            raise ValueError("TWITTERAPI_IO_STREAM_URL must use wss://")
        if self.enabled and not self.webhook_token:
            raise RuntimeError("BSMART_X_WEBHOOK_TOKEN is required when X ingestion is enabled")
        if self.enabled and not self.twitterapi_io_key:
            raise RuntimeError("TWITTERAPI_IO_KEY is required when X ingestion is enabled")
        if self.environment == "production":
            if self.database_url.startswith("sqlite") or self.read_model_database_url.startswith("sqlite"):
                raise RuntimeError("Production X ingestion and read models must use PostgreSQL")
            if self.enabled and len(self.webhook_token) < 24:
                raise RuntimeError("Production BSMART_X_WEBHOOK_TOKEN must be at least 24 characters")
            if self.enabled and not self.priority_database_url:
                raise RuntimeError(
                    "Production X ingestion requires BSMART_CLIENT_API_DATABASE_URL for portfolio priority and notifications"
                )
