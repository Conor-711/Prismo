"""Atomic publication into manually provisioned Supabase tables; no DDL."""
from datetime import datetime, timedelta, timezone
import os
import json

from sqlalchemy import select, text, func, cast, Text
from sqlalchemy.orm import Session

from .contract import SCHEMAS, date, digest, load_baseline, pages, validate
from .models import Active, Page, Release
from ..publish_daily_x import is_x, load_release
from .push import should_enqueue, new_events
from .push_queue import enqueue
from . import cache
from .partition import load_partition, merge_partition
from .ranking_freeze import apply as apply_frozen_rankings, snapshot as ranking_snapshot


def read_collections(session, revision, *, use_cache=True):
    release = session.get(Release, revision)
    if use_cache and release:
        cached = cache.load(revision, release.manifest)
        if cached is not None:
            return cached
    collections = {name: [] for name in SCHEMAS}
    # Supabase's session pooler can leave long-lived server-side cursors waiting
    # indefinitely. Read bounded pages instead; a release is immutable, and the
    # publication transaction keeps the active revision stable while we merge.
    offset, batch_size = 0, 25
    while True:
        # Keep each database response small even when individual JSONB pages are large.
        # Avoid holding a streaming cursor across pooler/network round trips.
        rows = session.execute(select(Page.collection, Page.owner, Page.page,
            func.length(cast(Page.payload, Text))).where(Page.revision == revision)
            .order_by(Page.collection, Page.owner, Page.page).limit(batch_size).offset(offset)).all()
        if not rows:
            break
        for name, owner, page, length in rows:
            parts = []
            for start in range(1, length + 1, 8192):
                parts.append(session.scalar(select(func.substr(cast(Page.payload, Text), start, 8192))
                    .where(Page.revision == revision, Page.collection == name, Page.owner == owner, Page.page == page)))
            payload = json.loads("".join(parts))
            if payload.get("revision") != revision or payload.get("page") != page:
                raise ValueError("Stored content page identity mismatch")
            collections[name].extend(payload["items"])
        offset += len(rows)
    return collections


def merge_x(collections, metadata, incoming, source, allow_drop=False, *, historical_test=False, backfill=False):
    now = datetime.now(timezone.utc)
    as_of, through = date(source["asOf"]), date(source["sourceThrough"])
    if not historical_test and (as_of < now - timedelta(hours=36) or through < now - timedelta(hours=96)):
        raise ValueError("Daily X package is stale")
    updated, timestamps = dict(collections), dict(metadata)
    incoming = dict(incoming)
    # Daily exports are a current window, not proof that older evidence was deleted.
    # Preserve history only while its author remains in the new published author set.
    if 'smart-account-evidence' in incoming and not backfill:
        authors = {row['id'] for row in incoming.get('smart-accounts', collections['smart-accounts'])}
        evidence = {row['id']: row for row in collections['smart-account-evidence']
                    if is_x('smart-account-evidence', row) and row.get('authorId') in authors}
        evidence.update({row['id']: row for row in incoming['smart-account-evidence']})
        incoming['smart-account-evidence'] = list(evidence.values())
    for name, items in incoming.items():
        prior = [item for item in collections[name] if is_x(name, item)]
        if backfill:
            merged = {row['id']: row for row in items}
            merged.update({row['id']: row for row in prior})
            items = list(merged.values())
        if not allow_drop and len(prior) >= 10 and len(items) < len(prior) * .75:
            raise ValueError(f"{name}: X rows would drop more than 25%")
        updated[name] = [item for item in collections[name] if not is_x(name, item)] + items
        field = "occurredAt" if name == "portfolio-signals" else "publishedAt"
        content_dates = [date(row[field]) for row in updated[name] if row.get(field)]
        latest = max(content_dates).isoformat() if content_dates else (
            metadata[name].get("latestContentAt") if name == "smart-accounts" else None)
        timestamps[name] = {"checkedAt": max(date(metadata[name]["checkedAt"]), as_of).isoformat(),
                            "latestContentAt": latest}
    return updated, timestamps


def publish(engine, directory, *, baseline=False, apply=False, allow_drop=False, reencode_baseline=False, historical_test=False, restore_rankings=False):
    if restore_rankings and (baseline or reencode_baseline or historical_test):
        raise ValueError("Ranking restoration cannot be combined with another publication mode")
    if historical_test and baseline:
        raise ValueError("Historical test requires a daily release")
    # Validate disk input before taking a database publication lock.
    if reencode_baseline and not baseline:
        raise ValueError("Re-encoding requires an identical reviewed baseline")
    if baseline or restore_rankings:
        incoming, source_metadata = load_baseline(directory)
    else:
        partition = (directory / "platform-manifest.json").is_file()
        incoming, source, package_hash = load_partition(directory) if partition else load_release(directory)
    backfill = False
    with Session(engine) as session, session.begin():
        if engine.dialect.name == "postgresql":
            session.execute(text("select pg_advisory_xact_lock(721534915)"))
        active = session.get(Active, "production")
        previous = session.get(Release, active.revision) if active else None
        prior_collections = None
        if restore_rankings:
            if not previous:
                raise ValueError("A published release is required before restoring rankings")
            baseline_hash = digest(incoming["smart-accounts"])
            if previous.provenance.get("rankingsFrozen", {}).get("baselineHash") == baseline_hash:
                return {"status": "already-published", "revision": active.revision, "publicAPIVerified": False}
            collections = read_collections(session, active.revision)
            metadata = previous.manifest["collections"]
            frozen, restored = ranking_snapshot(collections["smart-accounts"], incoming["smart-accounts"],
                current_updates=collections["smart-account-updates"], baseline_updates=incoming["smart-account-updates"])
            collections = apply_frozen_rankings(collections, frozen)
            provenance = {**previous.provenance, "kind": "rankings-restored",
                          "rankingsFrozen": {"baselineHash": baseline_hash, "sourceRevision": active.revision,
                                             "restoredProfiles": restored, "snapshot": frozen}}
        elif baseline:
            if active:
                stored = read_collections(session, active.revision)
                if previous.provenance.get("kind") == "baseline" and all(
                    sorted(stored[name], key=lambda row: row.get("id", row.get("ticker", "")))
                        == sorted(incoming[name], key=lambda row: row.get("id", row.get("ticker", "")))
                    and all(previous.manifest["collections"][name].get(key) == source_metadata[name].get(key)
                            for key in ("checkedAt", "latestContentAt")) for name in SCHEMAS):
                    same_hashes = all(previous.manifest["collections"][name]["sha256"] == digest(
                        sorted(incoming[name], key=lambda row: row.get("id", row.get("ticker", "")))) for name in SCHEMAS)
                    if same_hashes:
                        return {"status": "already-published", "revision": active.revision, "publicAPIVerified": False}
                    if not reencode_baseline:
                        raise ValueError("Baseline encoding differs; review and use --reencode-baseline")
                else:
                    raise ValueError("Baseline already exists; use a partition update or explicit rollback")
            collections, metadata, provenance = incoming, source_metadata, {"kind": "baseline", "xPackages": []}
            x_dates = [date(row["publishedAt"]) for row in collections["smart-account-updates"]
                       if is_x("smart-account-updates", row)]
            if x_dates:
                provenance.update(xAsOf=metadata["smart-account-updates"]["checkedAt"],
                                  xSourceThrough=max(x_dates).isoformat())
        else:
            if not previous:
                raise ValueError("A complete multi-platform baseline must be published first")
            prior_collections = read_collections(session, active.revision)
            provenance = dict(previous.provenance)
            if partition:
                platform = source['platform']
                partitions = dict(provenance.get('partitions', {}))
                prior = partitions.get(platform, {})
                if package_hash == prior.get('packageHash'):
                    return {"status": "already-published", "revision": active.revision, "publicAPIVerified": False}
                if prior.get('asOf') and date(source['asOf']) <= date(prior['asOf']):
                    raise ValueError('Newer platform data is already published')
                if prior.get('crawlThrough') and date(source['crawlThrough']) < date(prior['crawlThrough']):
                    raise ValueError('Newer platform crawl is already published')
                collections, metadata = merge_partition(prior_collections,
                    previous.manifest['collections'], incoming, source)
                partitions[platform] = {'asOf': source['asOf'], 'packageHash': package_hash,
                                        'crawlThrough': source['crawlThrough'],
                                        'sourceThrough': source.get('sourceThrough')}
                provenance.update(kind='platform-refresh', partitions=partitions)
            else:
                if package_hash in provenance.get("xPackages", []):
                    return {"status": "already-published", "revision": active.revision, "publicAPIVerified": False}
                if provenance.get("xAsOf") and date(source["asOf"]) <= date(provenance["xAsOf"]):
                    raise ValueError("Newer X data is already published")
                backfill = bool(provenance.get("xSourceThrough") and
                                date(source["sourceThrough"]) < date(provenance["xSourceThrough"]))
                if apply and os.environ.get("X_INGEST_ENABLED", "true").lower() not in {"0", "false", "no"}:
                    raise ValueError("Stop the realtime X writer and set X_INGEST_ENABLED=false")
                collections, metadata = merge_x(prior_collections,
                    previous.manifest["collections"], incoming, source, allow_drop,
                    historical_test=historical_test, backfill=backfill)
                provenance.update(kind="historical-test" if historical_test else "daily-x-backfill" if backfill else "daily-x",
                                  xAsOf=source["asOf"],
                                  xSourceThrough=provenance["xSourceThrough"] if backfill else source["sourceThrough"],
                                  xPackages=[*provenance.get("xPackages", []), package_hash])
            if "rankingsFrozen" in provenance:
                freeze = dict(provenance["rankingsFrozen"])
                frozen = dict(freeze["snapshot"])
                collections = apply_frozen_rankings(collections, frozen)
                freeze["snapshot"] = frozen
                provenance["rankingsFrozen"] = freeze
        # Stable ordering makes page boundaries/hashes repeatable after DB round trips.
        collections = {name: sorted(items, key=lambda row: row.get("id", row.get("ticker", ""))) for name, items in collections.items()}
        validate(collections, metadata)
        entries = {name: {"count": len(items), "sha256": digest(items),
                          "checkedAt": metadata[name]["checkedAt"], "latestContentAt": metadata[name].get("latestContentAt")}
                   for name, items in collections.items()}
        revision = digest({"schemaVersion": 1, "collections": entries, "provenance": provenance})
        manifest = {"schemaVersion": 1, "revision": revision, "collections": entries}
        result = {"status": "validated", "revision": revision, "previousRevision": active.revision if active else None,
                  "counts": {name: entry["count"] for name, entry in entries.items()}, "publicAPIVerified": False}
        if restore_rankings:
            result["restoredRankingProfiles"] = restored
        if not apply:
            return result
        if not session.get(Release, revision):
            session.add(Release(revision=revision, manifest=manifest, provenance=provenance))
            session.flush()
            for name, items in collections.items():
                batch = []
                for owner, page, payload in pages(revision, name, items):
                    batch.append({"revision": revision, "collection": name, "owner": owner, "page": page, "payload": payload})
                    if len(batch) == 100:
                        session.execute(Page.__table__.insert(), batch)
                        batch = []
                if batch:
                    session.execute(Page.__table__.insert(), batch)
        now = datetime.now(timezone.utc)
        if active:
            active.revision, active.activated_at = revision, now
        else:
            session.add(Active(channel="production", revision=revision, activated_at=now))
        session.flush()
        if not restore_rankings and not historical_test and not backfill and should_enqueue(baseline, previous, entries):
            result["notificationsQueued"] = enqueue(session, revision, new_events(prior_collections, collections))
    # Receipt is written only after commit, and never claims the public API was checked.
    with Session(engine) as session:
        if session.get(Active, "production").revision != revision:
            raise RuntimeError("A concurrent publication superseded this release; inspect active revision")
    if engine.dialect.name == "postgresql":
        cache.save(revision, collections)
    return {**result, "status": "published", "publishedAt": now.isoformat()}


def rollback(engine, revision, *, apply=False):
    with Session(engine) as session, session.begin():
        if engine.dialect.name == "postgresql":
            session.execute(text("select pg_advisory_xact_lock(721534915)"))
        target, active = session.get(Release, revision), session.get(Active, "production")
        if not target or not active:
            raise ValueError("Unknown retained revision")
        result = {"status": "validated", "revision": revision, "previousRevision": active.revision, "publicAPIVerified": False}
        if apply:
            active.revision, active.activated_at = revision, datetime.now(timezone.utc)
            result["status"] = "published"
    return result
