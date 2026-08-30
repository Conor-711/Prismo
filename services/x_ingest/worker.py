from __future__ import annotations

import logging
import os
import threading
import time
from collections.abc import Callable

from apscheduler.schedulers.blocking import BlockingScheduler
from sqlalchemy import inspect, text

from pipeline.common.config import normalize_db_url
from pipeline.domain.smart_voice.realtime_x import RealtimeXAnalyzer
from pipeline.jobs.smart_voice.x_realtime import XRealtimeJobs
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from pipeline.platforms.x.realtime.twitterapi_io import TwitterAPIIOProvider
from services.client_api.read_models import RealtimeReadModelPublisher
from services.client_api.notification_planner import NotificationPlanner
from services.client_api.state_store import ClientStateStore
from services.x_ingest.config import XIngestSettings
from services.x_ingest.signals import build_portfolio_signals
from services.x_ingest.stream import TwitterAPIIOStreamConsumer


logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("bsmart.x_ingest")


def _enabled() -> bool:
    return os.environ.get("X_INGEST_ENABLED", "false").strip().lower() in {"1", "true", "yes", "on"}


def _priority_tickers(settings: XIngestSettings) -> set[str]:
    tickers = set(settings.priority_tickers)
    if not settings.priority_database_url:
        return tickers
    from sqlalchemy import create_engine

    engine = create_engine(normalize_db_url(settings.priority_database_url), pool_pre_ping=True)
    try:
        if "client_portfolio_entry" not in inspect(engine).get_table_names():
            return tickers
        with engine.connect() as connection:
            tickers.update(
                str(row[0]).upper()
                for row in connection.execute(
                    text(
                        "SELECT DISTINCT ticker FROM client_portfolio_entry "
                        "WHERE entry_kind IN ('position','watchlist')"
                    )
                )
                if row[0]
            )
    finally:
        engine.dispose()
    return tickers


def _guarded(name: str, operation: Callable[[], object]) -> None:
    if not _enabled():
        LOGGER.warning("%s skipped because X_INGEST_ENABLED is off", name)
        return
    try:
        result = operation()
        LOGGER.info("%s completed: %s", name, result)
    except Exception:  # noqa: BLE001 - scheduler must keep later jobs alive
        LOGGER.exception("%s failed", name)


def _monitor(repository: XRealtimeRepository, settings: XIngestSettings) -> dict[str, object]:
    snapshot = repository.health_snapshot()
    if not snapshot["activeSubscriptions"] or not snapshot["activeRules"]:
        LOGGER.error("X realtime author pool or provider rules are empty: %s", snapshot)
    if snapshot["estimatedMonthCostUSD"] >= settings.monthly_cost_limit_usd:
        LOGGER.critical(
            "X provider cost limit exceeded: estimated=%s limit=%s",
            snapshot["estimatedMonthCostUSD"],
            settings.monthly_cost_limit_usd,
        )
    if snapshot["ingestionLatencyP95Seconds"] > 120:
        LOGGER.error("X ingestion P95 exceeds two minutes: %s", snapshot)
    if snapshot["readyLatencyP95Seconds"] > 900 or snapshot["oldestQueueAgeSeconds"] > 900:
        LOGGER.error("X ready-data SLA exceeds fifteen minutes: %s", snapshot)
    if snapshot["currentFailedJobs"]:
        LOGGER.warning("X realtime jobs currently failing: %s", snapshot)
    return snapshot


def main() -> None:
    settings = XIngestSettings.from_environment()
    if not settings.enabled:
        raise SystemExit("X_INGEST_ENABLED is off")
    repository = XRealtimeRepository(settings.database_url)
    repository.initialize()
    provider = TwitterAPIIOProvider(
        settings.twitterapi_io_key,
        base_url=settings.twitterapi_io_base_url,
    )
    analyzer = RealtimeXAnalyzer(tickers=settings.tickers)
    requeued = repository.requeue_outdated_posts(analyzer.processing_version)
    if requeued:
        LOGGER.info("requeued %s posts for processing version %s", requeued, analyzer.processing_version)
    jobs = XRealtimeJobs(
        repository,
        provider,
        analyzer,
        priority_tickers=set(settings.priority_tickers),
        rule_interval_seconds=settings.rule_interval_seconds,
        reconciliation_max_pages=settings.reconciliation_max_pages,
        process_workers=settings.process_workers,
        pool_limit=settings.pool_limit,
        freeze_author_pool=settings.freeze_author_pool,
        estimated_model_cost_per_post_usd=settings.estimated_model_cost_per_post_usd,
    )
    read_model_publisher = RealtimeReadModelPublisher(settings.read_model_database_url)
    state_store = (
        ClientStateStore(normalize_db_url(settings.priority_database_url))
        if settings.priority_database_url
        else None
    )
    notification_planner = NotificationPlanner(state_store) if state_store else None
    stream_consumer = (
        TwitterAPIIOStreamConsumer(settings, repository) if settings.stream_enabled else None
    )
    stream_thread = (
        threading.Thread(
            target=stream_consumer.run,
            name="twitterapi-io-websocket",
            daemon=True,
        )
        if stream_consumer
        else None
    )
    cached_priority_tickers = set(settings.priority_tickers)
    next_priority_refresh = 0.0

    def current_priority_tickers() -> set[str]:
        nonlocal cached_priority_tickers, next_priority_refresh
        now = time.monotonic()
        if now >= next_priority_refresh:
            cached_priority_tickers = _priority_tickers(settings)
            next_priority_refresh = now + 60
        return cached_priority_tickers

    def publish(collections, source_version):
        updates = collections["smart-account-updates"]
        signals = build_portfolio_signals(updates)
        collections["portfolio-signals"] = signals
        pending_call_ids = repository.ready_event_call_ids()
        result = read_model_publisher.publish_partitioned(
            collections,
            producer="x-realtime",
            source_version=source_version,
            owns_document=lambda collection, item: (
                collection == "smart-account-updates"
                and str(item.get("platform") or "").lower() in {"x", "twitter"}
            ),
        )
        pending_signals = [
            signal
            for signal in signals
            if str(signal["evidence"][0]["referenceId"]) in pending_call_ids
        ]
        published_pending_ids = {
            str(signal["evidence"][0]["referenceId"])
            for signal in pending_signals
        }
        if notification_planner:
            for signal in pending_signals:
                notification_planner.plan_signal(signal)
        repository.mark_events_published(published_pending_ids)
        return result

    scheduler = BlockingScheduler(timezone="UTC")
    scheduler.add_job(
        lambda: _guarded(
            "process",
            lambda: jobs.process(
                settings.process_batch_size,
                priority_tickers=current_priority_tickers(),
            ),
        ),
        "interval",
        seconds=settings.process_interval_seconds,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        lambda: _guarded("reconcile", jobs.reconcile),
        "interval",
        seconds=settings.reconcile_interval_seconds,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        lambda: _guarded("publish", lambda: jobs.publish(publish)),
        "interval",
        seconds=settings.publish_interval_seconds,
        max_instances=1,
        coalesce=True,
    )
    if not settings.freeze_author_pool:
        scheduler.add_job(
            lambda: _guarded("pool_and_rules", jobs.refresh_pool_and_rules),
            "interval",
            hours=24,
            max_instances=1,
            coalesce=True,
        )
    scheduler.add_job(
        lambda: _guarded("compliance", jobs.compliance_check),
        "interval",
        hours=24,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        lambda: _guarded("monitor", lambda: _monitor(repository, settings)),
        "interval",
        seconds=60,
        max_instances=1,
        coalesce=True,
    )
    _guarded("pool_and_rules", jobs.refresh_pool_and_rules)
    # Start the low-latency path as soon as provider rules are active. The
    # startup reconciliation is intentionally secondary and may take longer
    # under provider rate limiting.
    if stream_thread:
        stream_thread.start()
    _guarded("reconcile", jobs.reconcile)
    _guarded(
        "process",
        lambda: jobs.process(
            settings.process_batch_size,
            priority_tickers=current_priority_tickers(),
        ),
    )
    _guarded("publish", lambda: jobs.publish(publish))
    _guarded("monitor", lambda: _monitor(repository, settings))
    try:
        scheduler.start()
    finally:
        if stream_consumer:
            stream_consumer.stop()
        if stream_thread:
            stream_thread.join(timeout=5)
        if state_store:
            state_store.dispose()
        read_model_publisher.dispose()
        repository.dispose()


if __name__ == "__main__":
    main()
