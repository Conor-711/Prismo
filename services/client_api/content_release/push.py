"""APNs content notifications; independent of the legacy signal-notification worker."""
import argparse
import json
import os
import time
from uuid import NAMESPACE_URL, uuid5

import httpx
from dotenv import dotenv_values
from sqlalchemy import create_engine

from ..apns import APNsSettings, APNsProviderToken, _endpoint, _response_reason
from ..config import REPO_ROOT, normalize_database_url
from . import push_queue


def load_push_environment():
    path = REPO_ROOT / "services/client_api/.env.push.local"
    if path.is_file():
        for key, value in dotenv_values(path, interpolate=False).items():
            if value and (key.startswith("BSMART_APNS_") or key == "BSMART_UPDATE_PUSH_ENABLED"):
                os.environ.setdefault(key, value)


def enabled():
    return os.environ.get("BSMART_UPDATE_PUSH_ENABLED", "false").lower() in {"1", "true", "yes"}


def should_enqueue(baseline, previous, entries):
    return not baseline and enabled() and previous is not None and any(
        previous.manifest["collections"][name]["sha256"] != entry["sha256"]
        for name, entry in entries.items())


def new_events(previous, current):
    """Only new stable IDs qualify; metadata/Score changes never generate alerts."""
    def opinion_identity(row):
        source = row.get("sourcePostId")
        if not source:
            return row["id"]
        key = f"bsmart-opinion:{row['platform'].lower()}:{row['authorId'].lower()}:{source}:{row['ticker'].upper()}"
        return str(uuid5(NAMESPACE_URL, key))

    prior_opinions = {opinion_identity(row) for name in ("smart-account-updates", "smart-account-evidence")
                      for row in previous[name]}
    prior_movements = {row["id"] for row in previous["smart-money-movements"]}
    events = {}
    for row in current["smart-account-updates"]:
        identity = opinion_identity(row)
        if identity not in prior_opinions:
            events[("opinion", identity)] = {
                "event_kind": "opinion", "event_id": identity, "actor_id": row["authorId"],
                "ticker": row["ticker"].upper(), "actor_name": row["authorName"][:160],
            }
    for row in current["smart-money-movements"]:
        if row["id"] not in prior_movements:
            events[("movement", row["id"])] = {
                "event_kind": "movement", "event_id": row["id"], "actor_id": row["accountId"],
                "ticker": row["ticker"].upper(), "actor_name": row["accountLabel"][:160],
            }
    return list(events.values())


def payload(delivery):
    zh = delivery["locale"].lower().startswith("zh")
    count = delivery["item_count"]
    return {"type": "content_digest", "slotAt": delivery["slot_at"].isoformat(), "aps": {
        "alert": {"title": "bSmart 新动态" if zh else "New on bSmart",
                  "body": f"你关注的作者或标的有 {count} 条新观点或动态。" if zh else
                          f"{count} new views or updates from authors and tickers you follow."},
        "sound": "default", "thread-id": "bsmart.content-digest"}}


def outcome(status, reason, attempts):
    invalid = reason in {"BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered", "ExpiredToken"}
    if status == 200:
        return "accepted", False
    return "failed", invalid


def drain(engine, limit=200, *, client=None, settings=None, token=None):
    if not enabled():
        return {"status": "disabled", "attempted": 0}
    slot = push_queue.due_slot()
    if slot is None:
        return {"status": "waiting_for_slot", "attempted": 0}
    settings = settings or APNsSettings.from_environment()
    token = token or APNsProviderToken(settings)
    # Validate credentials before claiming any work.
    token.value()
    owned = client is None
    client = client or httpx.Client(http2=True, timeout=10)
    counts = {"attempted": 0, "accepted": 0, "failed": 0}
    try:
        push_queue.prepare_slot(engine, slot)
        for _ in range(limit):
            if not enabled():
                break
            delivery = push_queue.claim(engine)
            if not delivery:
                break
            status, reason = None, None
            try:
                response = client.post(_endpoint(delivery["environment"], delivery["apns_token"]),
                    headers={"authorization": f"bearer {token.value()}", "apns-topic": settings.topic,
                             "apns-id": str(delivery["apns_id"]),
                             "apns-collapse-id": f"bsmart.{int(delivery['slot_at'].timestamp())}.{delivery['user_id']}",
                             "apns-push-type": "alert", "apns-priority": "10",
                             "apns-expiration": str(int((delivery["slot_at"] + push_queue.SLOT_GRACE).timestamp()))},
                    json=payload(delivery))
                status, reason = response.status_code, _response_reason(response)
                if reason in {"ExpiredProviderToken", "InvalidProviderToken"}:
                    token.invalidate()
            except httpx.TransportError:
                pass
            state, invalid = outcome(status, reason, delivery["attempts"])
            push_queue.complete(engine, delivery, state, status, invalid)
            counts["attempted"] += 1
            counts[state] += 1
            # A credential outage must not fail every queued batch in one run.
            if status in {401, 403}:
                break
        return {"status": "processed", **counts}
    finally:
        if owned:
            client.close()


def main():
    from .__main__ import publication_database_url
    parser = argparse.ArgumentParser(description="Dispatch interest digests in three UTC+8 slots; no DDL")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--watch", action="store_true", help="Keep this worker running; check slots every 60 seconds")
    args = parser.parse_args()
    if not 1 <= args.limit <= 1000:
        parser.error("limit must be 1..1000")
    load_push_environment()
    url = publication_database_url()
    if not url.startswith(("postgresql", "postgres://")):
        parser.error("Configure protected BSMART_CONTENT_DATABASE_URL")
    engine = create_engine(normalize_database_url(url), pool_pre_ping=True)
    try:
        while True:
            try:
                print(json.dumps(drain(engine, args.limit)), flush=True)
            except Exception:
                print(json.dumps({"status": "pending", "message": "Check database migration and APNs configuration locally"}), flush=True)
                if not args.watch:
                    raise SystemExit(1) from None
            if not args.watch:
                break
            time.sleep(60)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
