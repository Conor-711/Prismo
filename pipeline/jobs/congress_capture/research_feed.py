"""Turn the provenance-preserving congressional research export into an app feed.

Portraits are keyed by Bioguide ID, not by a person's display name. Rows whose
identity or portrait cannot be resolved are withheld instead of showing another
member's face.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, datetime, timezone
import json
from pathlib import Path
import re
import sqlite3
from urllib.parse import urlparse

from pipeline.jobs.congress_capture.ios_feed import attach_prices, build_feed
from pipeline.platforms.congress.disclosures import load_disclosures


TICKER = re.compile(r"^[A-Z][A-Z0-9.]{0,9}$")
BIOGUIDE = re.compile(r"^[A-Z][0-9]{6}$")
PHOTO_ROOT = "https://unitedstates.github.io/images/congress/225x275/"

# Reviewed against the member's official portrait or Bioguide identity. Several
# upstream photo IDs point to a different person or no longer resolve.
PORTRAIT_OVERRIDES = {
    "house_aprilmcclain_delaney": ("M001232", PHOTO_ROOT + "M001232.jpg"),
    "house_elizabeth_fletcher": ("F000468", PHOTO_ROOT + "F000468.jpg"),
    "house_richarddeandr_mccormick": ("M001218", PHOTO_ROOT + "M001218.jpg"),
    "house_christiand_menefee": (
        "M001245",
        "https://upload.wikimedia.org/wikipedia/commons/4/40/"
        "Christian_Menefee%2C_official_portrait_%28119th_Congress%29.jpg",
    ),
    "house_johnjmr_mcguire_iii": ("M001239", PHOTO_ROOT + "M001239.jpg"),
    "house_matthewrobert_vanepps": (
        "V000139",
        "https://upload.wikimedia.org/wikipedia/commons/d/d9/Matt_Van_Epps_official_portrait.jpg",
    ),
    "senate_alan_armstrong": (
        "A000383",
        "https://upload.wikimedia.org/wikipedia/commons/5/55/"
        "Alan_S_Armstrong_official_portrait_%28cropped_2%29.jpg",
    ),
}

MINIMUM_INSTITUTIONAL_COVERAGE = {"celebrity": 15, "institution": 30}


def require_institutional_coverage(feed: dict) -> None:
    counts = Counter(subject["kind"] for subject in feed["subjects"])
    missing = [f"{kind}: {counts[kind]}/{minimum}" for kind, minimum in MINIMUM_INSTITUTIONAL_COVERAGE.items()
               if counts[kind] < minimum]
    if missing:
        raise ValueError("Insufficient verified 13F subjects: " + ", ".join(missing))


def portrait_for(member: object) -> tuple[str, str] | None:
    member_id = member.member_id
    if member_id in PORTRAIT_OVERRIDES:
        return PORTRAIT_OVERRIDES[member_id]
    url = member.photo_url
    if not url or not url.startswith(PHOTO_ROOT):
        return None
    bioguide = url.removeprefix(PHOTO_ROOT).removesuffix(".jpg")
    return (bioguide, url) if BIOGUIDE.fullmatch(bioguide) else None


def build_research_feed(
    rows: list[dict], members: list[object], *, institutional_feed: dict | None = None,
    snapshot_at: str | None = None,
) -> tuple[dict, dict]:
    by_id = {member.member_id: member for member in members}
    by_name: dict[str, list[object]] = {}
    for member in members:
        by_name.setdefault(member.name.casefold(), []).append(member)
    subjects = {subject["id"]: subject for subject in (institutional_feed or {}).get("subjects", [])}
    events = list((institutional_feed or {}).get("events", []))
    seen = {event["id"] for event in events}
    skipped = Counter()

    for row in rows:
        ticker = str(row.get("ticker") or "").strip().upper()
        if not TICKER.fullmatch(ticker):
            skipped["unsupported_ticker"] += 1
            continue
        raw_action = str(row.get("action") or "").strip().lower()
        if raw_action in {"purchase", "p", "buy"}:
            action = "buy"
        elif raw_action in {"sale (full)", "sale (partial)", "sale", "s", "sell"}:
            action = "sell"
        else:
            skipped["unsupported_action"] += 1
            continue
        trade_id = str(row.get("trade_id") or "")
        event_id = f"congress:trade:{trade_id}"
        if not trade_id or event_id in seen:
            skipped["duplicate_or_missing_id"] += 1
            continue
        try:
            transaction = date.fromisoformat(row["transaction_date"])
            filed = date.fromisoformat(row["filing_date"])
        except (TypeError, KeyError, ValueError):
            skipped["missing_disclosure_date"] += 1
            continue
        if transaction > filed:
            skipped["invalid_date_order"] += 1
            continue
        source_url = str(row.get("evidence_url") or "")
        if urlparse(source_url).scheme != "https":
            skipped["missing_evidence"] += 1
            continue
        member = by_id.get(row.get("member_id"))
        if member is None and row.get("member_id") is None:
            candidates = by_name.get(str(row.get("member_name") or "").casefold(), [])
            if len(candidates) == 1:
                member = candidates[0]
        if member is None or member.name != row.get("member_name"):
            skipped["unresolved_identity"] += 1
            continue
        portrait = portrait_for(member)
        if portrait is None:
            skipped["unresolved_portrait"] += 1
            continue
        bioguide, avatar_url = portrait
        subject_id = f"politician:{bioguide}"
        existing = subjects.get(subject_id)
        if existing is not None and existing["avatarURL"] != avatar_url:
            skipped["conflicting_identity"] += 1
            continue
        if existing is None:
            subjects[subject_id] = {"id": subject_id, "kind": "politician", "name": member.name,
                                    "avatarURL": avatar_url, "metrics": None}
        low, high = row.get("amount_low"), row.get("amount_high")
        amount_range = f"${low:,} - ${high:,}" if isinstance(low, int) and isinstance(high, int) else None
        source_note = ("House Clerk filing; automatically extracted, pending review"
                       if row.get("data_source") == "house_clerk_pdf_auto_extracted"
                       else "Official filing; third-party extraction, pending review")
        events.append({
            "id": event_id, "subjectID": subject_id, "ticker": ticker,
            "type": "trade", "action": action, "direction": None, "summary": None,
            "occurredDay": transaction.isoformat(), "displayDay": filed.isoformat(),
            "amountRange": amount_range, "assetDescription": row.get("asset_name"),
            "sourceURL": source_url, "sourceNote": source_note, "isSample": False,
        })
        seen.add(event_id)

    events.sort(key=lambda event: (event["displayDay"], event["id"]), reverse=True)
    feed = {"schemaVersion": 1, "snapshotAt": snapshot_at,
            "subjects": sorted(subjects.values(), key=lambda subject: subject["id"]),
            "events": events}
    report = {"subjects": sum(s["kind"] == "politician" for s in subjects.values()),
              "published_trades": sum(e["type"] == "trade" for e in events),
              "skipped": dict(sorted(skipped.items()))}
    return feed, report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades", type=Path,
                        default=Path("data/exports/congress/congress_trades_1y_research.jsonl"))
    parser.add_argument("--reference-zip", type=Path,
                        default=Path("data/exports/congress/congress-trading-monitor-current.zip"))
    parser.add_argument("--institutional-directory", type=Path,
                        default=Path("data/exports/institutional_holdings"))
    parser.add_argument("--output", type=Path,
                        default=Path("ios/BSmart/Resources/subject-activity.json"))
    parser.add_argument("--price-db", type=Path, default=Path("data/dev.db"))
    args = parser.parse_args()
    from pipeline.domain.institutional_holdings.registry import SUBJECTS
    filings = [json.loads(path.read_text()) for subject in SUBJECTS
               if (path := args.institutional_directory / f"{subject.id}.json").is_file()]
    institutional_feed = build_feed({"source": "disclosed_capitol", "trades": []},
                                    institutional_snapshots=filings)
    members, _ = load_disclosures(args.reference_zip, start_date=date(2000, 1, 1),
                                  end_date=datetime.now(timezone.utc).date())
    rows = [json.loads(line) for line in args.trades.read_text().splitlines() if line.strip()]
    feed, report = build_research_feed(rows, members, institutional_feed=institutional_feed,
                                       snapshot_at=datetime.now(timezone.utc).isoformat())
    if not report["published_trades"] or not report["subjects"]:
        raise ValueError("No publishable congressional trades")
    require_institutional_coverage(feed)
    if args.price_db.is_file():
        with sqlite3.connect(f"file:{args.price_db.resolve()}?mode=ro", uri=True) as connection:
            report["priced_events"] = attach_prices(feed, connection, as_of=date.today())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".tmp")
    tmp.write_text(json.dumps(feed, ensure_ascii=False, separators=(",", ":")) + "\n")
    tmp.replace(args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
