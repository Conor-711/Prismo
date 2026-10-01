"""Read and combine verified, locally cached SEC 13F quarterly reports."""

from __future__ import annotations

import gzip
import json
from collections import defaultdict
from datetime import date
from pathlib import Path

from pipeline.jobs.congress_capture.backfill_three_years import combine_quarter
from pipeline.platforms.institutional_holdings.sec_13f import FilingError


def reports_by_cik(
    history: Path, cik: int, since: date, as_of: date
) -> tuple[list[dict], list[str]]:
    by_period: dict[str, list[dict]] = defaultdict(list)
    for path in (history / str(cik)).glob("*.json.gz"):
        with gzip.open(path, "rt", encoding="utf-8") as handle:
            report = json.load(handle)
        if (
            since.isoformat() <= report["periodOfReport"] <= as_of.isoformat()
            and report["filedAt"] <= as_of.isoformat()
        ):
            by_period[report["periodOfReport"]].append(report)
    combined = []
    errors = []
    for period in sorted(by_period):
        try:
            report, pieces = combine_quarter(by_period[period])
        except FilingError as error:
            errors.append(f"{period}:{error}")
            continue
        combined.append(
            {**report, "publicAt": max(piece["filedAt"] for piece in pieces)}
        )
    return combined, errors
