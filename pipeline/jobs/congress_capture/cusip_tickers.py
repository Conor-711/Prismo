"""Resolve SEC 13F CUSIPs to unambiguous US-listed ticker symbols."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re

import requests


DEFAULT_CACHE = Path(__file__).with_name("cusip_tickers.json")
CUSIP = re.compile(r"[A-Z0-9]{9}\Z")
TICKER = re.compile(r"[A-Z][A-Z0-9.]{0,9}\Z")
API_URL = "https://api.openfigi.com/v3/mapping"


def load_cache(path: Path = DEFAULT_CACHE) -> dict:
    if not path.is_file():
        return {"schemaVersion": 1, "source": "OpenFIGI ID_CUSIP US", "resolved": {}, "unresolved": {}}
    cache = json.loads(path.read_text())
    if (cache.get("schemaVersion") != 1 or not isinstance(cache.get("resolved"), dict)
            or not isinstance(cache.get("unresolved"), dict)):
        raise ValueError("Invalid CUSIP mapping cache")
    return cache


def tickers(path: Path = DEFAULT_CACHE) -> dict[str, str]:
    return resolved_tickers(load_cache(path))


def resolved_tickers(cache: dict) -> dict[str, str]:
    return {cusip: entry["ticker"] for cusip, entry in cache["resolved"].items()
            if CUSIP.fullmatch(cusip) and isinstance(entry, dict)
            and isinstance(entry.get("ticker"), str) and TICKER.fullmatch(entry["ticker"])}


def choose_us_ticker(result: dict) -> tuple[dict | None, str | None]:
    candidates = [row for row in result.get("data", [])
                  if row.get("exchCode") == "US" and row.get("marketSector") == "Equity"
                  and row.get("securityType2") != "Option"
                  and isinstance(row.get("ticker"), str)
                  and TICKER.fullmatch(row["ticker"])]
    symbols = {row["ticker"] for row in candidates}
    if len(symbols) != 1:
        return None, "ambiguous" if symbols else "no_us_equity_ticker"
    row = candidates[0]
    return {"ticker": row["ticker"], "name": row.get("name"),
            "securityType": row.get("securityType2"), "figi": row.get("figi")}, None


def refresh_cache(cusips: set[str], *, path: Path = DEFAULT_CACHE,
                  session: requests.Session | None = None, persist: bool = True) -> dict:
    cache = load_cache(path)
    missing = sorted(cusip for cusip in cusips if CUSIP.fullmatch(cusip)
                     and cusip not in cache["resolved"] and cusip not in cache["unresolved"])
    if not missing:
        return cache
    client = session or requests.Session()
    headers = {"Content-Type": "application/json"}
    if key := os.environ.get("OPENFIGI_API_KEY"):
        headers["X-OPENFIGI-APIKEY"] = key
    for offset in range(0, len(missing), 10):
        batch = missing[offset:offset + 10]
        jobs = [{"idType": "ID_CUSIP", "idValue": cusip, "exchCode": "US"} for cusip in batch]
        response = client.post(API_URL, json=jobs, headers=headers, timeout=(8, 40))
        response.raise_for_status()
        results = response.json()
        if not isinstance(results, list) or len(results) != len(batch):
            raise ValueError("OpenFIGI returned an incomplete mapping batch")
        for cusip, result in zip(batch, results):
            match, reason = choose_us_ticker(result)
            if match:
                cache["resolved"][cusip] = match
            else:
                cache["unresolved"][cusip] = reason
    cache["updatedAt"] = datetime.now(timezone.utc).isoformat()
    if persist:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(cache, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        temporary.replace(path)
    return cache


def main() -> None:
    from pipeline.domain.institutional_holdings.registry import SUBJECTS
    from pipeline.jobs.congress_capture.ios_feed import build_feed

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--institutional-directory", type=Path,
                        default=Path("data/exports/institutional_holdings"))
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    args = parser.parse_args()
    filings = [json.loads(path.read_text()) for subject in SUBJECTS
               if (path := args.institutional_directory / f"{subject.id}.json").is_file()]
    draft = build_feed({"source": "disclosed_capitol", "trades": []},
                       institutional_snapshots=filings, cusip_tickers={})
    cusips = {event["cusip"] for event in draft["events"] if event["type"] == "holding"
              and CUSIP.fullmatch(event["cusip"])}
    cache = refresh_cache(cusips, path=args.cache)
    matched = len(cusips & cache["resolved"].keys())
    print(f"Mapped {matched}/{len(cusips)} selected CUSIPs; "
          f"{len(cusips & cache['unresolved'].keys())} unresolved")


if __name__ == "__main__":
    main()
