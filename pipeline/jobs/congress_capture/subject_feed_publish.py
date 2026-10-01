"""Validate and publish a subject-activity snapshot to the iOS content project."""

from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import ssl
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from uuid import uuid4

import certifi


TICKER = re.compile(r"^[A-Z][A-Z0-9.]{0,9}$")
KINDS = {"politician", "celebrity", "institution"}
ACTIONS = {"buy", "sell"}
HOLDING_ACTIONS = {"new", "increased", "reduced", "no_longer_reported", "held"}
MANAGEMENT_CHUNK_SIZE = 300_000
PRICE_FIELDS = ("eventDayAdjustedClose", "latestAdjustedClose", "latestPriceDay", "priceBasis")


def merge_price_observations(current: dict, incoming: dict) -> tuple[dict, int]:
    """Keep the live snapshot intact while adding verified, newer price observations."""
    incoming_events = {event["id"]: event for event in incoming["events"]}
    if len(incoming_events) != len(incoming["events"]) or set(incoming_events) != {
        event["id"] for event in current["events"]
    }:
        raise ValueError("Live and local subject event identities differ")
    changed = 0
    merged_events = []
    for event in current["events"]:
        source = incoming_events[event["id"]]
        if any(event.get(field) != source.get(field) for field in
               ("subjectID", "ticker", "type", "occurredDay", "displayDay")):
            raise ValueError(f"Subject event changed since local export: {event['id']}")
        updated = dict(event)
        if (source.get("eventDayAdjustedClose") is not None
                and source.get("latestAdjustedClose") is not None
                and source.get("latestPriceDay") is not None
                and source["latestPriceDay"] >= (event.get("latestPriceDay") or "")):
            for field in PRICE_FIELDS:
                if field in source:
                    updated[field] = source[field]
            changed += updated != event
        merged_events.append(updated)
    return {**current, "events": merged_events}, changed


def merge_holding_enrichment(current: dict, incoming: dict) -> tuple[dict, int, int, int]:
    incoming_holdings = {event["id"]: event for event in incoming["events"]
                         if event["type"] == "holding"}
    mapped = identified = priced = 0
    merged_events = []
    for event in current["events"]:
        source = incoming_holdings.get(event["id"]) if event["type"] == "holding" else None
        if source is None:
            merged_events.append(event)
            continue
        if any(event.get(field) != source.get(field) for field in
               ("subjectID", "type", "action", "assetName", "occurredDay", "displayDay")):
            raise ValueError(f"Live 13F event changed since local export: {event['id']}")
        updated = dict(event)
        if source.get("cusip"):
            if updated.get("cusip") and updated["cusip"] != source["cusip"]:
                raise ValueError(f"Conflicting 13F CUSIP: {event['id']}")
            updated["cusip"] = source["cusip"]
        if source.get("ticker"):
            if updated.get("ticker") and updated["ticker"] != source["ticker"]:
                raise ValueError(f"Conflicting 13F ticker: {event['id']}")
            mapped += updated.get("ticker") != source["ticker"]
            updated["ticker"] = source["ticker"]
            if (source.get("eventDayAdjustedClose") is not None
                    and source.get("latestAdjustedClose") is not None
                    and source.get("latestPriceDay") is not None
                    and source["latestPriceDay"] >= (updated.get("latestPriceDay") or "")):
                before = {field: updated.get(field) for field in PRICE_FIELDS}
                for field in PRICE_FIELDS:
                    if field in source:
                        updated[field] = source[field]
                priced += before != {field: updated.get(field) for field in PRICE_FIELDS}
        if source.get("underlyingTicker"):
            if updated.get("ticker"):
                raise ValueError(f"Option underlying conflicts with trade ticker: {event['id']}")
            if (updated.get("underlyingTicker")
                    and updated["underlyingTicker"] != source["underlyingTicker"]):
                raise ValueError(f"Conflicting 13F underlying ticker: {event['id']}")
            identified += updated.get("underlyingTicker") != source["underlyingTicker"]
            updated["underlyingTicker"] = source["underlyingTicker"]
        merged_events.append(updated)
    return {**current, "events": merged_events}, mapped, identified, priced


def publish_holding_enrichment_to_content_database(snapshot: dict) -> tuple[int, int, int]:
    from dotenv import dotenv_values
    import psycopg

    key = "BSMART_CONTENT_DATABASE_URL"
    root = Path(__file__).resolve().parents[3]
    url = os.environ.get(key) or dotenv_values(root / "services/client_api/.env.content.local",
                                                interpolate=False).get(key)
    if not url or not url.startswith(("postgres://", "postgresql://")):
        raise ValueError("Protected BSMART_CONTENT_DATABASE_URL is required")
    with psycopg.connect(url, connect_timeout=10) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                           "WHERE channel='production' FOR UPDATE")
            row = cursor.fetchone()
            if not row:
                raise ValueError("No live subject snapshot exists")
            merged, mapped, identified, priced = merge_holding_enrichment(row[0], snapshot)
            validate_snapshot(merged)
            if mapped or identified or priced:
                cursor.execute("UPDATE public.bsmart_subject_activity_snapshots "
                               "SET payload=%s::jsonb, updated_at=now() WHERE channel='production'",
                               (json.dumps(merged, ensure_ascii=False, allow_nan=False),))
                cursor.execute("SELECT payload FROM public.bsmart_subject_activity_snapshots "
                               "WHERE channel='production'")
                if cursor.fetchone()[0] != merged:
                    raise RuntimeError("Subject holding publication failed readback verification")
    return mapped, identified, priced


def publish_price_observations_to_content_database(snapshot: dict) -> int:
    from dotenv import dotenv_values
    import psycopg

    key = "BSMART_CONTENT_DATABASE_URL"
    root = Path(__file__).resolve().parents[3]
    url = os.environ.get(key) or dotenv_values(root / "services/client_api/.env.content.local",
                                                interpolate=False).get(key)
    if not url or not url.startswith(("postgres://", "postgresql://")):
        raise ValueError("Protected BSMART_CONTENT_DATABASE_URL is required")
    with psycopg.connect(url, connect_timeout=10) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT payload FROM public.bsmart_subject_activity_snapshots "
                "WHERE channel='production' FOR UPDATE"
            )
            row = cursor.fetchone()
            if not row:
                raise ValueError("No live subject snapshot exists")
            merged, changed = merge_price_observations(row[0], snapshot)
            validate_snapshot(merged)
            if changed:
                cursor.execute(
                    "UPDATE public.bsmart_subject_activity_snapshots "
                    "SET payload=%s::jsonb, updated_at=now() WHERE channel='production'",
                    (json.dumps(merged, ensure_ascii=False, allow_nan=False),),
                )
                cursor.execute(
                    "SELECT payload FROM public.bsmart_subject_activity_snapshots "
                    "WHERE channel='production'"
                )
                if cursor.fetchone()[0] != merged:
                    raise RuntimeError("Subject price publication failed readback verification")
    return changed


def publish_management_snapshot(snapshot: dict, query) -> None:
    serialized = json.dumps(snapshot, ensure_ascii=True, separators=(",", ":"))
    direct_sql = """insert into public.bsmart_subject_activity_snapshots (channel,payload,updated_at)
                    values ('production',$1::jsonb,now())
                    on conflict (channel) do update
                    set payload=excluded.payload, updated_at=excluded.updated_at"""
    try:
        query(direct_sql, [serialized])
    except HTTPError as error:
        if error.code != 413:
            raise
        publication_id = str(uuid4())
        chunks = [serialized[i:i + MANAGEMENT_CHUNK_SIZE]
                  for i in range(0, len(serialized), MANAGEMENT_CHUNK_SIZE)]
        for index, chunk in enumerate(chunks):
            query("""insert into public.bsmart_subject_activity_publish_chunks
                     (publication_id,chunk_index,payload_text) values ($1::uuid,$2,$3)""",
                  [publication_id, index, chunk])
        promoted = query("""with assembled as (
                            select string_agg(payload_text, '' order by chunk_index) as body
                            from public.bsmart_subject_activity_publish_chunks
                            where publication_id=$1::uuid
                            having count(*)=$2 and min(chunk_index)=0 and max(chunk_index)=$2-1
                               and md5(string_agg(payload_text, '' order by chunk_index))=$3
                          ), promoted as (
                            insert into public.bsmart_subject_activity_snapshots (channel,payload,updated_at)
                            select 'production', body::jsonb, now() from assembled
                            on conflict (channel) do update
                            set payload=excluded.payload, updated_at=excluded.updated_at
                            returning channel
                          ) select count(*) as promoted from promoted""",
                         [publication_id, len(chunks), hashlib.md5(serialized.encode()).hexdigest()])
        if promoted != [{"promoted": 1}]:
            raise RuntimeError("Staged snapshot failed integrity checks; production was not changed")
        query("delete from public.bsmart_subject_activity_publish_chunks where publication_id=$1::uuid",
              [publication_id])


def validate_snapshot(snapshot: dict, *, allow_samples: bool = False) -> None:
    if snapshot.get("schemaVersion") != 1:
        raise ValueError("Unsupported subject-activity schema")
    subjects, events = snapshot.get("subjects"), snapshot.get("events")
    if not isinstance(subjects, list) or not isinstance(events, list) or len(subjects) > 10_000 or len(events) > 100_000:
        raise ValueError("Invalid subject/event collection")
    ids = set()
    for subject in subjects:
        if not isinstance(subject, dict):
            raise ValueError("Invalid subject")
        subject_id = subject.get("id")
        if (not isinstance(subject_id, str) or not subject_id or subject_id in ids
                or not isinstance(subject.get("kind"), str) or subject["kind"] not in KINDS
                or not isinstance(subject.get("name"), str) or not subject["name"].strip()
                or subject.get("avatarURL") is not None
                and urlparse(str(subject["avatarURL"])).scheme not in {"http", "https"}):
            raise ValueError("Invalid subject identity")
        ids.add(subject_id)
        metrics = subject.get("metrics")
        if metrics is not None and (not isinstance(metrics, dict)
                or any(not isinstance(metrics.get(key), int) or metrics[key] < 0 for key in ("wins", "losses"))
                or not isinstance(metrics.get("trackedReturn"), (int, float))
                or not math.isfinite(metrics["trackedReturn"])):
            raise ValueError("Invalid subject metrics")
        research = subject.get("research")
        if research is not None:
            if not isinstance(research, dict) or research.get("method") != "three_year_open_positions_v1":
                raise ValueError("Invalid subject research method")
            try:
                date.fromisoformat(research["asOf"])
                date.fromisoformat(research["sourceSince"])
                date.fromisoformat(research["latestMarketDate"])
                counts = ("candidatePositions", "pricedPositions", "directionalWins",
                          "directionalLosses", "directionalObservations")
                if any(type(research[key]) is not int or research[key] < 0 for key in counts):
                    raise ValueError
                if (research["pricedPositions"] > research["candidatePositions"]
                        or research["directionalWins"] + research["directionalLosses"]
                        > research["directionalObservations"]):
                    raise ValueError
                for key in ("directionalWinRate", "meanOpenReturn", "openPositionPositiveRate"):
                    value = research.get(key)
                    if value is not None and (type(value) not in (int, float) or not math.isfinite(value)):
                        raise ValueError
                if (research.get("directionalWinRate") is not None
                        and (not 0 <= research["directionalWinRate"] <= 1
                             or research["directionalObservations"] == 0)):
                    raise ValueError
                if (research.get("meanOpenReturn") is not None
                        and (research["meanOpenReturn"] < -1 or research["pricedPositions"] == 0)):
                    raise ValueError
                if (research.get("openPositionPositiveRate") is not None
                        and not 0 <= research["openPositionPositiveRate"] <= 1):
                    raise ValueError
            except (KeyError, TypeError, ValueError) as exc:
                raise ValueError("Invalid subject research") from exc
    event_ids = set()
    for event in events:
        if not isinstance(event, dict):
            raise ValueError("Invalid event")
        event_id = event.get("id")
        subject_id = event.get("subjectID")
        if (not isinstance(event_id, str) or not event_id or event_id in event_ids
                or not isinstance(subject_id, str) or subject_id not in ids
                or not isinstance(event.get("isSample"), bool)):
            raise ValueError("Invalid event identity/action")
        event_ids.add(event_id)
        event_type = event.get("type")
        ticker = event.get("ticker")
        if event_type in {"trade", "opinion"}:
            if not isinstance(ticker, str) or not TICKER.fullmatch(ticker):
                raise ValueError("Invalid ticker")
        elif ticker is not None and (not isinstance(ticker, str) or not TICKER.fullmatch(ticker)):
            raise ValueError("Invalid holding ticker")
        underlying = event.get("underlyingTicker")
        if underlying is not None and (event_type != "holding" or ticker is not None
                                       or not isinstance(underlying, str)
                                       or not TICKER.fullmatch(underlying)):
            raise ValueError("Invalid option underlying ticker")
        if event_type == "trade":
            if event.get("action") not in ACTIONS:
                raise ValueError("Invalid trade action")
        elif event_type == "opinion":
            if (event.get("direction") not in {"bullish", "bearish", "neutral"}
                    or not isinstance(event.get("summary"), str) or not event["summary"].strip()):
                raise ValueError("Invalid opinion")
        elif event_type == "holding":
            if (event.get("action") not in HOLDING_ACTIONS
                    or not isinstance(event.get("assetName"), str) or not event["assetName"].strip()
                    or not isinstance(event.get("sourceURL"), str)):
                raise ValueError("Invalid holding")
        else:
            raise ValueError("Unknown event type")
        try:
            occurred = date.fromisoformat(event["occurredDay"])
            displayed = date.fromisoformat(event["displayDay"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError("Invalid event date") from exc
        if occurred > displayed:
            raise ValueError("Event predates action")
        if event["isSample"] and not allow_samples:
            raise ValueError("Sample events require --allow-samples")
        if event.get("sourceURL") is not None and urlparse(str(event["sourceURL"])).scheme not in {"http", "https"}:
            raise ValueError("Invalid source URL")
        price_fields = ("eventDayAdjustedClose", "latestAdjustedClose", "latestPriceDay")
        if any(event.get(field) is not None for field in price_fields):
            if (any(event.get(field) is None for field in price_fields)
                    or any(not isinstance(event[field], (int, float)) or not math.isfinite(event[field])
                           or event[field] <= 0 for field in price_fields[:2])):
                raise ValueError("Invalid event price observation")
            try:
                latest_price_day = date.fromisoformat(event["latestPriceDay"])
            except (TypeError, ValueError) as exc:
                raise ValueError("Invalid event price date") from exc
            if latest_price_day < occurred:
                raise ValueError("Event price predates action")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--allow-samples", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--management-project-ref", help="Use the Supabase Management API when project REST is unreachable")
    parser.add_argument("--content-database-prices", action="store_true",
                        help="Merge only newer price fields into the protected live content snapshot")
    parser.add_argument("--content-database-holdings", action="store_true",
                        help="Merge verified 13F tickers and newer prices into the protected live snapshot")
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    validate_snapshot(snapshot, allow_samples=args.allow_samples)
    print(f"Validated {len(snapshot['subjects'])} subjects and {len(snapshot['events'])} events")
    if not args.apply:
        return
    if args.content_database_holdings:
        if args.management_project_ref or args.content_database_prices:
            raise ValueError("Choose one publication transport")
        mapped, identified, priced = publish_holding_enrichment_to_content_database(snapshot)
        print(f"Published and verified {mapped} holding tickers, {identified} option underlyings "
              f"and {priced} price observations")
        return
    if args.content_database_prices:
        if args.management_project_ref:
            raise ValueError("Choose one publication transport")
        changed = publish_price_observations_to_content_database(snapshot)
        print(f"Published and verified prices for {changed} subject events")
        return
    if args.management_project_ref:
        token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
        if not token or not re.fullmatch(r"[a-z0-9]{20}", args.management_project_ref):
            raise ValueError("SUPABASE_ACCESS_TOKEN and a valid project ref are required")
        endpoint = ("https://api.supabase.com/v1/projects/"
                    f"{args.management_project_ref}/database/query")
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        context = ssl.create_default_context(cafile=certifi.where())

        def query(sql: str, parameters: list | None = None, *, read_only: bool = False) -> list:
            request = Request(endpoint, data=json.dumps({"query": sql, "parameters": parameters or [],
                                                         "read_only": read_only}).encode(),
                              method="POST", headers=headers)
            with urlopen(request, timeout=120, context=context) as response:
                if response.status != 201:
                    raise RuntimeError(f"Management query failed: HTTP {response.status}")
                return json.load(response)

        publish_management_snapshot(snapshot, query)
        rows = query("""select jsonb_array_length(payload->'subjects') as subjects,
                              jsonb_array_length(payload->'events') as events
                       from public.bsmart_subject_activity_snapshots
                       where channel='production'""", read_only=True)
        if len(rows) != 1 or rows[0] != {"subjects": len(snapshot["subjects"]),
                                         "events": len(snapshot["events"])}:
            raise RuntimeError("Published snapshot did not pass readback verification")
        print("Published and verified subject-activity snapshot")
        return
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    parsed = urlparse(base_url)
    if (parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"})) or not key:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    row = {"channel": "production", "payload": snapshot,
           "updated_at": datetime.now(timezone.utc).isoformat()}
    request = Request(f"{base_url}/rest/v1/bsmart_subject_activity_snapshots?on_conflict=channel",
                      data=json.dumps([row], separators=(",", ":")).encode(), method="POST",
                      headers={"apikey": key, "Authorization": f"Bearer {key}",
                               "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates"})
    with urlopen(request, timeout=30) as response:
        if response.status not in (200, 201, 204):
            raise RuntimeError(f"Subject activity publication failed: HTTP {response.status}")
    print("Published subject-activity snapshot")


if __name__ == "__main__":
    main()
