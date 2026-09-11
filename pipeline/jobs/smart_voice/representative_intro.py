"""Backfill compact representative metadata without rerunning scores or replacing text."""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from ...domain.smart_voice.representative_intro import enrich_representative_intros
from ...domain.smart_voice.client_read_model import build_representative_evidence
from ...domain.opinions.supporting_sources import enrich_collection


def backfill(*, db_path: str, directory: str, apply: bool = False) -> dict:
    root = Path(directory)
    paths = [root / f"{name}.json" for name in ("smart-accounts", "smart-account-evidence")]
    originals = [path.read_bytes() for path in paths]
    profiles, evidence = [json.loads(raw) for raw in originals]
    connection = sqlite3.connect(f"file:{Path(db_path).resolve()}?mode=ro", uri=True)
    try:
        refreshed = build_representative_evidence(connection)
        accounts = {(p["platform"].lower(), p["id"]) for p in profiles}
        refreshed = [w for w in refreshed if (w["platform"].lower(), w["authorId"]) in accounts]
        refreshed = enrich_collection("smart-account-evidence", refreshed)
        by_id = {work["id"]: work for work in evidence}
        # Keep former anchors available to existing deep links, but not in the three current works.
        for work in by_id.values():
            if work.get("evidenceRole") == "representative":
                work["evidenceRole"] = "strongest"
                for field in ("representativeTickerRank", "representativeTickerContribution", "representativeCallCount"):
                    work.pop(field, None)
        for work in refreshed:
            previous = by_id.get(work["id"], {})
            for field in ("translatedText", "translatedTextZH", "translatedTextEN", "originalText", "supportingSources"):
                if previous.get(field):
                    work[field] = previous[field]
            by_id[work["id"]] = work
        evidence = sorted(by_id.values(), key=lambda w: (w["platform"], w["authorId"],
                          w.get("evidenceRole") != "representative", w.get("representativeTickerRank") or 999,
                          w["publishedAt"], w["id"]))
        report = enrich_representative_intros(connection, profiles, evidence, as_of=datetime.now(timezone.utc))
    finally:
        connection.close()
    pool = [p for p in profiles if p.get("platformPercentile") is not None
            and 0 <= p["platformPercentile"] <= 0.25 and (p.get("platformRank") or 0) > 0]
    report.update(pool=len(pool), poolWithRepresentative=sum("representativeWork" in p for p in pool),
                  evidence=len(evidence),
                  poolWithFirstPrice=sum(p.get("representativeWork", {}).get("firstOpinion", {}).get("price") is not None for p in pool),
                  missing=[{"id": p["id"], "name": p["name"], "platform": p["platform"]}
                           for p in profiles if "representativeWork" not in p], applied=apply)
    if apply:
        # Refuse to overwrite any concurrent collection refresh; preserve exact inputs for audit.
        if any(path.read_bytes() != original for path, original in zip(paths, originals)):
            raise RuntimeError("Read models changed during backfill; retry against the new snapshot")
        backup = Path(__file__).resolve().parents[3] / "data/runtime/representative-intro-backup"
        backup.mkdir(parents=True, exist_ok=True)
        for path, original, documents in zip(paths, originals, (profiles, evidence)):
            digest = hashlib.sha256(original).hexdigest()[:12]
            (backup / f"{path.stem}-{digest}.json").write_bytes(original)
            temporary = path.with_suffix(".intro.tmp")
            temporary.write_text(json.dumps(documents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temporary.replace(path)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(backfill(db_path=args.db, directory=args.directory, apply=args.apply), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
