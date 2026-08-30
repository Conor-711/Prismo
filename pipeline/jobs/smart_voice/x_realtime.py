"""Orchestration for the 15-minute X Smart Account update service."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Callable

from ...domain.smart_voice.realtime_x import RealtimePostInput, RealtimeXAnalyzer
from ...platforms.x.realtime.normalizer import normalize_delivery
from ...platforms.x.realtime.provider import TweetProvider
from ...platforms.x.realtime.repository import XRealtimeRepository
from ...platforms.x.realtime.rules import build_rules


@dataclass(frozen=True)
class RuleSyncResult:
    population: int
    selected: int
    created: int
    retiring: int
    deleted: int


@dataclass(frozen=True)
class ReconcileResult:
    rules: int
    received: int
    inserted: int
    duplicates: int
    failed_rules: int
    billable_matches: int
    estimated_cost_usd: float


@dataclass(frozen=True)
class ProcessResult:
    claimed: int
    ready_calls: int
    terminal_posts: int
    retry_posts: int


class XRealtimeJobs:
    def __init__(
        self,
        repository: XRealtimeRepository,
        provider: TweetProvider,
        analyzer: RealtimeXAnalyzer,
        *,
        priority_tickers: set[str] | None = None,
        rule_interval_seconds: float = 60.0,
        reconciliation_overlap_minutes: int = 5,
        reconciliation_max_pages: int = 20,
        process_workers: int = 1,
        pool_limit: int = 0,
        freeze_author_pool: bool = False,
        estimated_model_cost_per_post_usd: float = 0.0003,
    ):
        self.repository = repository
        self.provider = provider
        self.analyzer = analyzer
        self.priority_tickers = {ticker.upper() for ticker in (priority_tickers or set())}
        self.rule_interval_seconds = rule_interval_seconds
        self.reconciliation_overlap_minutes = max(1, reconciliation_overlap_minutes)
        self.reconciliation_max_pages = max(1, reconciliation_max_pages)
        self.process_workers = max(1, process_workers)
        self.pool_limit = max(0, pool_limit)
        self.freeze_author_pool = freeze_author_pool
        self.estimated_model_cost_per_post_usd = max(0.0, estimated_model_cost_per_post_usd)

    def refresh_pool_and_rules(self, now: datetime | None = None) -> RuleSyncResult:
        now = now or datetime.now(UTC)
        run_id = self.repository.start_run("pool_and_rules")
        try:
            subscriptions = self.repository.active_subscriptions()
            if self.freeze_author_pool and subscriptions:
                pool = self.repository.frozen_pool_snapshot()
            else:
                pool = self.repository.refresh_top_quartile(now, selection_limit=self.pool_limit)
                subscriptions = self.repository.active_subscriptions()
            desired = build_rules(
                [subscription.handle for subscription in subscriptions],
                pool_version=pool.pool_version,
            )
            existing = {
                rule.rule_key: rule
                for rule in self.repository.list_rules()
                if rule.state in {"active", "retiring"}
            }
            provider_rules = self.provider.list_rules()
            provider_by_id = {rule.rule_id: rule for rule in provider_rules}
            provider_by_identity: dict[tuple[str, str], list] = {}
            for provider_rule in provider_rules:
                provider_by_identity.setdefault(
                    (provider_rule.tag, provider_rule.value), []
                ).append(provider_rule)
            created = 0
            active_keys: set[str] = set()
            for rule in desired:
                active_keys.add(rule.key)
                current = existing.get(rule.key)
                candidates = provider_by_identity.get((rule.tag, rule.value), [])
                current_provider = (
                    provider_by_id.get(current.provider_rule_id)
                    if current and current.provider_rule_id
                    else None
                )
                if current and current.state == "active" and current_provider:
                    if not current_provider.active:
                        self.provider.activate_rule(
                            rule_id=current.provider_rule_id,
                            tag=rule.tag,
                            value=rule.value,
                            interval_seconds=self.rule_interval_seconds,
                        )
                    for duplicate in candidates:
                        if duplicate.rule_id != current.provider_rule_id:
                            self.provider.delete_rule(duplicate.rule_id)
                    continue
                if current and current.state == "retiring" and current_provider:
                    self.provider.activate_rule(
                        rule_id=current.provider_rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        interval_seconds=self.rule_interval_seconds,
                    )
                    self.repository.save_rule(
                        rule_key=rule.key,
                        provider_rule_id=current.provider_rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        handles=list(rule.handles),
                        pool_version=pool.pool_version,
                        interval_seconds=self.rule_interval_seconds,
                        now=now,
                    )
                    for duplicate in candidates:
                        if duplicate.rule_id != current.provider_rule_id:
                            self.provider.delete_rule(duplicate.rule_id)
                    continue
                if candidates:
                    adopted = next((item for item in candidates if item.active), candidates[0])
                    self.provider.activate_rule(
                        rule_id=adopted.rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        interval_seconds=self.rule_interval_seconds,
                    )
                    self.repository.save_rule(
                        rule_key=rule.key,
                        provider_rule_id=adopted.rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        handles=list(rule.handles),
                        pool_version=pool.pool_version,
                        interval_seconds=self.rule_interval_seconds,
                        now=now,
                    )
                    for duplicate in candidates:
                        if duplicate.rule_id != adopted.rule_id:
                            self.provider.delete_rule(duplicate.rule_id)
                    continue
                provider_rule_id = self.provider.add_rule(
                    tag=rule.tag,
                    value=rule.value,
                    interval_seconds=self.rule_interval_seconds,
                )
                try:
                    self.provider.activate_rule(
                        rule_id=provider_rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        interval_seconds=self.rule_interval_seconds,
                    )
                    self.repository.save_rule(
                        rule_key=rule.key,
                        provider_rule_id=provider_rule_id,
                        tag=rule.tag,
                        value=rule.value,
                        handles=list(rule.handles),
                        pool_version=pool.pool_version,
                        interval_seconds=self.rule_interval_seconds,
                        now=now,
                    )
                except Exception:
                    try:
                        self.provider.delete_rule(provider_rule_id)
                    except Exception:
                        pass
                    raise
                created += 1

            old_active = [rule for rule in existing.values() if rule.state == "active" and rule.rule_key not in active_keys]
            self.repository.retire_rules_not_in(
                active_keys,
                retire_after=now + timedelta(hours=24),
            )
            deleted = 0
            for rule in self.repository.due_retiring_rules(now):
                if rule.provider_rule_id:
                    self.provider.delete_rule(rule.provider_rule_id)
                self.repository.mark_rule_deleted(rule.rule_key, now)
                deleted += 1
            result = RuleSyncResult(pool.population, pool.selected, created, len(old_active), deleted)
            self.repository.finish_run(run_id, status="success", details=asdict(result))
            return result
        except Exception as exc:
            self.repository.finish_run(run_id, status="failed", failed_count=1, details={"error": str(exc)})
            raise

    def reconcile(self, now: datetime | None = None) -> ReconcileResult:
        now = now or datetime.now(UTC)
        run_id = self.repository.start_run("reconcile")
        totals = {
            "rules": 0,
            "received": 0,
            "inserted": 0,
            "duplicates": 0,
            "failed_rules": 0,
            "billable_matches": 0,
        }
        for rule in self.repository.list_rules():
            if rule.state not in {"active", "retiring"}:
                continue
            totals["rules"] += 1
            since = (
                rule.last_reconciled_at - timedelta(minutes=self.reconciliation_overlap_minutes)
                if rule.last_reconciled_at
                else _naive(now) - timedelta(minutes=20)
            )
            try:
                payloads = self.provider.search_recent(
                    query=rule.value,
                    since=since,
                    until=now,
                    max_pages=self.reconciliation_max_pages,
                )
                totals["billable_matches"] += len(payloads)
                _, posts = normalize_delivery({"tweets": payloads, "tag": rule.tag})
                ingested = self.repository.ingest(
                    posts,
                    delivery_source="reconcile",
                    delivery_tag=rule.tag,
                    now=now,
                )
                totals["received"] += ingested.received
                totals["inserted"] += ingested.inserted
                totals["duplicates"] += ingested.duplicates
                self.repository.mark_rule_reconciled(rule.rule_key, now=now)
            except Exception as exc:  # noqa: BLE001 - continue other provider rules
                totals["failed_rules"] += 1
                self.repository.mark_rule_reconciled(rule.rule_key, now=now, error=str(exc))
        cost = round(totals["billable_matches"] * 0.00015, 6)
        result = ReconcileResult(**totals, estimated_cost_usd=cost)
        self.repository.finish_run(
            run_id,
            status="partial" if totals["failed_rules"] else "success",
            received_count=totals["received"],
            inserted_count=totals["inserted"],
            failed_count=totals["failed_rules"],
            estimated_cost_usd=cost,
            details=asdict(result),
        )
        return result

    def process(
        self,
        limit: int = 25,
        *,
        priority_tickers: set[str] | None = None,
    ) -> ProcessResult:
        run_id = self.repository.start_run("process")
        posts = self.repository.claim_posts(
            limit=limit,
            priority_tickers=(
                {ticker.upper() for ticker in priority_tickers}
                if priority_tickers is not None
                else self.priority_tickers
            ),
        )
        def process_post(post) -> tuple[int, int, int]:
            try:
                result = self.analyzer.analyze(
                    RealtimePostInput(
                        post_id=post.post_id,
                        original_text=post.original_text,
                        language=post.language,
                        published_at=post.published_at,
                        post_type=post.post_type,
                    )
                )
                if not result.tickers:
                    self.repository.mark_post_terminal(
                        post.post_id,
                        "no_ticker",
                        processing_version=self.analyzer.processing_version,
                    )
                    return 0, 1, 0
                elif not result.calls:
                    self.repository.mark_post_terminal(
                        post.post_id,
                        "no_actionable",
                        processing_version=self.analyzer.processing_version,
                    )
                    return 0, 1, 0
                else:
                    return self.repository.save_ready_calls(post.post_id, list(result.calls)), 0, 0
            except Exception as exc:  # noqa: BLE001 - fail closed and retry the whole post
                self.repository.mark_post_retry(post.post_id, exc)
                return 0, 0, 1

        if self.process_workers == 1 or len(posts) <= 1:
            outcomes = [process_post(post) for post in posts]
        else:
            with ThreadPoolExecutor(max_workers=self.process_workers) as executor:
                outcomes = list(executor.map(process_post, posts))
        ready_calls = sum(item[0] for item in outcomes)
        terminal = sum(item[1] for item in outcomes)
        retries = sum(item[2] for item in outcomes)
        result = ProcessResult(len(posts), ready_calls, terminal, retries)
        self.repository.finish_run(
            run_id,
            status="partial" if retries else "success",
            ready_count=ready_calls,
            failed_count=retries,
            estimated_cost_usd=round(
                len(posts) * self.estimated_model_cost_per_post_usd,
                6,
            ),
            details=asdict(result),
        )
        return result

    def compliance_check(self, *, days: int = 30, limit: int = 500) -> dict[str, int]:
        run_id = self.repository.start_run("compliance")
        post_ids = self.repository.compliance_post_ids(days=days, limit=limit)
        found = self.provider.get_posts(post_ids)
        missing = sorted(set(post_ids) - set(found))
        deleted = self.repository.mark_deleted(missing)
        result = {"checked": len(post_ids), "found": len(found), "deleted": deleted}
        self.repository.finish_run(run_id, status="success", details=result)
        return result

    def publish(
        self,
        publisher: Callable[[dict[str, list[dict[str, Any]]], str], Any],
        *,
        days: int = 30,
        limit: int = 500,
    ) -> int:
        updates = self.repository.ready_updates(days=days, limit=limit)
        publisher({"smart-account-updates": updates}, "x-realtime-v1")
        return len(updates)


def _naive(value: datetime) -> datetime:
    return value.astimezone(UTC).replace(tzinfo=None) if value.tzinfo else value


__all__ = [
    "ProcessResult",
    "ReconcileResult",
    "RuleSyncResult",
    "XRealtimeJobs",
]
