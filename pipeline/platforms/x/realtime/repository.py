"""Persistence boundary for realtime X collection and product-ready calls."""
from __future__ import annotations

import calendar
import hashlib
import json
import math
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Iterable

from sqlalchemy import case, create_engine, func, inspect, or_, select, text
from sqlalchemy.orm import Session, sessionmaker

from ....common.config import normalize_db_url
from ....common.smart_account_titles import build_smart_account_activity_titles
from ....common.models import (
    XRealtimeCall,
    XRealtimeEventCandidate,
    XRealtimePost,
    XRealtimeRule,
    XRealtimeRun,
    XRealtimeSubscription,
    XRealtimeTransportState,
)
from .normalizer import NormalizedPost


REALTIME_TABLES = (
    XRealtimeSubscription.__table__,
    XRealtimeRule.__table__,
    XRealtimeTransportState.__table__,
    XRealtimePost.__table__,
    XRealtimeCall.__table__,
    XRealtimeEventCandidate.__table__,
    XRealtimeRun.__table__,
)
CALL_NAMESPACE = uuid.UUID("a98961dc-9b93-4965-8d22-95a6a0867383")


@dataclass(frozen=True)
class PoolRefreshResult:
    pool_version: str
    population: int
    selected: int


@dataclass(frozen=True)
class IngestResult:
    received: int
    inserted: int
    duplicates: int
    ignored: int


def create_realtime_engine(database_url: str):
    normalized = normalize_db_url(database_url)
    if normalized.startswith("sqlite:///"):
        path = normalized.removeprefix("sqlite:///")
        if path != ":memory:":
            Path(path).resolve().parent.mkdir(parents=True, exist_ok=True)
    connect_args = {"check_same_thread": False} if normalized.startswith("sqlite") else {"prepare_threshold": None}
    return create_engine(normalized, pool_pre_ping=True, future=True, connect_args=connect_args)


class XRealtimeRepository:
    def __init__(self, database_url: str):
        self.engine = create_realtime_engine(database_url)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False, future=True)

    def initialize(self) -> None:
        XRealtimeSubscription.metadata.create_all(self.engine, tables=list(REALTIME_TABLES))

    def dispose(self) -> None:
        self.engine.dispose()

    def refresh_top_quartile(
        self,
        now: datetime | None = None,
        *,
        selection_limit: int = 0,
    ) -> PoolRefreshResult:
        """Snapshot the qualified formal X ranking, then select its top quartile."""
        now = _naive_utc(now or datetime.now(UTC))
        if "sv_investor_score" not in inspect(self.engine).get_table_names():
            raise RuntimeError("sv_investor_score is missing; publish the formal X ranking first")
        with self.engine.connect() as connection:
            rows = connection.execute(
                text(
                    """SELECT investor_id, name, handle, sv, n_eff, settled_calls,
                                      platform_scores_json, updated_at
                           FROM sv_investor_score
                          WHERE source='x' AND n_eff>=8 AND settled_calls>=10"""
                )
            ).mappings().all()
        ranked = sorted(
            rows,
            key=lambda row: (
                -_platform_score(row),
                -float(row.get("n_eff") or 0),
                -int(row.get("settled_calls") or 0),
                str(row.get("investor_id") or ""),
            ),
        )
        selected_count = math.ceil(len(ranked) * 0.25)
        if selection_limit > 0:
            selected_count = min(selected_count, selection_limit)
        selected = [row for row in ranked[:selected_count] if _clean_handle(row.get("handle"))]
        digest = hashlib.sha256(
            "|".join(str(row["investor_id"]) for row in selected).encode("utf-8")
        ).hexdigest()[:12]
        pool_version = f"x-top25-{digest}"
        with self.sessions() as session, session.begin():
            for current in session.scalars(select(XRealtimeSubscription)):
                current.active = False
                current.updated_at = now
            for rank, row in enumerate(ranked[:selected_count], start=1):
                handle = _clean_handle(row.get("handle"))
                if not handle:
                    continue
                author_id = str(row["investor_id"])
                record = session.get(XRealtimeSubscription, author_id)
                values = {
                    "handle": handle,
                    "display_name": str(row.get("name") or handle),
                    "author_score": _platform_score(row),
                    "platform_percentile": rank / max(1, len(ranked)),
                    "author_score_as_of": _parse_datetime(row.get("updated_at")),
                    "pool_version": pool_version,
                    "active": True,
                    "updated_at": now,
                }
                if record is None:
                    session.add(
                        XRealtimeSubscription(
                            author_id=author_id,
                            activated_at=now,
                            **values,
                        )
                    )
                else:
                    for key, value in values.items():
                        setattr(record, key, value)
        return PoolRefreshResult(pool_version, len(ranked), len(selected))

    def frozen_pool_snapshot(self) -> PoolRefreshResult:
        subscriptions = self.active_subscriptions()
        if not subscriptions:
            raise RuntimeError("The fixed X author pool is empty; run x-ingest-bootstrap first")
        versions = {subscription.pool_version for subscription in subscriptions}
        if len(versions) != 1:
            raise RuntimeError("The fixed X author pool contains inconsistent pool versions")
        pool_version = versions.pop()
        return PoolRefreshResult(pool_version, len(subscriptions) * 4, len(subscriptions))

    def active_subscriptions(self) -> list[XRealtimeSubscription]:
        with self.sessions() as session:
            return list(
                session.scalars(
                    select(XRealtimeSubscription)
                    .where(XRealtimeSubscription.active.is_(True))
                    .order_by(XRealtimeSubscription.platform_percentile, XRealtimeSubscription.author_id)
                )
            )

    def subscription(self, author_id: str) -> XRealtimeSubscription | None:
        with self.sessions() as session:
            record = session.get(XRealtimeSubscription, author_id)
            return record if record and record.active else None

    def existing_post_ids(self, post_ids: Iterable[str]) -> set[str]:
        ids = set(post_ids)
        if not ids:
            return set()
        with self.sessions() as session:
            return set(
                session.scalars(
                    select(XRealtimePost.post_id).where(XRealtimePost.post_id.in_(ids))
                )
            )

    def list_rules(self) -> list[XRealtimeRule]:
        with self.sessions() as session:
            return list(session.scalars(select(XRealtimeRule).order_by(XRealtimeRule.created_at)))

    def save_rule(
        self,
        *,
        rule_key: str,
        provider_rule_id: str,
        tag: str,
        value: str,
        handles: list[str],
        pool_version: str,
        interval_seconds: float,
        now: datetime,
    ) -> None:
        now = _naive_utc(now)
        with self.sessions() as session, session.begin():
            session.merge(
                XRealtimeRule(
                    rule_key=rule_key,
                    provider_rule_id=provider_rule_id,
                    tag=tag,
                    value=value,
                    handles=handles,
                    pool_version=pool_version,
                    state="active",
                    interval_seconds=interval_seconds,
                    activated_at=now,
                    last_success_at=now,
                    created_at=now,
                    updated_at=now,
                )
            )

    def retire_rules_not_in(self, active_keys: set[str], *, retire_after: datetime) -> None:
        retire_after = _naive_utc(retire_after)
        now = _naive_utc(datetime.now(UTC))
        with self.sessions() as session, session.begin():
            for record in session.scalars(
                select(XRealtimeRule).where(XRealtimeRule.state == "active")
            ):
                if record.rule_key not in active_keys:
                    record.state = "retiring"
                    record.retire_after = retire_after
                    record.updated_at = now

    def due_retiring_rules(self, now: datetime) -> list[XRealtimeRule]:
        now = _naive_utc(now)
        with self.sessions() as session:
            return list(
                session.scalars(
                    select(XRealtimeRule).where(
                        XRealtimeRule.state == "retiring",
                        XRealtimeRule.retire_after <= now,
                    )
                )
            )

    def mark_rule_deleted(self, rule_key: str, now: datetime) -> None:
        with self.sessions() as session, session.begin():
            record = session.get(XRealtimeRule, rule_key)
            if record:
                record.state = "deleted"
                record.updated_at = _naive_utc(now)

    def mark_rule_reconciled(
        self,
        rule_key: str,
        *,
        now: datetime,
        error: str = "",
    ) -> None:
        now = _naive_utc(now)
        with self.sessions() as session, session.begin():
            record = session.get(XRealtimeRule, rule_key)
            if record:
                record.last_reconciled_at = now
                record.last_error = error[:2000]
                record.updated_at = now
                if not error:
                    record.last_success_at = now

    def ingest(
        self,
        posts: Iterable[NormalizedPost],
        *,
        delivery_source: str,
        delivery_tag: str = "",
        now: datetime | None = None,
    ) -> IngestResult:
        now = _naive_utc(now or datetime.now(UTC))
        posts = list(posts)
        inserted = duplicates = ignored = 0
        with self.sessions() as session, session.begin():
            active_ids = set(
                session.scalars(
                    select(XRealtimeSubscription.author_id).where(
                        XRealtimeSubscription.active.is_(True)
                    )
                )
            )
            for post in posts:
                if post.is_retweet or post.author_id not in active_ids:
                    ignored += 1
                    continue
                record = session.get(XRealtimePost, post.post_id)
                if record is None:
                    session.add(
                        XRealtimePost(
                            post_id=post.post_id,
                            author_id=post.author_id,
                            author_handle=post.author_handle,
                            author_name=post.author_name,
                            author_avatar_url=post.author_avatar_url,
                            author_followers_count=post.author_followers_count,
                            author_verified=post.author_verified,
                            source_url=post.source_url,
                            original_text=post.original_text,
                            language=post.language,
                            post_type=post.post_type,
                            is_reply=post.is_reply,
                            is_quote=post.is_quote,
                            is_retweet=False,
                            parent_post_id=post.parent_post_id,
                            conversation_id=post.conversation_id,
                            like_count=post.like_count,
                            reply_count=post.reply_count,
                            retweet_count=post.retweet_count,
                            quote_count=post.quote_count,
                            view_count=post.view_count,
                            bookmark_count=post.bookmark_count,
                            raw_payload=post.raw_payload,
                            delivery_source=delivery_source,
                            delivery_tag=delivery_tag,
                            status="pending",
                            published_at=_naive_utc(post.published_at),
                            ingested_at=now,
                            last_seen_at=now,
                        )
                    )
                    inserted += 1
                else:
                    duplicates += 1
                    record.last_seen_at = now
                    record.like_count = post.like_count
                    record.reply_count = post.reply_count
                    record.retweet_count = post.retweet_count
                    record.quote_count = post.quote_count
                    record.view_count = post.view_count
                    record.bookmark_count = post.bookmark_count
                    record.raw_payload = post.raw_payload
                    if record.status == "deleted":
                        record.status = "pending"
                        record.deleted_at = None
                        record.next_attempt_at = None
        return IngestResult(len(posts), inserted, duplicates, ignored)

    def claim_posts(
        self,
        *,
        limit: int,
        priority_tickers: set[str],
        now: datetime | None = None,
    ) -> list[XRealtimePost]:
        now = _naive_utc(now or datetime.now(UTC))
        stale_before = now - timedelta(minutes=20)
        with self.sessions() as session, session.begin():
            for stale in session.scalars(
                select(XRealtimePost).where(
                    XRealtimePost.status == "processing",
                    XRealtimePost.next_attempt_at < stale_before,
                )
            ):
                stale.status = "retry"
            order_columns: list[Any] = []
            if priority_tickers:
                upper_text = func.upper(XRealtimePost.original_text)
                priority_match = or_(
                    *(
                        upper_text.contains(f"${ticker}")
                        | upper_text.contains(f" {ticker} ")
                        for ticker in sorted(priority_tickers)
                    )
                )
                order_columns.append(case((priority_match, 0), else_=1))
            order_columns.append(XRealtimePost.published_at.desc())
            statement = (
                select(XRealtimePost)
                .where(
                    XRealtimePost.status.in_(("pending", "retry")),
                    XRealtimePost.deleted_at.is_(None),
                    (XRealtimePost.next_attempt_at.is_(None) | (XRealtimePost.next_attempt_at <= now)),
                )
                .order_by(*order_columns)
                .limit(max(1, limit))
            )
            if self.engine.dialect.name == "postgresql":
                statement = statement.with_for_update(skip_locked=True)
            rows = list(session.scalars(statement))
            for row in rows:
                row.status = "processing"
                row.attempt_count += 1
                row.next_attempt_at = now
            return rows

    def mark_post_terminal(
        self,
        post_id: str,
        status: str,
        *,
        processing_version: str,
        now: datetime | None = None,
    ) -> None:
        if status not in {"no_ticker", "no_actionable"}:
            raise ValueError(f"unsupported terminal status: {status}")
        with self.sessions() as session, session.begin():
            record = session.get(XRealtimePost, post_id)
            if record:
                record.status = status
                record.processing_version = processing_version
                if record.processed_at is None:
                    record.processed_at = _naive_utc(now or datetime.now(UTC))
                record.next_attempt_at = None
                record.last_error = ""

    def requeue_outdated_posts(
        self,
        processing_version: str,
        *,
        now: datetime | None = None,
    ) -> int:
        now = _naive_utc(now or datetime.now(UTC))
        changed = 0
        with self.sessions() as session, session.begin():
            posts = list(
                session.scalars(
                    select(XRealtimePost).where(
                        XRealtimePost.status.in_(("ready", "no_ticker", "no_actionable")),
                        XRealtimePost.processing_version != processing_version,
                        XRealtimePost.deleted_at.is_(None),
                    )
                )
            )
            post_ids = {post.post_id for post in posts}
            for post in posts:
                post.status = "pending"
                post.next_attempt_at = now
                post.last_error = ""
                changed += 1
            if post_ids:
                for call in session.scalars(
                    select(XRealtimeCall).where(
                        XRealtimeCall.post_id.in_(post_ids),
                        XRealtimeCall.deleted_at.is_(None),
                    )
                ):
                    call.deleted_at = now
                    event = session.get(XRealtimeEventCandidate, call.idempotency_key)
                    if event:
                        event.status = "superseded"
        return changed

    def mark_post_retry(self, post_id: str, error: Exception | str, now: datetime | None = None) -> None:
        now = _naive_utc(now or datetime.now(UTC))
        with self.sessions() as session, session.begin():
            record = session.get(XRealtimePost, post_id)
            if record:
                delay = min(3600, 30 * (2 ** min(record.attempt_count, 7)))
                record.status = "retry"
                record.next_attempt_at = now + timedelta(seconds=delay)
                record.last_error = str(error)[:2000]

    def save_ready_calls(
        self,
        post_id: str,
        calls: list[dict[str, Any]],
        *,
        now: datetime | None = None,
    ) -> int:
        now = _naive_utc(now or datetime.now(UTC))
        with self.sessions() as session, session.begin():
            post = session.get(XRealtimePost, post_id)
            if post is None:
                raise ValueError(f"unknown X post: {post_id}")
            subscription = session.get(XRealtimeSubscription, post.author_id)
            if subscription is None or not subscription.active:
                post.status = "no_actionable"
                if post.processed_at is None:
                    post.processed_at = now
                return 0
            for item in calls:
                ticker = str(item["ticker"]).upper()
                version = str(item["call_scoring_version"])
                idempotency_key = f"x:{post_id}:{ticker}:{version}"
                call_id = str(uuid.uuid5(CALL_NAMESPACE, idempotency_key))
                session.merge(
                    XRealtimeCall(
                        call_id=call_id,
                        idempotency_key=idempotency_key,
                        post_id=post_id,
                        ticker=ticker,
                        direction=str(item["direction"]),
                        horizon=str(item.get("horizon") or "unknown"),
                        target_price=item.get("target_price"),
                        lifecycle=str(item.get("lifecycle") or "open_call"),
                        invalidation=str(item.get("invalidation") or ""),
                        evidence_span=str(item["evidence_span"]),
                        original_text=post.original_text,
                        translated_text_zh=str(item["translated_text_zh"]),
                        translated_text_en=str(item["translated_text_en"]),
                        thesis_zh=str(item.get("thesis_zh") or ""),
                        thesis_en=str(item.get("thesis_en") or ""),
                        author_score=subscription.author_score,
                        author_percentile=subscription.platform_percentile,
                        author_score_as_of=subscription.author_score_as_of,
                        extraction_model=str(item.get("extraction_model") or ""),
                        translation_model=str(item.get("translation_model") or ""),
                        call_scoring_version=version,
                        call_policy_version=str(item["call_policy_version"]),
                        ready_at=now,
                    )
                )
                session.merge(
                    XRealtimeEventCandidate(
                        idempotency_key=idempotency_key,
                        call_id=call_id,
                        ticker=ticker,
                        event_type="smart_account_update",
                        status="ready",
                        created_at=now,
                    )
                )
            post.status = "ready" if calls else "no_actionable"
            post.processing_version = str(calls[0]["call_scoring_version"]) if calls else ""
            if post.processed_at is None:
                post.processed_at = now
            post.next_attempt_at = None
            post.last_error = ""
            return len(calls)

    def ready_updates(self, *, days: int = 30, limit: int = 500) -> list[dict[str, Any]]:
        cutoff = _naive_utc(datetime.now(UTC)) - timedelta(days=max(1, days))
        with self.sessions() as session:
            rows = session.execute(
                select(XRealtimeCall, XRealtimePost)
                .join(XRealtimePost, XRealtimePost.post_id == XRealtimeCall.post_id)
                .where(
                    XRealtimeCall.deleted_at.is_(None),
                    XRealtimePost.status == "ready",
                    XRealtimePost.deleted_at.is_(None),
                    XRealtimeCall.ready_at >= cutoff,
                )
                .order_by(XRealtimeCall.ready_at.desc())
                .limit(max(1, limit))
            ).all()
            return [_client_update(call, post) for call, post in rows]

    def compliance_post_ids(self, *, days: int = 30, limit: int = 500) -> list[str]:
        cutoff = _naive_utc(datetime.now(UTC)) - timedelta(days=max(1, days))
        with self.sessions() as session:
            return list(
                session.scalars(
                    select(XRealtimePost.post_id)
                    .where(
                        XRealtimePost.status == "ready",
                        XRealtimePost.deleted_at.is_(None),
                        XRealtimePost.published_at >= cutoff,
                    )
                    .order_by(XRealtimePost.published_at.desc())
                    .limit(max(1, limit))
                )
            )

    def mark_deleted(self, post_ids: Iterable[str], now: datetime | None = None) -> int:
        now = _naive_utc(now or datetime.now(UTC))
        ids = set(post_ids)
        if not ids:
            return 0
        changed = 0
        with self.sessions() as session, session.begin():
            for post in session.scalars(select(XRealtimePost).where(XRealtimePost.post_id.in_(ids))):
                post.status = "deleted"
                post.deleted_at = now
                changed += 1
            for call in session.scalars(select(XRealtimeCall).where(XRealtimeCall.post_id.in_(ids))):
                call.deleted_at = now
                event = session.get(XRealtimeEventCandidate, call.idempotency_key)
                if event:
                    event.status = "deleted"
        return changed

    def mark_events_published(
        self,
        call_ids: Iterable[str],
        now: datetime | None = None,
    ) -> int:
        ids = set(call_ids)
        if not ids:
            return 0
        consumed_at = _naive_utc(now or datetime.now(UTC))
        changed = 0
        with self.sessions() as session, session.begin():
            for event in session.scalars(
                select(XRealtimeEventCandidate).where(
                    XRealtimeEventCandidate.call_id.in_(ids),
                    XRealtimeEventCandidate.status == "ready",
                )
            ):
                event.status = "published"
                event.consumed_at = consumed_at
                changed += 1
        return changed

    def ready_event_call_ids(self) -> set[str]:
        with self.sessions() as session:
            return set(
                session.scalars(
                    select(XRealtimeEventCandidate.call_id).where(
                        XRealtimeEventCandidate.status == "ready"
                    )
                )
            )

    def start_run(self, job: str, *, details: dict[str, Any] | None = None) -> str:
        run_id = str(uuid.uuid4())
        with self.sessions() as session, session.begin():
            session.add(XRealtimeRun(run_id=run_id, job=job, status="running", details=details))
        return run_id

    def record_delivery(
        self,
        *,
        source: str,
        received: int,
        inserted: int,
        estimated_cost_usd: float,
    ) -> None:
        run_id = self.start_run(f"delivery_{source}")
        self.finish_run(
            run_id,
            status="success",
            received_count=received,
            inserted_count=inserted,
            estimated_cost_usd=estimated_cost_usd,
        )

    def mark_transport_connected(
        self,
        transport: str,
        now: datetime | None = None,
    ) -> None:
        now = _naive_utc(now or datetime.now(UTC))
        with self.sessions() as session, session.begin():
            state = session.get(XRealtimeTransportState, transport)
            if state is None:
                session.add(
                    XRealtimeTransportState(
                        transport=transport,
                        connected=True,
                        connected_at=now,
                        last_heartbeat_at=now,
                        last_error="",
                        updated_at=now,
                    )
                )
                return
            state.connected = True
            state.connected_at = now
            state.last_heartbeat_at = now
            state.last_error = ""
            state.updated_at = now

    def mark_transport_heartbeat(
        self,
        transport: str,
        now: datetime | None = None,
    ) -> None:
        now = _naive_utc(now or datetime.now(UTC))
        with self.sessions() as session, session.begin():
            state = session.get(XRealtimeTransportState, transport)
            if state is None:
                session.add(
                    XRealtimeTransportState(
                        transport=transport,
                        connected=True,
                        connected_at=now,
                        last_heartbeat_at=now,
                        last_error="",
                        updated_at=now,
                    )
                )
                return
            state.connected = True
            state.last_heartbeat_at = now
            state.last_error = ""
            state.updated_at = now

    def mark_transport_disconnected(
        self,
        transport: str,
        error: Exception | str = "",
        now: datetime | None = None,
    ) -> None:
        now = _naive_utc(now or datetime.now(UTC))
        with self.sessions() as session, session.begin():
            state = session.get(XRealtimeTransportState, transport)
            if state is None:
                session.add(
                    XRealtimeTransportState(
                        transport=transport,
                        connected=False,
                        last_error=str(error)[:2_000],
                        updated_at=now,
                    )
                )
                return
            state.connected = False
            state.last_error = str(error)[:2_000]
            state.updated_at = now

    def health_snapshot(self, now: datetime | None = None) -> dict[str, Any]:
        now = _naive_utc(now or datetime.now(UTC))
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        day_start = now - timedelta(hours=24)
        with self.sessions() as session:
            queued = session.scalar(
                select(func.count()).select_from(XRealtimePost).where(
                    XRealtimePost.status.in_(("pending", "processing", "retry"))
                )
            ) or 0
            oldest = session.scalar(
                select(func.min(XRealtimePost.ingested_at)).where(
                    XRealtimePost.status.in_(("pending", "processing", "retry"))
                )
            )
            ready = session.scalar(
                select(func.count()).select_from(XRealtimeCall).where(
                    XRealtimeCall.deleted_at.is_(None)
                )
            ) or 0
            month_cost = session.scalar(
                select(func.sum(XRealtimeRun.estimated_cost_usd)).where(
                    XRealtimeRun.started_at >= month_start
                )
            ) or 0.0
            day_cost = session.scalar(
                select(func.sum(XRealtimeRun.estimated_cost_usd)).where(
                    XRealtimeRun.started_at >= day_start
                )
            ) or 0.0
            failed_runs = session.scalar(
                select(func.count()).select_from(XRealtimeRun).where(
                    XRealtimeRun.started_at >= now - timedelta(hours=24),
                    XRealtimeRun.status.in_(("failed", "partial")),
                )
            ) or 0
            active_subscriptions = session.scalar(
                select(func.count()).select_from(XRealtimeSubscription).where(
                    XRealtimeSubscription.active.is_(True)
                )
            ) or 0
            active_rules = session.scalar(
                select(func.count()).select_from(XRealtimeRule).where(
                    XRealtimeRule.state == "active"
                )
            ) or 0
            pending_events = session.scalar(
                select(func.count()).select_from(XRealtimeEventCandidate).where(
                    XRealtimeEventCandidate.status == "ready"
                )
            ) or 0
            recent_posts = list(
                session.scalars(
                    select(XRealtimePost).where(
                        XRealtimePost.ingested_at >= now - timedelta(hours=24)
                    )
                )
            )
            recent_runs = list(
                session.scalars(
                    select(XRealtimeRun).where(
                        XRealtimeRun.started_at >= now - timedelta(hours=24)
                    )
                )
            )
            transport = session.get(XRealtimeTransportState, "websocket")
            latest_raw_published_at = session.scalar(
                select(func.max(XRealtimePost.published_at)).where(
                    XRealtimePost.deleted_at.is_(None)
                )
            )
            latest_raw_ingested_at = session.scalar(
                select(func.max(XRealtimePost.ingested_at)).where(
                    XRealtimePost.deleted_at.is_(None)
                )
            )
            latest_ready_published_at = session.scalar(
                select(func.max(XRealtimePost.published_at))
                .join(XRealtimeCall, XRealtimeCall.post_id == XRealtimePost.post_id)
                .where(
                    XRealtimePost.status == "ready",
                    XRealtimePost.deleted_at.is_(None),
                    XRealtimeCall.deleted_at.is_(None),
                )
            )
        realtime_posts = [
            post
            for post in recent_posts
            if post.delivery_source in {"webhook", "websocket"}
        ]
        ingestion_latencies = [
            max(0.0, (post.ingested_at - post.published_at).total_seconds())
            for post in realtime_posts
        ]
        ready_latencies = [
            max(0.0, (post.processed_at - post.published_at).total_seconds())
            for post in realtime_posts
            if post.status == "ready" and post.processed_at is not None
        ]
        completed = sum(
            post.status in {"ready", "no_ticker", "no_actionable"}
            for post in recent_posts
        )
        failed = sum(post.status == "retry" for post in recent_posts)
        last_success: dict[str, str] = {}
        latest_run_by_job: dict[str, XRealtimeRun] = {}
        for run in sorted(recent_runs, key=lambda item: item.started_at, reverse=True):
            latest_run_by_job.setdefault(run.job, run)
            if run.status == "success" and run.job not in last_success:
                last_success[run.job] = _iso(run.finished_at or run.started_at) or ""
        current_failed_jobs = sorted(
            job
            for job, run in latest_run_by_job.items()
            if run.status in {"failed", "partial"}
        )
        status_counts: dict[str, int] = {}
        for post in recent_posts:
            status_counts[post.status] = status_counts.get(post.status, 0) + 1
        elapsed_month_days = max(1 / 24, (now - month_start).total_seconds() / 86_400)
        projected_month_cost = float(month_cost) * (
            calendar.monthrange(now.year, now.month)[1] / elapsed_month_days
        )
        return {
            "queueDepth": int(queued),
            "oldestQueueAgeSeconds": max(0, int((now - oldest).total_seconds())) if oldest else 0,
            "readyCalls": int(ready),
            "estimatedCost24hUSD": round(float(day_cost), 4),
            "estimatedCostMonthToDateUSD": round(float(month_cost), 4),
            "estimatedMonthCostUSD": round(projected_month_cost, 4),
            "failedRuns24h": int(failed_runs),
            "currentFailedJobs": current_failed_jobs,
            "activeSubscriptions": int(active_subscriptions),
            "activeRules": int(active_rules),
            "pendingEvents": int(pending_events),
            "postsReceived24h": len(recent_posts),
            "ingestionLatencyP95Seconds": round(_percentile(ingestion_latencies, 0.95), 2),
            "readyLatencyP95Seconds": round(_percentile(ready_latencies, 0.95), 2),
            "processingSuccessRate24h": round(completed / max(1, completed + failed), 4),
            "reconcileRecoveredPosts24h": sum(
                run.inserted_count for run in recent_runs if run.job == "reconcile"
            ),
            "streamRecoveredPosts24h": sum(
                post.delivery_source == "websocket_backfill" for post in recent_posts
            ),
            "lastSuccessfulRuns": last_success,
            "latestRawPostAt": _iso(latest_raw_published_at),
            "latestRawIngestedAt": _iso(latest_raw_ingested_at),
            "latestReadyPostAt": _iso(latest_ready_published_at),
            "postStatusCounts24h": status_counts,
            "streamConnected": bool(transport and transport.connected),
            "streamConnectedAt": _iso(transport.connected_at) if transport else None,
            "lastStreamHeartbeatAt": _iso(transport.last_heartbeat_at) if transport else None,
            "streamLastError": transport.last_error if transport else "",
        }

    def finish_run(self, run_id: str, *, status: str, **counts: Any) -> None:
        with self.sessions() as session, session.begin():
            record = session.get(XRealtimeRun, run_id)
            if record is None:
                return
            record.status = status
            record.finished_at = _naive_utc(datetime.now(UTC))
            for key in ("received_count", "inserted_count", "ready_count", "failed_count", "estimated_cost_usd"):
                if key in counts:
                    setattr(record, key, counts[key])
            if "details" in counts:
                record.details = counts["details"]


def _platform_score(row: Any) -> float:
    try:
        values = json.loads(row.get("platform_scores_json") or "{}")
    except (TypeError, json.JSONDecodeError):
        values = {}
    try:
        return float(values.get("x", row.get("sv") or 100))
    except (TypeError, ValueError):
        return 100.0


def _clean_handle(value: Any) -> str:
    handle = str(value or "").strip().lstrip("@").lower()
    return handle if handle.replace("_", "").isalnum() and len(handle) <= 15 else ""


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return _naive_utc(value)
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        return _naive_utc(datetime.fromisoformat(raw.replace("Z", "+00:00")))
    except ValueError:
        return None


def _naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)


def _iso(value: datetime | None) -> str | None:
    return value.replace(tzinfo=UTC).isoformat().replace("+00:00", "Z") if value else None


def _percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(len(ordered) * quantile) - 1))
    return ordered[index]


def _client_update(call: XRealtimeCall, post: XRealtimePost) -> dict[str, Any]:
    translated = call.translated_text_zh or call.translated_text_en
    activity_titles = build_smart_account_activity_titles(
        ticker=call.ticker,
        direction=call.direction,
        lifecycle=call.lifecycle,
        horizon=call.horizon,
        target_price=call.target_price,
        thesis_zh=call.thesis_zh,
        thesis_en=call.thesis_en,
    )
    return {
        "id": call.call_id,
        "ticker": call.ticker,
        "companyName": call.ticker,
        "authorId": post.author_id,
        "authorName": post.author_name or post.author_handle,
        "platform": "X",
        "score": round(call.author_score, 2),
        "platformPercentile": round(call.author_percentile, 6),
        "direction": "bullish" if call.direction == "bull" else "bearish",
        "lifecycle": {
            "open_call": "new",
            "reinforce_call": "strengthened",
            "close_prior_call": "closed",
            "invalidate_prior_call": "invalidated",
            "reverse_call": "reversed",
        }.get(call.lifecycle, "new"),
        "horizon": call.horizon,
        "targetPrice": call.target_price,
        "thesis": call.thesis_zh or call.thesis_en,
        "invalidation": call.invalidation or None,
        "sourcePostId": post.post_id,
        "sourceURL": post.source_url,
        "evidenceURL": post.source_url,
        "publishedAt": _iso(post.published_at),
        "ingestedAt": _iso(post.ingested_at),
        "processedAt": _iso(call.ready_at),
        "originalText": post.original_text,
        "translatedText": translated,
        "translatedTextZH": call.translated_text_zh,
        "translatedTextEN": call.translated_text_en,
        "evidenceSpan": call.evidence_span,
        "authorScoreAsOf": _iso(call.author_score_as_of),
        "callScoringVersion": call.call_scoring_version,
        "authorAvatarURL": post.author_avatar_url,
        "authorFollowersCount": post.author_followers_count,
        "authorVerified": post.author_verified,
        "priceEvidence": None,
        **activity_titles,
    }
