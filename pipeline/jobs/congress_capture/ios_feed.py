"""Export a subject-activity snapshot for the home feed and content API."""

from __future__ import annotations

import argparse
from datetime import date, timedelta
import hashlib
import json
import re
import sqlite3
from decimal import Decimal
from pathlib import Path

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.jobs.congress_capture.cusip_tickers import (
    CUSIP, refresh_cache, tickers as cached_tickers,
)


TICKER = re.compile(r"^[A-Z][A-Z0-9.]{0,9}$")
SIDES = {"Buy": "buy", "Sell": "sell"}
AVATAR_URLS = {
    entry["id"]: entry.get("url")
    for entry in json.loads(Path(__file__).with_name("subject_avatar_sources.json").read_text())["subjects"]
}


def build_feed(snapshot: dict, *, institutional_snapshots: list[dict] | None = None,
               cusip_tickers: dict[str, str] | None = None) -> dict:
    if snapshot.get("source") != "disclosed_capitol" or not isinstance(snapshot.get("trades"), list):
        raise ValueError("Unexpected politician snapshot")

    cusip_tickers = cached_tickers() if cusip_tickers is None else cusip_tickers
    events = []
    subjects = {}
    seen = set()
    for trade in snapshot["trades"]:
        ticker = str(trade.get("ticker") or "").upper().strip()
        side = SIDES.get(trade.get("trade_type"))
        operation_id = trade.get("id")
        politician_id = trade.get("politician_id")
        name = str(trade.get("politician_name") or "").strip()
        transaction_day = trade.get("transaction_date")
        disclosure_day = trade.get("disclosure_date")
        if (not isinstance(operation_id, int) or not isinstance(politician_id, int)
                or operation_id in seen or not name or not TICKER.fullmatch(ticker)
                or not side or not isinstance(transaction_day, str)
                or not isinstance(disclosure_day, str)
                or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", transaction_day)
                or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", disclosure_day)
                or transaction_day > disclosure_day):
            continue
        seen.add(operation_id)
        subject_id = f"politician:{politician_id}"
        subjects[subject_id] = {"id": subject_id, "kind": "politician", "name": name,
                                "avatarURL": AVATAR_URLS.get(subject_id), "metrics": None}
        events.append({
            "id": f"politician:trade:{operation_id}",
            "subjectID": subject_id,
            "ticker": ticker,
            "type": "trade",
            "action": side,
            "direction": None,
            "summary": None,
            "occurredDay": transaction_day,
            "displayDay": disclosure_day,
            "amountRange": trade.get("amount_range"),
            "assetDescription": trade.get("asset_description"),
            "sourceURL": None,
            "sourceNote": None,
            "isSample": False,
        })

    known = {subject.id: subject for subject in SUBJECTS}
    for filing in institutional_snapshots or []:
        subject = known.get(filing.get("subjectId"))
        if (subject is None or filing.get("kind") != subject.kind
                or filing.get("title") != subject.title
                or filing.get("source") != "SEC EDGAR Form 13F"):
            raise ValueError("Unexpected institutional subject snapshot")
        period = str(filing.get("periodOfReport") or "")
        filed = str(filing.get("filedAt") or "")[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", period) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", filed):
            raise ValueError("Invalid institutional filing dates")
        date.fromisoformat(period)
        date.fromisoformat(filed)
        if period > filed:
            raise ValueError("Institutional filing predates report period")
        filing_url = str(filing.get("filingUrl") or "")
        if not filing_url.startswith("https://www.sec.gov/"):
            raise ValueError("Institutional filing URL missing")
        status_note = {
            "stale": f"Stale 13F; report period {period}",
            "newer_notice_without_holdings": "Newer 13F notice has no holdings table",
            "partial_quarterly_report": "Partial 13F combination report",
        }.get(filing.get("disclosureStatus"))
        source_note = subject.attribution + (f"; {status_note}" if status_note else "")
        subject_id = f"{subject.kind}:{subject.id}"
        subjects[subject_id] = {"id": subject_id, "kind": subject.kind,
                                "name": subject.title, "avatarURL": AVATAR_URLS.get(subject_id),
                                "metrics": None}

        def key(row: dict) -> tuple:
            return tuple(row.get(field) for field in
                         ("cusip", "securityClass", "option", "shareType"))

        holdings: dict[tuple, dict] = {}
        values: dict[tuple, int] = {}
        for row in filing.get("holdings", []):
            identity = key(row)
            value = int(row.get("reportedValueUsd") or 0)
            values[identity] = values.get(identity, 0) + value
            if identity not in holdings or value > int(holdings[identity].get("reportedValueUsd") or 0):
                holdings[identity] = row
        deltas: dict[tuple, Decimal] = {}
        classifications: dict[tuple, set[str]] = {}
        for row in filing.get("changes", []):
            identity = key(row)
            if identity not in holdings:
                continue
            deltas[identity] = deltas.get(identity, Decimal(0)) + Decimal(row["reportedShareChange"])
            classifications.setdefault(identity, set()).add(row["classification"])
        changed = []
        for identity, delta in deltas.items():
            if delta == 0:
                continue
            action = ("new" if classifications[identity] == {"new_reported_position"}
                      else "increased" if delta > 0 else "reduced")
            changed.append((action, identity))
        selected = sorted(changed or [("held", identity) for identity in holdings],
                          key=lambda pair: (-values[pair[1]], str(pair[1])))[:8]
        for action, identity in selected:
            holding = holdings[identity]
            digest = hashlib.sha256(json.dumps([subject_id, filing.get("accession"), identity],
                                                  sort_keys=True).encode()).hexdigest()[:20]
            issuer = str(holding.get("issuer") or "").strip()
            if not issuer:
                continue
            option = holding.get("option")
            cusip = str(holding.get("cusip") or "").upper()
            mapped_ticker = cusip_tickers.get(cusip) if holding.get("shareType") == "SH" else None
            events.append({"id": f"13f:{digest}", "subjectID": subject_id,
                           "ticker": mapped_ticker if option is None else None,
                           "underlyingTicker": mapped_ticker if option else None,
                           "cusip": cusip, "assetName": issuer,
                           "type": "holding", "action": action,
                           "direction": None, "summary": f"{option} option" if option else None,
                           "occurredDay": period, "displayDay": filed, "amountRange": None,
                           "assetDescription": holding.get("securityClass"),
                           "sourceURL": filing_url, "sourceNote": source_note,
                           "isSample": False})

    events.sort(key=lambda row: (row["displayDay"], row["id"]), reverse=True)
    return {"schemaVersion": 1, "snapshotAt": snapshot.get("fetched_at"),
            "subjects": sorted(subjects.values(), key=lambda row: row["id"]), "events": events}


def attach_prices(feed: dict, connection: sqlite3.Connection, *, as_of: date) -> int:
    """Attach same-basis daily closes; disclosure dates are never trade dates."""
    columns = {row[1] for row in connection.execute("PRAGMA table_info(price_daily)")}
    basis_sql = ("CASE WHEN source IN ('nasdaq', 'nasdaq_raw') THEN 'raw' "
                 "ELSE 'adjusted' END") if "source" in columns else "'adjusted'"
    latest: dict[str, tuple[str, float, str] | None] = {}
    attached = 0
    for event in feed["events"]:
        for field in ("eventDayAdjustedClose", "latestAdjustedClose", "latestPriceDay", "priceBasis"):
            event.pop(field, None)
        ticker = event.get("ticker")
        if not ticker or event.get("isSample"):
            continue
        if ticker not in latest:
            latest[ticker] = connection.execute(
                f"SELECT day, adj_close, {basis_sql} FROM price_daily WHERE ticker=? "
                "AND day<=? AND adj_close > 0 ORDER BY day DESC LIMIT 1",
                (ticker, as_of.isoformat()),
            ).fetchone()
        end = latest[ticker]
        if not end or not 0 <= (as_of - date.fromisoformat(end[0])).days <= 7:
            continue
        event_day = event["displayDay"] if event["type"] == "opinion" else event["occurredDay"]
        final_day = (date.fromisoformat(event_day) + timedelta(days=4)).isoformat()
        start = connection.execute(
            f"SELECT day, adj_close FROM price_daily WHERE ticker=? AND day>=? AND day<=? "
            f"AND adj_close > 0 AND {basis_sql}=? ORDER BY day LIMIT 1",
            (ticker, event_day, final_day, end[2]),
        ).fetchone()
        if not start or start[0] > end[0]:
            continue
        event["eventDayAdjustedClose"] = float(start[1])
        event["latestAdjustedClose"] = float(end[1])
        event["latestPriceDay"] = end[0]
        event["priceBasis"] = end[2]
        attached += 1
    return attached


def enrich_existing_holdings(feed: dict, institutional_feed: dict) -> int:
    by_id = {event["id"]: event for event in institutional_feed["events"]
             if event["type"] == "holding"}
    updated = 0
    for event in feed["events"]:
        source = by_id.get(event["id"])
        if source is None:
            continue
        if any(event.get(field) != source.get(field) for field in
               ("subjectID", "type", "action", "assetName", "occurredDay", "displayDay")):
            raise ValueError(f"13F event identity changed: {event['id']}")
        if event.get("ticker") and source.get("ticker") and event["ticker"] != source["ticker"]:
            raise ValueError(f"Conflicting ticker for 13F event: {event['id']}")
        if (event.get("underlyingTicker") and source.get("underlyingTicker")
                and event["underlyingTicker"] != source["underlyingTicker"]):
            raise ValueError(f"Conflicting underlying ticker for 13F event: {event['id']}")
        event["cusip"] = source["cusip"]
        if source.get("ticker") and not event.get("ticker"):
            event["ticker"] = source["ticker"]
            updated += 1
        if source.get("underlyingTicker") and not event.get("underlyingTicker"):
            event["underlyingTicker"] = source["underlyingTicker"]
            updated += 1
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=Path("data/exports/congress/disclosed_capitol.json"))
    parser.add_argument("--institutional-directory", type=Path,
                        default=Path("data/exports/institutional_holdings"))
    parser.add_argument("--output", type=Path, default=Path("ios/BSmart/Resources/subject-activity.json"))
    parser.add_argument("--price-db", type=Path, default=Path("data/dev.db"))
    parser.add_argument("--enrich-existing", action="store_true",
                        help="Keep the existing subject/event snapshot and add available price observations")
    parser.add_argument("--refresh-tickers", action="store_true",
                        help="Resolve new selected 13F CUSIPs using OpenFIGI before exporting")
    parser.add_argument("--holdings-only", action="store_true",
                        help="Only update 13F price observations when enriching an existing snapshot")
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today() - timedelta(days=1),
                        help="Last completed pricing day; defaults to the previous calendar day")
    args = parser.parse_args()
    filings = [json.loads(path.read_text()) for subject in SUBJECTS
               if (path := args.institutional_directory / f"{subject.id}.json").is_file()]
    if args.refresh_tickers:
        draft = build_feed({"source": "disclosed_capitol", "trades": []},
                           institutional_snapshots=filings, cusip_tickers={})
        selected = {event["cusip"] for event in draft["events"] if event["type"] == "holding"
                    and CUSIP.fullmatch(event["cusip"])}
        refresh_cache(selected)
    if args.enrich_existing:
        feed = json.loads(args.output.read_text())
        institutional = build_feed({"source": "disclosed_capitol", "trades": []},
                                   institutional_snapshots=filings)
        print(f"Mapped {enrich_existing_holdings(feed, institutional)} existing 13F events")
    else:
        feed = build_feed(json.loads(args.snapshot.read_text()), institutional_snapshots=filings)
    if args.price_db.is_file():
        with sqlite3.connect(f"file:{args.price_db.resolve()}?mode=ro", uri=True) as connection:
            priced = ({"events": [event for event in feed["events"] if event["type"] == "holding"]}
                      if args.holdings_only else feed)
            attached = attach_prices(priced, connection, as_of=args.as_of)
        print(f"Attached same-basis daily-close moves to {attached} events")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(feed, ensure_ascii=False, separators=(",", ":")) + "\n")
    temporary.replace(args.output)
    print(f"Exported {len(feed['events'])} subject events to {args.output}")


if __name__ == "__main__":
    main()
